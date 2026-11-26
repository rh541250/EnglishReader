import 'dart:async';

import 'package:flutter/widgets.dart';

/// 曝光判定：元素在视口内的可见面积 ≥ [minFraction] 且连续停留 ≥ [minDuration] 记一次曝光。
///
/// 用法：列表外层放 [ExposureScope]，它监听滚动通知；每个卡片包一层 [ExposureDetector]。
/// 滚动时（节流到 ~100ms 一次）各卡片计算自己与视口的交集面积：
/// 达到阈值就启动一个 500ms 定时器，期间滑出视口则取消，定时器走完才回调。
/// 快速划过的卡片不会被算作曝光。
class ExposureScope extends StatefulWidget {
  const ExposureScope({super.key, required this.child});
  final Widget child;

  static _ExposureScopeState? _of(BuildContext context) => context.findAncestorStateOfType<_ExposureScopeState>();

  @override
  State<ExposureScope> createState() => _ExposureScopeState();
}

class _ExposureScopeState extends State<ExposureScope> {
  final Set<_ExposureDetectorState> _items = {};
  Timer? _throttle;

  Rect? get viewport {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _schedule() {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 100), _checkAll);
  }

  void _checkAll() {
    if (!mounted) return;
    final vp = viewport;
    if (vp == null) return;
    for (final item in _items.toList()) {
      item._check(vp);
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: widget.child,
    );
  }
}

class ExposureDetector extends StatefulWidget {
  const ExposureDetector({
    super.key,
    required this.onExposed,
    required this.child,
    this.minFraction = 0.5,
    this.minDuration = const Duration(milliseconds: 500),
  });

  final VoidCallback onExposed;
  final Widget child;
  final double minFraction;
  final Duration minDuration;

  @override
  State<ExposureDetector> createState() => _ExposureDetectorState();
}

class _ExposureDetectorState extends State<ExposureDetector> {
  _ExposureScopeState? _scope;
  Timer? _dwell;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _scope = ExposureScope._of(context);
    _scope?._items.add(this);
    // 首屏不滚动也要判定一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _scope?._schedule());
  }

  @override
  void dispose() {
    _scope?._items.remove(this);
    _dwell?.cancel();
    super.dispose();
  }

  void _check(Rect viewport) {
    if (_fired || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final visible = rect.intersect(viewport);
    final area = rect.width * rect.height;
    final fraction = (visible.width <= 0 || visible.height <= 0 || area <= 0)
        ? 0.0
        : (visible.width * visible.height) / area;
    if (fraction >= widget.minFraction) {
      _dwell ??= Timer(widget.minDuration, () {
        _dwell = null;
        if (!mounted || _fired) return;
        // 停留期满时再确认一次仍然可见。
        final vp = _scope?.viewport;
        final b = context.findRenderObject() as RenderBox?;
        if (vp == null || b == null || !b.attached) return;
        final r = b.localToGlobal(Offset.zero) & b.size;
        final v = r.intersect(vp);
        if (v.width > 0 && v.height > 0 && (v.width * v.height) / (r.width * r.height) >= widget.minFraction) {
          _fired = true;
          widget.onExposed();
        }
      });
    } else {
      _dwell?.cancel();
      _dwell = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
