import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/progress_repository.dart';
import '../../l10n/strings.dart';
import '../../motion/app_page_route.dart';
import '../../motion/entrance.dart';
import '../../motion/motion.dart';
import '../../motion/pressable.dart';
import '../debug/debug_panel_page.dart';
import '../favorites/favorites_page.dart';

/// 「我的」：阅读统计、近 7 日阅读时长、收藏的文章、设置（主题 / 语言）、调试入口、退出登录。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ReadingStats? _stats;
  List<MapEntry<String, int>> _daily = const [];
  int _notes = 0;
  int _favorites = 0;

  @override
  void initState() {
    super.initState();
    for (final n in _sources) {
      n.addListener(_load);
    }
    _load();
  }

  @override
  void dispose() {
    for (final n in _sources) {
      n.removeListener(_load);
    }
    super.dispose();
  }

  List<Listenable> get _sources => [
    app.progress.revision,
    app.vocab.revision,
    app.sentences.revision,
    app.favorites.revision,
  ];

  Future<void> _load() async {
    final uid = app.userId;
    if (uid.isEmpty) return;
    final stats = await app.progress.stats(uid);
    final daily = await app.progress.dailyDurations(uid);
    final notes = await app.vocab.count(uid) + await app.sentences.count(uid);
    final favorites = await app.favorites.count(uid);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _daily = daily;
      _notes = notes;
      _favorites = favorites;
    });
  }

  void _pickLanguage() {
    showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => const _LanguageSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = S.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final user = app.auth.currentUser.value;
    final s = _stats;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 28),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: p.accent.withValues(alpha: 0.15),
                child: Text(
                  (user?.username ?? '?').characters.first.toUpperCase(),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username ?? '',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text),
                    ),
                    Text(t.localAccount, style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (s != null)
          EntranceItem(
            child: Row(
              children: [
                _StatTile(label: t.statStreak, value: s.streakDays, suffix: t.unitDays, color: const Color(0xFFFF7A1A)),
                const SizedBox(width: 10),
                _StatTile(label: t.statFinished, value: s.finishedCount, suffix: t.unitArticles, color: p.success),
                const SizedBox(width: 10),
                _StatTile(
                  label: t.statTotal,
                  value: (s.totalDurationMs / 60000).round(),
                  suffix: t.unitMinutes,
                  color: p.accent,
                ),
                const SizedBox(width: 10),
                _StatTile(label: t.statNotes, value: _notes, suffix: t.unitItems, color: const Color(0xFFF5A623)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 70),
          child: _Section(
            title: t.weekChartTitle,
            trailing: s == null ? null : t.todayMinutes((s.todayDurationMs / 60000).toStringAsFixed(1)),
            child: SizedBox(height: 132, child: _WeekChart(data: _daily)),
          ),
        ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 140),
          child: _Group(
            children: [
              _MenuRow(
                icon: Icons.bookmarks_outlined,
                title: t.favoritesTitle,
                value: '$_favorites',
                onTap: () => Navigator.of(context).push(FavoritesPage.route()),
              ),
              // 主题收成一行：三个色点，选中项外圈描边。完整的主题卡片仍在阅读页的设置面板里。
              _MenuRow(
                icon: Icons.palette_outlined,
                title: t.theme,
                trailing: ListenableBuilder(listenable: app.settings, builder: (_, _) => const _ThemeDots()),
              ),
              ListenableBuilder(
                listenable: app.settings,
                builder: (context, _) => _MenuRow(
                  icon: Icons.translate_rounded,
                  title: t.language,
                  value: t.languageName(app.settings.language),
                  onTap: _pickLanguage,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 210),
          child: _Group(
            children: [
              _MenuRow(
                icon: Icons.insights_rounded,
                title: t.debugPanel,
                subtitle: t.debugPanelSubtitle,
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    settings: const RouteSettings(name: 'debug'),
                    builder: (_) => const DebugPanelPage(),
                  ),
                ),
              ),
              _MenuRow(
                icon: Icons.logout_rounded,
                title: t.logout,
                subtitle: t.logoutSubtitle,
                onTap: () => app.auth.logout(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一组设置行，共用一张圆角卡片，行间细分隔线。
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 52, color: p.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, this.subtitle, this.value, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: p.textSecondary, size: 21),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: p.textTertiary)),
                ],
              ],
            ),
          ),
          if (value != null) Text(value!, style: TextStyle(fontSize: 14, color: p.textTertiary)),
          ?trailing,
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
    return onTap == null ? row : Pressable(pressedScale: 0.985, onTap: onTap, child: row);
  }
}

