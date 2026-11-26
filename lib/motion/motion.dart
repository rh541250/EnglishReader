import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// 全局动效参数。集中定义，保证全 App 手感一致，也方便统一调参。
abstract final class Motion {
  // ---- 弹簧 ----
  // 阻尼比 ζ = damping / (2·√(stiffness·mass))。ζ<1 有回弹，ζ=1 临界阻尼无回弹。

  /// 跟手交互的收尾（返回手势取消回弹、Tab 指示器）：ζ≈0.83，快而稳，几乎不过冲。
  static const SpringDescription snappy = SpringDescription(mass: 1, stiffness: 420, damping: 34);

  /// 强调型反馈（收藏按钮、取词气泡、庆祝卡片）：ζ≈0.46，明显回弹 1~2 次。
  static const SpringDescription bouncy = SpringDescription(mass: 1, stiffness: 380, damping: 18);

  /// 大面积元素的落定（卡片按压回弹）：ζ≈0.89。
  static const SpringDescription gentle = SpringDescription(mass: 1, stiffness: 200, damping: 25);

  // ---- 时长 ----
  static const Duration pagePush = Duration(milliseconds: 460);
  static const Duration pagePop = Duration(milliseconds: 380);
  static const Duration entrance = Duration(milliseconds: 420);
  static const Duration staggerStep = Duration(milliseconds: 55);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration tab = Duration(milliseconds: 360);

  // ---- 曲线 ----
  /// 入场：先快后慢，元素「落座」感。
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;

  /// 页面转场（非手势）：与 iOS 原生一致的快入缓出。
  static const Curve page = Curves.fastEaseInToSlowEaseOut;

  /// 入场位移距离。
  static const double entranceOffset = 22;
}

/// 用弹簧把 [controller] 驱动到 [target]（controller 需为 unbounded 或范围覆盖过冲）。
TickerFuture springTo(
  AnimationController controller,
  double target, {
  SpringDescription spring = Motion.bouncy,
  double velocity = 0,
}) {
  return controller.animateWith(SpringSimulation(spring, controller.value, target, velocity));
}
