import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'event_repository.dart';
import 'transport.dart';

/// 失败退避：第 n 次失败后等待 base × 2^(n-1)，封顶 [max]，再乘 [jitter]（0.8~1.2）打散重试时间。
/// 5s → 10s → 20s → 40s → … → 10min。
Duration backoffDelay(
  int attempts, {
  Duration base = const Duration(seconds: 5),
  Duration max = const Duration(minutes: 10),
  double jitter = 1.0,
}) {
  if (attempts <= 0) return Duration.zero;
  final exp = attempts - 1 > 20 ? 20 : attempts - 1;
  final raw = base.inMilliseconds * pow(2, exp);
  final capped = raw > max.inMilliseconds ? max.inMilliseconds : raw.toInt();
  return Duration(milliseconds: (capped * jitter).round());
}

/// 批量上报器。
///
/// 触发时机：① 冷启动补报 ② 每 [flushInterval] 定时 ③ 待上报累计达到 [batchSize]
/// ④ App 切后台 ⑤ 调试面板手动触发。
/// 全程异步，与 UI 线程只通过 sqflite 的平台通道交互，不阻塞渲染。
class EventUploader {
  EventUploader(
    this._repo,
    this._transport, {
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 30),
    Random? random,
    int Function()? nowMs,
  }) : _random = random ?? Random(),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final EventRepository _repo;
  final EventTransport _transport;
  final int batchSize;
  final Duration flushInterval;
  final Random _random;
  final int Function() _nowMs;

  Timer? _timer;
  bool _flushing = false;
  int _enqueuedSinceFlush = 0;

  /// 每次上报尝试结束后 +1，调试面板据此刷新。
  final ValueNotifier<int> revision = ValueNotifier(0);

  EventTransport get transport => _transport;

  Future<void> start() async {
    await _repo.recoverInFlight();
    await _repo.purgeSent(nowMs: _nowMs());
    _timer?.cancel();
    _timer = Timer.periodic(flushInterval, (_) => flush());
    unawaited(flush());
  }

  void dispose() => _timer?.cancel();

  void onEnqueued() {
    _enqueuedSinceFlush++;
    if (_enqueuedSinceFlush >= batchSize) unawaited(flush());
  }

  /// 把到期的待上报事件一批批发出去，遇到失败即停（等待退避）。
  /// [force] 为 true 时忽略退避等待（手动触发）。返回本次成功上报的条数。
  Future<int> flush({bool force = false}) async {
    if (_flushing) return 0;
    _flushing = true;
    _enqueuedSinceFlush = 0;
    var sent = 0;
    try {
      if (force) await _repo.clearBackoff();
      while (true) {
        final batch = await _repo.claimBatch(limit: batchSize, nowMs: _nowMs());
        if (batch == null) break;
        final started = _nowMs();
        try {
          await _transport.send(batch);
          await _repo.markSent(
            batch.batchId,
            nowMs: _nowMs(),
            count: batch.events.length,
            durationMs: _nowMs() - started,
          );
          sent += batch.events.length;
        } catch (e) {
          final delay = backoffDelay(batch.maxAttempts + 1, jitter: 0.8 + _random.nextDouble() * 0.4);
          await _repo.markFailed(
            batch.batchId,
            nowMs: _nowMs(),
            nextRetryAt: _nowMs() + delay.inMilliseconds,
            count: batch.events.length,
            durationMs: _nowMs() - started,
            error: e.toString(),
          );
          break;
        }
      }
    } finally {
      _flushing = false;
      revision.value++;
    }
    return sent;
  }
}
