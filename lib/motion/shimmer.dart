import 'package:flutter/widgets.dart';

import '../app/theme.dart';

/// 骨架屏微光。
///
/// 整块骨架只用一个 ShaderMask + 一个 AnimationController：
/// 一条倾斜的高光带以 1.3s 为周期从左扫到右。所有占位块共享同一个着色器，
/// 高光在各块之间是连续的一道光，而不是每块各闪各的，同时只产生一个离屏图层。
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1, -0.3),
              end: const Alignment(1, 0.3),
              colors: [p.skeleton, p.skeletonHighlight, p.skeleton],
              stops: const [0.35, 0.5, 0.65],
              // 把渐变整体平移：-1 → +1 个宽度。
              transform: _SlideTransform(_c.value * 2 - 1),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.fraction);
  final double fraction;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * fraction, 0, 0);
  }
}

/// 骨架占位块。颜色由外层 [Shimmer] 的着色器覆盖，这里只负责形状。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.palette.skeleton, borderRadius: BorderRadius.circular(radius)),
    );
  }
}
