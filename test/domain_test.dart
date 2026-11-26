import 'package:english_reader/core/ids.dart';
import 'package:english_reader/domain/reading_math.dart';
import 'package:english_reader/domain/reading_timer.dart';
import 'package:english_reader/domain/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenizer', () {
    test('切分单词与标点，wordIndex 连续递增', () {
      final tokens = tokenize("Don't panic, it's the city's plan.");
      final words = tokens.where((t) => t.isWord).toList();
      expect(words.map((t) => t.text), ["Don't", 'panic', "it's", 'the', "city's", 'plan']);
      expect(words.map((t) => t.wordIndex), [0, 1, 2, 3, 4, 5]);
      // 所有片段首尾相接，拼回去等于原文。
      expect(tokens.map((t) => t.text).join(), "Don't panic, it's the city's plan.");
    });

    test('wordAtOffset：落在单词内返回该词，落在标点 / 空白返回 null', () {
      const text = 'Hello, world';
      final tokens = tokenize(text);
      expect(wordAtOffset(tokens, 0)?.text, 'Hello');
      expect(wordAtOffset(tokens, 4)?.text, 'Hello');
      expect(wordAtOffset(tokens, 5), isNull); // 逗号
      expect(wordAtOffset(tokens, 6), isNull); // 空格
      expect(wordAtOffset(tokens, 7)?.text, 'world');
      expect(wordAtOffset(tokens, 99), isNull);
    });

    test('countWords', () {
      expect(countWords('One two, three-four.'), 4);
    });
  });

  group('阅读位置', () {
    // 三个段落，段间距 20。
    const extents = [ParagraphExtent(300, 200), ParagraphExtent(520, 100), ParagraphExtent(640, 400)];

    test('锚线 → 位置 → 锚线 往返一致', () {
      for (final anchor in [300.0, 350.0, 499.9, 520.0, 570.0, 640.0, 900.0, 1040.0]) {
        final p = positionForAnchor(extents, anchor);
        expect(anchorForPosition(extents, p), closeTo(anchor, 1e-6), reason: 'anchor=$anchor');
      }
    });

    test('段落之前归到开头，段间距归到上一段末尾，超出末尾归到最后', () {
      expect(positionForAnchor(extents, 0), ReadingPosition.start);
      expect(positionForAnchor(extents, 510), const ReadingPosition(0, 1));
      expect(positionForAnchor(extents, 5000), const ReadingPosition(2, 1));
    });

    test('字号变化后（段落高度全变）仍恢复到同一段的同一比例处', () {
      final p = positionForAnchor(extents, 590); // 第 2 段的 70%
      expect(p.paragraphIndex, 1);
      expect(p.offsetFraction, closeTo(0.7, 1e-9));
      // 字号调大：每段更高、位置整体下移。
      const larger = [ParagraphExtent(300, 320), ParagraphExtent(650, 160), ParagraphExtent(840, 640)];
      expect(anchorForPosition(larger, p), closeTo(650 + 160 * 0.7, 1e-9));
    });

    test('滚动进度与读完阈值', () {
      expect(scrollProgress(0, 1000), 0);
      expect(scrollProgress(500, 1000), 0.5);
      expect(scrollProgress(1200, 1000), 1); // 回弹越界
      expect(scrollProgress(0, 0), 1); // 内容不足一屏
      expect(isFinished(0.96), isFalse);
      expect(isFinished(0.97), isTrue);
    });

    test('滚动深度里程碑只在首次跨过时触发', () {
      expect(crossedMilestones(0, 0.3), [25]);
      expect(crossedMilestones(0.3, 0.8), [50, 75]);
      expect(crossedMilestones(0.8, 0.98), [100]);
      expect(crossedMilestones(0.98, 1.0), isEmpty);
      expect(crossedMilestones(0, 1.0), [25, 50, 75, 100]);
    });
  });

  group('连续打卡', () {
    final today = DateTime(2026, 11, 26);
    test('今天读了：从今天往前数', () {
      expect(computeStreak({'2026-11-26', '2026-11-25', '2026-11-24'}, today, dayKey), 3);
    });
    test('今天还没读：昨天的连续记录不清零', () {
      expect(computeStreak({'2026-11-25', '2026-11-24'}, today, dayKey), 2);
    });
    test('中断一天即重新计数', () {
      expect(computeStreak({'2026-11-26', '2026-11-24', '2026-11-23'}, today, dayKey), 1);
      expect(computeStreak({'2026-11-23'}, today, dayKey), 0);
      expect(computeStreak({}, today, dayKey), 0);
    });
    test('跨月', () {
      expect(computeStreak({'2026-11-01', '2026-10-31', '2026-10-30'}, DateTime(2026, 11, 1), dayKey), 3);
    });
  });

  group('有效阅读时长', () {
    test('持续交互时按真实时间计', () {
      final t = ReadingTimer()..resume(0);
      t.interact(10000);
      t.interact(20000);
      expect(t.elapsedMs(25000), 25000);
    });

    test('无交互超过 60 秒的部分不计', () {
      final t = ReadingTimer()..resume(0);
      t.interact(10000);
      // 之后放下手机 5 分钟：只计到「最后一次交互 + 60s」。
      expect(t.elapsedMs(310000), 70000);
      // 回来继续滚动：重新起一段。
      t.interact(310000);
      expect(t.elapsedMs(320000), 80000);
    });

    test('后台时间不计', () {
      final t = ReadingTimer()..resume(0);
      t.interact(5000);
      t.pause(8000);
      expect(t.elapsedMs(100000), 8000);
      t.resume(100000);
      expect(t.elapsedMs(103000), 11000);
    });

    test('重复 pause / resume 是幂等的', () {
      final t = ReadingTimer()..resume(0);
      t.resume(500);
      t.pause(1000);
      t.pause(2000);
      expect(t.elapsedMs(9000), 1000);
    });
  });
}
