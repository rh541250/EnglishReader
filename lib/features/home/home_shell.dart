import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../articles/article_list_page.dart';
import '../profile/profile_page.dart';
import '../vocabulary/vocab_page.dart';

/// 登录后的主框架：阅读 / 生词本 / 我的。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _pages = ['article_list', 'vocabulary', 'profile'];
  int _index = 0;

  /// 懒创建：没点过的 Tab 不构建。
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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ArticleListPage(),
          _built.contains(1) ? const VocabPage() : const SizedBox.shrink(),
          _built.contains(2) ? const ProfilePage() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '阅读',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: '生词本',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
