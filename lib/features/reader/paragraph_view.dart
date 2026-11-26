import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/text_ranges.dart';
import '../../domain/tokenizer.dart';

/// 长按命中的单词。
class WordHit {
  const WordHit({required this.paragraphIndex, required this.token, required this.globalRect});
  final int paragraphIndex;
  final Token token;

  /// 单词在屏幕坐标系中的包围盒，用于定位释义气泡。
  final Rect globalRect;
}

/// 一个可长按取词的段落。
///
/// 实现思路：整段只用一个 RichText（一次文本布局），而不是「每个单词一个 Widget」：
/// - 命中测试：长按位置 → `RenderParagraph.getPositionForOffset` 得到字符偏移 →
///   在预先分好的 token 表里二分查找所属单词 → `getBoxesForSelection` 取单词包围盒，
///   并校验手指确实落在盒内（否则行尾空白处也会「吸附」到最近的词）；
/// - 高亮：包围盒交给 CustomPainter 画在文字下层，换词时只重绘这一段，不触发文本重排；
/// - 长按后不抬手继续拖动，可以连续换词（每换一个词给一次轻触感）；
/// - 句子划线同样画在文字下层（荧光笔底色），新划的句子沿行逐段「涂」出来。
class ParagraphView extends StatefulWidget {
  const ParagraphView({
    super.key,
    required this.index,
    required this.text,
    required this.tokens,
    required this.style,
    required this.collected,
    required this.lemmaOf,
    required this.collectedColor,
    required this.highlightColor,
    required this.markColor,
    required this.activeWordIndex,
    required this.marks,
    required this.markAnimation,
    required this.animatingMark,
    required this.flash,
    required this.flashRange,
    required this.onWordHit,
    required this.onLongPressEnd,
  });

  final int index;
  final String text;
  final List<Token> tokens;
  final TextStyle style;

  /// 已收藏的词元集合（每次变更都是新实例，可用 identical 判断是否需要重建 span）。
  final Set<String> collected;
  final String Function(String token) lemmaOf;
  final Color collectedColor;
  final Color highlightColor;
  final Color markColor;

  /// 当前被取词高亮的单词序号（不在本段则为 null）。
  final int? activeWordIndex;

  /// 本段已划线的句子区间。
  final List<Span> marks;

  /// 正在「涂出 / 擦除」的那一句（不在本段为 null），进度取 [markAnimation]。
  final Animation<double> markAnimation;
  final Span? animatingMark;

  /// 「跳回原文出处」/ 搜索命中的闪烁高亮。
  final Animation<double> flash;
  final Span? flashRange;

  final ValueChanged<WordHit> onWordHit;
  final VoidCallback onLongPressEnd;

  @override
  State<ParagraphView> createState() => ParagraphViewState();
}

class ParagraphViewState extends State<ParagraphView> {
  final GlobalKey _textKey = GlobalKey();
  late TextSpan _span = _buildSpan();
  int? _lastHitWord;

  RenderParagraph? get _paragraph => _textKey.currentContext?.findRenderObject() as RenderParagraph?;

  @override
  void didUpdateWidget(ParagraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.collected, widget.collected) ||
        oldWidget.style != widget.style ||
        oldWidget.collectedColor != widget.collectedColor ||
        oldWidget.text != widget.text) {
      _span = _buildSpan();
    }
  }

  TextSpan _buildSpan() {
    if (widget.collected.isEmpty) return TextSpan(text: widget.text, style: widget.style);
    // 把相邻的普通片段合并成一个 span，只有已收藏的词单独成 span。
    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      children.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }

    final collectedStyle = TextStyle(
      color: widget.collectedColor,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: widget.collectedColor,
      decorationThickness: 1.6,
    );
    for (final t in widget.tokens) {
      if (t.isWord && widget.collected.contains(widget.lemmaOf(t.text))) {
        flush();
        children.add(TextSpan(text: t.text, style: collectedStyle));
      } else {
        buffer.write(t.text);
      }
    }
    flush();
    return TextSpan(style: widget.style, children: children);
  }

  /// 指定单词在屏幕坐标系中的包围盒。
  Rect? globalRectOfWord(int wordIndex) {
    final token = wordByIndex(widget.tokens, wordIndex);
    return token == null ? null : globalRectOfRange(Span(token.start, token.end));
  }

  /// 任意字符区间在屏幕坐标系中的包围盒（「跳回原文」、搜索命中定位用）。
  Rect? globalRectOfRange(Span range) {
    final rp = _paragraph;
    if (rp == null) return null;
    final rect = _localRect(rp, range.start, range.end);
    return rect == null ? null : rp.localToGlobal(rect.topLeft) & rect.size;
  }

  Rect? _localRect(RenderParagraph rp, int start, int end) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
    if (boxes.isEmpty) return null;
    var rect = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      rect = rect.expandToInclude(b.toRect());
    }
    return rect;
  }

  void _hit(Offset local) {
    final rp = _paragraph;
    if (rp == null) return;
    final position = rp.getPositionForOffset(local);
    // 落在词尾右侧时偏移等于 token.end，往前再试一个字符。
    final token =
        wordAtOffset(widget.tokens, position.offset) ??
        (position.offset > 0 ? wordAtOffset(widget.tokens, position.offset - 1) : null);
    if (token == null) return;
    final rect = _localRect(rp, token.start, token.end);
    if (rect == null || !rect.inflate(6).contains(local)) return;
    if (_lastHitWord == token.wordIndex) return;
    _lastHitWord = token.wordIndex;
    HapticFeedback.selectionClick();
    widget.onWordHit(
      WordHit(paragraphIndex: widget.index, token: token, globalRect: rp.localToGlobal(rect.topLeft) & rect.size),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          // 350ms：比系统默认 500ms 更跟手，又不至于在滚动起手时误触发。
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 350)),
          (r) => r
            ..onLongPressStart = (d) {
              _lastHitWord = null;
              _hit(d.localPosition);
            }
            ..onLongPressMoveUpdate = (d) {
              _hit(d.localPosition);
            }
            ..onLongPressEnd = (_) {
              _lastHitWord = null;
              widget.onLongPressEnd();
            },
        ),
      },
      child: CustomPaint(
        painter: _HighlightPainter(
          paragraph: () => _paragraph,
          tokens: widget.tokens,
          activeWordIndex: widget.activeWordIndex,
          activeColor: widget.highlightColor,
          marks: widget.marks,
          markColor: widget.markColor,
          markAnimation: widget.markAnimation,
          animatingMark: widget.animatingMark,
          flashRange: widget.flashRange,
          flash: widget.flash,
          flashColor: widget.collectedColor,
        ),
        child: RichText(key: _textKey, text: _span, textScaler: MediaQuery.textScalerOf(context)),
      ),
    );
  }
}

