import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_queries.dart';
import '../analytics/event_repository.dart';
import '../analytics/network_monitor.dart';
import '../analytics/transport.dart';
import '../analytics/uploader.dart';
import '../core/db/app_database.dart';
import '../core/db/seed_importer.dart';
import '../core/ids.dart';
import '../data/article_repository.dart';
import '../data/auth_service.dart';
import '../data/dictionary_repository.dart';
import '../data/progress_repository.dart';
import '../data/vocab_repository.dart';
import 'settings.dart';

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 应用级依赖容器。App 很小，数据以 SQLite 为唯一真相源，
/// 各仓储自带 ValueNotifier 通知变更，不需要额外的状态管理框架。
class AppScope {
  AppScope._({
    required this.db,
    required this.settings,
    required this.articles,
    required this.progress,
    required this.vocab,
    required this.dictionary,
    required this.auth,
    required this.events,
    required this.network,
    required this.uploader,
    required this.analytics,
    required this.queries,
    required this.seed,
  });

  static late AppScope instance;

  final Database db;
  final AppSettings settings;
  final ArticleRepository articles;
  final ProgressRepository progress;
  final VocabRepository vocab;
  final DictionaryRepository dictionary;
  final AuthService auth;
  final EventRepository events;
  final NetworkMonitor network;
  final EventUploader uploader;
  final Analytics analytics;
  final AnalyticsQueries queries;
  final SeedResult seed;

  String get userId => auth.userId;

  static const _analyticsEndpoint = String.fromEnvironment('ANALYTICS_ENDPOINT');

  /// 冷启动初始化：开库（含迁移）→ 导入种子 → 载入词表 → 恢复登录态 → 启动埋点。
  static Future<AppScope> bootstrap() async {
    final dbPath = p.join(await getDatabasesPath(), 'english_reader.db');
    final db = await openAppDatabase(factory: databaseFactory, path: dbPath);

    final seed = await importSeedIfNeeded(
      db,
      articlesJson: await rootBundle.loadString('assets/seed/articles.json'),
      dictionaryJson: await rootBundle.loadString('assets/seed/dictionary.json'),
    );

    final dictionary = DictionaryRepository(db);
    await dictionary.load();

    final auth = AuthService(db, const SecureTokenStore());
    await auth.ensureDemoAccount();
    try {
      await auth.restore();
    } catch (_) {
      // 安全存储读取异常时按未登录处理。
    }

    var deviceId = await readMeta(db, 'device_id');
    if (deviceId == null) {
      deviceId = uuidV4();
      await writeMeta(db, 'device_id', deviceId);
    }

    final events = EventRepository(db);
    final network = NetworkMonitor();
    final transport = _analyticsEndpoint.isEmpty
        ? MockTransport(events, network)
        : HttpTransport(Uri.parse(_analyticsEndpoint));
    final uploader = EventUploader(events, transport);
    final analytics = Analytics(
      repo: events,
      uploader: uploader,
      network: network,
      deviceId: deviceId,
      platform: Platform.operatingSystem,
      userId: () => auth.userId,
    );

    final scope = AppScope._(
      db: db,
      settings: AppSettings(
        initial: {
          for (final key in AppSettings.keys)
            if (await readMeta(db, key) case final String value) key: value,
        },
        persist: (key, value) => writeMeta(db, key, value),
      ),
      articles: ArticleRepository(db),
      progress: ProgressRepository(db),
      vocab: VocabRepository(db),
      dictionary: dictionary,
      auth: auth,
      events: events,
      network: network,
      uploader: uploader,
      analytics: analytics,
      queries: AnalyticsQueries(db),
      seed: seed,
    );
    instance = scope;

    // 探测联网状态后再补报，冷启动事件带上正确的 network 字段。
    await network.check().timeout(const Duration(seconds: 2), onTimeout: () => false);
    analytics.onColdStart();
    await uploader.start();
    return scope;
  }
}

/// 全局访问的简写。
AppScope get app => AppScope.instance;
