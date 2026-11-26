/// 有效阅读时长计时器（纯逻辑，时间由调用方注入，便于单测）。
///
/// 口径：仅在「页面前台可见」且「最近 [idleThreshold] 内有交互（滚动 / 触摸）」时计时。
/// 用户把手机放着不动超过阈值，超出部分不计入阅读时长。
class ReadingTimer {
  ReadingTimer({this.idleThreshold = const Duration(seconds: 60)});

  final Duration idleThreshold;

  int _accumulatedMs = 0;
  int? _segmentStartMs;
  int? _lastInteractionMs;

  bool get running => _segmentStartMs != null;

  /// 页面可见（进入页面 / 回到前台）。
  void resume(int nowMs) {
    if (_segmentStartMs != null) return;
    _segmentStartMs = nowMs;
    _lastInteractionMs = nowMs;
  }

  /// 用户交互。若此前已因空闲超时而停表，则从现在重新起一段。
  void interact(int nowMs) {
    if (_segmentStartMs == null) return;
    final last = _lastInteractionMs ?? nowMs;
    if (nowMs - last > idleThreshold.inMilliseconds) {
      // 上一段只计到「最后一次交互 + 阈值」。
      _accumulatedMs += (last + idleThreshold.inMilliseconds) - _segmentStartMs!;
      _segmentStartMs = nowMs;
    }
    _lastInteractionMs = nowMs;
  }

  /// 页面不可见（离开页面 / 进入后台）。
  void pause(int nowMs) {
    if (_segmentStartMs == null) return;
    _accumulatedMs += _activeSegmentMs(nowMs);
    _segmentStartMs = null;
    _lastInteractionMs = null;
  }

  /// 截至 [nowMs] 的累计有效时长（毫秒）。
  int elapsedMs(int nowMs) => _accumulatedMs + _activeSegmentMs(nowMs);

  int _activeSegmentMs(int nowMs) {
    final start = _segmentStartMs;
    if (start == null) return 0;
    final last = _lastInteractionMs ?? start;
    final cap = last + idleThreshold.inMilliseconds;
    final end = nowMs < cap ? nowMs : cap;
    return end > start ? end - start : 0;
  }
}