/// 文字下层的所有高亮：句子划线、取词高亮、定位闪烁。只重绘，不重排文本。
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.paragraph,
    required this.tokens,
    required this.activeWordIndex,
    required this.activeColor,
    required this.marks,
    required this.markColor,
    required this.markAnimation,
    required this.animatingMark,
    required this.flashRange,
    required this.flash,
    required this.flashColor,
  }) : super(repaint: Listenable.merge([flash, markAnimation]));

  final RenderParagraph? Function() paragraph;
  final List<Token> tokens;
  final int? activeWordIndex;
  final Color activeColor;
  final List<Span> marks;
  final Color markColor;
  final Animation<double> markAnimation;
  final Span? animatingMark;
  final Span? flashRange;
  final Animation<double> flash;
  final Color flashColor;

  @override
  void paint(Canvas canvas, Size size) {
    // paint 阶段文本已完成布局，可以安全地向 RenderParagraph 查询包围盒。
    final rp = paragraph();
    if (rp == null) return;
    final markPaint = Paint()..color = markColor;
    for (final m in marks) {
      if (m == animatingMark) continue;
      _paintMarker(canvas, rp, m, 1, markPaint);
    }
    final anim = animatingMark;
    if (anim != null) {
      _paintMarker(canvas, rp, anim, Curves.easeInOutCubic.transform(markAnimation.value), markPaint);
    }
    if (activeWordIndex != null) {
      final token = wordByIndex(tokens, activeWordIndex!);
      if (token != null) _paintBox(canvas, rp, Span(token.start, token.end), activeColor);
    }
    final f = flashRange;
    if (f != null && flash.value > 0) {
      _paintBox(canvas, rp, f, flashColor.withValues(alpha: 0.38 * flash.value));
    }
  }

  void _paintBox(Canvas canvas, RenderParagraph rp, Span range, Color color) {
    final paint = Paint()..color = color;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: range.start, extentOffset: range.end))) {
      canvas.drawRRect(RRect.fromRectAndRadius(b.toRect().inflate(2.5), const Radius.circular(5)), paint);
    }
  }

  /// 荧光笔：每行画一条覆盖字形下半部的色带。[progress] < 1 时按总长度从第一行左端
  /// 「涂」到最后一行右端——跨行时上一行涂满才进入下一行，像真的用笔划过去。
  void _paintMarker(Canvas canvas, RenderParagraph rp, Span range, double progress, Paint paint) {
    if (progress <= 0) return;
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: range.start, extentOffset: range.end));
    if (boxes.isEmpty) return;
    final total = boxes.fold<double>(0, (w, b) => w + (b.right - b.left));
    var remaining = total * progress.clamp(0.0, 1.0);
    for (final b in boxes) {
      if (remaining <= 0) break;
      final width = b.right - b.left;
      final drawn = remaining < width ? remaining : width;
      remaining -= drawn;
      final h = b.bottom - b.top;
      final rect = Rect.fromLTRB(b.left - 1, b.top + h * 0.50, b.left + drawn + 1, b.top + h * 0.84);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.activeWordIndex != activeWordIndex ||
      !identical(old.marks, marks) ||
      old.animatingMark != animatingMark ||
      old.flashRange != flashRange ||
      old.activeColor != activeColor ||
      old.markColor != markColor ||
      old.flashColor != flashColor ||
      !identical(old.tokens, tokens);
}
