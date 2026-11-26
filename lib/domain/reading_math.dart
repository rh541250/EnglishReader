import 'dart:math' as math;

/// 阅读位置：段落序号 + 段内纵向比例（0~1）。
///
/// 不存像素：字号 / 行距 / 屏幕宽度变化后段落高度会变，
/// 但「第 N 段的 37% 处」仍然指向同一句话，因此可以跨排版精确恢复。
class ReadingPosition {
  const ReadingPosition(this.paragraphIndex, this.offsetFraction);

  static const ReadingPosition start = ReadingPosition(0, 0);

  final int paragraphIndex;
  final double offsetFraction;

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.paragraphIndex == paragraphIndex &&
      (other.offsetFraction - offsetFraction).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(paragraphIndex, (offsetFraction * 1e6).round());

  @override
  String toString() => 'ReadingPosition($paragraphIndex, ${offsetFraction.toStringAsFixed(3)})';
}

/// 一个段落在滚动内容坐标系中的纵向范围。
class ParagraphExtent {
  const ParagraphExtent(this.top, this.height);
  final double top;
  final double height;
  double get bottom => top + height;
}

/// 由「锚线」（视口顶部阅读线在内容坐标系中的 y）反推阅读位置。
ReadingPosition positionForAnchor(List<ParagraphExtent> extents, double anchorY) {
  if (extents.isEmpty) return ReadingPosition.start;
  if (anchorY <= extents.first.top) return ReadingPosition.start;
  for (var i = 0; i < extents.length; i++) {
    final e = extents[i];
    final nextTop = i + 1 < extents.length ? extents[i + 1].top : double.infinity;
    if (anchorY < nextTop) {
      // 落在段落内，或落在本段与下一段之间的段间距里（归到本段末尾）。
      final f = e.height <= 0 ? 0.0 : ((anchorY - e.top) / e.height).clamp(0.0, 1.0);
      return ReadingPosition(i, f);
    }
  }
  return ReadingPosition(extents.length - 1, 1);
}

/// 阅读位置对应的锚线 y。
double anchorForPosition(List<ParagraphExtent> extents, ReadingPosition p) {
  if (extents.isEmpty) return 0;
  final i = p.paragraphIndex.clamp(0, extents.length - 1);
  final e = extents[i];
  return e.top + e.height * p.offsetFraction.clamp(0.0, 1.0);
}

/// 滚动进度 0~1。内容不足一屏时视为已到底。
double scrollProgress(double offset, double maxScrollExtent) {
  if (maxScrollExtent <= 0) return 1;
  return (offset / maxScrollExtent).clamp(0.0, 1.0);
}

/// 读完阈值：滚动到 97% 即视为读完（留出底部回弹与「下一篇」卡片的余量）。
const double kFinishThreshold = 0.97;

bool isFinished(double progress) => progress >= kFinishThreshold;

/// 滚动深度里程碑（埋点 read_progress 用），返回本次新跨过的里程碑。
List<int> crossedMilestones(double before, double after, {List<int> steps = const [25, 50, 75, 100]}) {
  final out = <int>[];
  for (final s in steps) {
    final t = s == 100 ? kFinishThreshold : s / 100;
    if (before < t && after >= t) out.add(s);
  }
  return out;
}

/// 连续打卡天数：从今天（今天没读则从昨天）往前数连续有阅读记录的天数。
int computeStreak(Set<String> days, DateTime today, String Function(DateTime) keyOf) {
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(keyOf(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(keyOf(cursor))) return 0;
  }
  var n = 0;
  while (days.contains(keyOf(cursor))) {
    n++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return n;
}

/// 预估阅读分钟数（按 180 词 / 分钟）。
int estimateMinutes(int wordCount) => math.max(1, (wordCount / 180).round());
