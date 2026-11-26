import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../motion/collect_button.dart';
import '../../motion/motion.dart';

/// 取词气泡。贴着被选中的单词出现：上方空间够就在上方，否则在下方。
///
/// 入场：以贴近单词的那条边为原点，弹簧缩放 0.82 → 1（[Motion.bouncy]）并淡入，
/// 让气泡看起来是从单词里「弹」出来的。拖动换词时气泡跟着移动并重播一次入场。
class WordPopup extends StatefulWidget {
  const WordPopup({
    super.key,
    required this.anchor,
    required this.topInset,
    required this.display,
    required this.entry,
    required this.collected,
    required this.onToggleCollect,
  });

  /// 单词包围盒（所在 Stack 的坐标系）。
  final Rect anchor;

  /// 顶部不可用高度（状态栏 + 顶栏）。
  final double topInset;
  final String display;
  final DictEntry entry;
  final bool collected;
  final ValueChanged<bool> onToggleCollect;

  @override
  State<WordPopup> createState() => _WordPopupState();
}

class _WordPopupState extends State<WordPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    _c.animateWith(SpringSimulation(Motion.bouncy, 0, 1, 0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final above = widget.anchor.top - widget.topInset > 170;
    final e = widget.entry;

    final card = Container(
      constraints: const BoxConstraints(maxWidth: 300, minWidth: 180),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        e.found ? e.word : widget.display,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.text, height: 1.2),
                      ),
                    ),
                    if (e.phonetic.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(e.phonetic, style: TextStyle(fontSize: 13, color: p.textTertiary)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      if (e.pos.isNotEmpty)
                        TextSpan(
                          text: '${e.pos} ',
                          style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
                        ),
                      TextSpan(text: e.meaning),
                    ],
                  ),
                  style: TextStyle(fontSize: 14.5, height: 1.45, color: e.found ? p.textSecondary : p.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          CollectButton(collected: widget.collected, onChanged: widget.onToggleCollect, size: 26),
        ],
      ),
    );

    return CustomSingleChildLayout(
      delegate: _PopupLayout(widget.anchor, widget.topInset, above),
      child: AnimatedBuilder(
        animation: _c,
        child: card,
        builder: (context, child) {
          final v = _c.value;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.82 + 0.18 * v,
              alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _PopupLayout extends SingleChildLayoutDelegate {
  _PopupLayout(this.anchor, this.topInset, this.above);
  final Rect anchor;
  final double topInset;
  final bool above;

  static const double _margin = 12;
  static const double _gap = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(maxWidth: constraints.maxWidth - _margin * 2).loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.center.dx - childSize.width / 2).clamp(_margin, size.width - childSize.width - _margin);
    final y = above ? anchor.top - _gap - childSize.height : anchor.bottom + _gap;
    return Offset(x.toDouble(), y.clamp(topInset + 4, size.height - childSize.height - _margin).toDouble());
  }

  @override
  bool shouldRelayout(_PopupLayout old) => old.anchor != anchor || old.above != above || old.topInset != topInset;
}
