import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../motion/app_page_route.dart';
import '../../motion/entrance.dart';
import '../../motion/progress_ring.dart';
import '../articles/article_card.dart';
import '../reader/reader_page.dart';

/// 收藏的文章：按收藏时间倒序，左滑取消收藏（可撤销），点击进入阅读。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  static Route<void> route() => AppPageRoute<void>(
    settings: const RouteSettings(name: 'favorites'),
    builder: (_) => const FavoritesPage(),
  );

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final StaggerController _stagger = StaggerController();
  List<ArticleSummary>? _items;

  @override
  void initState() {
    super.initState();
    app.favorites.revision.addListener(_load);
    app.progress.revision.addListener(_load);
    app.analytics.track(Ev.pageView, {'page': 'favorites', 'from': 'profile'});
    _load();
  }

  @override
  void dispose() {
    app.favorites.revision.removeListener(_load);
    app.progress.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final items = await app.favorites.list(app.userId);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _remove(ArticleSummary a) async {
    unawaited(HapticFeedback.mediumImpact());
    final s = S.of(context);
    setState(() => _items = _items?.where((x) => x.id != a.id).toList());
    await app.favorites.setFavorite(app.userId, a.id, false);
    app.analytics.track(Ev.articleUnfavorite, {'article_id': a.id, 'source': 'favorites'});
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.deleted(a.title), maxLines: 1, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: s.undo,
            // 撤销时写回原收藏时间，列表顺序不变。
            onPressed: () => unawaited(app.favorites.setFavorite(app.userId, a.id, true, nowMs: a.favoritedAt)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    final items = _items;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.favoritesTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: s.back,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: items == null
          ? const SizedBox.shrink()
          : items.isEmpty
          ? EntranceItem(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmarks_outlined, size: 54, color: p.textTertiary),
                      const SizedBox(height: 14),
                      Text(
                        s.emptyFavoritesTitle,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(s.emptyFavoritesHint, style: TextStyle(fontSize: 13.5, color: p.textTertiary)),
                    ],
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final a = items[i];
                final savedAt = s.shortDate(DateTime.fromMillisecondsSinceEpoch(a.favoritedAt ?? 0), now);
                return Padding(
                  key: ValueKey('fav-${a.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EntranceItem(
                    controller: _stagger,
                    itemKey: a.id,
                    index: i,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Dismissible(
                        key: ValueKey('dismiss-fav-${a.id}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _remove(a),
                        background: Container(
                          color: const Color(0xFFE5484D),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22),
                          child: const Icon(Icons.bookmark_remove_outlined, color: Colors.white),
                        ),
                        child: ArticleRow(
                          article: a,
                          heroScope: 'favorites',
                          onTap: () =>
                              Navigator.of(context)
                                  .push(ReaderPage.route(summary: a, source: 'favorites', heroScope: 'favorites')),
                          title: Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: kReadingFont,
                              fontFamilyFallback: kReadingFontFallback,
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                          ),
                          subtitle: Text(
                            '${s.category(a.category)} · ${s.difficulty(a.difficulty)} · ${s.minutes(a.minutes)}',
                            style: TextStyle(fontSize: 12, color: p.textTertiary),
                          ),
                          footer: Row(
                            children: [
                              const Icon(Icons.bookmark_rounded, size: 14, color: Color(0xFFF5A623)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  s.favoritedAt(savedAt),
                                  style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                                ),
                              ),
                              if (a.completed || a.maxProgress > 0.02)
                                AnimatedProgressRing(
                                  progress: a.maxProgress,
                                  completed: a.completed,
                                  size: 24,
                                  strokeWidth: 2.4,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
