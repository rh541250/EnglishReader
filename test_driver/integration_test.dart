import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// `flutter drive` 的宿主端驱动：把测试里截的图存到 build/screenshots/，
/// 把帧耗时等上报数据存到 build/integration_response_data.json。
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('build/screenshots/$name.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
