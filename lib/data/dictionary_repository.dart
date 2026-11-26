import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Mock 词表。数据落在 SQLite，启动时整表读入内存（约两千词，几十 KB），
/// 之后取词是同步的内存查找——长按拖动换词时不能有任何等待。
class DictionaryRepository {
  DictionaryRepository(this._db);
  final Database _db;

  final Map<String, DictEntry> _entries = {};
  final Map<String, String> _forms = {};

  int get size => _entries.length;

  Future<void> load() async {
    _entries.clear();
    _forms.clear();
    for (final r in await _db.query('dictionary')) {
      final w = r['word'] as String;
      _entries[w] = DictEntry(
        word: w,
        phonetic: r['phonetic'] as String? ?? '',
        pos: r['pos'] as String? ?? '',
        meaning: r['meaning'] as String,
      );
    }
    for (final r in await _db.query('dictionary_forms')) {
      _forms[r['form'] as String] = r['lemma'] as String;
    }
  }

  /// 把正文里的词形还原为词元。查不到时返回小写原词。
  String lemmaOf(String token) => _resolve(token.toLowerCase())?.word ?? token.toLowerCase();

  /// 取词。词表未收录时返回占位词条（found = false），仍可收藏。
  DictEntry lookup(String token) {
    final lower = token.toLowerCase();
    return _resolve(lower) ?? DictEntry(word: lower, phonetic: '', pos: '', meaning: 'Mock 词表暂未收录该词', found: false);
  }

  DictEntry? _resolve(String lower) {
    final direct = _entries[lower];
    if (direct != null) return direct;
    final viaForm = _forms[lower];
    if (viaForm != null && _entries[viaForm] != null) return _entries[viaForm];
    for (final candidate in _stemCandidates(lower)) {
      final e = _entries[candidate];
      if (e != null) return e;
    }
    return null;
  }

  /// 词表 forms 未覆盖时的兜底：按常见英语屈折后缀尝试还原。
  static Iterable<String> _stemCandidates(String w) sync* {
    if (w.endsWith("'s")) yield w.substring(0, w.length - 2);
    if (w.endsWith("s'")) yield w.substring(0, w.length - 1);
    if (w.endsWith('ies') && w.length > 4) yield '${w.substring(0, w.length - 3)}y';
    if (w.endsWith('es') && w.length > 3) yield w.substring(0, w.length - 2);
    if (w.endsWith('s') && w.length > 2) yield w.substring(0, w.length - 1);
    if (w.endsWith('ied') && w.length > 4) yield '${w.substring(0, w.length - 3)}y';
    if (w.endsWith('ed') && w.length > 3) {
      yield w.substring(0, w.length - 2);
      yield w.substring(0, w.length - 1);
      if (w.length > 5 && w[w.length - 3] == w[w.length - 4]) yield w.substring(0, w.length - 3);
    }
    if (w.endsWith('ing') && w.length > 4) {
      final stem = w.substring(0, w.length - 3);
      yield stem;
      yield '${stem}e';
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        yield stem.substring(0, stem.length - 1);
      }
    }
    if (w.endsWith('ly') && w.length > 3) yield w.substring(0, w.length - 2);
    if (w.endsWith('er') && w.length > 3) {
      yield w.substring(0, w.length - 2);
      yield w.substring(0, w.length - 1);
    }
    if (w.endsWith('est') && w.length > 4) {
      yield w.substring(0, w.length - 3);
      yield w.substring(0, w.length - 2);
    }
  }
}
