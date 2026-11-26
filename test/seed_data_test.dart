import 'dart:convert';
import 'dart:io';

import 'package:english_reader/core/db/seed_importer.dart';
import 'package:english_reader/data/article_repository.dart';
import 'package:english_reader/data/dictionary_repository.dart';
import 'package:english_reader/data/models.dart';
import 'package:english_reader/domain/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 对真正打进安装包的种子数据做校验：结构合法、可导入、词表覆盖正文里的每一个词。
void main() {
  final articlesJson = File('assets/seed/articles.json').readAsStringSync();
  final dictionaryJson = File('assets/seed/dictionary.json').readAsStringSync();

  test('文章结构与分布', () {
    final articles = (jsonDecode(articlesJson) as List).cast<Map<String, dynamic>>();
    expect(articles.length, greaterThanOrEqualTo(20));
    expect(articles.map((a) => a['id']).toSet().length, articles.length);
    final keys = ArticleCategory.values.map((c) => c.key).toSet();
    for (final a in articles) {
      expect(keys.contains(a['category']), isTrue, reason: '${a['id']} category');
      expect([1, 2, 3].contains(a['difficulty']), isTrue, reason: '${a['id']} difficulty');
      expect((a['paragraphs'] as List).length, greaterThanOrEqualTo(4), reason: '${a['id']} paragraphs');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(a['published_at'] as String), isTrue);
    }
    // 每个分类、每个难度都有内容，筛选不会出现空列表。
    for (final c in keys) {
      for (final d in [1, 2, 3]) {
        expect(articles.any((a) => a['category'] == c && a['difficulty'] == d), isTrue, reason: '$c/$d');
      }
    }
  });

  test('可导入，且词表覆盖正文与标题中的每个单词（长按任意词都有释义）', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    final result = await importSeedIfNeeded(db, articlesJson: articlesJson, dictionaryJson: dictionaryJson);
    expect(result.imported, isTrue);

    final dict = DictionaryRepository(db);
    await dict.load();
    final repo = ArticleRepository(db);
    final missing = <String>{};
    for (final s in await repo.list(userId: '', limit: 1000)) {
      final article = (await repo.getById(s.id))!;
      for (final text in [article.summary.title, ...article.paragraphs]) {
        for (final t in tokenize(text).where((t) => t.isWord && t.text.length >= 2)) {
          if (!dict.lookup(t.text).found) missing.add(t.lower);
        }
      }
    }
    expect(missing, isEmpty, reason: '词表未覆盖: ${missing.take(20).join(', ')}');
  });
}
