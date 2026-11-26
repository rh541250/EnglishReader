import 'package:english_reader/core/db/app_database.dart';
import 'package:english_reader/core/db/migrations.dart';
import 'package:english_reader/core/db/seed_importer.dart';
import 'package:english_reader/data/article_repository.dart';
import 'package:english_reader/data/auth_service.dart';
import 'package:english_reader/data/dictionary_repository.dart';
import 'package:english_reader/data/models.dart';
import 'package:english_reader/data/progress_repository.dart';
import 'package:english_reader/data/vocab_repository.dart';
import 'package:english_reader/domain/reading_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

ProgressSnapshot snapshot({
  String articleId = 'a001',
  ReadingPosition position = const ReadingPosition(1, 0.4),
  double progress = 0.5,
  bool completed = false,
  int total = 30000,
  String sessionId = 's1',
  int sessionMs = 30000,
  int now = 1000000,
}) => ProgressSnapshot(
  userId: 'u1',
  articleId: articleId,
  position: position,
  progress: progress,
  completed: completed,
  totalDurationMs: total,
  sessionId: sessionId,
  sessionStartedAt: now - sessionMs,
  sessionDurationMs: sessionMs,
  nowMs: now,
);

void main() {
  late Database db;
  tearDown(() async => db.close());

  group('迁移与种子', () {
    test('全新安装：建出全部表并写入 user_version', () async {
      db = await openTestDb();
      final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'])
          .toSet();
      expect(
        tables,
        containsAll([
          'users',
          'sessions',
          'articles',
          'reading_progress',
          'reading_sessions',
          'vocabulary',
          'dictionary',
          'dictionary_forms',
          'event_queue',
          'upload_log',
          'meta',
        ]),
      );
      expect(await db.getVersion(), kSchemaVersion);
    });

    test('真实升级 v1 → v2：老用户的进度和生词保留，新表可用', () async {
      final path = tempDbPath('upgrade');
      // 只执行 v1 脚本，模拟「装着上一个版本的老用户」。
      db = await openAppDatabase(factory: databaseFactoryFfi, path: path, version: 1, migrations: {1: kMigrations[1]!});
      await importSeedIfNeeded(db, articlesJson: kTestArticles, dictionaryJson: kTestDictionary);
      await ProgressRepository(db).save(snapshot(position: const ReadingPosition(1, 0.5)));
      await db.close();

      db = await openAppDatabase(factory: databaseFactoryFfi, path: path);
      expect(await db.getVersion(), kSchemaVersion);
      expect((await ProgressRepository(db).get('u1', 'a001'))!.position, const ReadingPosition(1, 0.5));
      for (final table in ['article_favorites', 'sentence_marks', 'search_history']) {
        expect(await db.query(table), isEmpty, reason: table);
      }
    });

    test('后续版本：只执行尚未执行的脚本，旧数据保留', () async {
      final path = tempDbPath('upgrade-next');
      db = await openTestDb(path: path);
      await writeMeta(db, 'k', 'v');
      await db.close();
      final next = kSchemaVersion + 1;
      final migrations = {
        ...kMigrations,
        next: ['CREATE TABLE reading_goals (user_id TEXT PRIMARY KEY, minutes INTEGER NOT NULL)'],
      };
      db = await openAppDatabase(factory: databaseFactoryFfi, path: path, version: next, migrations: migrations);
      expect(await db.getVersion(), next);
      expect(await readMeta(db, 'k'), 'v');
      await db.insert('reading_goals', {'user_id': 'u1', 'minutes': 10});
    });

    test('种子导入幂等：重复启动不重复导入，版本变化才重新导入', () async {
      db = await openTestDb();
      final first = await importSeedIfNeeded(db, articlesJson: kTestArticles, dictionaryJson: kTestDictionary);
      expect(first.imported, isTrue);
      expect(first.articles, 3);
      final second = await importSeedIfNeeded(db, articlesJson: kTestArticles, dictionaryJson: kTestDictionary);
      expect(second.imported, isFalse);
      expect(await ArticleRepository(db).count(), 3);
      // 种子版本升级：重新导入但不产生重复行。
      final third = await importSeedIfNeeded(
        db,
        articlesJson: kTestArticles,
        dictionaryJson: kTestDictionary,
        seedVersion: '2',
      );
      expect(third.imported, isTrue);
      expect(await ArticleRepository(db).count(), 3);
    });
  });

  group('文章', () {
    setUp(() async => db = await openSeededTestDb());

    test('分类 / 难度筛选与分页', () async {
      final repo = ArticleRepository(db);
      final all = await repo.list(userId: 'u1', limit: 2);
      expect(all.map((a) => a.id), ['a001', 'a002']); // 发布时间倒序
      final page2 = await repo.list(userId: 'u1', limit: 2, offset: 2);
      expect(page2.map((a) => a.id), ['a003']);
      final tech = await repo.list(userId: 'u1', category: ArticleCategory.tech);
      expect(tech.map((a) => a.id), ['a001', 'a003']);
      final hard = await repo.list(userId: 'u1', difficulty: 3);
      expect(hard.single.id, 'a003');
    });

    test('上下篇', () async {
      final repo = ArticleRepository(db);
      final a2 = (await repo.getById('a002'))!.summary;
      expect((await repo.previousOf(a2))?.id, 'a001');
      expect((await repo.nextOf(a2))?.id, 'a003');
      final a1 = (await repo.getById('a001'))!.summary;
      expect(await repo.previousOf(a1), isNull);
    });

    test('导入时计算词数并保存正文', () async {
      final a = (await ArticleRepository(db).getById('a001'))!;
      expect(a.paragraphs.length, 2);
      expect(a.summary.wordCount, 11);
    });
  });

  group('阅读进度', () {
    setUp(() async => db = await openSeededTestDb());

    test('写入后可精确读回位置', () async {
      final repo = ProgressRepository(db);
      await repo.save(snapshot(position: const ReadingPosition(3, 0.3725)));
      final p = (await repo.get('u1', 'a001'))!;
      expect(p.position, const ReadingPosition(3, 0.3725));
      expect(p.progress, 0.5);
      expect(p.durationMs, 30000);
      expect(p.completed, isFalse);
    });

    test('幂等：同一快照重复写入 N 次，结果与写入一次相同', () async {
      final repo = ProgressRepository(db);
      final s = snapshot();
      await repo.save(s);
      final once = await db.query('reading_progress');
      for (var i = 0; i < 5; i++) {
        await repo.save(s);
      }
      final many = await db.query('reading_progress');
      expect(many.length, 1);
      for (final key in [
        'paragraph_index',
        'paragraph_offset',
        'progress',
        'max_progress',
        'completed',
        'duration_ms',
        'last_read_at',
      ]) {
        expect(many.first[key], once.first[key], reason: key);
      }
      // 时长是绝对值，不会因为重复写入而累加。
      expect((await db.query('reading_sessions')).single['duration_ms'], 30000);
    });

    test('往回翻：当前位置跟着变，最远进度与完成状态不回退', () async {
      final repo = ProgressRepository(db);
      await repo.save(snapshot(progress: 0.98, completed: true, now: 2000000));
      await repo.save(snapshot(progress: 0.2, completed: false, position: const ReadingPosition(0, 0.5), now: 3000000));
      final p = (await repo.get('u1', 'a001'))!;
      expect(p.progress, 0.2);
      expect(p.position, const ReadingPosition(0, 0.5));
      expect(p.maxProgress, 0.98);
      expect(p.completed, isTrue);
      expect(p.completedAt, 2000000); // 首次读完的时间不被覆盖
    });

    test('乱序到达的旧快照不会让时长倒退', () async {
      final repo = ProgressRepository(db);
      await repo.save(snapshot(total: 60000, sessionMs: 60000, now: 2000000));
      await repo.save(snapshot(total: 30000, sessionMs: 30000, now: 1500000));
      final p = (await repo.get('u1', 'a001'))!;
      expect(p.durationMs, 60000);
      expect(p.lastReadAt, 2000000);
    });

    test('进程被杀：已落库的进度在重新打开数据库后仍在', () async {
      await db.close();
      final path = tempDbPath('kill');
      db = await openSeededTestDb(path: path);
      await ProgressRepository(db).save(snapshot(position: const ReadingPosition(2, 0.61), progress: 0.44));
      // 不做任何「正常退出」清理，直接关闭连接后重开，模拟进程重启。
      await db.close();
      db = await openTestDb(path: path);
      final p = (await ProgressRepository(db).get('u1', 'a001'))!;
      expect(p.position, const ReadingPosition(2, 0.61));
      expect(p.progress, 0.44);
    });

    test('统计：累计时长、读完数、连续打卡', () async {
      final repo = ProgressRepository(db);
      final today = DateTime(2026, 11, 26, 10);
      final yesterday = DateTime(2026, 11, 25, 21);
      await repo.save(
        snapshot(sessionId: 'y', sessionMs: 120000, total: 120000, now: yesterday.millisecondsSinceEpoch),
      );
      await repo.save(
        snapshot(
          articleId: 'a002',
          sessionId: 't',
          sessionMs: 60000,
          total: 60000,
          completed: true,
          progress: 1,
          now: today.millisecondsSinceEpoch,
        ),
      );
      final stats = await repo.stats('u1', now: today);
      expect(stats.totalDurationMs, 180000);
      expect(stats.todayDurationMs, 60000);
      expect(stats.finishedCount, 1);
      expect(stats.streakDays, 2);
      final daily = await repo.dailyDurations('u1', now: today);
      expect(daily.length, 7);
      expect(daily.last.value, 60000);
      expect(daily[5].value, 120000);
      expect(daily.first.value, 0);
    });

    test('列表联查能带出进度，「继续阅读」取最近未读完的一篇', () async {
      final progress = ProgressRepository(db);
      final articles = ArticleRepository(db);
      await progress.save(snapshot(articleId: 'a001', progress: 0.4, now: 1000));
      await progress.save(snapshot(articleId: 'a003', progress: 0.6, now: 2000, sessionId: 's2'));
      await progress.save(snapshot(articleId: 'a002', progress: 1, completed: true, now: 3000, sessionId: 's3'));
      final list = await articles.list(userId: 'u1');
      expect(list.firstWhere((a) => a.id == 'a001').maxProgress, 0.4);
      expect(list.firstWhere((a) => a.id == 'a002').completed, isTrue);
      expect((await articles.continueReading('u1'))?.id, 'a003');
      // 其他用户看不到这些进度。
      expect((await articles.list(userId: 'u2')).every((a) => a.maxProgress == 0), isTrue);
    });
  });

  group('词表与生词本', () {
    setUp(() async => db = await openSeededTestDb());

    test('取词：直接命中、词形表还原、后缀兜底、未收录', () async {
      final dict = DictionaryRepository(db);
      await dict.load();
      expect(dict.lookup('Cat').meaning, '猫');
      expect(dict.lookup('running').word, 'run'); // forms
      expect(dict.lookup('cats').word, 'cat'); // 复数兜底
      expect(dict.lookup("cat's").word, 'cat');
      expect(dict.lookup('sleeping').word, 'sleep');
      final missing = dict.lookup('Quux');
      expect(missing.found, isFalse);
      expect(missing.word, 'quux');
      expect(dict.lemmaOf('Running'), 'run');
    });

    test('收藏幂等：同一词元重复收藏只有一行，保留首次出处', () async {
      final dict = DictionaryRepository(db);
      await dict.load();
      final vocab = VocabRepository(db);
      Future<bool> add(String display, int para, int word) => vocab.add(
        userId: 'u1',
        entry: dict.lookup(display),
        display: display,
        articleId: 'a001',
        paragraphIndex: para,
        wordIndex: word,
        context: 'ctx',
      );
      expect(await add('Cats', 0, 0), isTrue);
      expect(await add('cat', 1, 3), isFalse);
      expect(await add('cats', 1, 5), isFalse);
      final list = await vocab.list('u1');
      expect(list.length, 1);
      expect(list.single.word, 'cat');
      expect(list.single.paragraphIndex, 0);
      expect(list.single.wordIndex, 0);
      expect(list.single.articleTitle, 'First Story'); // 用于「跳回原文」
      expect(await vocab.collectedWords('u1'), {'cat'});
    });

    test('删除后可重新收藏；不同用户互不影响', () async {
      final dict = DictionaryRepository(db);
      await dict.load();
      final vocab = VocabRepository(db);
      Future<bool> add(String user) => vocab.add(
        userId: user,
        entry: dict.lookup('run'),
        display: 'run',
        articleId: 'a001',
        paragraphIndex: 0,
        wordIndex: 5,
        context: '',
      );
      expect(await add('u1'), isTrue);
      expect(await add('u2'), isTrue);
      await vocab.remove('u1', 'run');
      expect(await vocab.count('u1'), 0);
      expect(await vocab.count('u2'), 1);
      expect(await add('u1'), isTrue);
    });
  });

  group('Mock 鉴权', () {
    setUp(() async => db = await openTestDb());

    test('注册 → 登录态持久化 → 重启恢复', () async {
      final store = MemoryTokenStore();
      final auth = AuthService(db, store);
      final user = await auth.register('alice', 'secret1');
      expect(auth.currentUser.value?.id, user.id);
      // 模拟重启：新的 AuthService 实例，只有数据库和安全存储是持久的。
      final restarted = AuthService(db, store);
      expect(restarted.currentUser.value, isNull);
      final restored = await restarted.restore();
      expect(restored?.username, 'alice');
    });

    test('密码不存明文；错误密码与重复注册被拒', () async {
      final auth = AuthService(db, MemoryTokenStore());
      await auth.register('alice', 'secret1');
      final row = (await db.query('users')).single;
      expect(row['password_hash'], isNot(contains('secret1')));
      await expectLater(auth.login('alice', 'wrong'), throwsA(isA<AuthException>()));
      await expectLater(auth.register('alice', 'another1'), throwsA(isA<AuthException>()));
      await expectLater(auth.register('ab', 'secret1'), throwsA(isA<AuthException>()));
      await expectLater(auth.register('bob', '123'), throwsA(isA<AuthException>()));
    });

    test('Token 校验：被篡改、已过期、已登出的 Token 都无效', () async {
      final store = MemoryTokenStore();
      var now = DateTime(2026, 11, 26);
      final auth = AuthService(db, store, now: () => now);
      await auth.register('alice', 'secret1');
      final token = (await auth.currentToken())!;
      expect((await auth.verify(token))?.username, 'alice');

      // 篡改签名
      final tampered = '${token.substring(0, token.length - 2)}xx';
      expect(await auth.verify(tampered), isNull);
      // 篡改载荷（签名对不上）
      expect(await auth.verify('AAAA${token.substring(4)}'), isNull);

      // 过期
      now = now.add(AuthService.tokenTtl + const Duration(seconds: 1));
      expect(await auth.verify(token), isNull);
      now = DateTime(2026, 11, 26);

      // 登出后旧 Token 被吊销
      await auth.logout();
      expect(await auth.verify(token), isNull);
      expect(await AuthService(db, store).restore(), isNull);
    });

    test('演示账号只创建一次', () async {
      final auth = AuthService(db, MemoryTokenStore());
      await auth.ensureDemoAccount();
      await auth.ensureDemoAccount();
      expect((await db.query('users')).length, 1);
      await auth.login(AuthService.demoUsername, AuthService.demoPassword);
    });
  });
}
