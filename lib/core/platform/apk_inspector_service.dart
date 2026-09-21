import 'package:flutter/services.dart';

import '../../models/apk_info.dart';

/// Android-only bridge to inspect a received (not yet installed) `.apk`
/// file's own metadata, and to hand it to the system installer.
class ApkInspectorService {
  static const MethodChannel _channel = MethodChannel('dropnet/android_apps');

  Future<ApkInfo?> inspect(String path) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'inspectApk',
        {'path': path},
      );
      if (result == null) {
        return null;
      }
      return ApkInfo.fromMap(path, result);
    } catch (_) {
      return null;
    }
  }

  Future<bool> install(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {'path': path});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
