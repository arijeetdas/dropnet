import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Facts about the device the app runs on that Dart can't learn by itself.
///
/// Loaded once before the UI starts (see `main`) and immutable afterwards, so
/// every consumer (discovery, settings, receive screen, dialogs) can read it
/// synchronously and they can never disagree with each other.
class DeviceEnvironment {
  DeviceEnvironment._();

  static const MethodChannel _channel = MethodChannel('dropnet/android_storage');

  static bool _isChromeOS = false;
  static String _buildManufacturer = '';
  static String _buildBrand = '';
  static bool _initialized = false;

  /// True when this Android build is running on a Chromebook through
  /// ChromeOS's Android runtime (ARC++ / ARCVM). Always false elsewhere.
  static bool get isChromeOS => _isChromeOS;

  /// Android `Build.MANUFACTURER` / `Build.BRAND` exactly as the OS reports
  /// them — unlike the user-editable manufacturer tag.
  static String get buildManufacturer => _buildManufacturer;
  static String get buildBrand => _buildBrand;

  /// Display name of the OS the app is installed on.
  static String get platformDisplayName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return _isChromeOS ? 'ChromeOS' : 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Web';
  }

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceEnvironment')
          .timeout(const Duration(seconds: 2));
      if (result == null) {
        return;
      }
      _isChromeOS = result['isChromeOS'] == true;
      _buildManufacturer = (result['manufacturer']?.toString() ?? '').trim();
      _buildBrand = (result['brand']?.toString() ?? '').trim();
    } catch (_) {
      // Unknown: behave exactly like a regular Android device.
    }
  }

  @visibleForTesting
  static void debugOverride({bool? isChromeOS}) {
    if (isChromeOS != null) {
      _isChromeOS = isChromeOS;
    }
  }
}
