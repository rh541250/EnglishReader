import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/progress_repository.dart';
import '../../motion/app_page_route.dart';
import '../../motion/entrance.dart';
import '../../motion/motion.dart';
import '../../motion/pressable.dart';
import '../debug/debug_panel_page.dart';
import '../reader/reader_settings_sheet.dart';

/// 「我的」：阅读统计、近 7 日阅读时长、主题、调试入口、退出登录。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ReadingStats? _stats;
  List<MapEntry<String, int>> _daily = const [];
  int _words = 0;

  @override
  void initState() {
    super.initState();
    app.progress.revision.addListener(_load);
    app.vocab.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.progress.revision.removeListener(_load);
    app.vocab.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = app.userId;
    if (uid.isEmpty) return;
    final stats = await app.progress.stats(uid);
    final daily = await app.progress.dailyDurations(uid);
    final words = await app.vocab.count(uid);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _daily = daily;
      _words = words;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
                    Text('本地账号 · 数据仅保存在这台设备', style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
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
                _StatTile(label: '连续打卡', value: s.streakDays, suffix: ' 天', color: const Color(0xFFFF7A1A)),
                const SizedBox(width: 10),
                _StatTile(label: '读完文章', value: s.finishedCount, suffix: ' 篇', color: p.success),
                const SizedBox(width: 10),
                _StatTile(label: '累计阅读', value: (s.totalDurationMs / 60000).round(), suffix: ' 分钟', color: p.accent),
                const SizedBox(width: 10),
                _StatTile(label: '生词', value: _words, suffix: ' 个', color: const Color(0xFFF5A623)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 70),
          child: _Section(
            title: '近 7 日阅读时长',
            trailing: s == null ? null : '今日 ${(s.todayDurationMs / 60000).toStringAsFixed(1)} 分钟',
            child: SizedBox(height: 132, child: _WeekChart(data: _daily)),
          ),
        ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 140),
          child: _Section(
            title: '主题',
            child: ListenableBuilder(listenable: app.settings, builder: (_, _) => const ThemeSelector()),
          ),
        ),
        const SizedBox(height: 14),
        EntranceItem(
          delay: const Duration(milliseconds: 210),
          child: Column(
            children: [
              _MenuTile(
                icon: Icons.insights_rounded,
                title: '埋点与性能调试面板',
                subtitle: '事件队列 · 上报结果 · 分析查询 · 帧耗时',
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    settings: const RouteSettings(name: 'debug'),
                    builder: (_) => const DebugPanelPage(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _MenuTile(
                icon: Icons.logout_rounded,
                title: '退出登录',
                subtitle: '吊销本地 Token，阅读数据保留',
                onTap: () => app.auth.logout(),
              ),
            ],
          ),
        ),
      ],
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

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      pressedScale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: p.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: p.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          ],
        ),
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
                  i == data.length - 1 ? '今天' : data[i].key.substring(5),
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
