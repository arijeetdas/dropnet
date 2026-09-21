import 'dart:io';

import 'package:dropnet/core/utils/cache_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CacheCleanupService', () {
    test('sweepColdStart wipes directory contents except excluded paths', () async {
      final tempDir = await Directory.systemTemp.createTemp('dropnet_cache_test_');
      final originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

      final keep = File('${tempDir.path}/keep.txt')..writeAsStringSync('keep');
      final junk = File('${tempDir.path}/junk.txt')..writeAsStringSync('junk');
      final junkDir = Directory('${tempDir.path}/junk_dir')..createSync();
      File('${junkDir.path}/inner.txt').writeAsStringSync('inner');

      await CacheCleanupService.sweepColdStart(excludePaths: [keep.path]);

      expect(await keep.exists(), isTrue, reason: 'Excluded paths must survive the wipe.');
      expect(await junk.exists(), isFalse, reason: 'Everything else in the temp dir is junk.');
      expect(await junkDir.exists(), isFalse, reason: 'Subdirectories are wiped too.');

      PathProviderPlatform.instance = originalPlatform;
      await tempDir.delete(recursive: true);
    });

    test('sweepOnResumeIfDue removes only stale dropnet_web_pending entries', () async {
      final pending = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_web_pending',
      );
      await pending.create(recursive: true);

      final staleFile = File('${pending.path}/stale_upload.bin')
        ..writeAsStringSync('old');
      final freshFile = File('${pending.path}/fresh_upload.bin')
        ..writeAsStringSync('new');

      final oldTime = DateTime.now().subtract(const Duration(hours: 2));
      await staleFile.setLastModified(oldTime);

      await CacheCleanupService.sweepOnResumeIfDue();

      expect(
        await staleFile.exists(),
        isFalse,
        reason: 'Entries older than the safety margin should be removed.',
      );
      expect(
        await freshFile.exists(),
        isTrue,
        reason: 'Recently-created entries must be left alone (still in flight).',
      );

      await pending.delete(recursive: true);
    });

    test('sweepOnResumeIfDue is rate-limited', () async {
      final pending = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_web_pending',
      );
      await pending.create(recursive: true);
      final staleFile = File('${pending.path}/stale_2.bin')..writeAsStringSync('old');
      await staleFile.setLastModified(DateTime.now().subtract(const Duration(hours: 2)));

      await CacheCleanupService.sweepOnResumeIfDue();
      expect(await staleFile.exists(), isFalse);

      // Recreate it; a second call within the rate-limit window must not
      // scan again (nothing to assert on directly here besides "no crash"
      // since the gate is time-based and internal), but we confirm calling
      // it repeatedly is always safe.
      final staleFile2 = File('${pending.path}/stale_3.bin')..writeAsStringSync('old');
      await staleFile2.setLastModified(DateTime.now().subtract(const Duration(hours: 2)));
      await CacheCleanupService.sweepOnResumeIfDue();
      expect(
        await staleFile2.exists(),
        isTrue,
        reason: 'Second call within the rate-limit window should be a no-op.',
      );

      await pending.delete(recursive: true);
    });

    test('sweepOnResumeIfDue removes only stale web_sessions leaf directories', () async {
      final root = await Directory.systemTemp.createTemp('dropnet_root_test_');
      final staleSession = Directory('${root.path}/web_sessions/peer1/stale-session');
      final freshSession = Directory('${root.path}/web_sessions/peer1/fresh-session');
      await staleSession.create(recursive: true);
      await freshSession.create(recursive: true);
      File('${staleSession.path}/file.bin').writeAsStringSync('data');
      final oldStamp = DateTime.now().subtract(const Duration(hours: 2));
      final stampArg =
          '${oldStamp.year.toString().padLeft(4, '0')}'
          '${oldStamp.month.toString().padLeft(2, '0')}'
          '${oldStamp.day.toString().padLeft(2, '0')}'
          '${oldStamp.hour.toString().padLeft(2, '0')}'
          '${oldStamp.minute.toString().padLeft(2, '0')}.'
          '${oldStamp.second.toString().padLeft(2, '0')}';
      await Process.run('touch', ['-t', stampArg, staleSession.path]);

      SharedPreferences.setMockInitialValues({});
      await CacheCleanupService.sweepOnResumeIfDue(dropNetRootDirectory: root.path);

      expect(await staleSession.exists(), isFalse);
      expect(await freshSession.exists(), isTrue);

      await root.delete(recursive: true);
    });
  });
}
