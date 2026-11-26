import 'package:sqflite/sqflite.dart';

import 'models.dart';

const String _summaryColumns =
    'a.id, a.title, a.title_zh, a.category, a.difficulty, a.author, a.published_at, a.summary, a.word_count';

/// 当前用户的阅读状态与收藏状态。
const String _userColumns = 'p.max_progress, p.completed, p.last_read_at, f.created_at AS favorited_at';

/// 两个 LEFT JOIN 各需要绑定一次 user_id。
const String _userJoins = '''LEFT JOIN reading_progress p ON p.article_id = a.id AND p.user_id = ?
      LEFT JOIN article_favorites f ON f.article_id = a.id AND f.user_id = ?''';

class ArticleRepository {
  ArticleRepository(this._db);
  final Database _db;

  /// 分页列表。排序固定为发布时间倒序 + id，保证翻页稳定。
  Future<List<ArticleSummary>> list({
    required String userId,
    ArticleCategory? category,
    int? difficulty,
    int limit = 8,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[userId, userId];
    if (category != null) {
      where.add('a.category = ?');
      args.add(category.key);
    }
    if (difficulty != null) {
      where.add('a.difficulty = ?');
      args.add(difficulty);
    }
    args
      ..add(limit)
      ..add(offset);
    final rows = await _db.rawQuery('''
      SELECT $_summaryColumns, $_userColumns
      FROM articles a
      $_userJoins
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY a.published_at DESC, a.id
      LIMIT ? OFFSET ?
    ''', args);
    return rows.map(ArticleSummary.fromRow).toList();
  }

  Future<Article?> getById(String id, {String userId = ''}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT $_summaryColumns, a.body_json, $_userColumns
      FROM articles a
      $_userJoins
      WHERE a.id = ?
    ''',
      [userId, userId, id],
    );
    return rows.isEmpty ? null : Article.fromRow(rows.first);
  }

  Future<ArticleSummary?> summaryById(String id, {String userId = ''}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT $_summaryColumns, $_userColumns
      FROM articles a
      $_userJoins
      WHERE a.id = ?
    ''',
      [userId, userId, id],
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.first);
  }

  /// 上一篇（列表中更靠前、即更新的一篇）。
  Future<ArticleSummary?> previousOf(ArticleSummary a) async {
    final rows = await _db.rawQuery(
      '''
      SELECT $_summaryColumns FROM articles a
      WHERE a.published_at > ? OR (a.published_at = ? AND a.id < ?)
      ORDER BY a.published_at ASC, a.id DESC LIMIT 1
    ''',
      [a.publishedAt, a.publishedAt, a.id],
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.first);
  }

  /// 下一篇（列表中更靠后、即更早的一篇）。
  Future<ArticleSummary?> nextOf(ArticleSummary a) async {
    final rows = await _db.rawQuery(
      '''
      SELECT $_summaryColumns FROM articles a
      WHERE a.published_at < ? OR (a.published_at = ? AND a.id > ?)
      ORDER BY a.published_at DESC, a.id ASC LIMIT 1
    ''',
      [a.publishedAt, a.publishedAt, a.id],
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.first);
  }

  /// 最近一篇未读完的文章，用于首页「继续阅读」。
  Future<ArticleSummary?> continueReading(String userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT $_summaryColumns, $_userColumns
      FROM reading_progress p JOIN articles a ON a.id = p.article_id
      LEFT JOIN article_favorites f ON f.article_id = a.id AND f.user_id = p.user_id
      WHERE p.user_id = ? AND p.completed = 0 AND p.max_progress > 0.02
      ORDER BY p.last_read_at DESC LIMIT 1
    ''',
      [userId],
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.first);
  }

  Future<int> count() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM articles')) ?? 0;
}
