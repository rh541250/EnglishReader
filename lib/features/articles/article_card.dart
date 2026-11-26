import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
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
              child: CoverHero(tag: coverHeroTag(heroScope, a.id), articleId: a.id, category: a.category, radius: 14),
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
                      _Tag(text: a.category.label, color: p.accent),
                      const SizedBox(width: 6),
                      DifficultyDots(level: a.difficulty),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${kDifficultyLabels[a.difficulty]} · ${a.minutes} 分钟',
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
                    '继续阅读',
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
