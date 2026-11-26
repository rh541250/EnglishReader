import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../analytics/exposure.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/progress_repository.dart';
import '../../motion/entrance.dart';
import '../../motion/motion.dart';
import '../../motion/shimmer.dart';
import '../../motion/sliding_tabs.dart';
import '../reader/reader_page.dart';
import 'article_card.dart';

/// 数据都在本地 SQLite，查询是毫秒级的；首次加载与下拉刷新时加一段模拟延迟，
/// 用来代表「真实场景下的远端同步耗时」，否则骨架屏和刷新指示器根本看不到。
const Duration kMockLatency = Duration(milliseconds: 650);

class ArticleListPage extends StatefulWidget {
  const ArticleListPage({super.key});

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  static const int _pageSize = 8;
  static const List<ArticleCategory?> _categories = [null, ...ArticleCategory.values];

  final ScrollController _scroll = ScrollController();
  final StaggerController _stagger = StaggerController();

  int _categoryIndex = 0;
  int? _difficulty;
  List<ArticleSummary> _items = [];
  ArticleSummary? _continue;
  int _streak = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _generation = 0;

  ArticleCategory? get _category => _categories[_categoryIndex];

  @override
  void initState() {
    super.initState();
    app.progress.revision.addListener(_refreshSilently);
    app.analytics.track(Ev.pageView, {'page': 'article_list'});
    _loadFirstPage(withLatency: true);
  }

