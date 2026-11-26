import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 自绘彩纸庆祝动效。
///
/// 一个 Ticker 驱动一个粒子系统，全部粒子在同一个 CustomPainter 里一次画完：
/// 不创建任何粒子 Widget，每帧只有一次 paint，没有 build / layout。
///
/// 物理模型（每帧按真实 dt 积分，掉帧时轨迹仍然正确）：
/// - 初速度：从屏幕下方两侧向中上方喷射，速度 900~1700 px/s，带 ±0.45rad 的扇形散布；
/// - 重力 1500 px/s²；空气阻力按速度指数衰减（每秒保留约 28%），所以粒子冲高后缓缓飘落；
/// - 每片纸有独立的自转角速度与「翻面」相位，翻面用 cos 压缩宽度模拟薄片转动；
/// - 最后 600ms 整体淡出。
class ConfettiController extends ChangeNotifier {
  int _burst = 0;
  int get burstId => _burst;

  void fire() {
    _burst++;
    notifyListeners();
  }
}

class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.controller, this.count = 110});
  final ConfettiController controller;
  final int count;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _Particle {
  late double x, y, vx, vy, rotation, spin, flip, flipSpeed, w, h;
  late Color color;
  late int shape; // 0 矩形 1 圆 2 细条
}

class _ConfettiOverlayState extends State<ConfettiOverlay> with SingleTickerProviderStateMixin {
  static const _lifetime = 3.2; // 秒
  static const _gravity = 1500.0;
  static const _dragPerSecond = 0.28;

  static const _colors = [
    Color(0xFFFF5A5F),
    Color(0xFFFFB400),
    Color(0xFF00C2A8),
    Color(0xFF4F7CFF),
    Color(0xFFB36BFF),
    Color(0xFFFF8AC4),
    Color(0xFF7ED957),
  ];

  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final List<_Particle> _particles = [];
  final math.Random _rnd = math.Random();

  Duration _last = Duration.zero;
  double _age = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_start);
  }

  @override
  void didUpdateWidget(ConfettiOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_start);
      widget.controller.addListener(_start);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_start);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _start() {
    if (_size.isEmpty) return;
    _particles.clear();
    for (var i = 0; i < widget.count; i++) {
      final fromLeft = i.isEven;
      final p = _Particle();
      p.x = fromLeft ? -10 : _size.width + 10;
      p.y = _size.height * (0.62 + _rnd.nextDouble() * 0.12);
      // 左侧朝右上（约 -62°），右侧朝左上（约 -118°）。
      final base = fromLeft ? -math.pi * 0.345 : -math.pi * 0.655;
      final angle = base + (_rnd.nextDouble() - 0.5) * 0.9;
      final speed = 900 + _rnd.nextDouble() * 800;
      p.vx = math.cos(angle) * speed;
      p.vy = math.sin(angle) * speed;
      p.rotation = _rnd.nextDouble() * math.pi * 2;
      p.spin = (_rnd.nextDouble() - 0.5) * 12;
      p.flip = _rnd.nextDouble() * math.pi * 2;
      p.flipSpeed = 4 + _rnd.nextDouble() * 8;
      p.shape = _rnd.nextInt(3);
      p.w = 7 + _rnd.nextDouble() * 6;
      p.h = p.shape == 2 ? 3 : 5 + _rnd.nextDouble() * 5;
      p.color = _colors[_rnd.nextInt(_colors.length)];
      _particles.add(p);
    }
    _age = 0;
    _last = Duration.zero;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    // dt 上限 1/20 秒：从后台回来等长间隔不会让粒子瞬移。
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 0.05);
    _last = elapsed;
    _age += dt;
    if (_age >= _lifetime) {
      _ticker.stop();
      _particles.clear();
      _frame.value++;
      return;
    }
    final drag = math.pow(_dragPerSecond, dt).toDouble();
    for (final p in _particles) {
      p.vx *= drag;
      p.vy = p.vy * drag + _gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rotation += p.spin * dt;
      p.flip += p.flipSpeed * dt;
    }
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(_particles, _frame, () => _age, _lifetime),
            ),
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, Listenable repaint, this.age, this.lifetime) : super(repaint: repaint);

  final List<_Particle> particles;
  final double Function() age;
  final double lifetime;

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;
    final remaining = lifetime - age();
    final alpha = (remaining / 0.6).clamp(0.0, 1.0);
    final paint = Paint();
    for (final p in particles) {
      if (p.y > size.height + 40) continue;
      paint.color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      final flip = math.cos(p.flip).abs() * 0.85 + 0.15;
      switch (p.shape) {
        case 1:
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: p.w * 0.8 * flip, height: p.w * 0.8), paint);
        default:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.w * flip, height: p.h),
              const Radius.circular(1.5),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
