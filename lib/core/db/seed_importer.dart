import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/tokenizer.dart';
import 'app_database.dart';

/// 种子数据版本。内置 JSON 有更新时 +1，下次启动会重新导入（upsert）。
const String kSeedVersion = '1';
const String _metaSeedKey = 'seed_version';

class SeedResult {
  const SeedResult({required this.imported, required this.articles, required this.words});
  final bool imported;
  final int articles;
  final int words;
}

/// 首次启动（或种子版本变化）时把内置 JSON 导入 SQLite。
///
/// 幂等：整个导入在一个事务内，文章按 id、词条按 word 做 REPLACE，
/// 版本号最后写入；中途被杀则事务回滚，下次启动重新导入。
Future<SeedResult> importSeedIfNeeded(
  Database db, {
  required String articlesJson,
  required String dictionaryJson,
  String seedVersion = kSeedVersion,
  int Function()? nowMs,
}) async {
  final current = await readMeta(db, _metaSeedKey);
  if (current == seedVersion) {
    return const SeedResult(imported: false, articles: 0, words: 0);
  }
  final now = (nowMs ?? () => DateTime.now().millisecondsSinceEpoch)();
  final articles = (jsonDecode(articlesJson) as List).cast<Map<String, dynamic>>();
  final dict = jsonDecode(dictionaryJson) as Map<String, dynamic>;
  final entries = (dict['entries'] as Map).cast<String, dynamic>();
  final forms = (dict['forms'] as Map? ?? const {}).cast<String, dynamic>();

  await db.transaction((txn) async {
    final batch = txn.batch();
    for (final a in articles) {
      final paragraphs = (a['paragraphs'] as List).cast<String>();
      final wordCount = paragraphs.fold<int>(0, (n, p) => n + countWords(p));
      batch.insert('articles', {
        'id': a['id'],
        'title': a['title'],
        'title_zh': a['title_zh'] ?? '',
        'category': a['category'],
        'difficulty': a['difficulty'],
        'author': a['author'] ?? '',
        'published_at': a['published_at'],
        'summary': a['summary'] ?? '',
        'body_json': jsonEncode(paragraphs),
        'word_count': wordCount,
        'version': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    entries.forEach((word, value) {
      final e = (value as Map).cast<String, dynamic>();
      batch.insert('dictionary', {
        'word': word.toLowerCase(),
        'phonetic': e['phonetic'] ?? '',
        'pos': e['pos'] ?? '',
        'meaning': e['meaning'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    forms.forEach((form, lemma) {
      batch.insert('dictionary_forms', {
        'form': form.toLowerCase(),
        'lemma': (lemma as String).toLowerCase(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
    await writeMeta(txn, _metaSeedKey, seedVersion);
  });
  return SeedResult(imported: true, articles: articles.length, words: entries.length);
}
