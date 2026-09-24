import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

/// Builds the platform-specific "Check for Updates" link, e.g.
///   https://dropnet.arijeet.in/updates/android/25-arm64-v8a
///   https://dropnet.arijeet.in/updates/windows/25
class UpdateLink {
  UpdateLink._();

  static const String _baseUrl = 'https://dropnet.arijeet.in';

  /// Android APK flavours that are actually published
  /// (`flutter build apk` + `flutter build apk --split-per-abi`).
  static const Set<String> _publishedAndroidAbis = {
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  };

  /// Maps the device's comma-separated ABI list (most preferred first) to the
  /// recommended ABI, or `null` when no dedicated build type applies.
  static String? recommendedAbi(String cpuArchitecture) {
    final abis = cpuArchitecture
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (abis.isEmpty) return null;
    const known = {'arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'};
    final best = abis.first;
    return known.contains(best) ? best : null;
  }

  /// Recommended Android install type as used in the update URL:
  /// `universal`, `arm64-v8a`, `armeabi-v7a` or `x86_64`.
  static String recommendedAndroidInstallType(String cpuArchitecture) {
    final abi = recommendedAbi(cpuArchitecture);
    return (abi != null && _publishedAndroidAbis.contains(abi)) ? abi : 'universal';
  }

  static String? _cachedBuildNumber;

  /// The `<buildNo>` part of `version: <versionName>+<buildNo>` in
  /// pubspec.yaml (e.g. `2.5.2+26` -> `26`).
  ///
  /// Read from the bundled pubspec.yaml because the runtime build number is
  /// not reliable: Android split-per-ABI APKs report an ABI-prefixed version
  /// code (e.g. 2026 instead of 26).
  static Future<String?> pubspecBuildNumber() async {
    if (_cachedBuildNumber != null) return _cachedBuildNumber;
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*[^+\s]+\+(\d+)', multiLine: true).firstMatch(pubspec);
      if (match != null) return _cachedBuildNumber = match.group(1);
    } catch (_) {}

    // Fallback: runtime build number, stripping Flutter's split-per-ABI
    // prefix (abiCode * 1000 + buildNo) on Android.
    try {
      final info = await PackageInfo.fromPlatform();
      final parsed = int.tryParse(info.buildNumber);
      if (parsed == null) return null;
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      return (isAndroid && parsed >= 1000 ? parsed % 1000 : parsed).toString();
    } catch (_) {
      return null;
    }
  }

  static String? _platformSlug() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  /// Full update URL for the running platform. Falls back to the site root
  /// when the platform or build number can't be determined.
  static Future<Uri> build({required String cpuArchitecture}) async {
    final platform = _platformSlug();
    final buildNumber = await pubspecBuildNumber();
    if (platform == null || buildNumber == null) return Uri.parse(_baseUrl);

    final segment = platform == 'android'
        ? '$buildNumber-${recommendedAndroidInstallType(cpuArchitecture)}'
        : buildNumber;
    return Uri.parse('$_baseUrl/updates/$platform/$segment');
  }
}
