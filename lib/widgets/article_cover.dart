import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';

/// 文章封面：按文章 id 确定性生成的矢量图（渐变 + 几何图形 + 分类图标）。
///
/// 为什么不用图片：离线优先——首次安装、飞行模式下也必须有封面；
/// 矢量绘制可以无损缩放到任意尺寸，正好适合共享元素转场中从卡片放大到整幅头图。
class ArticleCover extends StatelessWidget {
  const ArticleCover({super.key, required this.articleId, required this.category, this.showIcon = true});

  final String articleId;
  final ArticleCategory category;
  final bool showIcon;

  static const Map<ArticleCategory, List<List<Color>>> _palettes = {
    ArticleCategory.tech: [
      [Color(0xFF3B4BDB), Color(0xFF7A5CFF)],
      [Color(0xFF1F6FEB), Color(0xFF39C6F0)],
      [Color(0xFF4338CA), Color(0xFF22B8CF)],
    ],
    ArticleCategory.business: [
      [Color(0xFF0F766E), Color(0xFF34D399)],
      [Color(0xFF1E5F74), Color(0xFF6FCF97)],
      [Color(0xFF166534), Color(0xFFA3D977)],
    ],
    ArticleCategory.culture: [
      [Color(0xFFB4411F), Color(0xFFF59E0B)],
      [Color(0xFF9D2B5B), Color(0xFFF97366)],
      [Color(0xFF7C3AED), Color(0xFFF472B6)],
    ],
    ArticleCategory.daily: [
      [Color(0xFFE0762F), Color(0xFFFFC857)],
      [Color(0xFF2F80C2), Color(0xFF8ED1C6)],
      [Color(0xFFD9506B), Color(0xFFFFB199)],
    ],
  };

  static const Map<ArticleCategory, IconData> icons = {
    ArticleCategory.tech: Icons.memory_rounded,
    ArticleCategory.business: Icons.trending_up_rounded,
    ArticleCategory.culture: Icons.palette_outlined,
    ArticleCategory.daily: Icons.local_cafe_outlined,
  };

  static int _seedOf(String id) {
    var h = 0x811c9dc5;
    for (final c in id.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final seed = _seedOf(articleId);
    final options = _palettes[category]!;
    final colors = options[seed % options.length];
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CoverPainter(seed, colors),
        child: showIcon
            ? LayoutBuilder(
                builder: (context, c) {
                  final s = math.min(c.maxWidth, c.maxHeight);
                  return Align(
                    alignment: const Alignment(0.82, 0.7),
                    child: Icon(icons[category], size: s * 0.26, color: Colors.white.withValues(alpha: 0.9)),
                  );
                },
              )
            : null,
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.seed, this.colors);
  final int seed;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRect(rect);
    // 所有坐标都是相对尺寸，封面缩放时构图保持不变。
    final unit = size.shortestSide;
    for (var i = 0; i < 4; i++) {
      final cx = size.width * rnd.nextDouble();
      final cy = size.height * rnd.nextDouble();
      final r = unit * (0.25 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.05 + rnd.nextDouble() * 0.09),
      );
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.012
      ..color = Colors.white.withValues(alpha: 0.22);
    final ringCenter = Offset(
      size.width * (0.15 + rnd.nextDouble() * 0.3),
      size.height * (0.25 + rnd.nextDouble() * 0.4),
    );
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(ringCenter, unit * 0.13 * i, ring);
    }
    // 斜向条纹
    final stripe = Paint()
      ..strokeWidth = unit * 0.02
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.16);
    final sx = size.width * (0.55 + rnd.nextDouble() * 0.2);
    final sy = size.height * (0.12 + rnd.nextDouble() * 0.2);
    for (var i = 0; i < 4; i++) {
      final o = Offset(sx + i * unit * 0.07, sy + i * unit * 0.03);
      canvas.drawLine(o, o + Offset(unit * 0.16, -unit * 0.16), stripe);
    }
    // 底部压暗，保证叠加的文字 / 图标可读。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.22)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed || old.colors != colors;
}

