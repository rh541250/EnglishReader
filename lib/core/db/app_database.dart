import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// 打开（必要时创建 / 升级）应用数据库。
///
/// [factory] 可注入：App 内用 sqflite 默认工厂，单测用 sqflite_common_ffi。
Future<Database> openAppDatabase({
  required DatabaseFactory factory,
  required String path,
  int version = kSchemaVersion,
  Map<int, List<String>> migrations = kMigrations,
}) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // WAL：写入只追加日志，进程被杀时已提交事务不会丢，且读写互不阻塞。
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        } catch (_) {
          // 内存库或个别平台不支持时退回默认模式。
        }
      },
      onCreate: (db, v) => runMigrations(db, 0, v, migrations),
      onUpgrade: (db, from, to) => runMigrations(db, from, to, migrations),
    ),
  );
}

/// 依次执行 (from, to] 区间内的迁移。sqflite 会把 onCreate / onUpgrade
/// 包在一个事务里，并在成功后写入 `PRAGMA user_version`。
Future<void> runMigrations(DatabaseExecutor db, int from, int to, Map<int, List<String>> migrations) async {
  for (var v = from + 1; v <= to; v++) {
    final statements = migrations[v];
    if (statements == null) {
      throw StateError('缺少数据库迁移脚本: v$v');
    }
    for (final sql in statements) {
      await db.execute(sql);
    }
  }
}

/// meta 表读写小工具。
Future<String?> readMeta(DatabaseExecutor db, String key) async {
  final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
  return rows.isEmpty ? null : rows.first['value'] as String;
}

Future<void> writeMeta(DatabaseExecutor db, String key, String value) async {
  await db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
