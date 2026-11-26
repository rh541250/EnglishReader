import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 帧耗时统计（「不丢帧」的证据来源）。
///
/// 通过 `SchedulerBinding.addTimingsCallback` 拿到引擎上报的每一帧
/// build（UI 线程）与 raster（光栅线程）耗时，这是 DevTools 性能面板的同一数据源。
/// 判定：build + raster 超过一帧预算（60Hz 为 16.67ms，120Hz 为 8.33ms）记为一次掉帧。
/// 注意：debug 模式有断言和 JIT 开销，数据只有在 profile / release 模式下才有参考价值。
class FrameMonitor {
  FrameMonitor._();
  static final FrameMonitor instance = FrameMonitor._();

  static const int _capacity = 1800;

  final List<double> _build = [];
  final List<double> _raster = [];
  bool _attached = false;

  final ValueNotifier<int> revision = ValueNotifier(0);

  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void reset() {
    _build.clear();
    _raster.clear();
    revision.value++;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    if (_build.length > _capacity) {
      _build.removeRange(0, _build.length - _capacity);
      _raster.removeRange(0, _raster.length - _capacity);
    }
    revision.value++;
  }

  double get refreshRate {
    try {
      final r = PlatformDispatcher.instance.views.first.display.refreshRate;
      return r > 0 ? r : 60;
    } catch (_) {
      return 60;
    }
  }

  FrameStats snapshot() {
    final n = _build.length;
    if (n == 0) return FrameStats.empty(refreshRate);
    final budget = 1000 / refreshRate;
    final total = [for (var i = 0; i < n; i++) _build[i] + _raster[i]]..sort();
    final sortedBuild = [..._build]..sort();
    final sortedRaster = [..._raster]..sort();
    double pct(List<double> s, double p) => s[((s.length - 1) * p).round()];
    double avg(List<double> s) => s.reduce((a, b) => a + b) / s.length;
    final jank = total.where((t) => t > budget).length;
    return FrameStats(
      frames: n,
      refreshRate: refreshRate,
      budgetMs: budget,
      avgBuildMs: avg(sortedBuild),
      avgRasterMs: avg(sortedRaster),
      p90TotalMs: pct(total, 0.90),
      p99TotalMs: pct(total, 0.99),
      worstTotalMs: total.last,
      jankFrames: jank,
    );
  }
}

class FrameStats {
  const FrameStats({
    required this.frames,
    required this.refreshRate,
    required this.budgetMs,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p90TotalMs,
    required this.p99TotalMs,
    required this.worstTotalMs,
    required this.jankFrames,
  });

  factory FrameStats.empty(double refreshRate) => FrameStats(
    frames: 0,
    refreshRate: refreshRate,
    budgetMs: 1000 / refreshRate,
    avgBuildMs: 0,
    avgRasterMs: 0,
    p90TotalMs: 0,
    p99TotalMs: 0,
    worstTotalMs: 0,
    jankFrames: 0,
  );

  final int frames;
  final double refreshRate;
  final double budgetMs;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p90TotalMs;
  final double p99TotalMs;
  final double worstTotalMs;
  final int jankFrames;

  double get jankRate => frames == 0 ? 0 : jankFrames / frames;

  @override
  String toString() =>
      'frames=$frames budget=${budgetMs.toStringAsFixed(2)}ms '
      'avg(build=${avgBuildMs.toStringAsFixed(2)}ms raster=${avgRasterMs.toStringAsFixed(2)}ms) '
      'p90=${p90TotalMs.toStringAsFixed(2)}ms p99=${p99TotalMs.toStringAsFixed(2)}ms '
      'worst=${worstTotalMs.toStringAsFixed(2)}ms jank=$jankFrames (${(jankRate * 100).toStringAsFixed(2)}%)';
}
