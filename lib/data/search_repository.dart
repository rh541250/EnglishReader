import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/text_ranges.dart';
import 'models.dart';

/// 一条搜索结果。
class SearchResult {
  const SearchResult({required this.article, required this.titleMatches, this.bodyHit});

  final ArticleSummary article;

  /// 标题里命中的区间（高亮用）。
  final List<Span> titleMatches;

  /// 正文里的第一个命中（展示片段、打开后定位）；只命中标题 / 摘要时为 null。
  final SearchHit? bodyHit;
}

/// 本地全文搜索 + 搜索历史。
///
/// 匹配：每个搜索词都必须出现在「标题 / 中文标题 / 摘要 / 正文」之一（多词 AND），不区分大小写。
/// 实现用 LIKE 而不是 FTS5：Android 系统自带的 SQLite 不保证编译了 FTS5，
/// 而内置文章只有几十篇，LIKE 全表扫描在毫秒级。文章量上千后再切 FTS（见 README）。
/// 排序：标题命中 > 摘要命中 > 只在正文命中，同级按发布时间倒序。
class SearchRepository {
  SearchRepository(this._db);
  final Database _db;

  static const int historyLimit = 10;

  Future<List<SearchResult>> search(String userId, String query, {int limit = 50}) async {
    final terms = parseSearchTerms(query);
    if (terms.isEmpty) return const [];

    final where = <String>[];
    final args = <Object?>[userId, userId];
    for (final t in terms) {
      final like = '%${_escapeLike(t)}%';
      where.add(
        "(a.title LIKE ? ESCAPE '\\' OR a.title_zh LIKE ? ESCAPE '\\' "
        "OR a.summary LIKE ? ESCAPE '\\' OR a.body_json LIKE ? ESCAPE '\\')",
      );
      args.addAll([like, like, like, like]);
    }
    // 排序分：所有词都在标题里 = 0，都在摘要里 = 1，其余 = 2。
    final titleAll = terms.map((_) => "a.title LIKE ? ESCAPE '\\'").join(' AND ');
    final summaryAll = terms.map((_) => "a.summary LIKE ? ESCAPE '\\'").join(' AND ');
    for (final t in terms) {
      args.add('%${_escapeLike(t)}%');
    }
    for (final t in terms) {
      args.add('%${_escapeLike(t)}%');
    }
    args.add(limit);

    final rows = await _db.rawQuery('''
      SELECT a.id, a.title, a.title_zh, a.category, a.difficulty, a.author, a.published_at, a.summary,
             a.word_count, a.body_json,
             p.max_progress, p.completed, p.last_read_at, f.created_at AS favorited_at
      FROM articles a
      LEFT JOIN reading_progress p ON p.article_id = a.id AND p.user_id = ?
      LEFT JOIN article_favorites f ON f.article_id = a.id AND f.user_id = ?
      WHERE ${where.join(' AND ')}
      ORDER BY CASE WHEN $titleAll THEN 0 WHEN $summaryAll THEN 1 ELSE 2 END, a.published_at DESC, a.id
      LIMIT ?
    ''', args);

    return [
      for (final r in rows)
        () {
          final summary = ArticleSummary.fromRow(r);
          final paragraphs = (jsonDecode(r['body_json'] as String) as List).cast<String>();
          return SearchResult(
            article: summary,
            titleMatches: findMatches(summary.title, terms),
            bodyHit: firstBodyHit(paragraphs, terms),
          );
        }(),
    ];
  }

  /// LIKE 的通配符 % 和 _ 需要转义，否则搜「50%」会匹配到所有含「50」的文章。
  static String _escapeLike(String s) => s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  // ---- 搜索历史 ----

  Future<List<String>> history(String userId) async {
    final rows = await _db.query(
      'search_history',
      columns: ['query'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'last_used_at DESC',
      limit: historyLimit,
    );
    return [for (final r in rows) r['query'] as String];
  }

  /// 记录一次搜索：同一关键词刷新时间（整行替换），并只保留最近 [historyLimit] 条。
  Future<void> addHistory(String userId, String query, {int? nowMs}) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await _db.transaction((txn) async {
      await txn.insert('search_history', {
        'user_id': userId,
        'query': q,
        'last_used_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete(
        '''
        DELETE FROM search_history WHERE user_id = ? AND query NOT IN (
          SELECT query FROM search_history WHERE user_id = ? ORDER BY last_used_at DESC LIMIT ?
        )
      ''',
        [userId, userId, historyLimit],
      );
    });
  }

  Future<void> clearHistory(String userId) => _db.delete('search_history', where: 'user_id = ?', whereArgs: [userId]);
}
