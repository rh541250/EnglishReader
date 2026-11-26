import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import 'motion.dart';

/// 进度环（纯绘制）。[progress] 0~1；[checkT] 0~1 控制「完成对勾」的描绘进度。
class ProgressRingPainter extends CustomPainter {
  ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 3,
    this.checkT = 0,
    this.checkColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double checkT;
  final Color? checkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(color, checkColor ?? color, checkT)!;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * p, false, arc);
    }

    if (checkT > 0) {
      // 对勾由两段折线组成，按路径长度逐步描出。
      final s = size.shortestSide;
      final path = Path()
        ..moveTo(center.dx - s * 0.20, center.dy + s * 0.01)
        ..lineTo(center.dx - s * 0.06, center.dy + s * 0.15)
        ..lineTo(center.dx + s * 0.21, center.dy - s * 0.13);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = checkColor ?? color,
      );
    }
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) =>
      old.progress != progress ||
      old.checkT != checkT ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}

/// 会自己做补间的进度环：[progress] 变化时在 600ms 内平滑推进到新值；
/// [completed] 变为 true 时环闭合并描出对勾。用于列表卡片。
class AnimatedProgressRing extends StatelessWidget {
  const AnimatedProgressRing({
    super.key,
    required this.progress,
    this.completed = false,
    this.size = 30,
    this.strokeWidth = 3,
    this.showLabel = false,
  });

  final double progress;
  final bool completed;
  final double size;
  final double strokeWidth;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final target = completed ? 1.0 : progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 600),
      curve: Motion.enter,
      builder: (context, value, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween(end: completed ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 420),
          curve: Motion.enter,
          builder: (context, check, _) {
            return SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: ProgressRingPainter(
                  progress: value,
                  color: p.accent,
                  trackColor: p.text.withValues(alpha: 0.10),
                  strokeWidth: strokeWidth,
                  checkT: check,
                  checkColor: p.success,
                ),
                child: showLabel && check == 0
                    ? Center(
                        child: Text(
                          '${(value * 100).round()}',
                          style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w700, color: p.textSecondary),
                        ),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
