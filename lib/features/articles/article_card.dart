import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../domain/text_ranges.dart';
import '../../l10n/strings.dart';
import '../../motion/collect_button.dart';
import '../../motion/motion.dart';
import '../../motion/pressable.dart';
import '../../motion/progress_ring.dart';
import '../../motion/shimmer.dart';
import '../../widgets/article_cover.dart';

/// 列表卡片。封面与标题是共享元素（Hero），点击后飞入详情页。
class ArticleCard extends StatelessWidget {
  const ArticleCard({super.key, required this.article, required this.onTap, this.heroScope = 'list'});

  final ArticleSummary article;
  final VoidCallback onTap;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    final a = article;
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.divider),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7.6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverHero(tag: coverHeroTag(heroScope, a.id), articleId: a.id, category: a.category, radius: 14),
                  // 收藏角标放在 Hero 之外：它属于列表卡片，不应该跟着封面飞进详情页。
                  Positioned(top: 10, right: 10, child: FavoriteBadge(visible: a.favorited)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TitleHero(
                    tag: titleHeroTag(heroScope, a.id),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kReadingFont,
                          fontFamilyFallback: kReadingFontFallback,
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: p.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Tag(text: s.category(a.category), color: p.accent),
                      const SizedBox(width: 6),
                      DifficultyDots(level: a.difficulty),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.difficulty(a.difficulty)} · ${s.minutes(a.minutes)} · '
                          '${s.publishDate(a.publishedDate, DateTime.now())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.textTertiary),
                        ),
                      ),
                      if (a.completed || a.maxProgress > 0.02)
                        AnimatedProgressRing(
                          progress: a.maxProgress,
                          completed: a.completed,
                          size: 28,
                          strokeWidth: 2.8,
                          showLabel: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// 难度指示：三个点，亮几个代表几级。
class DifficultyDots extends StatelessWidget {
  const DifficultyDots({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const colors = {1: Color(0xFF2EAD6B), 2: Color(0xFFE59A1F), 3: Color(0xFFE0533D)};
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= level ? colors[level] : p.text.withValues(alpha: 0.12),
            ),
          ),
      ],
    );
  }
}

/// 「继续阅读」横向小卡片。
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.article, required this.onTap});
  final ArticleSummary article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CoverHero(
                tag: coverHeroTag('continue', article.id),
                articleId: article.id,
                category: article.category,
                radius: 13,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).continueReading,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.accent),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.text),
                  ),
                  const SizedBox(height: 9),
                  // 进度条：数值变化时平滑推进。
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: article.maxProgress.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Stack(
                              children: [
                                Container(height: 5, color: p.text.withValues(alpha: 0.08)),
                                FractionallySizedBox(
                                  widthFactor: v,
                                  child: Container(height: 5, color: p.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${(v * 100).round()}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 列表骨架屏：形状与真实卡片一致，加载完成后内容「原地长出来」而不是跳一下。
class ArticleCardSkeleton extends StatelessWidget {
  const ArticleCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.divider),
      ),
      padding: const EdgeInsets.all(10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 7.6,
            child: SkeletonBox(height: double.infinity, radius: 14),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(6, 14, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 240, height: 20),
                SizedBox(height: 10),
                SkeletonBox(height: 12),
                SizedBox(height: 7),
                SkeletonBox(width: 200, height: 12),
                SizedBox(height: 14),
                Row(
                  children: [
                    SkeletonBox(width: 44, height: 18),
                    SizedBox(width: 8),
                    SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片封面右上角的收藏角标：收藏状态变化时弹簧缩放出现 / 收起。
class FavoriteBadge extends StatelessWidget {
  const FavoriteBadge({super.key, required this.visible, this.size = 30});
  final bool visible;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: Motion.entrance,
      curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(Icons.bookmark_rounded, size: size * 0.6, color: CollectButton.activeColor),
      ),
    );
  }
}

/// 把 [text] 里的 [matches] 区间渲染为高亮（搜索结果用）。
TextSpan highlightedSpan(String text, List<Span> matches, TextStyle base, TextStyle highlight) {
  if (matches.isEmpty) return TextSpan(text: text, style: base);
  final children = <TextSpan>[];
  var cursor = 0;
  for (final m in matches) {
    if (m.start > cursor) children.add(TextSpan(text: text.substring(cursor, m.start)));
    children.add(TextSpan(text: text.substring(m.start, m.end), style: highlight));
    cursor = m.end;
  }
  if (cursor < text.length) children.add(TextSpan(text: text.substring(cursor)));
  return TextSpan(style: base, children: children);
}

/// 紧凑的文章行：小封面（共享元素）+ 标题 + 副标题。用于搜索结果与「收藏的文章」。
class ArticleRow extends StatelessWidget {
  const ArticleRow({
    super.key,
    required this.article,
    required this.heroScope,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.footer,
  });

  final ArticleSummary article;
  final String heroScope;
  final VoidCallback onTap;
  final Widget title;
  final Widget subtitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      pressedScale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: CoverHero(
                tag: coverHeroTag(heroScope, article.id),
                articleId: article.id,
                category: article.category,
                radius: 12,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 4),
                  subtitle,
                  if (footer != null) ...[const SizedBox(height: 8), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
