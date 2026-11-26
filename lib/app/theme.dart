import 'package:material_ui/material_ui.dart';

/// 阅读主题：日间 / 护眼 / 夜间。作用于整个 App。
enum ReaderTheme {
  light('light'),
  sepia('sepia'),
  dark('dark');

  const ReaderTheme(this.key);
  final String key;

  static ReaderTheme fromKey(String? key) => values.firstWhere((t) => t.key == key, orElse: () => ReaderTheme.light);
}

/// 语义化调色板，通过 ThemeExtension 注入；切换主题时由 MaterialApp 自动做颜色补间。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.divider,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.success,
    required this.highlight,
    required this.marker,
    required this.brightness,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color onAccent;
  final Color divider;
  final Color skeleton;
  final Color skeletonHighlight;
  final Color success;

  /// 取词高亮底色。
  final Color highlight;

  /// 句子划线的荧光笔底色。
  final Color marker;
  final Brightness brightness;

  static const light = AppPalette(
    background: Color(0xFFF6F5F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEDE7),
    text: Color(0xFF1B1B1F),
    textSecondary: Color(0xFF5F5E66),
    textTertiary: Color(0xFF9B9AA3),
    accent: Color(0xFF3F51E0),
    onAccent: Color(0xFFFFFFFF),
    divider: Color(0x14000000),
    skeleton: Color(0xFFE7E5DF),
    skeletonHighlight: Color(0xFFF7F6F2),
    success: Color(0xFF1FA971),
    highlight: Color(0x333F51E0),
    marker: Color(0x66FFD54F),
    brightness: Brightness.light,
  );

  static const sepia = AppPalette(
    background: Color(0xFFF3EAD3),
    surface: Color(0xFFFAF3E0),
    surfaceAlt: Color(0xFFEADFC4),
    text: Color(0xFF3A2E1F),
    textSecondary: Color(0xFF6E5E48),
    textTertiary: Color(0xFFA08F76),
    accent: Color(0xFFB4601F),
    onAccent: Color(0xFFFFFFFF),
    divider: Color(0x1A3A2E1F),
    skeleton: Color(0xFFE6DABD),
    skeletonHighlight: Color(0xFFF6EED9),
    success: Color(0xFF4E8A3E),
    highlight: Color(0x38B4601F),
    marker: Color(0x59F2B33D),
    brightness: Brightness.light,
  );

  static const dark = AppPalette(
    background: Color(0xFF111215),
    surface: Color(0xFF1B1C21),
    surfaceAlt: Color(0xFF25262D),
    text: Color(0xFFE7E4DD),
    textSecondary: Color(0xFFA5A3AC),
    textTertiary: Color(0xFF6D6C75),
    accent: Color(0xFF8EA2FF),
    onAccent: Color(0xFF10121C),
    divider: Color(0x1FFFFFFF),
    skeleton: Color(0xFF25262D),
    skeletonHighlight: Color(0xFF33343D),
    success: Color(0xFF4CCB95),
    highlight: Color(0x408EA2FF),
    marker: Color(0x4DE0B341),
    brightness: Brightness.dark,
  );

  static AppPalette of(ReaderTheme t) => switch (t) {
    ReaderTheme.light => light,
    ReaderTheme.sepia => sepia,
    ReaderTheme.dark => dark,
  };

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      text: c(text, other.text),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      divider: c(divider, other.divider),
      skeleton: c(skeleton, other.skeleton),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      success: c(success, other.success),
      highlight: c(highlight, other.highlight),
      marker: c(marker, other.marker),
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// 正文字体：衬线体更适合长文阅读。iOS 用 Georgia，Android 回退到系统 serif。
const String kReadingFont = 'Georgia';
const List<String> kReadingFontFallback = ['Noto Serif', 'serif'];

ThemeData buildTheme(ReaderTheme theme) {
  final p = AppPalette.of(theme);
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  ).copyWith(primary: p.accent, onPrimary: p.onAccent, surface: p.surface, onSurface: p.text);
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    dividerColor: p.divider,
    textTheme: Typography.material2021(platform: TargetPlatform.iOS).black
        .apply(bodyColor: p.text, displayColor: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.accent : p.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? p.accent : p.textSecondary),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.brightness == Brightness.dark ? const Color(0xFF2E2F37) : const Color(0xFF26262B),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.surfaceAlt,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
  );
}
