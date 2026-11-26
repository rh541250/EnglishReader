import 'package:english_reader/data/article_repository.dart';
import 'package:english_reader/data/favorite_repository.dart';
import 'package:english_reader/data/search_repository.dart';
import 'package:english_reader/data/sentence_repository.dart';
import 'package:english_reader/domain/text_ranges.dart';
import 'package:english_reader/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  group('分句', () {
    test('按句末标点切分，区间不含句间空格', () {
      const text = 'Cats sleep a lot. Do they dream? Yes!  Maybe';
      final spans = splitSentences(text);
      expect(
        [for (final s in spans) text.substring(s.start, s.end)],
        ['Cats sleep a lot.', 'Do they dream?', 'Yes!', 'Maybe'],
      );
    });

    test('引号 / 省略号跟在句末，缩写不断句', () {
      const text = 'He said "Stop." Then Dr. Lee left... Mr. Smith stayed.';
      final spans = splitSentences(text);
      expect(
        [for (final s in spans) text.substring(s.start, s.end)],
        ['He said "Stop."', 'Then Dr. Lee left...', 'Mr. Smith stayed.'],
      );
    });

    test('sentenceAt：句内返回该句，句间空白归到前一句', () {
      const text = 'One two. Three four.';
      final spans = splitSentences(text);
      expect(sentenceAt(spans, 0), const Span(0, 8));
      expect(sentenceAt(spans, 8), const Span(0, 8)); // 空格
      expect(sentenceAt(spans, 12), const Span(9, 20));
    });
  });

  group('搜索文本', () {
    test('解析搜索词：转小写、去重、按空白切分', () {
      expect(parseSearchTerms('  Phone  WARM phone '), ['phone', 'warm']);
      expect(parseSearchTerms('   '), isEmpty);
    });

    test('命中区间：不区分大小写，重叠合并', () {
      expect(findMatches('Warm phones warm up', ['warm']), const [Span(0, 4), Span(12, 16)]);
      expect(findMatches('reading', ['read', 'ading']), const [Span(0, 7)]);
      expect(findMatches('abc', ['x']), isEmpty);
    });

    test('正文片段：返回命中段落与区间，片段内命中可高亮，截断处带省略号', () {
      final long = '${'word ' * 30}target ${'tail ' * 40}';
      final hit = firstBodyHit(['nothing here', long], ['target'])!;
      expect(hit.paragraphIndex, 1);
      expect(long.substring(hit.match.start, hit.match.end), 'target');
      expect(hit.snippet.startsWith('…'), isTrue);
      expect(hit.snippet.endsWith('…'), isTrue);
      final m = hit.snippetMatches.single;
      expect(hit.snippet.substring(m.start, m.end), 'target');
    });
  });

  group('文案与日期', () {
    final now = DateTime(2026, 11, 26, 9);

    test('发布时间：7 天内相对时间，更早显示日期，跨年带年份', () {
      const zh = SZh(), en = SEn();
      expect(zh.publishDate(DateTime(2026, 11, 26), now), '今天');
      expect(zh.publishDate(DateTime(2026, 11, 25, 23), now), '昨天');
      expect(zh.publishDate(DateTime(2026, 11, 20), now), '6 天前');
      expect(zh.publishDate(DateTime(2026, 11, 4), now), '11月4日');
      expect(zh.publishDate(DateTime(2025, 12, 31), now), '2025年12月31日');
      expect(en.publishDate(DateTime(2026, 11, 25), now), 'Yesterday');
      expect(en.publishDate(DateTime(2026, 11, 4), now), 'Nov 4');
      expect(en.publishDate(DateTime(2025, 12, 31), now), 'Dec 31, 2025');
    });

    test('跟随系统：中文系统用中文，其余语言一律英文', () {
      expect(resolveAppLocale(const Locale('zh', 'TW')), const Locale('zh'));
      expect(resolveAppLocale(const Locale('ja')), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
      expect(S.forLocale(const Locale('zh')), isA<SZh>());
    });
  });

  group('收藏 / 划线 / 搜索仓储', () {
    late Database db;
    setUp(() async => db = await openSeededTestDb());
    tearDown(() async => db.close());

    test('文章收藏：幂等、保留首次收藏时间、按收藏时间倒序，列表联查带出状态', () async {
      final fav = FavoriteRepository(db);
      await fav.setFavorite('u1', 'a002', true, nowMs: 100);
      await fav.setFavorite('u1', 'a003', true, nowMs: 200);
      await fav.setFavorite('u1', 'a002', true, nowMs: 999); // 重复收藏
      final list = await fav.list('u1');
      expect(list.map((a) => a.id), ['a003', 'a002']);
      expect(list.last.favoritedAt, 100);
      expect(await fav.count('u1'), 2);

      final articles = await ArticleRepository(db).list(userId: 'u1');
      expect(articles.where((a) => a.favorited).map((a) => a.id).toSet(), {'a002', 'a003'});
      expect((await ArticleRepository(db).getById('a003', userId: 'u1'))!.summary.favorited, isTrue);
      expect((await ArticleRepository(db).list(userId: 'u2')).any((a) => a.favorited), isFalse);

      await fav.setFavorite('u1', 'a002', false);
      await fav.setFavorite('u1', 'a002', false); // 重复取消
      expect(await fav.isFavorite('u1', 'a002'), isFalse);
    });

    test('句子划线：同一句只记一次，按文章取出，删除后可重新划线', () async {
      final repo = SentenceRepository(db);
      Future<bool> mark(int start, {int now = 1}) => repo.add(
        userId: 'u1',
        articleId: 'a001',
        paragraphIndex: 0,
        start: start,
        end: start + 5,
        text: 'x',
        nowMs: now,
      );
      expect(await mark(0), isTrue);
      expect(await mark(0, now: 2), isFalse);
      expect(await mark(18, now: 3), isTrue);
      final marks = await repo.forArticle('u1', 'a001');
      expect(marks.map((m) => m.start), [0, 18]);
      final all = await repo.list('u1');
      expect(all.first.start, 18); // 最新的在前
      expect(all.first.articleTitle, 'First Story');
      await repo.remove(userId: 'u1', articleId: 'a001', paragraphIndex: 0, start: 0);
      expect(await repo.count('u1'), 1);
      expect(await mark(0, now: 4), isTrue);
    });

    test('搜索：多词 AND、标题命中排在正文命中之前、正文命中给出定位', () async {
      final repo = SearchRepository(db);
      // 「story」只在标题里，三篇都命中，按发布时间倒序。
      expect((await repo.search('u1', 'story')).map((r) => r.article.id), ['a001', 'a002', 'a003']);
      // 多词 AND：两个词都要出现。
      final both = await repo.search('u1', 'cats running');
      expect(both.single.article.id, 'a001');
      final hit = both.single.bodyHit!;
      expect(hit.paragraphIndex, 0);
      expect('Cats sleep a lot. They are running fast.'.substring(hit.match.start, hit.match.end), 'Cats');
      // 标题命中优先：「chips」在 a003 正文，「third」在 a003 标题。
      final ranked = await repo.search('u1', 'second');
      expect(ranked.first.article.id, 'a002'); // 标题含 Second
      expect(ranked.first.titleMatches, isNotEmpty);
      expect(await repo.search('u1', 'nothing-matches'), isEmpty);
    });

    test('搜索：LIKE 通配符被转义', () async {
      expect(await SearchRepository(db).search('u1', '%'), isEmpty);
      expect(await SearchRepository(db).search('u1', '_'), isEmpty);
    });

    test('搜索历史：同词刷新时间不重复，最多保留 10 条，可清空', () async {
      final repo = SearchRepository(db);
      for (var i = 0; i < 12; i++) {
        await repo.addHistory('u1', 'q$i', nowMs: i);
      }
      await repo.addHistory('u1', 'q3', nowMs: 100);
      final h = await repo.history('u1');
      expect(h.length, SearchRepository.historyLimit);
      expect(h.first, 'q3');
      expect(h.contains('q0'), isFalse);
      await repo.clearHistory('u1');
      expect(await repo.history('u1'), isEmpty);
    });
  });
}
