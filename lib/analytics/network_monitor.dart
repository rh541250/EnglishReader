import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 轻量联网探测：对公共 DNS 的 53 端口做一次短超时 TCP 连接。
///
/// 不引入 connectivity 插件：插件只能告诉「连着 Wi-Fi」，不能说明「真的通外网」；
/// 而本项目只需要一个布尔值来决定是否尝试上报、以及是否记一次「离线命中」。
class NetworkMonitor {
  NetworkMonitor({Future<bool> Function()? probe}) : _probe = probe ?? _defaultProbe;

  final Future<bool> Function() _probe;

  /// 最近一次探测结果。
  final ValueNotifier<bool> online = ValueNotifier(true);

  /// 调试面板「模拟离线」开关：打开后一律视为离线，方便在模拟器上演示离线链路。
  final ValueNotifier<bool> simulateOffline = ValueNotifier(false);

  int _lastProbeMs = 0;
  Future<bool>? _inFlight;

  bool get isOnline => !simulateOffline.value && online.value;

  Future<bool> check({Duration maxAge = Duration.zero}) {
    if (simulateOffline.value) return Future.value(false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProbeMs < maxAge.inMilliseconds) return Future.value(online.value);
    return _inFlight ??= _probe()
        .then((ok) {
          online.value = ok;
          _lastProbeMs = DateTime.now().millisecondsSinceEpoch;
          return ok;
        })
        .whenComplete(() => _inFlight = null);
  }

  static Future<bool> _defaultProbe() async {
    for (final host in const ['223.5.5.5', '1.1.1.1']) {
      try {
        final socket = await Socket.connect(host, 53, timeout: const Duration(milliseconds: 1500));
        socket.destroy();
        return true;
      } catch (_) {
        // 换下一个探测点。
      }
    }
    return false;
  }
}
