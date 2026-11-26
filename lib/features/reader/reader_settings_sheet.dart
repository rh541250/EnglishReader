import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';

/// 阅读设置面板：字号、行距、主题。改动即时生效，背后的正文实时预览。
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => const ReaderSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = app.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final p = context.palette;
        final s = S.of(context);
        final label = TextStyle(fontSize: 13, color: p.textSecondary, fontWeight: FontWeight.w600);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(color: p.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(s.fontSize, style: label),
                    const Spacer(),
                    Text('${settings.fontSize.round()}', style: label.copyWith(color: p.text)),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'A',
                      style: TextStyle(fontSize: 14, color: p.textSecondary, fontWeight: FontWeight.w700),
                    ),
                    Expanded(
                      child: Slider(
                        value: settings.fontSize,
                        min: AppSettings.minFontSize,
                        max: AppSettings.maxFontSize,
                        divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
                        onChanged: (v) {
                          if (v.round() != settings.fontSize.round()) HapticFeedback.selectionClick();
                          settings.fontSize = v;
                        },
                        onChangeEnd: (v) =>
                            app.analytics.track(Ev.settingChange, {'key': 'font_size', 'value': v.round()}),
                      ),
                    ),
                    Text(
                      'A',
                      style: TextStyle(fontSize: 22, color: p.textSecondary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(s.lineHeight, style: label),
                    const Spacer(),
                    Text(settings.lineHeight.toStringAsFixed(1), style: label.copyWith(color: p.text)),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.density_small_rounded, size: 18, color: p.textSecondary),
                    Expanded(
                      child: Slider(
                        value: settings.lineHeight,
                        min: AppSettings.minLineHeight,
                        max: AppSettings.maxLineHeight,
                        divisions: ((AppSettings.maxLineHeight - AppSettings.minLineHeight) * 10).round(),
                        onChanged: (v) => settings.lineHeight = v,
                        onChangeEnd: (v) => app.analytics.track(Ev.settingChange, {
                          'key': 'line_height',
                          'value': (v * 10).round() / 10,
                        }),
                      ),
                    ),
                    Icon(Icons.density_large_rounded, size: 18, color: p.textSecondary),
                  ],
                ),
                const SizedBox(height: 10),
                Text(s.theme, style: label),
                const SizedBox(height: 12),
                const ThemeSelector(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 三个主题色块，选中项有外环并轻微放大。
class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = app.settings;
    final p = context.palette;
    return Row(
      children: [
        for (final t in ReaderTheme.values) ...[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (settings.theme == t) return;
                HapticFeedback.selectionClick();
                settings.theme = t;
                app.analytics.track(Ev.settingChange, {'key': 'theme', 'value': t.key});
              },
              child: AnimatedScale(
                scale: settings.theme == t ? 1.0 : 0.96,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppPalette.of(t).background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: settings.theme == t ? p.accent : p.divider,
                      width: settings.theme == t ? 2.2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    S.of(context).themeName(t),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.of(t).text),
                  ),
                ),
              ),
            ),
          ),
          if (t != ReaderTheme.values.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}
