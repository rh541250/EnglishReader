import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';

class QueuedEvent {
  const QueuedEvent({
    required this.eventId,
    required this.name,
    required this.ts,
    required this.payload,
    required this.status,
    required this.attempts,
    this.sentAt,
    this.lastError,
  });

  final String eventId;
  final String name;
  final int ts;
  final Map<String, dynamic> payload;
  final int status;
  final int attempts;
  final int? sentAt;
  final String? lastError;

  factory QueuedEvent.fromRow(Map<String, Object?> r) => QueuedEvent(
    eventId: r['event_id'] as String,
    name: r['name'] as String,
    ts: r['ts'] as int,
    payload: jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
    status: r['status'] as int,
    attempts: r['attempts'] as int,
    sentAt: r['sent_at'] as int?,
    lastError: r['last_error'] as String?,
  );
}

class EventBatch {
  const EventBatch(this.batchId, this.events);
  final String batchId;
  final List<QueuedEvent> events;
  int get maxAttempts => events.fold(0, (m, e) => e.attempts > m ? e.attempts : m);
}

class UploadLogEntry {
  const UploadLogEntry({
    required this.batchId,
    required this.ts,
    required this.count,
    required this.ok,
    required this.durationMs,
    this.error,
  });
  final String batchId;
  final int ts;
  final int count;
  final bool ok;
  final int durationMs;
  final String? error;
}

class QueueCounts {
  const QueueCounts({required this.pending, required this.sending, required this.sent});
  final int pending;
  final int sending;
  final int sent;
  int get total => pending + sending + sent;
}

abstract final class EventStatus {
  static const pending = 0;
  static const sending = 1;
  static const sent = 2;
}

/// 本地事件队列。
class EventRepository {
  EventRepository(this._db);
  final Database _db;

  /// 入队。event_id 为主键，重复入队被忽略。
  Future<void> enqueue(Map<String, dynamic> payload) async {
    await _db.insert('event_queue', {
      'event_id': payload['event_id'],
      'name': payload['event'],
      'ts': payload['ts'],
      'session_id': payload['session_id'] ?? '',
      'user_id': payload['user_id'] ?? '',
      'payload_json': jsonEncode(payload),
      'status': EventStatus.pending,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 冷启动补报的前置步骤：上次进程被杀时停留在「上报中」的事件退回「待上报」。
  /// 这些事件服务端可能已收到，重发由服务端按 event_id 去重。
  Future<int> recoverInFlight() => _db.update(
    'event_queue',
    {'status': EventStatus.pending, 'batch_id': null},
    where: 'status = ?',
    whereArgs: [EventStatus.sending],
  );

  /// 取一批到期的待上报事件并标记为「上报中」（同一事务，避免并发重复取）。
  Future<EventBatch?> claimBatch({required int limit, required int nowMs}) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'event_queue',
        where: 'status = ? AND next_retry_at <= ?',
        whereArgs: [EventStatus.pending, nowMs],
        orderBy: 'ts ASC',
        limit: limit,
      );
      if (rows.isEmpty) return null;
      final batchId = uuidV4();
      final ids = rows.map((r) => r['event_id'] as String).toList();
      await txn.rawUpdate(
        'UPDATE event_queue SET status = ?, batch_id = ? WHERE event_id IN (${List.filled(ids.length, '?').join(',')})',
        [EventStatus.sending, batchId, ...ids],
      );
      return EventBatch(batchId, rows.map(QueuedEvent.fromRow).toList());
    });
  }

  Future<void> markSent(String batchId, {required int nowMs, required int count, required int durationMs}) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE event_queue SET status = ?, sent_at = ?, last_error = NULL WHERE batch_id = ? AND status = ?',
        [EventStatus.sent, nowMs, batchId, EventStatus.sending],
      );
      await txn.insert('upload_log', {
        'batch_id': batchId,
        'ts': nowMs,
        'event_count': count,
        'ok': 1,
        'duration_ms': durationMs,
      });
    });
  }

  Future<void> markFailed(
    String batchId, {
    required int nowMs,
    required int nextRetryAt,
    required int count,
    required int durationMs,
    required String error,
  }) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE event_queue
        SET status = ?, attempts = attempts + 1, next_retry_at = ?, last_error = ?, batch_id = NULL
        WHERE batch_id = ? AND status = ?
      ''',
        [EventStatus.pending, nextRetryAt, error, batchId, EventStatus.sending],
      );
      await txn.insert('upload_log', {
        'batch_id': batchId,
        'ts': nowMs,
        'event_count': count,
        'ok': 0,
        'duration_ms': durationMs,
        'error': error,
      });
    });
  }

  /// 手动「立即上报」时清除退避等待。
  Future<void> clearBackoff() =>
      _db.rawUpdate('UPDATE event_queue SET next_retry_at = 0 WHERE status = ?', [EventStatus.pending]);

  Future<QueueCounts> counts() async {
    final rows = await _db.rawQuery('SELECT status, COUNT(*) AS n FROM event_queue GROUP BY status');
    final m = {for (final r in rows) r['status'] as int: r['n'] as int};
    return QueueCounts(
      pending: m[EventStatus.pending] ?? 0,
      sending: m[EventStatus.sending] ?? 0,
      sent: m[EventStatus.sent] ?? 0,
    );
  }

  /// 最早的下次重试时间（仅统计仍在退避中的待上报事件）。
  Future<int?> nextRetryAt(int nowMs) async {
    final v = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT MIN(next_retry_at) FROM event_queue WHERE status = ? AND next_retry_at > ?', [
        EventStatus.pending,
        nowMs,
      ]),
    );
    return v;
  }

  Future<List<QueuedEvent>> recent({int limit = 50, int? status}) async {
    final rows = await _db.query(
      'event_queue',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: 'ts DESC',
      limit: limit,
    );
    return rows.map(QueuedEvent.fromRow).toList();
  }

  Future<List<UploadLogEntry>> recentUploads({int limit = 20}) async {
    final rows = await _db.query('upload_log', orderBy: 'id DESC', limit: limit);
    return [
      for (final r in rows)
        UploadLogEntry(
          batchId: r['batch_id'] as String,
          ts: r['ts'] as int,
          count: r['event_count'] as int,
          ok: (r['ok'] as int) == 1,
          durationMs: r['duration_ms'] as int,
          error: r['error'] as String?,
        ),
    ];
  }

  /// 已上报事件保留 [keep] 用于本地分析查询，更早的清理掉，防止队列表无限增长。
  Future<int> purgeSent({required int nowMs, Duration keep = const Duration(days: 30)}) => _db.delete(
    'event_queue',
    where: 'status = ? AND sent_at < ?',
    whereArgs: [EventStatus.sent, nowMs - keep.inMilliseconds],
  );

  // ---- Mock 接收端 ----

  /// 模拟服务端落库：按 event_id 去重，返回实际新增条数。
  Future<int> mockServerAccept(List<QueuedEvent> events, int nowMs) async {
    var accepted = 0;
    await _db.transaction((txn) async {
      for (final e in events) {
        final exists = await txn.query(
          'mock_server_events',
          columns: ['event_id'],
          where: 'event_id = ?',
          whereArgs: [e.eventId],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;
        await txn.insert('mock_server_events', {
          'event_id': e.eventId,
          'name': e.name,
          'ts': e.ts,
          'received_at': nowMs,
        });
        accepted++;
      }
    });
    return accepted;
  }

  Future<int> mockServerCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM mock_server_events')) ?? 0;
}
