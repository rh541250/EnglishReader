/// 文本区间相关的纯函数：分句、搜索词匹配、摘要片段。不依赖 Flutter，便于单测。
library;

/// 半开区间 [start, end)，字符偏移。
class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;

  bool contains(int offset) => offset >= start && offset < end;

  @override
  bool operator ==(Object other) => other is Span && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Span($start, $end)';
}

/// 把一个段落切成句子。
///
/// 规则：句末标点（. ! ?，可连续出现，后面可跟引号 / 右括号）之后是空白或段落结尾，即为一句结束。
/// 每句去掉首尾空白；区间不包含句间空格。常见缩写（Mr. / Dr. / e.g. 等）不断句。
/// 内置文章由我们自己撰写，规则足够；接入外部文章时可替换为更完整的分句器。
List<Span> splitSentences(String text) {
  final out = <Span>[];
  var start = _skipSpace(text, 0);
  var i = start;
  while (i < text.length) {
    final c = text[i];
    if (c == '.' || c == '!' || c == '?') {
      var end = i + 1;
      while (end < text.length && '.!?'.contains(text[end])) {
        end++;
      }
      while (end < text.length && '"\')'.contains(text[end])) {
        end++;
      }
      final atBoundary = end >= text.length || _isSpace(text[end]);
      if (atBoundary && !(c == '.' && _isAbbreviation(text, start, i))) {
        out.add(Span(start, end));
        start = _skipSpace(text, end);
        i = start;
        continue;
      }
      i = end;
      continue;
    }
    i++;
  }
  // 末尾没有句末标点的残句。
  var tail = text.length;
  while (tail > start && _isSpace(text[tail - 1])) {
    tail--;
  }
  if (tail > start) out.add(Span(start, tail));
  return out;
}

/// 包含字符偏移 [offset] 的句子；落在句间空白上时返回前一句。
Span? sentenceAt(List<Span> sentences, int offset) {
  Span? previous;
  for (final s in sentences) {
    if (s.contains(offset)) return s;
    if (s.start > offset) return previous;
    previous = s;
  }
  return previous;
}

const _abbreviations = {'mr', 'mrs', 'ms', 'dr', 'st', 'vs', 'etc', 'e.g', 'i.e', 'prof', 'jr', 'sr', 'no'};

bool _isAbbreviation(String text, int sentenceStart, int dot) {
  var j = dot;
  while (j > sentenceStart && !_isSpace(text[j - 1])) {
    j--;
  }
  final word = text.substring(j, dot).toLowerCase();
  return _abbreviations.contains(word);
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t';

int _skipSpace(String text, int i) {
  while (i < text.length && _isSpace(text[i])) {
    i++;
  }
  return i;
}

// ---------------------------------------------------------------------------
// 搜索
// ---------------------------------------------------------------------------

/// 把用户输入拆成搜索词：按空白切分、转小写、去重，最多 5 个。
List<String> parseSearchTerms(String query) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
    if (raw.isEmpty || !seen.add(raw)) continue;
    out.add(raw);
    if (out.length == 5) break;
  }
  return out;
}

/// [text] 中所有搜索词出现的位置（不区分大小写），重叠或相邻的区间会合并。
List<Span> findMatches(String text, List<String> terms) {
  if (terms.isEmpty || text.isEmpty) return const [];
  final lower = text.toLowerCase();
  final spans = <Span>[];
  for (final t in terms) {
    var from = 0;
    while (true) {
      final i = lower.indexOf(t, from);
      if (i < 0) break;
      spans.add(Span(i, i + t.length));
      from = i + t.length;
    }
  }
  if (spans.isEmpty) return const [];
  spans.sort((a, b) => a.start.compareTo(b.start));
  final merged = <Span>[spans.first];
  for (final s in spans.skip(1)) {
    final last = merged.last;
    if (s.start <= last.end) {
      if (s.end > last.end) merged[merged.length - 1] = Span(last.start, s.end);
    } else {
      merged.add(s);
    }
  }
  return merged;
}

/// 正文命中片段：命中位置所在的段落与区间。
class SearchHit {
  const SearchHit({
    required this.paragraphIndex,
    required this.match,
    required this.snippet,
    required this.snippetMatches,
  });

  final int paragraphIndex;

  /// 第一个命中在段落中的区间（打开文章后据此滚动并闪烁）。
  final Span match;

  /// 用于结果列表展示的片段（前后可能带省略号）。
  final String snippet;

  /// 片段内所有命中的区间，用于高亮。
  final List<Span> snippetMatches;
}

/// 在正文段落中找第一个命中，截取前后若干字符作为片段，并尽量从单词边界开始。
SearchHit? firstBodyHit(List<String> paragraphs, List<String> terms, {int before = 36, int after = 84}) {
  for (var p = 0; p < paragraphs.length; p++) {
    final text = paragraphs[p];
    final matches = findMatches(text, terms);
    if (matches.isEmpty) continue;
    final m = matches.first;
    var start = (m.start - before).clamp(0, text.length);
    var end = (m.end + after).clamp(0, text.length);
    if (start > 0) {
      final space = text.indexOf(' ', start);
      if (space >= 0 && space < m.start) start = space + 1;
    }
    if (end < text.length) {
      final space = text.lastIndexOf(' ', end);
      if (space > m.end) end = space;
    }
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    final snippet = '$prefix${text.substring(start, end)}$suffix';
    return SearchHit(paragraphIndex: p, match: m, snippet: snippet, snippetMatches: findMatches(snippet, terms));
  }
  return null;
}
