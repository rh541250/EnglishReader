import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app_scope.dart';
import 'app/theme.dart';
import 'data/models.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_shell.dart';
import 'motion/app_page_route.dart';
import 'motion/frame_monitor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FrameMonitor.instance.attach();
  runApp(const EnglishReaderApp());
}

/// `--dart-define=PERF_OVERLAY=true` 时显示 Flutter 自带的性能浮层（录屏取证用）。
const bool _perfOverlay = bool.fromEnvironment('PERF_OVERLAY');

class EnglishReaderApp extends StatefulWidget {
  const EnglishReaderApp({super.key});

  @override
  State<EnglishReaderApp> createState() => _EnglishReaderAppState();
}

class _EnglishReaderAppState extends State<EnglishReaderApp> with WidgetsBindingObserver {
  late Future<AppScope> _boot = AppScope.bootstrap();
  bool _background = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 会话切分与「切后台补报」的统一入口。
    final ready = _bootDone;
    if (!ready) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_background) {
        _background = true;
        app.analytics.onAppBackground();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_background) {
        _background = false;
        app.analytics.onAppForeground();
      }
    }
  }

  bool _bootDone = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppScope>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootMessage(
            text: '启动失败：${snapshot.error}',
            onRetry: () => setState(() => _boot = AppScope.bootstrap()),
          );
        }
        if (!snapshot.hasData) return const _BootMessage();
        _bootDone = true;
        final scope = snapshot.data!;
        return ListenableBuilder(
          listenable: scope.settings,
          builder: (context, _) {
            final palette = AppPalette.of(scope.settings.theme);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: (palette.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                  .copyWith(statusBarColor: const Color(0x00000000)),
              child: MaterialApp(
                title: 'English Reader',
                debugShowCheckedModeBanner: false,
                showPerformanceOverlay: _perfOverlay,
                theme: buildTheme(scope.settings.theme),
                // 主题切换时全局颜色做 260ms 补间，而不是硬切。
                themeAnimationDuration: const Duration(milliseconds: 260),
                themeAnimationCurve: Curves.easeOut,
                onGenerateRoute: (settings) =>
                    AppPageRoute<void>(settings: settings, swipeBack: false, builder: (_) => const _AuthGate()),
              ),
            );
          },
        );
      },
    );
  }
}

/// 根据登录态在登录页与首页之间切换（淡入淡出 + 轻微缩放）。
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: app.auth.currentUser,
      builder: (context, user, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(animation), child: child),
          ),
          child: user == null ? const LoginPage(key: ValueKey('login')) : HomeShell(key: ValueKey('home-${user.id}')),
        );
      },
    );
  }
}

class _BootMessage extends StatelessWidget {
  const _BootMessage({this.text, this.onRetry});
  final String? text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.light;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: p.background,
        child: Center(
          child: text == null
              ? Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(22)),
                  child: Icon(Icons.auto_stories_rounded, color: p.onAccent, size: 38),
                )
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.text, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      if (onRetry != null)
                        GestureDetector(
                          onTap: onRetry,
                          child: Text('重试', style: TextStyle(color: p.accent, fontSize: 16)),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
