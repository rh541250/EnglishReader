import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import 'motion.dart';

/// 分类 Tab：胶囊指示器在选项之间滑动，带「拉伸」形变。
///
/// 指示器的左右两条边用不同的时间窗口移动：
/// 朝运动方向的前缘先走（0%~65%），后缘晚走（35%~100%），
/// 于是中途指示器被拉长、到位后再收拢，像一滴被拖动的水，而不是一块平移的色块。
/// 各 Tab 的位置在布局后实测（GlobalKey），所以文字宽度不等也能对齐。
/// 文字颜色随胶囊的覆盖范围反色（见 build 里的三层结构）。
class SlidingTabs extends StatefulWidget {
  const SlidingTabs({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<SlidingTabs> createState() => _SlidingTabsState();
}

class _SlidingTabsState extends State<SlidingTabs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.tab, value: 1);
  late List<GlobalKey> _keys = List.generate(widget.labels.length, (_) => GlobalKey());
  final GlobalKey _rowKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  Rect? _from;
  Rect? _to;

  static const _lead = Interval(0.0, 0.65, curve: Curves.easeOutCubic);
  static const _trail = Interval(0.35, 1.0, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
  }

  @override
  void didUpdateWidget(SlidingTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _keys = List.generate(widget.labels.length, (_) => GlobalKey());
      WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
    } else if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateTo(widget.index));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Rect? _rectOf(int i) {
    final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
    final row = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || row == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: row) & box.size;
  }

  void _snap() {
    if (!mounted) return;
    setState(() {
      _from = _to = _rectOf(widget.index);
      _c.value = 1;
    });
  }

  void _animateTo(int i) {
    if (!mounted) return;
    final target = _rectOf(i);
    if (target == null) return;
    setState(() {
      _from = _current() ?? target;
      _to = target;
    });
    _c.forward(from: 0);
    // 选中项尽量滚到可视区域中间。只动自己的横向滚动条——
    // Scrollable.ensureVisible 会连带滚动外层的纵向列表，这里不能用。
    if (_scroll.hasClients) {
      final position = _scroll.position;
      const padding = 16.0;
      final centered = padding + target.center.dx - position.viewportDimension / 2;
      _scroll.animateTo(centered.clamp(0.0, position.maxScrollExtent), duration: Motion.tab, curve: Motion.standard);
    }
  }

  /// 动画进行到一半时再次切换：从当前插值位置出发，避免跳变。
  Rect? _current() {
    final a = _from, b = _to;
    if (a == null || b == null) return b;
    final t = _c.value;
    final movingRight = b.left >= a.left;
    final leftT = (movingRight ? _trail : _lead).transform(t);
    final rightT = (movingRight ? _lead : _trail).transform(t);
    return Rect.fromLTRB(a.left + (b.left - a.left) * leftT, b.top, a.right + (b.right - a.right) * rightT, b.bottom);
  }

  Widget _labels(Color color, {required bool interactive}) {
    final style = TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.labels.length; i++)
          GestureDetector(
            key: interactive ? _keys[i] : null,
            behavior: HitTestBehavior.opaque,
            onTap: !interactive
                ? null
                : () {
                    if (i == widget.index) return;
                    HapticFeedback.selectionClick();
                    widget.onChanged(i);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(widget.labels[i], style: style),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 三层：灰色文字 → 胶囊 → 被胶囊形状裁剪的反色文字。
    // 文字颜色不做补间，而是「胶囊盖到哪里，哪里的文字就是反色」，
    // 所以滑动途中任意一帧的文字都清晰可读，颜色边界精确贴着胶囊边缘。
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          key: _rowKey,
          children: [
            _labels(p.textSecondary, interactive: true),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final r = _current();
                    if (r == null) return const SizedBox.shrink();
                    return CustomPaint(painter: _IndicatorPainter(r, p.accent));
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _c,
                    child: _labels(p.onAccent, interactive: false),
                    builder: (context, child) {
                      final r = _current();
                      if (r == null) return const SizedBox.shrink();
                      return ClipPath(clipper: _PillClipper(r), child: child);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillClipper extends CustomClipper<Path> {
  _PillClipper(this.rect);
  final Rect rect;

  @override
  Path getClip(Size size) => Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)));

  @override
  bool shouldReclip(_PillClipper oldClipper) => oldClipper.rect != rect;
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter(this.rect, this.color);
  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) => old.rect != rect || old.color != color;
}
