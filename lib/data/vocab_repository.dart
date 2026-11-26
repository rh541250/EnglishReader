import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import 'models.dart';

class VocabRepository {
  VocabRepository(this._db);
  final Database _db;

  /// 生词本有增删时 +1。
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// 收藏。同一用户同一词元重复收藏不产生新行（UNIQUE + INSERT OR IGNORE，幂等）。
  /// 返回是否为新增。
  Future<bool> add({
    required String userId,
    required DictEntry entry,
    required String display,
    required String articleId,
    required int paragraphIndex,
    required int wordIndex,
    required String context,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final inserted = await _db.transaction((txn) async {
      final existing = await txn.query(
        'vocabulary',
        columns: ['id'],
        where: 'user_id = ? AND word = ?',
        whereArgs: [userId, entry.word],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await txn.insert('vocabulary', {
        'id': uuidV4(),
        'user_id': userId,
        'word': entry.word,
        'display': display,
        'phonetic': entry.phonetic,
        'pos': entry.pos,
        'meaning': entry.meaning,
        'article_id': articleId,
        'paragraph_index': paragraphIndex,
        'word_index': wordIndex,
        'context': context,
        'created_at': now,
        'version': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    });
    if (inserted) revision.value++;
    return inserted;
  }

  Future<void> remove(String userId, String word) async {
    await _db.delete('vocabulary', where: 'user_id = ? AND word = ?', whereArgs: [userId, word]);
    revision.value++;
  }

  Future<List<VocabEntry>> list(String userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT v.*, a.title AS article_title
      FROM vocabulary v LEFT JOIN articles a ON a.id = v.article_id
      WHERE v.user_id = ?
      ORDER BY v.created_at DESC, v.word
    ''',
      [userId],
    );
    return rows.map(VocabEntry.fromRow).toList();
  }

  /// 当前用户已收藏的全部词元，阅读页用来给正文里的生词加下划线。
  Future<Set<String>> collectedWords(String userId) async {
    final rows = await _db.query('vocabulary', columns: ['word'], where: 'user_id = ?', whereArgs: [userId]);
    return {for (final r in rows) r['word'] as String};
  }

  Future<int> count(String userId) async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM vocabulary WHERE user_id = ?', [userId])) ?? 0;
}
