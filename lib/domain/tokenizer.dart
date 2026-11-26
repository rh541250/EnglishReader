/// 正文分词：把一段文本切成「单词」与「非单词」片段。
///
/// 单词 = 连续字母，允许内部一个撇号（don't / city's）。
/// [Token.wordIndex] 是该词在段落内的序号（从 0 开始），与字号、排版无关，
/// 用作生词「原文出处」的稳定定位。
class Token {
  const Token({required this.start, required this.end, required this.text, required this.wordIndex});

  final int start;
  final int end;
  final String text;

  /// 非单词片段为 -1。
  final int wordIndex;

  bool get isWord => wordIndex >= 0;
  String get lower => text.toLowerCase();
}

final RegExp _wordRe = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?");

List<Token> tokenize(String text) {
  final out = <Token>[];
  var cursor = 0;
  var index = 0;
  for (final m in _wordRe.allMatches(text)) {
    if (m.start > cursor) {
      out.add(Token(start: cursor, end: m.start, text: text.substring(cursor, m.start), wordIndex: -1));
    }
    out.add(Token(start: m.start, end: m.end, text: m.group(0)!, wordIndex: index++));
    cursor = m.end;
  }
  if (cursor < text.length) {
    out.add(Token(start: cursor, end: text.length, text: text.substring(cursor), wordIndex: -1));
  }
  return out;
}

int countWords(String text) => _wordRe.allMatches(text).length;

/// 找到包含字符偏移 [offset] 的单词；落在标点 / 空白上返回 null。
Token? wordAtOffset(List<Token> tokens, int offset) {
  var lo = 0, hi = tokens.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final t = tokens[mid];
    if (offset < t.start) {
      hi = mid - 1;
    } else if (offset >= t.end) {
      lo = mid + 1;
    } else {
      return t.isWord ? t : null;
    }
  }
  return null;
}

Token? wordByIndex(List<Token> tokens, int wordIndex) {
  for (final t in tokens) {
    if (t.wordIndex == wordIndex) return t;
  }
  return null;
}
