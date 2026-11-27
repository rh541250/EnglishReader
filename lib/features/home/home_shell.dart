import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../motion/motion.dart';
import '../articles/article_list_page.dart';
import '../notebook/notebook_page.dart';
import '../profile/profile_page.dart';

/// 登录后的主框架：阅读 / 笔记 / 我的。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _pages = ['article_list', 'notebook', 'profile'];
  int _index = 0;

  /// 懒创建：没点过的 Tab 不构建。已创建的页面保留状态（滚动位置等）。
  final Set<int> _built = {0};

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _built.add(i);
    });
    app.analytics.track(Ev.pageView, {'page': _pages[i], 'from': 'tab'});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: _FadeThrough(
        index: _index,
        children: [
          const ArticleListPage(),
          _built.contains(1) ? const NotebookPage() : const SizedBox.shrink(),
          _built.contains(2) ? const ProfilePage() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _TabBar(
        index: _index,
        onTap: _select,
        items: [
          _TabSpec(Icons.menu_book_outlined, Icons.menu_book_rounded, s.tabRead),
          _TabSpec(Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded, s.tabNotebook),
          _TabSpec(Icons.person_outline_rounded, Icons.person_rounded, s.tabMe),
        ],
      ),
    );
  }
}

/// 页面切换：旧页淡出，新页从 0.97 倍淡入放大（Material 的 fade-through 模式）。
///
/// 已创建的页面都保留在树里（保留滚动位置）；未选中的页面关闭 [TickerMode]，
/// 不在后台跑动画，也不接收点击。
class _FadeThrough extends StatelessWidget {
  const _FadeThrough({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != index,
              child: TickerMode(
                enabled: i == index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: const Duration(milliseconds: 280),
                  curve: Motion.standard,
                  child: AnimatedScale(
                    scale: i == index ? 1 : 0.97,
                    duration: const Duration(milliseconds: 360),
                    curve: Motion.enter,
                    child: children[i],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TabSpec {
  const _TabSpec(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 底部导航（自绘，替代 NavigationBar 以便控制图标动画）。
/// 选中项：指示胶囊展开，图标从描边变为实心并弹性放大。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<_TabSpec> items;

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: _height + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _TabItem(spec: items[i], selected: i == index, onTap: () => onTap(i)),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.spec, required this.selected, required this.onTap});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              width: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: Motion.entrance,
                    curve: Motion.enter,
                    width: selected ? 64 : 24,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: selected ? 0.14 : 0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      selected ? spec.selectedIcon : spec.icon,
                      key: ValueKey(selected),
                      size: 24,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              curve: Motion.enter,
              style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
              child: Text(spec.label),
            ),
          ],
        ),
      ),
    );
  }
}
