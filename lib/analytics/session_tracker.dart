import '../core/ids.dart';

/// 会话切分（纯逻辑）。
///
/// 规则：冷启动开启新会话；App 进入后台超过 [threshold]（默认 30 秒）后再回到前台，
/// 视为新会话；不足阈值（切出去回条消息）沿用原会话。
class SessionTracker {
  SessionTracker({this.threshold = const Duration(seconds: 30), String Function()? idGenerator})
    : _newId = idGenerator ?? uuidV4 {
    _sessionId = _newId();
  }

  final Duration threshold;
  final String Function() _newId;

  late String _sessionId;
  int? _backgroundedAt;

  String get sessionId => _sessionId;

  void onBackground(int nowMs) => _backgroundedAt ??= nowMs;

  /// 回到前台。返回后台停留毫秒数；若因此开启了新会话，[SessionResume.newSession] 为 true。
  SessionResume onForeground(int nowMs) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return const SessionResume(0, false);
    final away = nowMs - since;
    if (away > threshold.inMilliseconds) {
      _sessionId = _newId();
      return SessionResume(away, true);
    }
    return SessionResume(away, false);
  }
}

class SessionResume {
  const SessionResume(this.backgroundMs, this.newSession);
  final int backgroundMs;
  final bool newSession;
}
