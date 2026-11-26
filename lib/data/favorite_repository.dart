import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// 文章收藏。
class FavoriteRepository {
  FavoriteRepository(this._db);
  final Database _db;

  /// 收藏状态变化时 +1，列表页、我的页据此刷新。
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<bool> isFavorite(String userId, String articleId) async {
    final rows = await _db.query(
      'article_favorites',
      columns: ['article_id'],
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 设置收藏状态（幂等）：收藏时已存在则保留原收藏时间，取消时不存在也不报错。
  Future<void> setFavorite(String userId, String articleId, bool favorite, {int? nowMs}) async {
    if (favorite) {
      await _db.insert('article_favorites', {
        'user_id': userId,
        'article_id': articleId,
        'created_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.delete('article_favorites', where: 'user_id = ? AND article_id = ?', whereArgs: [userId, articleId]);
    }
    revision.value++;
  }

  /// 收藏的文章，按收藏时间倒序，附带阅读进度。
  Future<List<ArticleSummary>> list(String userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT a.id, a.title, a.title_zh, a.category, a.difficulty, a.author, a.published_at, a.summary, a.word_count,
             p.max_progress, p.completed, p.last_read_at, f.created_at AS favorited_at
      FROM article_favorites f
      JOIN articles a ON a.id = f.article_id
      LEFT JOIN reading_progress p ON p.article_id = a.id AND p.user_id = f.user_id
      WHERE f.user_id = ?
      ORDER BY f.created_at DESC, a.id
    ''',
      [userId],
    );
    return rows.map(ArticleSummary.fromRow).toList();
  }

  Future<int> count(String userId) async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM article_favorites WHERE user_id = ?', [userId])) ??
      0;
}
