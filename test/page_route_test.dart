import 'package:english_reader/motion/app_page_route.dart';
import 'package:english_reader/motion/fade_page_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 页面转场的几何约束：转场任何一帧，上下两层页面之间都不能露出缝隙（缝隙里是导航器背后的黑底）。
void main() {
  final navKey = GlobalKey<NavigatorState>();

  Widget page(String name) => SizedBox.expand(
    key: ValueKey(name),
    child: const ColoredBox(color: Colors.white),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        onGenerateRoute: (settings) =>
            AppPageRoute<void>(settings: settings, swipeBack: false, builder: (_) => page('bottom')),
      ),
    );
  }

  /// 上层页面左边缘不能越过下层页面的右边缘。
  void expectNoGap(WidgetTester tester, String phase, int frame) {
    // push 的第一帧新页面处于 offstage（框架借这一帧给 Hero 测量终点），此时跳过。
    if (find.byKey(const ValueKey('top')).evaluate().isEmpty) return;
    final top = tester.getRect(find.byKey(const ValueKey('top')));
    // 上层完全盖住后，下层会被置为 offstage（不再绘制），查找时不能跳过它。
    final bottom = tester.getRect(find.byKey(const ValueKey('bottom'), skipOffstage: false));
    expect(
      top.left,
      lessThanOrEqualTo(bottom.right + 0.5),
      reason: '$phase 第 $frame 帧：上层 ${top.left} / 下层 ${bottom.right}',
    );
  }

  testWidgets('点返回按钮 pop：上下两层同步移动，全程没有缝隙', (tester) async {
    await pumpApp(tester);
    navKey.currentState!.push(AppPageRoute<void>(builder: (_) => page('top')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectNoGap(tester, 'push', i);
    }
    await tester.pumpAndSettle();

    navKey.currentState!.pop();
    for (var i = 0; i < 30 && find.byKey(const ValueKey('top')).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(const ValueKey('top')).evaluate().isEmpty) break;
      expectNoGap(tester, 'pop', i);
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('bottom'), skipOffstage: false)).left, 0);
  });

  testWidgets('淡入路由（搜索页）盖上来时，下层页面不做视差位移', (tester) async {
    await pumpApp(tester);
    navKey.currentState!.push(FadePageRoute<void>(builder: (_) => page('top')));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(const ValueKey('bottom'), skipOffstage: false)).left, 0, reason: 'push 第 $i 帧');
    }
    await tester.pumpAndSettle();
    navKey.currentState!.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(const ValueKey('bottom'), skipOffstage: false)).left, 0, reason: 'pop 第 $i 帧');
    }
  });
}