/// 紧凑的主题选择：三个色点，选中项外圈描边并轻微放大。
class _ThemeDots extends StatelessWidget {
  const _ThemeDots();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = S.of(context);
    final current = app.settings.theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in ReaderTheme.values)
          Semantics(
            button: true,
            selected: t == current,
            label: s.themeName(t),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (t == current) return;
                HapticFeedback.selectionClick();
                app.settings.theme = t;
                app.analytics.track(Ev.settingChange, {'key': 'theme', 'value': t.key});
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  curve: Motion.enter,
                  width: 30,
                  height: 30,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t == current ? p.accent : Colors.transparent, width: 2),
                  ),
                  child: AnimatedScale(
                    scale: t == current ? 1 : 0.86,
                    duration: Motion.quick,
                    curve: Curves.easeOutBack,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppPalette.of(t).background,
                        border: Border.all(color: p.divider),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 语言选择面板。切换后整个 App 立即以新语言重建，选择持久化在本地。
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.settings,
      builder: (context, _) {
        final p = context.palette;
        final s = S.of(context);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: Text(
                    s.language,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text),
                  ),
                ),
                for (final l in AppLanguage.values)
                  Pressable(
                    pressedScale: 0.985,
                    onTap: () {
                      if (app.settings.language != l) {
                        HapticFeedback.selectionClick();
                        app.settings.language = l;
                        app.analytics.track(Ev.settingChange, {'key': 'language', 'value': l.key});
                      }
                      Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(s.languageName(l), style: TextStyle(fontSize: 15.5, color: p.text)),
                          ),
                          AnimatedScale(
                            scale: app.settings.language == l ? 1 : 0,
                            duration: Motion.quick,
                            curve: Curves.easeOutBack,
                            child: Icon(Icons.check_rounded, color: p.accent, size: 22),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.suffix, required this.color});
  final String label;
  final int value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.divider),
        ),
        child: Column(
          children: [
            // 数值变化时从旧值滚动到新值。
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Motion.enter,
              builder: (context, v, _) => Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${v.round()}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
                    ),
                    TextSpan(
                      text: suffix,
                      style: TextStyle(fontSize: 10.5, color: p.textTertiary),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, color: p.textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
              ),
              const Spacer(),
              if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 近 7 日柱状图：柱子从 0 生长到目标高度，数据变化时在新旧高度之间补间。
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.data});
  final List<MapEntry<String, int>> data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (data.isEmpty) return const SizedBox.shrink();
    final maxMs = data.map((e) => e.value).fold<int>(60000, (m, v) => v > m ? v : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < data.length; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  data[i].value == 0 ? '' : (data[i].value / 60000).toStringAsFixed(data[i].value < 600000 ? 1 : 0),
                  style: TextStyle(fontSize: 10.5, color: p.textTertiary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: data[i].value / maxMs),
                  duration: Duration(milliseconds: 520 + i * 60),
                  curve: Motion.enter,
                  builder: (context, v, _) => Container(
                    height: 4 + 80 * v,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: i == data.length - 1 ? p.accent : p.accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  i == data.length - 1 ? S.of(context).today : data[i].key.substring(5),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: i == data.length - 1 ? p.accent : p.textTertiary,
                    fontWeight: i == data.length - 1 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
