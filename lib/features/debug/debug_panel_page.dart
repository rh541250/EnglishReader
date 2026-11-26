import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/analytics_queries.dart';
import '../../analytics/event_repository.dart';
import '../../analytics/event_schema.dart';
import '../../analytics/transport.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../motion/frame_monitor.dart';

/// 埋点与性能调试面板。
///
/// 用途：让埋点方案「可验证」——能看到待上报队列、最近上报结果、
/// 手动触发上报 / 模拟离线 / 模拟服务端失败，并直接看到三个分析查询在本机数据上的输出。
class DebugPanelPage extends StatefulWidget {
  const DebugPanelPage({super.key});

  @override
  State<DebugPanelPage> createState() => _DebugPanelPageState();
}

class _DebugPanelPageState extends State<DebugPanelPage> {
  QueueCounts? _counts;
  int _serverCount = 0;
  int? _nextRetryAt;
  List<QueuedEvent> _events = const [];
  List<UploadLogEntry> _uploads = const [];
  DurationReport? _duration;
  List<FunnelStep> _funnel = const [];
  WordReport? _words;
  bool _onlyPending = false;
  bool _flushing = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    app.analytics.revision.addListener(_scheduleReload);
    app.uploader.revision.addListener(_scheduleReload);
    app.network.online.addListener(_scheduleReload);
    FrameMonitor.instance.revision.addListener(_onFrame);
    app.analytics.track(Ev.pageView, {'page': 'debug_panel'});
    _reload();
  }

  @override
  void dispose() {
    app.analytics.revision.removeListener(_scheduleReload);
    app.uploader.revision.removeListener(_scheduleReload);
    app.network.online.removeListener(_scheduleReload);
    FrameMonitor.instance.revision.removeListener(_onFrame);
    _debounce?.cancel();
    _frameThrottle?.cancel();
    super.dispose();
  }

  Timer? _frameThrottle;
  void _onFrame() {
    // 帧数据每帧都在变，面板 1 秒刷新一次即可，避免面板自身成为负载。
    if (_frameThrottle?.isActive ?? false) return;
    _frameThrottle = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() {});
    });
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _reload);
  }

  Future<void> _reload() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final counts = await app.events.counts();
    final server = await app.events.mockServerCount();
    final next = await app.events.nextRetryAt(now);
    final events = await app.events.recent(limit: 40, status: _onlyPending ? EventStatus.pending : null);
    final uploads = await app.events.recentUploads(limit: 8);
    final duration = await app.queries.readingDurationLast7Days();
    final funnel = await app.queries.readingFunnelLast7Days();
    final words = await app.queries.wordReportLast7Days();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _serverCount = server;
      _nextRetryAt = next;
      _events = events;
      _uploads = uploads;
      _duration = duration;
      _funnel = funnel;
      _words = words;
    });
  }

  Future<void> _flush() async {
    setState(() => _flushing = true);
    final sent = await app.uploader.flush(force: true);
    if (!mounted) return;
    setState(() => _flushing = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(sent > 0 ? '本次成功上报 $sent 条' : '没有上报成功的事件（队列为空或上报失败）')));
  }

  /// 把面板上的全部数据以纯文本打印到日志，并复制到剪贴板。
  Future<void> _dump() async {
    final b = StringBuffer();
    final c = _counts;
    b.writeln('== event queue ==');
    b.writeln('pending=${c?.pending} sending=${c?.sending} sent=${c?.sent} server_received=$_serverCount');
    b.writeln('== recent uploads ==');
    for (final u in _uploads) {
      b.writeln('${_time(u.ts)} ${u.ok ? 'OK ' : 'FAIL'} count=${u.count} ${u.durationMs}ms ${u.error ?? ''}');
    }
    b.writeln('== q1: reading duration, last 7 days (minutes) ==');
    _duration?.perDayMs.forEach((d, ms) => b.writeln('$d  ${(ms / 60000).toStringAsFixed(1)}'));
    _duration?.buckets.forEach((k, v) => b.writeln('$k  $v 次'));
    b.writeln('== q2: funnel, last 7 days ==');
    for (final s in _funnel) {
      b.writeln('${s.label}  ${s.count}  ${(s.rate * 100).toStringAsFixed(1)}%');
    }
    b.writeln('== q3: words, last 7 days ==');
    b.writeln(
      'lookup=${_words?.lookups} collect=${_words?.collects} '
      'rate=${((_words?.collectRate ?? 0) * 100).toStringAsFixed(1)}%',
    );
    b.writeln('== frames ==');
    b.writeln(FrameMonitor.instance.snapshot());
    final text = b.toString();
    debugPrint('[debug-panel]\n$text');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已输出到日志并复制到剪贴板')));
  }

  static String _time(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = _counts;
    final transport = app.uploader.transport;
    final frames = FrameMonitor.instance.snapshot();
    final now = DateTime.now().millisecondsSinceEpoch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('调试面板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [IconButton(tooltip: '输出到日志并复制', icon: const Icon(Icons.copy_all_rounded), onPressed: _dump)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _Card(
            title: '事件队列',
            subtitle: '上报通道：${transport.description}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Metric(label: '待上报', value: '${c?.pending ?? '-'}', color: const Color(0xFFE59A1F)),
                    _Metric(label: '上报中', value: '${c?.sending ?? '-'}', color: p.accent),
                    _Metric(label: '已上报', value: '${c?.sent ?? '-'}', color: p.success),
                    _Metric(label: '服务端已收', value: '$_serverCount', color: p.textSecondary),
                  ],
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<bool>(
                  valueListenable: app.network.online,
                  builder: (context, online, _) => Text(
                    '网络：${app.network.isOnline ? '在线' : '离线'}'
                    '${_nextRetryAt != null ? ' · 退避中，${((_nextRetryAt! - now) / 1000).ceil()} 秒后重试' : ''}',
                    style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _flushing ? null : _flush,
                        icon: _flushing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('立即上报'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await app.network.check();
                          _scheduleReload();
                        },
                        icon: const Icon(Icons.network_check_rounded, size: 18),
                        label: const Text('重新探测网络'),
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: app.network.simulateOffline,
                  builder: (context, v, _) => _SwitchRow(
                    title: '模拟离线',
                    subtitle: '上报失败并进入退避；阅读、取词照常（离线命中）',
                    value: v,
                    onChanged: (x) {
                      app.network.simulateOffline.value = x;
                      _scheduleReload();
                    },
                  ),
                ),
                if (transport is MockTransport)
                  ValueListenableBuilder<bool>(
                    valueListenable: transport.failNext,
                    builder: (context, v, _) => _SwitchRow(
                      title: '模拟服务端 500',
                      subtitle: '验证失败退避与重试',
                      value: v,
                      onChanged: (x) => transport.failNext.value = x,
                    ),
                  ),
              ],
            ),
          ),
          _Card(
            title: '最近上报结果',
            child: _uploads.isEmpty
                ? Text('暂无', style: TextStyle(color: p.textTertiary, fontSize: 13))
                : Column(
                    children: [
                      for (final u in _uploads)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                u.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                                size: 15,
                                color: u.ok ? p.success : const Color(0xFFE5484D),
                              ),
                              const SizedBox(width: 6),
                              Text(_time(u.ts), style: _mono(p.textSecondary)),
                              const SizedBox(width: 8),
                              Text('${u.count} 条', style: _mono(p.text)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  u.ok ? '${u.durationMs}ms' : (u.error ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _mono(u.ok ? p.textTertiary : const Color(0xFFE5484D)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          _Card(
            title: '查询 1 · 近 7 日阅读时长分布',
            subtitle: '口径：read_duration.duration_ms 按事件发生日求和（分钟）',
            child: _duration == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _duration!.perDayMs.entries)
                        _BarRow(
                          label: e.key.substring(5),
                          value: e.value / 60000,
                          max: _duration!.perDayMs.values.fold<int>(60000, (m, v) => v > m ? v : m) / 60000,
                          text: (e.value / 60000).toStringAsFixed(1),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '单次时长分桶：${_duration!.buckets.entries.map((e) => '${e.key} ${e.value} 次').join(' · ')}',
                        style: TextStyle(fontSize: 12, color: p.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
          ),
          _Card(
            title: '查询 2 · 近 7 日阅读漏斗',
            subtitle: '口径：按 (user_id, article_id) 去重；读到 50% / 读完的转化率相对「打开」',
            child: Column(
              children: [
                for (final s in _funnel)
                  _BarRow(
                    label: s.label,
                    value: s.count.toDouble(),
                    max: _funnel.isEmpty ? 1 : _funnel.first.count.toDouble().clamp(1, double.infinity),
                    text: '${s.count}  ${(s.rate * 100).toStringAsFixed(0)}%',
                    labelWidth: 64,
                  ),
              ],
            ),
          ),
          _Card(
            title: '查询 3 · 近 7 日取词与收藏',
            child: _words == null
                ? const SizedBox.shrink()
                : Text(
                    '取词 ${_words!.lookups} 次 · 收藏 ${_words!.collects} 次 · '
                    '收藏率 ${(_words!.collectRate * 100).toStringAsFixed(1)}%\n'
                    '取词 Top：${_words!.topWords.isEmpty ? '暂无' : _words!.topWords.map((e) => '${e.key}×${e.value}').join('  ')}',
                    style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.6),
                  ),
          ),
          _Card(
            title: '帧耗时',
            subtitle: kDebugMode ? '当前为 debug 模式，数据偏高仅供参考；请用 --profile 运行后查看' : '数据源：引擎 FrameTiming（与 DevTools 相同）',
            trailing: TextButton(onPressed: FrameMonitor.instance.reset, child: const Text('清零')),
            child: Text(
              '采样 ${frames.frames} 帧 · 刷新率 ${frames.refreshRate.toStringAsFixed(0)}Hz · '
              '单帧预算 ${frames.budgetMs.toStringAsFixed(2)}ms\n'
              'build 平均 ${frames.avgBuildMs.toStringAsFixed(2)}ms · raster 平均 ${frames.avgRasterMs.toStringAsFixed(2)}ms\n'
              'P90 ${frames.p90TotalMs.toStringAsFixed(2)}ms · P99 ${frames.p99TotalMs.toStringAsFixed(2)}ms · '
              '最差 ${frames.worstTotalMs.toStringAsFixed(2)}ms\n'
              '超预算 ${frames.jankFrames} 帧（${(frames.jankRate * 100).toStringAsFixed(2)}%）',
              style: _mono(p.textSecondary).copyWith(height: 1.7),
            ),
          ),
          _Card(
            title: '事件明细',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('仅待上报', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                Switch(
                  value: _onlyPending,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    setState(() => _onlyPending = v);
                    _reload();
                  },
                ),
              ],
            ),
            child: _events.isEmpty
                ? Text('暂无', style: TextStyle(color: p.textTertiary, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _events)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(top: 5, right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: switch (e.status) {
                                    EventStatus.sent => p.success,
                                    EventStatus.sending => p.accent,
                                    _ => const Color(0xFFE59A1F),
                                  },
                                ),
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: '${_time(e.ts)}  ', style: _mono(p.textTertiary)),
                                      TextSpan(
                                        text: e.name,
                                        style: _mono(p.text).copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      if (e.attempts > 0)
                                        TextSpan(text: '  重试×${e.attempts}', style: _mono(const Color(0xFFE5484D))),
                                      TextSpan(
                                        text: '\n${jsonEncode(e.payload['props'])}  [${e.payload['network']}]',
                                        style: _mono(p.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static TextStyle _mono(Color color) => TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: const ['monospace'],
    fontSize: 11.5,
    color: color,
    height: 1.4,
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.text),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: p.textTertiary, height: 1.4)),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: p.textTertiary, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.text,
    this.labelWidth = 44,
  });
  final String label;
  final double value;
  final double max;
  final String text;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  height: 10,
                  width: (max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0)) * c.maxWidth + 2,
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(5)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
