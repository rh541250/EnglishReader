import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'event_repository.dart';
import 'network_monitor.dart';

class TransportException implements Exception {
  const TransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 上报通道。失败抛异常，由上报器负责退避重试。
abstract class EventTransport {
  String get description;
  Future<void> send(EventBatch batch);
}

/// Mock 接收端：没有真实后端时使用。
///
/// 行为尽量贴近真实链路：无网络时失败、可注入服务端错误、有网络延迟，
/// 成功后把事件按 event_id 去重写入本地的 mock_server_events 表（扮演服务端）。
class MockTransport implements EventTransport {
  MockTransport(this._repo, this._network, {Random? random}) : _random = random ?? Random();

  final EventRepository _repo;
  final NetworkMonitor _network;
  final Random _random;

  /// 调试面板「模拟服务端 500」开关。
  final ValueNotifier<bool> failNext = ValueNotifier(false);

  @override
  String get description => 'Mock 接收端（本地 mock_server_events 表）';

  @override
  Future<void> send(EventBatch batch) async {
    if (!await _network.check()) {
      throw const TransportException('网络不可用');
    }
    await Future<void>.delayed(Duration(milliseconds: 120 + _random.nextInt(240)));
    if (failNext.value) {
      throw const TransportException('HTTP 500（模拟服务端错误）');
    }
    await _repo.mockServerAccept(batch.events, DateTime.now().millisecondsSinceEpoch);
  }
}

/// 真实 HTTP 上报：`--dart-define=ANALYTICS_ENDPOINT=https://...` 时启用。
/// 请求体 `{batch_id, sent_at, events:[...]}`，2xx 视为成功。
class HttpTransport implements EventTransport {
  HttpTransport(this.endpoint);
  final Uri endpoint;

  @override
  String get description => 'HTTP POST $endpoint';

  @override
  Future<void> send(EventBatch batch) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(endpoint);
      req.headers.contentType = ContentType.json;
      req.add(
        utf8.encode(
          jsonEncode({
            'batch_id': batch.batchId,
            'sent_at': DateTime.now().millisecondsSinceEpoch,
            'events': [for (final e in batch.events) e.payload],
          }),
        ),
      );
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain<void>();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw TransportException('HTTP ${resp.statusCode}');
      }
    } on TransportException {
      rethrow;
    } catch (e) {
      throw TransportException('请求失败: $e');
    } finally {
      client.close(force: true);
    }
  }
}
