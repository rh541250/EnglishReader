import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
/// - 长按后不抬手继续拖动，可以连续换词（每换一个词给一次轻触感）。
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
    required this.activeWordIndex,
    required this.flash,
    required this.flashWordIndex,
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

  /// 当前被取词高亮的单词序号（不在本段则为 null）。
  final int? activeWordIndex;

  /// 「跳回原文出处」的闪烁高亮。
  final Animation<double> flash;
  final int? flashWordIndex;

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

  /// 指定单词在屏幕坐标系中的包围盒（「跳回原文」定位用）。
  Rect? globalRectOfWord(int wordIndex) {
    final rp = _paragraph;
    final token = wordByIndex(widget.tokens, wordIndex);
    if (rp == null || token == null) return null;
    final rect = _localRect(rp, token);
    return rect == null ? null : rp.localToGlobal(rect.topLeft) & rect.size;
  }

  Rect? _localRect(RenderParagraph rp, Token token) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: token.start, extentOffset: token.end));
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
    final rect = _localRect(rp, token);
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
        painter: _WordHighlightPainter(
          paragraph: () => _paragraph,
          tokens: widget.tokens,
          activeWordIndex: widget.activeWordIndex,
          activeColor: widget.highlightColor,
          flashWordIndex: widget.flashWordIndex,
          flash: widget.flash,
          flashColor: widget.collectedColor,
        ),
        child: RichText(key: _textKey, text: _span, textScaler: MediaQuery.textScalerOf(context)),
      ),
    );
  }
}

class _WordHighlightPainter extends CustomPainter {
  _WordHighlightPainter({
    required this.paragraph,
    required this.tokens,
    required this.activeWordIndex,
    required this.activeColor,
    required this.flashWordIndex,
    required this.flash,
    required this.flashColor,
  }) : super(repaint: flash);

  final RenderParagraph? Function() paragraph;
  final List<Token> tokens;
  final int? activeWordIndex;
  final Color activeColor;
  final int? flashWordIndex;
  final Animation<double> flash;
  final Color flashColor;

  @override
  void paint(Canvas canvas, Size size) {
    // paint 阶段文本已完成布局，可以安全地向 RenderParagraph 查询包围盒。
    final rp = paragraph();
    if (rp == null) return;
    if (activeWordIndex != null) {
      _paintWord(canvas, rp, activeWordIndex!, activeColor);
    }
    if (flashWordIndex != null && flash.value > 0) {
      _paintWord(canvas, rp, flashWordIndex!, flashColor.withValues(alpha: 0.38 * flash.value));
    }
  }

  void _paintWord(Canvas canvas, RenderParagraph rp, int wordIndex, Color color) {
    final token = wordByIndex(tokens, wordIndex);
    if (token == null) return;
    final paint = Paint()..color = color;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: token.start, extentOffset: token.end))) {
      canvas.drawRRect(RRect.fromRectAndRadius(b.toRect().inflate(2.5), const Radius.circular(5)), paint);
    }
  }

  @override
  bool shouldRepaint(_WordHighlightPainter old) =>
      old.activeWordIndex != activeWordIndex ||
      old.flashWordIndex != flashWordIndex ||
      old.activeColor != activeColor ||
      old.flashColor != flashColor ||
      !identical(old.tokens, tokens);
}
