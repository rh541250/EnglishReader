import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';

/// 收藏按钮：形变弹跳 + 放射粒子。
///
/// 收藏时 620ms 的编排（[_c] 0→1）：
/// - 0~18%   蓄力：横向压扁（scaleX 1→1.25，scaleY 1→0.70），像被按下去；
/// - 18~45%  弹起：纵向拉长（scaleX→0.82，scaleY→1.32），同时空心星换成实心星；
/// - 45~100% 落定：elasticOut 回到 1，余震两次；
/// - 20~75%  8 颗粒子从中心向外放射并缩小淡出，外加一圈扩散的描边圆环。
/// 取消收藏只做一次轻微的缩小回弹，不放粒子——「取消」不应该比「收藏」更热闹。
class CollectButton extends StatefulWidget {
  const CollectButton({super.key, required this.collected, required this.onChanged, this.size = 26, this.label});

  final bool collected;
  final ValueChanged<bool> onChanged;
  final double size;

  /// 可选文字标签（显示在图标右侧）。
  final String? label;

  @override
  State<CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<CollectButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );

  bool _celebrate = false;

  static final Animatable<double> _scaleX = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.82).chain(CurveTween(curve: Curves.easeInOut)), weight: 27),
    TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 55),
  ]);

  static final Animatable<double> _scaleY = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.70).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
    TweenSequenceItem(tween: Tween(begin: 0.70, end: 1.32).chain(CurveTween(curve: Curves.easeInOut)), weight: 27),
    TweenSequenceItem(tween: Tween(begin: 1.32, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 55),
  ]);

  static final Animatable<double> _shrink = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.78).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.78, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 70),
  ]);

  @override
  void didUpdateWidget(CollectButton old) {
    super.didUpdateWidget(old);
    if (old.collected != widget.collected) {
      _celebrate = widget.collected;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.collected) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.mediumImpact();
    }
    widget.onChanged(!widget.collected);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const gold = Color(0xFFF5A623);
    final size = widget.size;

    final icon = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final sx = _celebrate ? _scaleX.transform(t) : _shrink.transform(t);
        final sy = _celebrate ? _scaleY.transform(t) : _shrink.transform(t);
        // 实心星在「弹起」那一刻出现。
        final filled = widget.collected && (!_celebrate || t >= 0.18);
        return SizedBox(
          width: size * 1.7,
          height: size * 1.7,
          child: CustomPaint(
            painter: _celebrate && t < 1 ? _BurstPainter(t, gold) : null,
            child: Center(
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(sx, sy, 1),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: filled ? gold : p.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );

    return Semantics(
      button: true,
      label: widget.collected ? '取消收藏' : '收藏',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: widget.label == null
            ? icon
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.collected ? gold : p.textSecondary,
                    ),
                    child: Text(widget.collected ? '已收藏' : widget.label!),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    // 扩散圆环：20%~60%。
    final ringT = ((t - 0.20) / 0.40).clamp(0.0, 1.0);
    if (ringT > 0 && ringT < 1) {
      final e = Curves.easeOutCubic.transform(ringT);
      canvas.drawCircle(
        center,
        maxR * (0.35 + 0.6 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - e)
          ..color = color.withValues(alpha: 0.7 * (1 - e)),
      );
    }

    // 粒子：20%~75%。
    final pt = ((t - 0.20) / 0.55).clamp(0.0, 1.0);
    if (pt > 0 && pt < 1) {
      final e = Curves.easeOutQuart.transform(pt);
      final paint = Paint()..color = color.withValues(alpha: 1 - pt * pt);
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4 + 0.2;
        final r = maxR * (0.45 + 0.55 * e);
        final radius = (i.isEven ? 2.4 : 1.6) * (1 - pt * 0.8);
        canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * r, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
