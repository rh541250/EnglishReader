import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import 'models.dart';

/// 句子划线。划线即收藏：同一句（文章 + 段落 + 起始偏移）只记一行。
class SentenceRepository {
  SentenceRepository(this._db);
  final Database _db;

  final ValueNotifier<int> revision = ValueNotifier(0);

  /// 划线（幂等）。返回是否为新增。
  Future<bool> add({
    required String userId,
    required String articleId,
    required int paragraphIndex,
    required int start,
    required int end,
    required String text,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    // 「先查后插」放在一个事务里；不依赖 insert(ignore) 的返回值，各平台对它的约定不一致。
    final inserted = await _db.transaction((txn) async {
      final existing = await txn.query(
        'sentence_marks',
        columns: ['id'],
        where: 'user_id = ? AND article_id = ? AND paragraph_index = ? AND char_start = ?',
        whereArgs: [userId, articleId, paragraphIndex, start],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await txn.insert('sentence_marks', {
        'id': uuidV4(),
        'user_id': userId,
        'article_id': articleId,
        'paragraph_index': paragraphIndex,
        'char_start': start,
        'char_end': end,
        'text': text,
        'created_at': now,
        'version': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    });
    if (inserted) revision.value++;
    return inserted;
  }

  Future<void> remove({
    required String userId,
    required String articleId,
    required int paragraphIndex,
    required int start,
  }) async {
    await _db.delete(
      'sentence_marks',
      where: 'user_id = ? AND article_id = ? AND paragraph_index = ? AND char_start = ?',
      whereArgs: [userId, articleId, paragraphIndex, start],
    );
    revision.value++;
  }

  /// 某篇文章里的全部划线（阅读页渲染用）。
  Future<List<SentenceMark>> forArticle(String userId, String articleId) async {
    final rows = await _db.query(
      'sentence_marks',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
      orderBy: 'paragraph_index, char_start',
    );
    return rows.map(SentenceMark.fromRow).toList();
  }

  /// 笔记页：全部划线，最新的在前。
  Future<List<SentenceMark>> list(String userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT m.*, a.title AS article_title
      FROM sentence_marks m LEFT JOIN articles a ON a.id = m.article_id
      WHERE m.user_id = ?
      ORDER BY m.created_at DESC, m.id
    ''',
      [userId],
    );
    return rows.map(SentenceMark.fromRow).toList();
  }

  Future<int> count(String userId) async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM sentence_marks WHERE user_id = ?', [userId])) ?? 0;
}
