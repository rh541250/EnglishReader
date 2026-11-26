import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import '../domain/reading_math.dart';
import 'models.dart';

/// 阅读页某一时刻的完整快照。所有字段都是「绝对值」而非增量：
/// 同一份快照重复写入多次，结果与写入一次相同（幂等），
/// 因此节流落库、切后台落库、离开页面落库可以放心地重叠触发。
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.userId,
    required this.articleId,
    required this.position,
    required this.progress,
    required this.completed,
    required this.totalDurationMs,
    required this.sessionId,
    required this.sessionStartedAt,
    required this.sessionDurationMs,
    required this.nowMs,
  });

  final String userId;
  final String articleId;
  final ReadingPosition position;
  final double progress;
  final bool completed;

  /// 该文章累计阅读时长 = 进入页面时库里的值 + 本次阅读会话已计时长。
  final int totalDurationMs;

  final String sessionId;
  final int sessionStartedAt;
  final int sessionDurationMs;
  final int nowMs;
}

class ReadingStats {
  const ReadingStats({
    required this.totalDurationMs,
    required this.finishedCount,
    required this.streakDays,
    required this.todayDurationMs,
  });
  final int totalDurationMs;
  final int finishedCount;
  final int streakDays;
  final int todayDurationMs;
}

class ProgressRepository {
  ProgressRepository(this._db);
  final Database _db;

  /// 进度有变化时 +1，列表页据此刷新卡片上的进度环。
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<ReadingProgress?> get(String userId, String articleId) async {
    final rows = await _db.query(
      'reading_progress',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
      limit: 1,
    );
    return rows.isEmpty ? null : ReadingProgress.fromRow(rows.first);
  }

  /// 幂等写入一份快照。
  ///
  /// 没用 `INSERT ... ON CONFLICT DO UPDATE`：Android 9 及以下系统自带的 SQLite
  /// 早于 3.24，不支持该语法，这里用事务内「先 UPDATE、无命中再 INSERT」保证兼容。
  Future<void> save(ProgressSnapshot s) async {
    await _db.transaction((txn) async {
      final completedAt = s.completed ? s.nowMs : null;
      final updated = await txn.rawUpdate(
        '''
        UPDATE reading_progress SET
          paragraph_index  = ?,
          paragraph_offset = ?,
          progress         = ?,
          max_progress     = MAX(max_progress, ?),
          completed        = MAX(completed, ?),
          completed_at     = COALESCE(completed_at, ?),
          duration_ms      = MAX(duration_ms, ?),
          last_read_at     = MAX(last_read_at, ?),
          version          = version + 1,
          updated_at       = ?
        WHERE user_id = ? AND article_id = ?
      ''',
        [
          s.position.paragraphIndex,
          s.position.offsetFraction,
          s.progress,
          s.progress,
          s.completed ? 1 : 0,
          completedAt,
          s.totalDurationMs,
          s.nowMs,
          s.nowMs,
          s.userId,
          s.articleId,
        ],
      );
      if (updated == 0) {
        await txn.insert('reading_progress', {
          'user_id': s.userId,
          'article_id': s.articleId,
          'paragraph_index': s.position.paragraphIndex,
          'paragraph_offset': s.position.offsetFraction,
          'progress': s.progress,
          'max_progress': s.progress,
          'completed': s.completed ? 1 : 0,
          'completed_at': completedAt,
          'duration_ms': s.totalDurationMs,
          'last_read_at': s.nowMs,
          'version': 1,
          'updated_at': s.nowMs,
        });
      }

      final sessionUpdated = await txn.rawUpdate(
        'UPDATE reading_sessions SET duration_ms = MAX(duration_ms, ?) WHERE id = ?',
        [s.sessionDurationMs, s.sessionId],
      );
      if (sessionUpdated == 0) {
        await txn.insert('reading_sessions', {
          'id': s.sessionId,
          'user_id': s.userId,
          'article_id': s.articleId,
          'day': dayKey(DateTime.fromMillisecondsSinceEpoch(s.sessionStartedAt)),
          'started_at': s.sessionStartedAt,
          'duration_ms': s.sessionDurationMs,
        });
      }
    });
    revision.value++;
  }

  /// 有阅读记录的日期集合：当天累计阅读 ≥ 30 秒，或当天读完过文章。
  Future<Set<String>> activeDays(String userId) async {
    final byDuration = await _db.rawQuery(
      '''
      SELECT day FROM reading_sessions WHERE user_id = ?
      GROUP BY day HAVING SUM(duration_ms) >= 30000
    ''',
      [userId],
    );
    final byFinish = await _db.rawQuery(
      '''
      SELECT completed_at FROM reading_progress
      WHERE user_id = ? AND completed = 1 AND completed_at IS NOT NULL
    ''',
      [userId],
    );
    return {
      for (final r in byDuration) r['day'] as String,
      for (final r in byFinish) dayKey(DateTime.fromMillisecondsSinceEpoch(r['completed_at'] as int)),
    };
  }

  Future<ReadingStats> stats(String userId, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final total =
        Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COALESCE(SUM(duration_ms), 0) FROM reading_sessions WHERE user_id = ?', [userId]),
        ) ??
        0;
    final todayMs =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COALESCE(SUM(duration_ms), 0) FROM reading_sessions WHERE user_id = ? AND day = ?',
            [userId, dayKey(today)],
          ),
        ) ??
        0;
    final finished =
        Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM reading_progress WHERE user_id = ? AND completed = 1', [userId]),
        ) ??
        0;
    final days = await activeDays(userId);
    return ReadingStats(
      totalDurationMs: total,
      finishedCount: finished,
      streakDays: computeStreak(days, today, dayKey),
      todayDurationMs: todayMs,
    );
  }

  /// 近 [days] 天每天的阅读时长（毫秒），含没有记录的日期（补 0），按日期升序。
  Future<List<MapEntry<String, int>>> dailyDurations(String userId, {int days = 7, DateTime? now}) async {
    final today = now ?? DateTime.now();
    final keys = [for (var i = days - 1; i >= 0; i--) dayKey(DateTime(today.year, today.month, today.day - i))];
    final rows = await _db.rawQuery(
      '''
      SELECT day, SUM(duration_ms) AS ms FROM reading_sessions
      WHERE user_id = ? AND day >= ? GROUP BY day
    ''',
      [userId, keys.first],
    );
    final map = {for (final r in rows) r['day'] as String: (r['ms'] as num).toInt()};
    return [for (final k in keys) MapEntry(k, map[k] ?? 0)];
  }
}
