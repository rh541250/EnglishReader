import 'package:english_reader/features/home/home_shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底部 Tab 切换：切换后旧页必须淡出并被隐藏，不能和新页叠在一起。
void main() {
  Widget host(int index) => Directionality(
    textDirection: TextDirection.ltr,
    child: FadeThrough(
      index: index,
      children: const [
        ColoredBox(key: ValueKey('a'), color: Color(0xFFFF0000)),
        ColoredBox(key: ValueKey('b'), color: Color(0xFF00FF00)),
      ],
    ),
  );

  testWidgets('切换完成后旧页不可见，且不再绘制', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 50));
    // 切换途中两页都可见（交叉淡入淡出）。
    expect(find.byKey(const ValueKey('a'), skipOffstage: false), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a')), findsNothing, reason: '旧页应被 Offstage 隐藏');
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
  });

  testWidgets('来回多次切换后，只有当前页可见', (tester) async {
    for (final i in [1, 0, 1, 0]) {
      await tester.pumpWidget(host(i));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
    expect(find.byKey(const ValueKey('b')), findsNothing);
  });
}
