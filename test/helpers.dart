import 'dart:convert';
import 'dart:io';

import 'package:english_reader/core/db/app_database.dart';
import 'package:english_reader/core/db/seed_importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 单测用数据库：桌面端通过 FFI 直接跑真实的 SQLite，执行的是与 App 完全相同的建表脚本。
Future<Database> openTestDb({String? path}) {
  sqfliteFfiInit();
  return openAppDatabase(factory: databaseFactoryFfi, path: path ?? inMemoryDatabasePath);
}

const String kTestArticles = '''
[
  {"id":"a001","title":"First Story","title_zh":"第一篇","category":"tech","difficulty":1,"author":"A","published_at":"2026-11-03","summary":"s1","paragraphs":["Cats sleep a lot. They are running fast.","Second paragraph here."]},
  {"id":"a002","title":"Second Story","title_zh":"第二篇","category":"business","difficulty":2,"author":"B","published_at":"2026-11-02","summary":"s2","paragraphs":["Money talks."]},
  {"id":"a003","title":"Third Story","title_zh":"第三篇","category":"tech","difficulty":3,"author":"C","published_at":"2026-11-01","summary":"s3","paragraphs":["Chips are small."]}
]
''';

final String kTestDictionary = jsonEncode({
  'entries': {
    'cat': {'phonetic': '/kæt/', 'pos': 'n.', 'meaning': '猫'},
    'run': {'phonetic': '/rʌn/', 'pos': 'v.', 'meaning': '跑'},
    'sleep': {'phonetic': '/sliːp/', 'pos': 'v.', 'meaning': '睡觉'},
  },
  'forms': {'running': 'run'},
});

Future<Database> openSeededTestDb({String? path}) async {
  final db = await openTestDb(path: path);
  await importSeedIfNeeded(db, articlesJson: kTestArticles, dictionaryJson: kTestDictionary);
  return db;
}

/// 临时文件数据库路径（用于「关闭后重新打开」类测试）。
String tempDbPath(String name) {
  final dir = Directory.systemTemp.createTempSync('english_reader_test_');
  return '${dir.path}/$name.db';
}
