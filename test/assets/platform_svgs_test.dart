import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String>[
    'assets/platforms/android_info.svg',
    'assets/platforms/chromeOS_info.svg',
    'assets/platforms/iOS_info.svg',
    'assets/platforms/linux_info.svg',
    'assets/platforms/macOS_info.svg',
    'assets/platforms/windows_info.svg',
    'assets/platforms/ChromeOS.svg',
  ];

  for (final asset in assets) {
    test('$asset is bundled and parses', () async {
      // Throws if the asset is missing from pubspec.yaml.
      await rootBundle.load(asset);
      final info = await vg.loadPicture(SvgAssetLoader(asset), null);
      expect(info.size.width, greaterThan(0));
      expect(info.size.height, greaterThan(0));
      info.picture.dispose();
    });
  }
}
