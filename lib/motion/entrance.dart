import 'package:flutter/widgets.dart';

import 'motion.dart';

/// 列表交错入场的协调者。
///
/// - 记录本轮入场的起始时刻：第 i 项的延迟 = i × [Motion.staggerStep] − 已经过去的时间。
///   首屏各项依次落座；之后因滚动才被构建的项延迟为 0，只做一次很短的淡入，不会「排队等」。
/// - 记录已经入场过的 key：列表项被回收后再次滚入视口时不重复播放。
/// - 切换分类 / 下拉刷新时调用 [restart] 开启新一轮。
class StaggerController {
  StaggerController();

  DateTime _epoch = DateTime.now();
  final Set<Object> _played = {};

  void restart() {
    _epoch = DateTime.now();
    _played.clear();
  }

  /// 返回该项应等待的延迟；已播放过返回 null。
  Duration? claim(Object key, int index) {
    if (!_played.add(key)) return null;
    final target = Motion.staggerStep * index.clamp(0, 10);
    final elapsed = DateTime.now().difference(_epoch);
    final wait = target - elapsed;
    return wait.isNegative ? Duration.zero : wait;
  }
}

/// 单个入场元素：淡入 + 自下而上位移 [Motion.entranceOffset]。
///
/// 只用 Opacity + Transform（合成层属性），不触发布局，整段动画没有 relayout。
class EntranceItem extends StatefulWidget {
  const EntranceItem({
    super.key,
    required this.child,
    this.controller,
    this.itemKey,
    this.index = 0,
    this.delay,
    this.offset = Motion.entranceOffset,
    this.duration = Motion.entrance,
  });

  final Widget child;

  /// 交错协调者；为空时按 [delay] 独立播放。
  final StaggerController? controller;
  final Object? itemKey;
  final int index;
  final Duration? delay;
  final double offset;
  final Duration duration;

  @override
  State<EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<EntranceItem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Motion.enter);

  @override
  void initState() {
    super.initState();
    Duration? wait = widget.delay ?? Duration.zero;
    if (widget.controller != null) {
      wait = widget.controller!.claim(widget.itemKey ?? widget.index, widget.index);
    }
    if (wait == null) {
      _c.value = 1;
    } else if (wait == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        if (t >= 1) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, widget.offset * (1 - t)), child: child),
        );
      },
    );
  }
}

/// 数字滚动（统计数值变化时从旧值平滑过渡到新值）。
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 800),
  });

  final int value;
  final TextStyle style;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Motion.enter,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}
