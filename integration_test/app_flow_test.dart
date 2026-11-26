import 'package:english_reader/app/app_scope.dart';
import 'package:english_reader/features/articles/article_card.dart';
import 'package:english_reader/features/reader/paragraph_view.dart';
import 'package:english_reader/features/reader/reader_page.dart';
import 'package:english_reader/features/reader/word_popup.dart';
import 'package:english_reader/main.dart' as entry;
import 'package:english_reader/motion/collect_button.dart';
import 'package:english_reader/motion/sliding_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// 端到端主链路：登录 → 列表 → 共享元素转场 → 取词收藏 → 位置恢复 → 读完庆祝
/// → 手势返回（中途取消 + 完成）→ 生词本跳回原文。
///
/// 运行（模拟器 / 真机均可，帧耗时数据请用真机 + --profile）：
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_flow_test.dart -d DEVICE_ID [--profile]
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 帧策略：按真实时间出帧，动画与真机表现一致。
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int timeoutMs = 15000}) async {
    final end = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('等待超时: $finder');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await binding.takeScreenshot(name);
  }

  ScrollController readerScroll(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.descendant(of: find.byType(ReaderPage), matching: find.byType(SingleChildScrollView)),
      )
      .controller!;

  testWidgets('主链路', (tester) async {
    entry.main();
    await pumpUntil(tester, find.byWidgetPredicate((w) => w is Text && (w.data == '登录' || w.data == '今天读点什么？')));

    // ---- 登录 ----
    if (find.text('今天读点什么？').evaluate().isEmpty) {
      await shot(tester, '00_login');
      await tester.tap(find.text('填入演示账号'));
      await wait(tester, 200);
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await pumpUntil(tester, find.text('今天读点什么？'));
    }

    // 干净的起点：清掉演示账号此前的阅读记录与生词，保证测试可重复运行。
    final uid = app.userId;
    await app.db.delete('reading_progress', where: 'user_id = ?', whereArgs: [uid]);
    await app.db.delete('reading_sessions', where: 'user_id = ?', whereArgs: [uid]);
    await app.db.delete('vocabulary', where: 'user_id = ?', whereArgs: [uid]);
    app.progress.revision.value++;
    app.vocab.revision.value++;

    // ---- 列表：骨架屏 → 交错入场 ----
    await pumpUntil(tester, find.byType(ArticleCard));
    await wait(tester, 900);
    await shot(tester, '01_list');

    // ---- 列表滚动（帧耗时）----
    await binding.watchPerformance(() async {
      await tester.fling(find.byType(CustomScrollView).first, const Offset(0, -900), 2400);
      await wait(tester, 1600);
      await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 1400), 3000);
      await wait(tester, 1800);
    }, reportKey: 'perf_list_scroll');

    // ---- 分类切换：指示器滑动 ----
    await tester.tap(find.descendant(of: find.byType(SlidingTabs), matching: find.text('文化')).first);
    await wait(tester, 150);
    await shot(tester, '02_tab_sliding');
    await wait(tester, 700);
    expect(find.byType(ArticleCard), findsWidgets);
    await tester.tap(find.descendant(of: find.byType(SlidingTabs), matching: find.text('全部')).first);
    await wait(tester, 800);

    // ---- 打开文章：共享元素转场（帧耗时）----
    final firstCard = find.byType(ArticleCard).first;
    final openedTitle = tester.widget<ArticleCard>(firstCard).article.title;
    await binding.watchPerformance(() async {
      await tester.tap(firstCard);
      await wait(tester, 160);
      await shot(tester, '03_hero_mid_flight');
      await wait(tester, 900);
    }, reportKey: 'perf_hero_push');
    expect(find.byType(ReaderPage), findsOneWidget);
    await pumpUntil(tester, find.byType(ParagraphView));
    await wait(tester, 800);
    await shot(tester, '04_reader_top');

    // ---- 长按取词 + 收藏 ----
    final paragraph = tester.state<ParagraphViewState>(find.byType(ParagraphView).first);
    final wordRect = paragraph.globalRectOfWord(4)!;
    final press = await tester.startGesture(wordRect.center);
    await wait(tester, 600);
    await press.up();
    await wait(tester, 500);
    expect(find.byType(WordPopup), findsOneWidget);
    await shot(tester, '05_word_popup');
    await tester.tap(find.descendant(of: find.byType(WordPopup), matching: find.byType(CollectButton)));
    await wait(tester, 220);
    await shot(tester, '06_collect_bounce');
    await wait(tester, 700);
    expect(await app.vocab.count(uid), 1);
    // 点空白处关闭气泡
    await tester.tapAt(const Offset(40, 140));
    await wait(tester, 300);
    expect(find.byType(WordPopup), findsNothing);

    // ---- 读到一半 → 返回 → 重进：精确恢复位置 ----
    final scroll = readerScroll(tester);
    scroll.jumpTo(0);
    await tester.drag(find.byType(ParagraphView).first, const Offset(0, -520));
    await wait(tester, 400);
    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -360), warnIfMissed: false);
    await wait(tester, 1500); // 等节流落库
    final leftAt = readerScroll(tester).offset;
    expect(leftAt, greaterThan(300));
    await shot(tester, '07_reader_mid');

    // 手势返回：先拖一小段再松手 → 回弹取消
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    var gesture = await tester.startGesture(Offset(30, size.height * 0.55));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await wait(tester, 16);
    }
    await shot(tester, '08_swipe_back_dragging');
    await wait(tester, 250); // 停住，让速度归零
    await gesture.up();
    await wait(tester, 900);
    expect(find.byType(ReaderPage), findsOneWidget, reason: '拖动不足半屏且无速度，应回弹留在阅读页');

    // 再来一次：快速右滑 → 完成返回
    await binding.watchPerformance(() async {
      gesture = await tester.startGesture(Offset(30, size.height * 0.55));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(26, 0));
        await wait(tester, 16);
      }
      await gesture.up();
      await wait(tester, 900);
    }, reportKey: 'perf_swipe_back');
    expect(find.byType(ReaderPage), findsNothing, reason: '快速右滑应完成返回');
    await wait(tester, 800);
    expect(find.text('继续阅读'), findsOneWidget);
    await shot(tester, '09_list_continue_card');

    // 从「继续阅读」重进：应回到刚才的位置
    await tester.tap(find.text('继续阅读'));
    await pumpUntil(tester, find.byType(ParagraphView));
    await wait(tester, 2200);
    final restored = readerScroll(tester).offset;
    expect(restored, closeTo(leftAt, 1.0), reason: '重进后应精确恢复到上次位置');
    await shot(tester, '10_restored_position');

    // ---- 调字号：位置跟着同一句话走（不跳走）----
    final before = app.settings.fontSize;
    app.settings.fontSize = before + 4;
    await wait(tester, 600);
    expect(readerScroll(tester).offset, greaterThan(leftAt), reason: '字号变大后同一句话的偏移应更靠后');
    app.settings.fontSize = before;
    await wait(tester, 600);
    expect(readerScroll(tester).offset, closeTo(leftAt, 2.0), reason: '字号还原后应回到原偏移');

    // ---- 读完：进度推进 + 庆祝（帧耗时）----
    await binding.watchPerformance(() async {
      for (var i = 0; i < 14 && find.text('已读完').evaluate().isEmpty; i++) {
        await tester.fling(find.byType(SingleChildScrollView).last, const Offset(0, -700), 2600, warnIfMissed: false);
        await wait(tester, 700);
      }
      await wait(tester, 500);
      await shot(tester, '11_finished_confetti');
      await wait(tester, 2200);
    }, reportKey: 'perf_read_and_celebrate');
    expect(find.text('已读完'), findsOneWidget);
    expect(find.text('读完啦！'), findsOneWidget);
    expect(await app.articles.continueReading(uid), isNull, reason: '读完后不应再出现在「继续阅读」');
    await shot(tester, '12_finish_card');

    // 返回列表
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await wait(tester, 1000);
    expect(find.byType(ReaderPage), findsNothing);

    // ---- 生词本 → 跳回原文出处 ----
    await tester.tap(find.text('生词本').last);
    await wait(tester, 900);
    await shot(tester, '13_vocab');
    expect(find.textContaining('原文：$openedTitle'), findsOneWidget);
    await tester.tap(find.textContaining('原文：$openedTitle'));
    await pumpUntil(tester, find.byType(ParagraphView));
    await wait(tester, 1500);
    await shot(tester, '14_jump_back_to_source');
    expect(find.byType(ReaderPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await wait(tester, 900);

    // ---- 我的 / 调试面板 ----
    await tester.tap(find.text('我的').last);
    await wait(tester, 1200);
    await shot(tester, '15_profile');
    await tester.tap(find.text('埋点与性能调试面板'));
    await wait(tester, 1500);
    await shot(tester, '16_debug_panel');

    // 埋点链路：主链路事件都已入队
    await app.analytics.idle;
    final names = (await app.db.rawQuery('SELECT DISTINCT name FROM event_queue')).map((r) => r['name']).toSet();
    expect(
      names,
      containsAll([
        'app_open',
        'session_start',
        'page_view',
        'article_expose',
        'category_switch',
        'article_open',
        'read_progress',
        'read_duration',
        'article_finish',
        'word_lookup',
        'word_collect',
      ]),
    );
  });
}
