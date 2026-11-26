import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import 'event_schema.dart';

/// 基于本地事件表的分析查询（调试面板展示，README 附等价 SQL）。
///
/// 为兼容没有 JSON1 扩展的旧版 Android 系统 SQLite，这里用 SQL 按事件名 + 时间
/// 走索引取行，再在 Dart 里解析 props 聚合；口径与 README 里的 json_extract 版 SQL 一致。
class AnalyticsQueries {
  AnalyticsQueries(this._db);
  final Database _db;

  Future<List<Map<String, dynamic>>> _events(List<String> names, int sinceMs) async {
    final rows = await _db.rawQuery(
      'SELECT name, ts, user_id, payload_json FROM event_queue '
      'WHERE name IN (${List.filled(names.length, '?').join(',')}) AND ts >= ? ORDER BY ts',
      [...names, sinceMs],
    );
    return [
      for (final r in rows)
        {
          'name': r['name'],
          'ts': r['ts'],
          'user_id': r['user_id'],
          'props': (jsonDecode(r['payload_json'] as String) as Map<String, dynamic>)['props'] ?? const {},
        },
    ];
  }

  static int _sinceDays(int days, DateTime now) =>
      DateTime(now.year, now.month, now.day - (days - 1)).millisecondsSinceEpoch;

  /// 查询 1：近 7 日阅读时长分布。
  /// 口径：read_duration.duration_ms 按事件发生日（本地时区）求和；
  /// 另按「单次阅读时长」分桶统计次数。
  Future<DurationReport> readingDurationLast7Days({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final events = await _events([Ev.readDuration], _sinceDays(7, today));
    final perDay = <String, int>{
      for (var i = 6; i >= 0; i--) dayKey(DateTime(today.year, today.month, today.day - i)): 0,
    };
    final buckets = <String, int>{'<1 分钟': 0, '1-3 分钟': 0, '3-5 分钟': 0, '≥5 分钟': 0};
    for (final e in events) {
      final ms = ((e['props'] as Map)['duration_ms'] as num?)?.toInt() ?? 0;
      final day = dayKey(DateTime.fromMillisecondsSinceEpoch(e['ts'] as int));
      if (perDay.containsKey(day)) perDay[day] = perDay[day]! + ms;
      final bucket = ms < 60000
          ? '<1 分钟'
          : ms < 180000
          ? '1-3 分钟'
          : ms < 300000
          ? '3-5 分钟'
          : '≥5 分钟';
      buckets[bucket] = buckets[bucket]! + 1;
    }
    return DurationReport(perDay, buckets);
  }

  /// 查询 2：近 7 日「曝光 → 打开 → 读到 50% → 读完」漏斗。
  /// 口径：每一步按 (user_id, article_id) 去重计数；后一步必须出现在前一步的集合内。
  Future<List<FunnelStep>> readingFunnelLast7Days({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final events = await _events([
      Ev.articleExpose,
      Ev.articleOpen,
      Ev.readProgress,
      Ev.articleFinish,
    ], _sinceDays(7, today));
    final exposed = <String>{}, opened = <String>{}, half = <String>{}, finished = <String>{};
    for (final e in events) {
      final props = e['props'] as Map;
      final key = '${e['user_id']}|${props['article_id']}';
      switch (e['name']) {
        case Ev.articleExpose:
          exposed.add(key);
        case Ev.articleOpen:
          opened.add(key);
        case Ev.readProgress:
          if (((props['depth'] as num?) ?? 0) >= 50) half.add(key);
        case Ev.articleFinish:
          finished.add(key);
      }
    }
    // 从生词本等入口直接打开的文章没有曝光，漏斗以「打开」之前的并集为起点。
    final step1 = exposed.union(opened);
    final step2 = opened;
    final step3 = half.intersection(step2);
    final step4 = finished.intersection(step2);
    return [
      FunnelStep('曝光', step1.length, 1),
      FunnelStep('打开', step2.length, _rate(step2.length, step1.length)),
      FunnelStep('读到 50%', step3.length, _rate(step3.length, step2.length)),
      FunnelStep('读完', step4.length, _rate(step4.length, step2.length)),
    ];
  }

  /// 查询 3：近 7 日取词与收藏。收藏率 = 收藏次数 / 取词次数；并给出取词 Top 词。
  Future<WordReport> wordReportLast7Days({DateTime? now, int top = 5}) async {
    final today = now ?? DateTime.now();
    final events = await _events([Ev.wordLookup, Ev.wordCollect], _sinceDays(7, today));
    var lookups = 0, collects = 0;
    final freq = <String, int>{};
    for (final e in events) {
      final word = ((e['props'] as Map)['word'] as String?) ?? '';
      if (e['name'] == Ev.wordLookup) {
        lookups++;
        freq[word] = (freq[word] ?? 0) + 1;
      } else {
        collects++;
      }
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return WordReport(lookups, collects, _rate(collects, lookups), sorted.take(top).toList());
  }

  static double _rate(int a, int b) => b == 0 ? 0 : a / b;
}

class DurationReport {
  const DurationReport(this.perDayMs, this.buckets);
  final Map<String, int> perDayMs;
  final Map<String, int> buckets;
}

class FunnelStep {
  const FunnelStep(this.label, this.count, this.rate);
  final String label;
  final int count;

  /// 相对上一步（读完相对「打开」）的转化率。
  final double rate;
}

class WordReport {
  const WordReport(this.lookups, this.collects, this.collectRate, this.topWords);
  final int lookups;
  final int collects;
  final double collectRate;
  final List<MapEntry<String, int>> topWords;
}
