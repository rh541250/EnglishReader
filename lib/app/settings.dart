import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import 'theme.dart';

/// 阅读设置（字号 / 行距 / 主题）与界面语言。
///
/// 持久化走 SQLite 的 `meta` 键值表（[persist] 由外部注入）：只有三个键，
/// 没必要为此再引入一个 KV 原生插件；启动时随开库一次读出，之后写入是异步的、不阻塞界面。
class AppSettings extends ChangeNotifier {
  AppSettings({Map<String, String> initial = const {}, this.persist})
    : _fontSize = double.tryParse(initial[keyFont] ?? '') ?? defaultFontSize,
      _lineHeight = double.tryParse(initial[keyLine] ?? '') ?? defaultLineHeight,
      _theme = ReaderTheme.fromKey(initial[keyTheme]),
      _language = AppLanguage.fromKey(initial[keyLanguage]);

  final Future<void> Function(String key, String value)? persist;

  static const keyFont = 'reader_font_size';
  static const keyLine = 'reader_line_height';
  static const keyTheme = 'reader_theme';
  static const keyLanguage = 'app_language';
  static const keys = [keyFont, keyLine, keyTheme, keyLanguage];

  static const double minFontSize = 15, maxFontSize = 26, defaultFontSize = 18;
  static const double minLineHeight = 1.4, maxLineHeight = 2.1, defaultLineHeight = 1.7;

  double _fontSize;
  double _lineHeight;
  ReaderTheme _theme;
  AppLanguage _language;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  ReaderTheme get theme => _theme;
  AppLanguage get language => _language;

  set fontSize(double v) {
    v = v.clamp(minFontSize, maxFontSize).roundToDouble();
    if (v == _fontSize) return;
    _fontSize = v;
    persist?.call(keyFont, '$v');
    notifyListeners();
  }

  set lineHeight(double v) {
    v = (v.clamp(minLineHeight, maxLineHeight) * 10).round() / 10;
    if (v == _lineHeight) return;
    _lineHeight = v;
    persist?.call(keyLine, '$v');
    notifyListeners();
  }

  set theme(ReaderTheme v) {
    if (v == _theme) return;
    _theme = v;
    persist?.call(keyTheme, v.key);
    notifyListeners();
  }

  set language(AppLanguage v) {
    if (v == _language) return;
    _language = v;
    persist?.call(keyLanguage, v.key);
    notifyListeners();
  }
}
