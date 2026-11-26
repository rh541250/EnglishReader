import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import 'event_repository.dart';
import 'event_schema.dart';
import 'network_monitor.dart';
import 'session_tracker.dart';
import 'uploader.dart';

const String kAppVersion = '1.0.0';

/// 埋点入口。业务代码只调用 [track]。
///
/// track 只做三件事：补齐公共参数、（debug 下）校验事件模型、写入本地队列。
/// 不发网络请求、不 await，调用方零等待；上报由 [EventUploader] 独立完成。
class Analytics {
  Analytics({
    required this.repo,
    required this.uploader,
    required this.network,
    required this.deviceId,
    required this.platform,
    required this.userId,
    SessionTracker? session,
    this.now = systemNow,
  }) : _session = session ?? SessionTracker();

  final EventRepository repo;
  final EventUploader uploader;
  final NetworkMonitor network;
  final String Function() userId;
  final SessionTracker _session;
  final NowFn now;

  final String deviceId;
  final String platform;

  /// 本会话已曝光的文章，保证「同一会话同一文章只报一次曝光」。
  final Set<String> _exposed = {};

  /// 最近写入队列的 Future，测试与「切后台前落库」时可等待。
  Future<void> _lastWrite = Future.value();
  Future<void> get idle => _lastWrite;

  /// 每入队一条 +1，调试面板据此刷新。
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get sessionId => _session.sessionId;

  void track(String name, [Map<String, Object?> props = const {}]) {
    assert(() {
      final spec = kEventSpecByName[name];
      final problems = spec == null ? ['未登记的事件 $name'] : spec.validate(props);
      if (problems.isNotEmpty) debugPrint('[analytics] ⚠️ ${problems.join('; ')}');
      return true;
    }());

    final payload = <String, dynamic>{
      'event_id': uuidV4(),
      'event': name,
      'ts': now().millisecondsSinceEpoch,
      'device_id': deviceId,
      'user_id': userId(),
      'session_id': _session.sessionId,
      'app_version': kAppVersion,
      'platform': platform,
      'network': network.isOnline ? 'online' : 'offline',
      'props': {
        for (final e in props.entries)
          if (e.value != null) e.key: e.value,
      },
    };
    if (kDebugMode) debugPrint('[analytics] $name ${payload['props']}');

    _lastWrite = _lastWrite
        .then((_) => repo.enqueue(payload))
        .then((_) {
          uploader.onEnqueued();
          revision.value++;
        })
        .catchError((Object e) {
          debugPrint('[analytics] enqueue failed: $e');
        });
  }

  /// 冷启动。
  void onColdStart() {
    track(Ev.appOpen, {'launch_type': 'cold'});
    track(Ev.sessionStart, {'reason': 'cold_start'});
  }

  void onAppBackground() {
    _session.onBackground(now().millisecondsSinceEpoch);
    // 切后台是最后的可靠时机：把队列尽量发出去。
    unawaited(_lastWrite.then((_) => uploader.flush()));
  }

  void onAppForeground() {
    final r = _session.onForeground(now().millisecondsSinceEpoch);
    unawaited(network.check());
    if (r.newSession) {
      _exposed.clear();
      track(Ev.appOpen, {'launch_type': 'warm', 'background_ms': r.backgroundMs});
      track(Ev.sessionStart, {'reason': 'background_timeout'});
    }
  }

  /// 曝光去重：返回 true 表示本会话首次曝光，应上报。
  bool markExposed(String articleId) => _exposed.add(articleId);
}