/// 共享元素的 Hero tag。同一篇文章可能同时出现在「继续阅读」和列表里，用 [scope] 区分。
String coverHeroTag(String scope, String articleId) => 'cover:$scope:$articleId';
String titleHeroTag(String scope, String articleId) => 'title:$scope:$articleId';

/// 封面 Hero。飞行途中圆角在卡片值与详情页值之间插值，尺寸由 Hero 负责。
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.tag,
    required this.articleId,
    required this.category,
    required this.radius,
    this.enabled = true,
  });

  final String tag;
  final String articleId;
  final ArticleCategory category;
  final double radius;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cover = ArticleCover(articleId: articleId, category: category);
    return HeroMode(
      enabled: enabled,
      child: Hero(
        tag: tag,
        transitionOnUserGestures: true,
        // 直线飞行：横向滑动返回时，弧线路径会让封面看起来「绕路」。
        createRectTween: (a, b) => RectTween(begin: a, end: b),
        flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
          final fromRadius = (fromContext.widget as Hero).child is ClipRRect
              ? (((fromContext.widget as Hero).child as ClipRRect).borderRadius as BorderRadius).topLeft.x
              : 0.0;
          final toRadius = (toContext.widget as Hero).child is ClipRRect
              ? (((toContext.widget as Hero).child as ClipRRect).borderRadius as BorderRadius).topLeft.x
              : 0.0;
          // pop 时 animation 从 1 → 0，对应的起止要反过来。
          final begin = direction == HeroFlightDirection.push ? fromRadius : toRadius;
          final end = direction == HeroFlightDirection.push ? toRadius : fromRadius;
          return AnimatedBuilder(
            animation: animation,
            child: cover,
            builder: (context, child) =>
                ClipRRect(borderRadius: BorderRadius.circular(begin + (end - begin) * animation.value), child: child),
          );
        },
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: cover),
      ),
    );
  }
}

/// 标题 Hero。
///
/// 列表与详情页的标题字号、可用宽度都不同，折行位置必然不一样；如果让文字在飞行途中
/// 随宽度重新排版，会出现明显的逐帧跳动。这里的做法是：飞行途中不重排，
/// 把两端各自已经排好版的标题都按宽度整体缩放（FittedBox）叠在一起，
/// 前半程列表侧淡出、中段详情侧淡入，位置和尺寸由 Hero 的矩形补间负责。
class TitleHero extends StatelessWidget {
  const TitleHero({super.key, required this.tag, required this.child, this.isDetail = false, this.enabled = true});

  final String tag;
  final Widget child;

  /// 是否为详情页一侧。
  final bool isDetail;
  final bool enabled;

  static const _listFade = Interval(0.0, 0.45, curve: Curves.easeOut);
  static const _detailFade = Interval(0.2, 0.7, curve: Curves.easeIn);

  static Widget _frozen(BuildContext heroContext) {
    final hero = heroContext.widget as Hero;
    final size = (heroContext.findRenderObject() as RenderBox?)?.size;
    return FittedBox(
      fit: BoxFit.fitWidth,
      alignment: Alignment.topLeft,
      child: size == null ? hero.child : SizedBox(width: size.width, height: size.height, child: hero.child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: enabled,
      child: Hero(
        tag: tag,
        transitionOnUserGestures: true,
        createRectTween: (a, b) => RectTween(begin: a, end: b),
        flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
          final pushing = direction == HeroFlightDirection.push;
          final listSide = _frozen(pushing ? fromContext : toContext);
          final detailSide = _frozen(pushing ? toContext : fromContext);
          // animation.value：0 = 列表，1 = 详情（pop 时从 1 走回 0）。
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Opacity(opacity: 1 - _listFade.transform(t), child: listSide),
                  Opacity(opacity: _detailFade.transform(t), child: detailSide),
                ],
              );
            },
          );
        },
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
