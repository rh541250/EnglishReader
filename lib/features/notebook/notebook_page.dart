import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../motion/entrance.dart';
import '../../motion/motion.dart';
import '../../motion/pressable.dart';
import '../../motion/sliding_tabs.dart';
import '../reader/reader_page.dart';

/// 笔记：阅读中积累下来的学习内容，分「单词」「句子」两栏。
///
/// 两栏共用同一套交互：左滑删除（可撤销）、点击跳回原文出处并闪烁高亮。
/// 文章收藏不放这里——收藏的是「整篇文章」，入口在「我的」。
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  final List<StaggerController> _stagger = [StaggerController(), StaggerController()];
  int _segment = 0;
  int _direction = 1;
  List<VocabEntry>? _words;
  List<SentenceMark>? _sentences;

  @override
  void initState() {
    super.initState();
    app.vocab.revision.addListener(_load);
    app.sentences.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.vocab.revision.removeListener(_load);
    app.sentences.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = app.userId;
    final words = await app.vocab.list(uid);
    final sentences = await app.sentences.list(uid);
    if (mounted) {
      setState(() {
        _words = words;
        _sentences = sentences;
      });
    }
  }

  void _switch(int i) {
    setState(() {
      _direction = i > _segment ? 1 : -1;
      _segment = i;
      _stagger[i].restart();
    });
    app.analytics.track(Ev.pageView, {'page': i == 0 ? 'notebook_words' : 'notebook_sentences', 'from': 'segment'});
  }

  void _showUndo(String text, Future<void> Function() undo) {
    final s = S.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.deleted(text), maxLines: 1, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: s.undo, onPressed: () => unawaited(undo())),
        ),
      );
  }

  Future<void> _deleteWord(VocabEntry e) async {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _words = _words?.where((x) => x.id != e.id).toList());
    await app.vocab.remove(app.userId, e.word);
    app.analytics.track(Ev.wordRemove, {'word': e.word, 'source': 'notebook', 'article_id': e.articleId});
    if (!mounted) return;
    _showUndo(e.display, () async {
      await app.vocab.add(
        userId: app.userId,
        entry: DictEntry(word: e.word, phonetic: e.phonetic, pos: e.pos, meaning: e.meaning),
        display: e.display,
        articleId: e.articleId,
        paragraphIndex: e.paragraphIndex,
        wordIndex: e.wordIndex,
        context: e.context,
        nowMs: e.createdAt,
      );
    });
  }

  Future<void> _deleteSentence(SentenceMark m) async {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _sentences = _sentences?.where((x) => x.id != m.id).toList());
    await app.sentences.remove(
      userId: app.userId,
      articleId: m.articleId,
      paragraphIndex: m.paragraphIndex,
      start: m.start,
    );
    app.analytics.track(Ev.sentenceUnmark, {
      'article_id': m.articleId,
      'paragraph_index': m.paragraphIndex,
      'source': 'notebook',
    });
    if (!mounted) return;
    final preview = m.text.length > 24 ? '${m.text.substring(0, 24)}…' : m.text;
    _showUndo(preview, () async {
      await app.sentences.add(
        userId: app.userId,
        articleId: m.articleId,
        paragraphIndex: m.paragraphIndex,
        start: m.start,
        end: m.end,
        text: m.text,
        nowMs: m.createdAt,
      );
    });
  }

  Future<void> _jump(String articleId, ReaderTarget target) async {
    final summary = await app.articles.summaryById(articleId, userId: app.userId);
    if (summary == null || !mounted) return;
    await Navigator.of(context)
        .push(ReaderPage.route(summary: summary, source: 'notebook', heroScope: 'notebook', target: target));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 14, 20, 10),
          child: Text(
            s.notebookTitle,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text),
          ),
        ),
        SlidingTabs(
          labels: [s.notebookWords(_words?.length ?? 0), s.notebookSentences(_sentences?.length ?? 0)],
          index: _segment,
          onChanged: _switch,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.quick,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            // 切到右边那栏时内容从右侧滑入，切回左栏时从左侧滑入，与指示器的运动方向一致。
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: Offset(0.06 * _direction, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: _segment == 0 ? _buildWords(p, s) : _buildSentences(p, s),
          ),
        ),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String hint, Key key) {
    final p = context.palette;
    return EntranceItem(
      key: key,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: p.textTertiary),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(hint, style: TextStyle(fontSize: 13.5, color: p.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWords(AppPalette p, S s) {
    final words = _words;
    if (words == null) return const SizedBox.shrink(key: ValueKey('words-loading'));
    if (words.isEmpty) {
      return _empty(Icons.translate_rounded, s.emptyWordsTitle, s.emptyWordsHint, const ValueKey('words-empty'));
    }
    return ListView.builder(
      key: const ValueKey('words'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: words.length,
      itemBuilder: (context, i) {
        final e = words[i];
        return _Item(
          key: ValueKey(e.id),
          stagger: _stagger[0],
          index: i,
          onDelete: () => _deleteWord(e),
          child: _WordTile(entry: e, onTap: () => _jump(e.articleId, ReaderTarget.word(e.paragraphIndex, e.wordIndex))),
        );
      },
    );
  }

  Widget _buildSentences(AppPalette p, S s) {
    final sentences = _sentences;
    if (sentences == null) return const SizedBox.shrink(key: ValueKey('sentences-loading'));
    if (sentences.isEmpty) {
      return _empty(
        Icons.format_quote_rounded,
        s.emptySentencesTitle,
        s.emptySentencesHint,
        const ValueKey('sentences-empty'),
      );
    }
    return ListView.builder(
      key: const ValueKey('sentences'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: sentences.length,
      itemBuilder: (context, i) {
        final m = sentences[i];
        return _Item(
          key: ValueKey(m.id),
          stagger: _stagger[1],
          index: i,
          onDelete: () => _deleteSentence(m),
          child: _SentenceTile(
            mark: m,
            onTap: () => _jump(m.articleId, ReaderTarget.range(m.paragraphIndex, m.start, m.end)),
          ),
        );
      },
    );
  }
}

/// 列表项外壳：交错入场 + 左滑删除。
class _Item extends StatelessWidget {
  const _Item({super.key, required this.stagger, required this.index, required this.onDelete, required this.child});
  final StaggerController stagger;
  final int index;
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EntranceItem(
        controller: stagger,
        itemKey: key,
        index: index,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Dismissible(
            key: ValueKey('dismiss-$key'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => onDelete(),
            background: Container(
              color: const Color(0xFFE5484D),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: p.accent),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            S.of(context).source(title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: p.accent, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({required this.entry, required this.onTap});
  final VocabEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = entry;
    return Pressable(
      pressedScale: 0.985,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  e.word,
                  style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, color: p.text),
                ),
                const SizedBox(width: 8),
                if (e.phonetic.isNotEmpty)
                  Expanded(
                    child: Text(e.phonetic, style: TextStyle(fontSize: 13, color: p.textTertiary)),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(
                children: [
                  if (e.pos.isNotEmpty)
                    TextSpan(
                      text: '${e.pos} ',
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
                    ),
                  TextSpan(text: e.meaning.isEmpty ? S.of(context).notInDictionary : e.meaning),
                ],
              ),
              style: TextStyle(fontSize: 14.5, height: 1.4, color: p.textSecondary),
            ),
            if (e.context.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                e.context,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kReadingFont,
                  fontFamilyFallback: kReadingFontFallback,
                  fontSize: 13.5,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: p.textTertiary,
                ),
              ),
            ],
            const SizedBox(height: 9),
            _SourceLine(title: e.articleTitle ?? e.articleId),
          ],
        ),
      ),
    );
  }
}

/// 句子卡片：左侧一道荧光笔色条，正文用衬线体，与阅读页里的划线样式呼应。
class _SentenceTile extends StatelessWidget {
  const _SentenceTile({required this.mark, required this.onTap});
  final SentenceMark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    return Pressable(
      pressedScale: 0.985,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.divider),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                margin: const EdgeInsets.fromLTRB(12, 16, 0, 16),
                decoration: BoxDecoration(color: p.marker.withValues(alpha: 1), borderRadius: BorderRadius.circular(3)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mark.text,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kReadingFont,
                          fontFamilyFallback: kReadingFontFallback,
                          fontSize: 15.5,
                          height: 1.5,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SourceLine(title: mark.articleTitle ?? mark.articleId),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: Text(
                          s.shortDate(DateTime.fromMillisecondsSinceEpoch(mark.createdAt), DateTime.now()),
                          style: TextStyle(fontSize: 11.5, color: p.textTertiary),
                        ),
                      ),
                    ],
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
