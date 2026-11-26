import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// 全 App 统一的页面路由：右侧滑入 + 下层视差 + 全屏宽度的跟手右滑返回。
///
/// 手势返回的实现要点（与 Hero 共享元素联动）：
/// 1. 手指按下并判定为横向拖动后，调用 `navigator.didStartUserGesture()`，
///    HeroController 据此启动一次由手势驱动的 Hero 飞行；
/// 2. 拖动过程中直接改写路由 AnimationController 的 value（1 → 0），
///    页面位移、下层视差、遮罩、Hero 飞行全部由这一个值驱动，天然同步跟手；
/// 3. 松手时按「速度优先、位移兜底」判定：
///    - 横向速度 ≥ [_minFlingVelocity]（屏宽 / 秒）时看方向：向右甩 = 返回，向左甩 = 取消；
///    - 否则看是否拖过半屏；
/// 4. 取消：用弹簧（[Motion.snappy]，带松手速度）回弹到 1；
///    返回：先 `navigator.pop()`，再用与剩余距离成正比的时长收尾到 0；
/// 5. 收尾动画结束后 `didStopUserGesture()`，Hero 落位。
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({required this.builder, super.settings, this.swipeBack = true});

  final WidgetBuilder builder;

  /// 是否允许右滑返回。
  final bool swipeBack;

  static const double _minFlingVelocity = 1.0; // 屏宽 / 秒

  @override
  Duration get transitionDuration => Motion.pagePush;

  @override
  Duration get reverseTransitionDuration => Motion.pagePop;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => nextRoute is PageRoute;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return Semantics(scopesRoute: true, explicitChildNodes: true, child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 手势进行中必须线性映射，否则页面位置和手指对不上。
    final linear = navigator?.userGestureInProgress ?? false;
    final t = linear ? animation.value : _curved(animation);
    final s = linear ? secondaryAnimation.value : Motion.page.transform(secondaryAnimation.value);

    final textDirection = Directionality.of(context);
    final sign = textDirection == TextDirection.rtl ? -1.0 : 1.0;

    Widget page = child;
    if (swipeBack) page = _BackGestureDetector<T>(route: this, child: page);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 压在下层页面上的遮罩，随进度加深，强化层级感。
        // 注意：这一层必须始终存在，否则 Stack 子节点数量变化会让页面子树重建。
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: Colors.black.withValues(alpha: t >= 1 ? 0 : 0.16 * t)),
          ),
        ),
        FractionalTranslation(
          // 被新页面盖住时向左视差移动 25%。
          translation: Offset(sign * ((1 - t) - 0.25 * s), 0),
          transformHitTests: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: t < 1
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18 * t),
                        blurRadius: 24,
                        offset: const Offset(-6, 0),
                      ),
                    ]
                  : null,
            ),
            child: page,
          ),
        ),
      ],
    );
  }

  double _curved(Animation<double> animation) {
    // 进场用快入缓出；退场用它的镜像，保证 pop 的起步同样干脆。
    return switch (animation.status) {
      AnimationStatus.reverse => 1 - Motion.page.transform(1 - animation.value),
      _ => Motion.page.transform(animation.value),
    };
  }

  // ---- 手势返回 ----

  @override
  bool get popGestureEnabled {
    // 框架自带的判定已覆盖：首个路由、PopScope 拦截、全屏弹窗、转场未结束。
    if (!swipeBack || !super.popGestureEnabled) return false;
    if (navigator?.userGestureInProgress ?? true) return false;
    return true;
  }

  void _dragStart() {
    navigator!.didStartUserGesture();
  }

  void _dragUpdate(double fractionalDelta) {
    controller!.value -= fractionalDelta;
  }

  void _dragEnd(double fractionalVelocity) {
    final c = controller!;
    final nav = navigator!;

    final bool stay;
    if (fractionalVelocity.abs() >= _minFlingVelocity) {
      stay = fractionalVelocity < 0;
    } else {
      stay = c.value > 0.5;
    }

    if (stay) {
      // 取消返回：带着松手速度弹回原位。
      c.animateWith(SpringSimulation(Motion.snappy, c.value, 1.0, -fractionalVelocity));
    } else {
      nav.pop();
      if (c.isAnimating) {
        // 剩余距离越短、甩得越快，收尾越短；上限为常规 pop 时长。
        final byDistance = (Motion.pagePop.inMilliseconds * c.value).round();
        final byVelocity = fractionalVelocity > 0 ? (c.value / fractionalVelocity * 1000).round() : byDistance;
        final ms = byVelocity.clamp(120, byDistance < 120 ? 120 : byDistance);
        c.animateBack(
          0,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOutCubic,
        );
      }
    }

    if (c.isAnimating) {
      late AnimationStatusListener onDone;
      onDone = (status) {
        nav.didStopUserGesture();
        c.removeStatusListener(onDone);
      };
      c.addStatusListener(onDone);
    } else {
      nav.didStopUserGesture();
    }
  }
}

class _BackGestureDetector<T> extends StatefulWidget {
  const _BackGestureDetector({required this.route, required this.child});
  final AppPageRoute<T> route;
  final Widget child;

  @override
  State<_BackGestureDetector<T>> createState() => _BackGestureDetectorState<T>();
}

class _BackGestureDetectorState<T> extends State<_BackGestureDetector<T>> {
  late final HorizontalDragGestureRecognizer _recognizer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _onStart
      ..onUpdate = _onUpdate
      ..onEnd = _onEnd
      ..onCancel = _onCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // 手势进行中页面被销毁时，确保不会把 Navigator 留在「手势中」状态。
    if (_dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = widget.route.navigator;
        if (nav != null && nav.userGestureInProgress) nav.didStopUserGesture();
      });
    }
    super.dispose();
  }

  double get _width => context.size?.width ?? MediaQuery.sizeOf(context).width;
  double get _sign => Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  void _onStart(DragStartDetails d) {
    _dragging = true;
    widget.route._dragStart();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    widget.route._dragUpdate(_sign * (d.primaryDelta ?? 0) / _width);
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    widget.route._dragEnd(_sign * d.velocity.pixelsPerSecond.dx / _width);
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    widget.route._dragEnd(0);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    // 整页都可以发起右滑返回。识别器在手势竞技场里与页面内的纵向滚动、长按取词公平竞争：
    // 横向位移先超过阈值才会胜出，所以不影响上下滚动。
    return Listener(onPointerDown: _onPointerDown, behavior: HitTestBehavior.translucent, child: widget.child);
  }
}
