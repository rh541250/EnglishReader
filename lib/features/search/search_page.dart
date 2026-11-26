import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/search_repository.dart';
import '../../l10n/strings.dart';
import '../../motion/entrance.dart';
import '../../motion/fade_page_route.dart';
import '../../motion/motion.dart';
import '../articles/article_card.dart';
import '../reader/reader_page.dart';
import 'search_bar.dart';

/// 搜索页：输入即搜（220ms 防抖），空输入时显示搜索历史。
///
/// 「一次搜索」的口径：边输入边出结果的中间状态不算，只有用户表现出确认意图——
/// 键盘回车、点搜索历史、或从结果里打开文章——才写入搜索历史并上报 search_submit。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  static Route<void> route() => FadePageRoute<void>(
    settings: const RouteSettings(name: 'search'),
    builder: (_) => const SearchPage(),
  );

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const Duration _debounceDelay = Duration(milliseconds: 220);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final StaggerController _stagger = StaggerController();

  List<String> _history = const [];
  List<SearchResult>? _results;
  String _query = '';
  String? _committed;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    app.analytics.track(Ev.pageView, {'page': 'search'});
    _loadHistory();
    // 等搜索栏飞到位再弹键盘：转场途中弹键盘会挤压布局，Hero 的终点位置也会跟着变。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        _focus.requestFocus();
        return;
      }
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          animation.removeStatusListener(listener);
          if (mounted) _focus.requestFocus();
        }
      }

      animation.addStatusListener(listener);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await app.search.history(app.userId);
    if (mounted) setState(() => _history = h);
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _generation++;
      setState(() {
        _query = '';
        _results = null;
      });
      return;
    }
    _debounce = Timer(_debounceDelay, () => _run(text));
  }

  Future<void> _run(String text) async {
    final generation = ++_generation;
    final results = await app.search.search(app.userId, text);
    // 期间输入又变了：丢弃过期结果，避免慢查询覆盖新结果。
    if (!mounted || generation != _generation) return;
    _stagger.restart();
    setState(() {
      _query = text.trim();
      _results = results;
    });
  }

  Future<void> _commit(String source) async {
    final q = _query;
    if (q.isEmpty || q == _committed) return;
    _committed = q;
    app.analytics.track(Ev.searchSubmit, {'keyword': q, 'result_count': _results?.length ?? 0, 'source': source});
    await app.search.addHistory(app.userId, q);
    await _loadHistory();
  }

  Future<void> _onSubmitted(String text) async {
    _debounce?.cancel();
    if (text.trim().isEmpty) return;
    await _run(text);
    await _commit('input');
  }

  Future<void> _useHistory(String q) async {
    unawaited(HapticFeedback.selectionClick());
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _focus.unfocus();
    await _run(q);
    await _commit('history');
  }

  Future<void> _clearHistory() async {
    await app.search.clearHistory(app.userId);
    await _loadHistory();
  }

  void _clearInput() {
    _controller.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  void _close() {
    _focus.unfocus();
    Navigator.of(context).maybePop();
  }

  Future<void> _open(SearchResult r, int position) async {
    _focus.unfocus();
    unawaited(_commit('result'));
    final hit = r.bodyHit;
    app.analytics.track(Ev.searchResultClick, {
      'article_id': r.article.id,
      'position': position,
      'keyword': _query,
      'hit': hit == null ? 'title' : 'body',
    });
    // 命中正文时直接定位到命中处并闪烁提示；只命中标题 / 摘要时按正常逻辑恢复阅读位置。
    await Navigator.of(context).push(
      ReaderPage.route(
        summary: r.article,
        source: 'search',
        heroScope: 'search',
        target: hit == null ? null : ReaderTarget.range(hit.paragraphIndex, hit.match.start, hit.match.end),
      ),
    );
    // 返回时刷新：期间可能收藏 / 读完了文章。
    if (mounted && _query.isNotEmpty) unawaited(_run(_query));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      onSubmitted: _onSubmitted,
                      onClear: _clearInput,
                    ),
                  ),
                  TextButton(
                    onPressed: _close,
                    child: Text(s.cancel, style: TextStyle(fontSize: 15, color: p.accent)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.quick,
                switchInCurve: Motion.enter,
                child: _results == null ? _buildHistory(p, s) : _buildResults(p, s, _results!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(AppPalette p, S s) {
    if (_history.isEmpty) return const SizedBox.expand(key: ValueKey('empty-history'));
    return ListView(
      key: const ValueKey('history'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Text(
              s.searchHistory,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearHistory,
              icon: Icon(Icons.delete_outline_rounded, size: 17, color: p.textTertiary),
              label: Text(s.clearHistory, style: TextStyle(fontSize: 13, color: p.textTertiary)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _history.length; i++)
              EntranceItem(
                delay: Duration(milliseconds: 30 * i),
                offset: 10,
                child: GestureDetector(
                  onTap: () => _useHistory(_history[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                    child: Text(_history[i], style: TextStyle(fontSize: 13.5, color: p.textSecondary)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildResults(AppPalette p, S s, List<SearchResult> results) {
    if (results.isEmpty) {
      return EntranceItem(
        key: ValueKey('none:$_query'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 120),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.manage_search_rounded, size: 52, color: p.textTertiary),
                const SizedBox(height: 12),
                Text(
                  s.noResults,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(s.noResultsHint, style: TextStyle(fontSize: 13, color: p.textTertiary)),
              ],
            ),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final highlight = TextStyle(color: p.accent, fontWeight: FontWeight.w800, backgroundColor: p.highlight);
    return ListView.builder(
      key: const ValueKey('results'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(s.resultCount(results.length), style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
          );
        }
        final r = results[i - 1];
        final a = r.article;
        final hit = r.bodyHit;
        return Padding(
          key: ValueKey('result-${a.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: EntranceItem(
            controller: _stagger,
            itemKey: '$_query|${a.id}',
            index: i - 1,
            child: ArticleRow(
              article: a,
              heroScope: 'search',
              onTap: () => _open(r, i - 1),
              title: Text.rich(
                highlightedSpan(
                  a.title,
                  r.titleMatches,
                  TextStyle(
                    fontFamily: kReadingFont,
                    fontFamilyFallback: kReadingFontFallback,
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                  highlight,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text.rich(
                hit == null
                    ? TextSpan(text: a.summary)
                    : highlightedSpan(hit.snippet, hit.snippetMatches, const TextStyle(), highlight),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.45, color: p.textSecondary),
              ),
              footer: Row(
                children: [
                  if (a.favorited) ...[
                    const Icon(Icons.bookmark_rounded, size: 14, color: Color(0xFFF5A623)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      '${s.category(a.category)} · ${s.difficulty(a.difficulty)} · ${s.publishDate(a.publishedDate, now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
