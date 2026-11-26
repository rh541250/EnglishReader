import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// 按压缩放反馈：按下缩到 [pressedScale]，松开用弹簧回到 1。
///
/// 按下用 90ms 的短补间（要「立刻有反应」），松开用弹簧（要「有弹性地回来」）。
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);

  void _down(TapDownDetails _) {
    _c.animateTo(widget.pressedScale, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _release() {
    _c.animateWith(SpringSimulation(Motion.gentle, _c.value, 1, 0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : _down,
      onTapUp: widget.onTap == null ? null : (_) => _release(),
      onTapCancel: widget.onTap == null ? null : _release,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => Transform.scale(scale: _c.value, child: child),
      ),
    );
  }
}
