import 'dart:math';

final Random _secure = Random.secure();

/// RFC 4122 v4 UUID。
String uuidV4() {
  final b = List<int>.generate(16, (_) => _secure.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// 可注入的时钟，便于单测。
typedef NowFn = DateTime Function();

DateTime systemNow() => DateTime.now();

/// 本地日期键 `yyyy-MM-dd`。
String dayKey(DateTime t) {
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}
