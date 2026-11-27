import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/strings.dart';

/// 收藏单词时的飞行反馈：单词胶囊从点中的位置沿抛物线飞到屏幕底部中央，
/// 落点处出现「笔记 +1」并弹一下，随后淡出。
///
/// 时间轴（总长 [_duration]）：
/// - 0 → 0.7   胶囊沿抛物线飞行，缩小并在末段淡出；
/// - 0.55 → 0.85 「笔记 +1」从 0.6 倍弹出；
/// - 0.7 → 1.0  落点弹跳一次，随后淡出。
///
/// 整层 [IgnorePointer]，不挡住阅读操作。
class WordFlyLayer extends StatefulWidget {
  const WordFlyLayer({super.key});

  @override
  State<WordFlyLayer> createState() => WordFlyLayerState();
}

class WordFlyLayerState extends State<WordFlyLayer> with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 900);
  static const double _flightEnd = 0.7;
  static const double _pillHeight = 40;

  late final AnimationController _c = AnimationController(vsync: this, duration: _duration);

  Offset? _from;
  String _word = '';

  /// 从 [from]（本层坐标系）出发飞行 [word]。
  void fly(Offset from, String word) {
    setState(() {
      _from = from;
      _word = word;
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _clamp01(double v) => v.clamp(0.0, 1.0);

  /// 二次贝塞尔曲线上的点：起点 [p0]、控制点 [p1]、终点 [p2]。
  static Offset _bezier(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx, u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final from = _from;
              if (from == null || _c.isDismissed) return const SizedBox.shrink();
              final t = _c.value;

              // 落点：底部中央「笔记 +1」胶囊的中心。
              final pillCenterY = box.maxHeight - bottomInset - 24 - _pillHeight / 2;
              final target = Offset(box.maxWidth / 2, pillCenterY);
              final control = Offset((from.dx + target.dx) / 2, math.min(from.dy, target.dy) - 160);

              final fly = _clamp01(t / _flightEnd);
              final eased = Curves.easeIn.transform(fly);
              final at = _bezier(from, control, target, eased);
              final flyAlpha = 1 - _clamp01((fly - 0.8) / 0.2);
              final flyScale = 1 - 0.45 * fly;

              final appear = Curves.easeOutBack.transform(_clamp01((t - 0.55) / 0.15));
              final arrival = _clamp01((t - _flightEnd) / 0.3);
              final bump = 1 + 0.2 * math.sin(math.pi * arrival);
              final pillScale = (0.6 + 0.4 * appear) * bump;
              final pillAlpha = _clamp01((t - 0.55) / 0.12) * (1 - _clamp01((t - 0.85) / 0.15));

              return Stack(
                children: [
                  if (t < _flightEnd + 0.05)
                    Positioned(
                      left: at.dx,
                      top: at.dy,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, -0.5),
                        child: Transform.scale(
                          scale: flyScale,
                          child: Opacity(
                            opacity: flyAlpha,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: p.accent,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: p.accent.withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                _word,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: p.onAccent,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset + 24,
                    child: Center(
                      child: Opacity(
                        opacity: pillAlpha,
                        child: Transform.scale(
                          scale: pillScale,
                          child: Container(
                            height: _pillHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: p.surface,
                              borderRadius: BorderRadius.circular(_pillHeight / 2),
                              border: Border.all(color: p.divider),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.collections_bookmark_rounded, size: 17, color: p.accent),
                                const SizedBox(width: 7),
                                Text(
                                  s.notebookPlusOne,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: p.text,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
