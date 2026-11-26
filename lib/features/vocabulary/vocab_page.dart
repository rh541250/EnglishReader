import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../motion/entrance.dart';
import '../../motion/pressable.dart';
import '../reader/reader_page.dart';

/// 生词本：查看、左滑删除（可撤销）、点击跳回原文出处。
class VocabPage extends StatefulWidget {
  const VocabPage({super.key});

  @override
  State<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends State<VocabPage> {
  final StaggerController _stagger = StaggerController();
  List<VocabEntry>? _entries;

  @override
  void initState() {
    super.initState();
    app.vocab.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.vocab.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await app.vocab.list(app.userId);
    if (mounted) setState(() => _entries = list);
  }

  Future<void> _delete(VocabEntry e) async {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _entries = _entries?.where((x) => x.id != e.id).toList());
    await app.vocab.remove(app.userId, e.word);
    app.analytics.track(Ev.wordRemove, {'word': e.word, 'source': 'vocab', 'article_id': e.articleId});
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${e.display}」'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
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
            },
          ),
        ),
      );
  }

  Future<void> _jumpToSource(VocabEntry e) async {
    final summary = await app.articles.summaryById(e.articleId, userId: app.userId);
    if (summary == null || !mounted) return;
    Navigator.of(context).push(
      ReaderPage.route(
        summary: summary,
        source: 'vocab',
        heroScope: 'vocab',
        target: ReaderTarget(e.paragraphIndex, e.wordIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top;
    final entries = _entries;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '生词本',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text),
                ),
                const SizedBox(width: 10),
                if (entries != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${entries.length} 个词', style: TextStyle(fontSize: 13.5, color: p.textTertiary)),
                  ),
              ],
            ),
          ),
        ),
        if (entries == null)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EntranceItem(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 54, color: p.textTertiary),
                  const SizedBox(height: 14),
                  Text(
                    '还没有生词',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text('阅读时长按任意单词即可取词收藏', style: TextStyle(fontSize: 13.5, color: p.textTertiary)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return Padding(
                  key: ValueKey(e.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EntranceItem(
                    controller: _stagger,
                    itemKey: e.id,
                    index: i,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Dismissible(
                        key: ValueKey('dismiss-${e.id}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _delete(e),
                        background: Container(
                          color: const Color(0xFFE5484D),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                        child: _VocabTile(entry: e, onTap: () => _jumpToSource(e)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _VocabTile extends StatelessWidget {
  const _VocabTile({required this.entry, required this.onTap});
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
                  TextSpan(text: e.meaning),
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
            Row(
              children: [
                Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: p.accent),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '原文：${e.articleTitle ?? e.articleId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.accent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