  @override
  void dispose() {
    app.progress.revision.removeListener(_refreshSilently);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage({bool withLatency = false, bool showSkeleton = true}) async {
    final generation = ++_generation;
    if (showSkeleton && withLatency) setState(() => _loading = true);
    final uid = app.userId;
    final results = await Future.wait<Object?>([
      app.articles.list(userId: uid, category: _category, difficulty: _difficulty, limit: _pageSize),
      app.articles.continueReading(uid),
      app.progress.stats(uid),
      if (withLatency) Future<void>.delayed(kMockLatency),
    ]);
    // 期间又切了筛选条件：丢弃这次过期的结果。
    if (!mounted || generation != _generation) return;
    final items = results[0] as List<ArticleSummary>;
    _stagger.restart();
    setState(() {
      _items = items;
      _continue = results[1] as ArticleSummary?;
      _streak = (results[2] as ReadingStats).streakDays;
      _hasMore = items.length == _pageSize;
      _loading = false;
    });
    if (!app.network.isOnline) {
      app.analytics.track(Ev.offlineHit, {'resource': 'article_list'});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final more = await app.articles.list(
      userId: app.userId,
      category: _category,
      difficulty: _difficulty,
      limit: _pageSize,
      offset: _items.length,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _items = [..._items, ...more];
      _hasMore = more.length == _pageSize;
      _loadingMore = false;
    });
  }

  /// 阅读进度有变化（从阅读页返回）：只刷新数据，不重播入场动效。
  Future<void> _refreshSilently() async {
    if (_loading || !mounted) return;
    final generation = _generation;
    final uid = app.userId;
    final results = await Future.wait<Object?>([
      app.articles.list(
        userId: uid,
        category: _category,
        difficulty: _difficulty,
        limit: _items.length < _pageSize ? _pageSize : _items.length,
      ),
      app.articles.continueReading(uid),
      app.progress.stats(uid),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _items = results[0] as List<ArticleSummary>;
      _continue = results[1] as ArticleSummary?;
      _streak = (results[2] as ReadingStats).streakDays;
    });
  }

  Future<void> _onRefresh() async {
    app.analytics.track(Ev.listRefresh, {'category': _category?.key ?? 'all', 'difficulty': _difficulty});
    unawaited(app.network.check());
    await _loadFirstPage(withLatency: true, showSkeleton: false);
  }

  void _onCategory(int index) {
    final from = _category?.key ?? 'all';
    setState(() => _categoryIndex = index);
    app.analytics.track(Ev.categorySwitch, {'filter_type': 'category', 'from': from, 'to': _category?.key ?? 'all'});
    _loadFirstPage();
  }

  void _onDifficulty(int? level) {
    if (level == _difficulty) return;
    HapticFeedback.selectionClick();
    final from = _difficulty;
    setState(() => _difficulty = level);
    app.analytics.track(Ev.categorySwitch, {
      'filter_type': 'difficulty',
      'from': '${from ?? 'all'}',
      'to': '${level ?? 'all'}',
    });
    _loadFirstPage();
  }

  void _open(ArticleSummary a, {String source = 'list', String heroScope = 'list'}) {
    Navigator.of(context).push(ReaderPage.route(summary: a, source: source, heroScope: heroScope));
  }

  void _onExposed(ArticleSummary a, int position) {
    if (!app.analytics.markExposed(a.id)) return;
    app.analytics.track(Ev.articleExpose, {
      'article_id': a.id,
      'position': position,
      'category': a.category.key,
      'difficulty': a.difficulty,
      'list_category': _category?.key ?? 'all',
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top;
    final user = app.auth.currentUser.value;

    return ExposureScope(
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 500) _loadMore();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: p.accent,
          backgroundColor: p.surface,
          edgeOffset: top,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 14, 20, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hi, ${user?.username ?? ''}',
                              style: TextStyle(fontSize: 14, color: p.textSecondary, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '今天读点什么？',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      _StreakChip(days: _streak),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: Motion.entrance,
                  curve: Motion.enter,
                  alignment: Alignment.topCenter,
                  child: _continue == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: ContinueCard(
                            article: _continue!,
                            onTap: () => _open(_continue!, source: 'continue', heroScope: 'continue'),
                          ),
                        ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterHeader(
                  background: p.background,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SlidingTabs(
                        labels: [for (final c in _categories) c?.label ?? '全部'],
                        index: _categoryIndex,
                        onChanged: _onCategory,
                      ),
                      const SizedBox(height: 8),
                      _DifficultyFilter(value: _difficulty, onChanged: _onDifficulty),
                    ],
                  ),
                ),
              ),
              if (_loading)
                SliverToBoxAdapter(
                  child: Shimmer(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Column(
                        children: [
                          for (var i = 0; i < 3; i++)
                            const Padding(padding: EdgeInsets.only(bottom: 14), child: ArticleCardSkeleton()),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('这个筛选条件下还没有文章', style: TextStyle(color: p.textTertiary, fontSize: 14)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  // SliverList 按需构建：只有视口附近的卡片存在于树中（虚拟滚动）。
                  sliver: SliverList.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final a = _items[i];
                      return Padding(
                        key: ValueKey('card-${a.id}'),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: EntranceItem(
                          controller: _stagger,
                          itemKey: a.id,
                          index: i,
                          child: ExposureDetector(
                            onExposed: () => _onExposed(a, i),
                            child: ArticleCard(article: a, onTap: () => _open(a)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 72,
                  child: Center(
                    child: _loading
                        ? null
                        : _loadingMore
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent),
                          )
                        : !_hasMore && _items.isNotEmpty
                        ? Text('— 已经到底啦 —', style: TextStyle(fontSize: 12.5, color: p.textTertiary))
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  _FilterHeader({required this.child, required this.background});
  final Widget child;
  final Color background;

  @override
  double get minExtent => 104;
  @override
  double get maxExtent => 104;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: background, child: child);
  }

  @override
  bool shouldRebuild(_FilterHeader old) => old.child != child || old.background != background;
}

class _DifficultyFilter extends StatelessWidget {
  const _DifficultyFilter({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final options = <int?, String>{null: '全部难度', ...kDifficultyLabels};
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  curve: Motion.enter,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == e.key ? p.accent.withValues(alpha: 0.13) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: value == e.key ? p.accent : p.divider),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: value == e.key ? p.accent : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const fire = Color(0xFFFF7A1A);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 13, 7),
      decoration: BoxDecoration(
        color: days > 0 ? fire.withValues(alpha: 0.13) : p.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 18, color: days > 0 ? fire : p.textTertiary),
          const SizedBox(width: 3),
          // 天数变化时旧数字上滑淡出、新数字从下方滑入。
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.6),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                child: child,
              ),
            ),
            child: Text(
              '$days 天',
              key: ValueKey(days),
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: days > 0 ? fire : p.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
