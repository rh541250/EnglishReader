import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// 淡入路由：给「搜索」这类模态浮层用。
///
/// 页面本身只做淡入 + 轻微上移 12px，主角是从列表页飞过来的搜索栏（Hero）。
/// 如果再叠加默认的右侧滑入，页面在横移、搜索栏在纵移，两个运动方向会互相打架。
/// 这类页面不支持右滑返回，通过「取消」按钮退出（与系统搜索的交互一致）。
class FadePageRoute<T> extends PageRoute<T> {
  FadePageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      Semantics(scopesRoute: true, explicitChildNodes: true, child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) => Transform.translate(offset: Offset(0, 12 * (1 - curved.value)), child: child),
      ),
    );
  }
}
