import 'dart:math';

import 'package:english_reader/analytics/analytics.dart';
import 'package:english_reader/analytics/analytics_queries.dart';
import 'package:english_reader/analytics/event_repository.dart';
import 'package:english_reader/analytics/event_schema.dart';
import 'package:english_reader/analytics/network_monitor.dart';
import 'package:english_reader/analytics/session_tracker.dart';
import 'package:english_reader/analytics/transport.dart';
import 'package:english_reader/analytics/uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 可控的上报通道：记录收到的批次，可让接下来的若干次失败。
class FakeTransport implements EventTransport {
  FakeTransport(this.repo);
  final EventRepository repo;
  int failures = 0;
  bool crashAfterServerAccept = false;
  final List<List<String>> batches = [];

  @override
  String get description => 'fake';

  @override
  Future<void> send(EventBatch batch) async {
    if (failures > 0) {
      failures--;
      throw const TransportException('HTTP 500');
    }
    batches.add([for (final e in batch.events) e.eventId]);
    await repo.mockServerAccept(batch.events, 1);
    if (crashAfterServerAccept) {
      // 服务端已落库，但客户端没收到响应。
      throw const TransportException('timeout');
    }
  }
}

void main() {
  late Database db;
  late EventRepository repo;
  late FakeTransport transport;
  var now = 0;

  Analytics makeAnalytics(EventUploader uploader, {SessionTracker? session, String user = 'u1'}) => Analytics(
    repo: repo,
    uploader: uploader,
    network: NetworkMonitor(probe: () async => true),
    deviceId: 'device-1',
    platform: 'ios',
    userId: () => user,
    session: session,
    now: () => DateTime.fromMillisecondsSinceEpoch(now),
  );

  EventUploader makeUploader({int batchSize = 20}) => EventUploader(
    repo,
    transport,
    batchSize: batchSize,
    flushInterval: const Duration(hours: 1),
    random: Random(1),
    nowMs: () => now,
  );

  setUp(() async {
    db = await openTestDb();
    repo = EventRepository(db);
    transport = FakeTransport(repo);
    now = DateTime(2026, 11, 26, 12).millisecondsSinceEpoch;
  });
  tearDown(() async => db.close());

  test('事件模型：命名规范、必填 / 未登记参数校验', () {
    for (final spec in kEventSpecs) {
      expect(RegExp(r'^[a-z]+(_[a-z]+)+$').hasMatch(spec.name), isTrue, reason: spec.name);
    }
    final spec = kEventSpecByName[Ev.articleOpen]!;
    expect(spec.validate({'article_id': 'a1', 'source': 'list'}), isEmpty);
    expect(spec.validate({'article_id': 'a1'}), hasLength(1)); // 缺 source
    expect(spec.validate({'article_id': 'a1', 'source': 'list', 'oops': 1}), hasLength(1));
  });

  test('track：补齐公共参数并落入本地队列', () async {
    final uploader = makeUploader();
    final analytics = makeAnalytics(uploader);
    analytics.track(Ev.articleOpen, {'article_id': 'a001', 'source': 'list', 'category': null});
    await analytics.idle;
    final e = (await repo.recent()).single;
    expect(e.name, Ev.articleOpen);
    expect(e.status, EventStatus.pending);
    for (final key in kCommonParams) {
      expect(e.payload.containsKey(key), isTrue, reason: '缺公共参数 $key');
    }
    expect(e.payload['user_id'], 'u1');
    expect(e.payload['device_id'], 'device-1');
    expect(e.payload['props'], {'article_id': 'a001', 'source': 'list'}); // null 值被剔除
  });

  test('入队幂等：相同 event_id 只保留一条', () async {
    final payload = {'event_id': 'dup', 'event': Ev.pageView, 'ts': now, 'session_id': 's', 'user_id': 'u'};
    await repo.enqueue(payload);
    await repo.enqueue(payload);
    expect((await repo.counts()).pending, 1);
  });

  test('批量上报：按批次大小分批，成功后标记已上报', () async {
    // 入队用一个不会自动触发的上报器，避免与下面的手动 flush 并发。
    final analytics = makeAnalytics(makeUploader(batchSize: 100000));
    final uploader = makeUploader(batchSize: 20);
    for (var i = 0; i < 45; i++) {
      now++;
      analytics.track(Ev.pageView, {'page': 'p$i'});
    }
    await analytics.idle;
    await uploader.flush();
    expect(transport.batches.map((b) => b.length), [20, 20, 5]);
    final counts = await repo.counts();
    expect(counts.pending, 0);
    expect(counts.sent, 45);
    expect(await repo.mockServerCount(), 45);
  });

  test('达到批次大小时自动触发上报', () async {
    final uploader = makeUploader(batchSize: 5);
    final analytics = makeAnalytics(uploader);
    for (var i = 0; i < 5; i++) {
      analytics.track(Ev.pageView, {'page': 'p$i'});
    }
    await analytics.idle;
    // 没有手动调用 flush：等自动触发的那次上报跑完。
    for (var i = 0; i < 100 && (await repo.counts()).sent < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await repo.counts()).sent, 5);
    expect(transport.batches.single.length, 5);
  });

  test('失败退避重试：失败后事件留在队列，未到重试时间不发，到时间后补发', () async {
    final uploader = makeUploader();
    final analytics = makeAnalytics(uploader);
    analytics.track(Ev.pageView, {'page': 'a'});
    analytics.track(Ev.pageView, {'page': 'b'});
    await analytics.idle;

    transport.failures = 1;
    expect(await uploader.flush(), 0);
    var events = await repo.recent();
    expect(events.every((e) => e.status == EventStatus.pending && e.attempts == 1), isTrue);
    expect(events.first.lastError, contains('500'));

    // 退避窗口内：不发送。
    now += 1000;
    expect(await uploader.flush(), 0);
    expect(transport.batches, isEmpty);

    // 第一次失败的退避约 5s（±20% 抖动），过了窗口后成功补发。
    now += 6000;
    expect(await uploader.flush(), 2);
    events = await repo.recent();
    expect(events.every((e) => e.status == EventStatus.sent), isTrue);

    final log = await repo.recentUploads();
    expect(log.map((l) => l.ok), [true, false]); // 最近的在前
  });

  test('退避时长：指数增长、封顶 10 分钟', () {
    expect(backoffDelay(0), Duration.zero);
    expect(backoffDelay(1), const Duration(seconds: 5));
    expect(backoffDelay(2), const Duration(seconds: 10));
    expect(backoffDelay(3), const Duration(seconds: 20));
    expect(backoffDelay(4), const Duration(seconds: 40));
    expect(backoffDelay(20), const Duration(minutes: 10));
    expect(backoffDelay(1000), const Duration(minutes: 10));
    expect(backoffDelay(2, jitter: 1.2), const Duration(seconds: 12));
  });

  test('离线缓存 → 恢复联网后补报，顺序与时间戳保持', () async {
    final uploader = makeUploader();
    final analytics = makeAnalytics(uploader);
    transport.failures = 999; // 一直离线
    for (var i = 0; i < 3; i++) {
      now += 1000;
      analytics.track(Ev.articleOpen, {'article_id': 'a00$i', 'source': 'list'});
      await analytics.idle;
      await uploader.flush(force: true);
    }
    expect((await repo.counts()).pending, 3);

    transport.failures = 0;
    expect(await uploader.flush(force: true), 3);
    expect(transport.batches.single.length, 3);
    final sent = await repo.recent();
    expect(sent.map((e) => e.payload['props']['article_id']), ['a002', 'a001', 'a000']);
  });

  test('冷启动补报：上次进程被杀时卡在「上报中」的事件会被重发，服务端按 event_id 去重', () async {
    final uploader = makeUploader();
    final analytics = makeAnalytics(uploader);
    analytics.track(Ev.pageView, {'page': 'a'});
    analytics.track(Ev.pageView, {'page': 'b'});
    await analytics.idle;

    // 第一次：服务端其实已收到，但客户端在拿到响应前「被杀」——事件停留在 sending。
    final claimed = await repo.claimBatch(limit: 20, nowMs: now);
    await repo.mockServerAccept(claimed!.events, now);
    expect((await repo.counts()).sending, 2);
    expect(await repo.mockServerCount(), 2);

    // 冷启动：start() 把 sending 退回 pending 并立即补报。
    final restarted = makeUploader();
    await restarted.start();
    await pumpEventQueue();
    await restarted.flush();
    restarted.dispose();

    expect((await repo.counts()).sent, 2);
    // 重发了一遍，但服务端没有重复数据。
    expect(transport.batches.single.length, 2);
    expect(await repo.mockServerCount(), 2);
  });

  test('会话切分：后台超过 30 秒开新会话，否则沿用', () {
    var n = 0;
    final s = SessionTracker(idGenerator: () => 'session-${++n}');
    expect(s.sessionId, 'session-1');

    s.onBackground(1000);
    final short = s.onForeground(1000 + 29000);
    expect(short.newSession, isFalse);
    expect(s.sessionId, 'session-1');

    s.onBackground(100000);
    final long = s.onForeground(100000 + 30001);
    expect(long.newSession, isTrue);
    expect(long.backgroundMs, 30001);
    expect(s.sessionId, 'session-2');

    // 没有进过后台就回前台（冷启动）：不切分。
    expect(s.onForeground(999999).newSession, isFalse);
  });

  test('回到前台开启新会话时补发 app_open / session_start，并重置曝光去重', () async {
    final uploader = makeUploader();
    var n = 0;
    final analytics = makeAnalytics(uploader, session: SessionTracker(idGenerator: () => 's${++n}'));
    expect(analytics.markExposed('a001'), isTrue);
    expect(analytics.markExposed('a001'), isFalse); // 同会话只曝光一次

    analytics.onAppBackground();
    now += 60000;
    analytics.onAppForeground();
    await analytics.idle;

    final names = (await repo.recent()).map((e) => e.name).toSet();
    expect(names, containsAll([Ev.appOpen, Ev.sessionStart]));
    expect(analytics.sessionId, 's2');
    expect(analytics.markExposed('a001'), isTrue);
  });

  group('分析查询', () {
    Future<void> seedEvents() async {
      // 只入队、不上报：分析查询直接读本地事件表。
      final uploader = makeUploader(batchSize: 100000);
      final today = DateTime(2026, 11, 26, 12);
      Future<void> at(DateTime t, String user, String name, Map<String, Object?> props) async {
        now = t.millisecondsSinceEpoch;
        final a = makeAnalytics(uploader, user: user);
        a.track(name, props);
        await a.idle;
      }

      // u1：曝光 a1 a2 a3，打开 a1 a2，a1 读完，a2 读到 50%。
      for (final id in ['a1', 'a2', 'a3']) {
        await at(today, 'u1', Ev.articleExpose, {'article_id': id, 'position': 0});
      }
      await at(today, 'u1', Ev.articleOpen, {'article_id': 'a1', 'source': 'list'});
      await at(today, 'u1', Ev.articleOpen, {'article_id': 'a1', 'source': 'list'}); // 重复打开，去重
      await at(today, 'u1', Ev.articleOpen, {'article_id': 'a2', 'source': 'list'});
      await at(today, 'u1', Ev.readProgress, {'article_id': 'a1', 'depth': 50});
      await at(today, 'u1', Ev.readProgress, {'article_id': 'a1', 'depth': 100});
      await at(today, 'u1', Ev.readProgress, {'article_id': 'a2', 'depth': 25});
      await at(today, 'u1', Ev.readProgress, {'article_id': 'a2', 'depth': 50});
      await at(today, 'u1', Ev.articleFinish, {'article_id': 'a1', 'total_duration_ms': 240000});
      // u2：曝光并打开 a1，没读到一半。
      await at(today, 'u2', Ev.articleExpose, {'article_id': 'a1', 'position': 0});
      await at(today, 'u2', Ev.articleOpen, {'article_id': 'a1', 'source': 'list'});

      // 阅读时长：今天 4 分钟 + 30 秒，两天前 2 分钟，8 天前的不计入。
      await at(today, 'u1', Ev.readDuration, {'article_id': 'a1', 'duration_ms': 240000, 'max_depth': 100});
      await at(today, 'u1', Ev.readDuration, {'article_id': 'a2', 'duration_ms': 30000, 'max_depth': 50});
      await at(today.subtract(const Duration(days: 2)), 'u1', Ev.readDuration, {
        'article_id': 'a3',
        'duration_ms': 120000,
        'max_depth': 80,
      });
      await at(today.subtract(const Duration(days: 8)), 'u1', Ev.readDuration, {
        'article_id': 'a3',
        'duration_ms': 999000,
        'max_depth': 80,
      });

      // 取词与收藏
      for (final w in ['resilient', 'resilient', 'supply', 'margin']) {
        await at(today, 'u1', Ev.wordLookup, {'article_id': 'a1', 'word': w});
      }
      await at(today, 'u1', Ev.wordCollect, {'article_id': 'a1', 'word': 'resilient'});
      now = today.millisecondsSinceEpoch;
    }

    test('近 7 日阅读时长分布', () async {
      await seedEvents();
      final r = await AnalyticsQueries(db).readingDurationLast7Days(now: DateTime(2026, 11, 26, 12));
      expect(r.perDayMs.keys.first, '2026-11-20');
      expect(r.perDayMs.keys.last, '2026-11-26');
      expect(r.perDayMs['2026-11-26'], 270000);
      expect(r.perDayMs['2026-11-24'], 120000);
      expect(r.perDayMs['2026-11-25'], 0);
      expect(r.perDayMs.values.reduce((a, b) => a + b), 390000); // 8 天前的不计入
      expect(r.buckets, {'<1 分钟': 1, '1-3 分钟': 1, '3-5 分钟': 1, '≥5 分钟': 0});
    });

    test('曝光 → 打开 → 读到 50% → 读完 漏斗', () async {
      await seedEvents();
      final f = await AnalyticsQueries(db).readingFunnelLast7Days(now: DateTime(2026, 11, 26, 12));
      expect(f.map((s) => s.count), [4, 3, 2, 1]);
      expect(f[1].rate, closeTo(3 / 4, 1e-9));
      expect(f[2].rate, closeTo(2 / 3, 1e-9));
      expect(f[3].rate, closeTo(1 / 3, 1e-9));
    });

    test('取词收藏率与 Top 词', () async {
      await seedEvents();
      final w = await AnalyticsQueries(db).wordReportLast7Days(now: DateTime(2026, 11, 26, 12));
      expect(w.lookups, 4);
      expect(w.collects, 1);
      expect(w.collectRate, 0.25);
      expect(w.topWords.first.key, 'resilient');
      expect(w.topWords.first.value, 2);
    });
  });
}
