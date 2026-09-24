import 'dart:typed_data';

/// Metadata extracted from a received (not necessarily installed) `.apk`
/// file's own manifest, plus whatever's already installed under the same
/// package name for comparison.
class ApkInfo {
  const ApkInfo({
    required this.path,
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.apkSize,
    required this.minSdkVersion,
    required this.deviceSdkVersion,
    required this.isOwnPackage,
    this.iconBytes,
    this.isInstalled = false,
    this.installedVersionName,
    this.installedVersionCode,
    this.pubspecBuildNumber,
  });

  final String path;
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final int apkSize;

  /// -1 when the platform couldn't report it (very old Android).
  final int minSdkVersion;
  final int deviceSdkVersion;

  /// True when this APK's package name matches the app currently running
  /// this code — i.e. this is a DropNet build, detected dynamically rather
  /// than by hardcoding a package name.
  final bool isOwnPackage;

  final Uint8List? iconBytes;
  final bool isInstalled;
  final String? installedVersionName;
  final int? installedVersionCode;

  /// For DropNet's own APKs: the `<buildNo>` from `version: <name>+<buildNo>`
  /// in the pubspec.yaml bundled inside the APK. Unlike [versionCode], it is
  /// not inflated by Flutter's split-per-ABI prefix (e.g. 26, not 2026).
  final int? pubspecBuildNumber;

  factory ApkInfo.fromMap(String path, Map<dynamic, dynamic> map) {
    return ApkInfo(
      path: path,
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
      versionName: map['versionName']?.toString() ?? '',
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      apkSize: (map['apkSize'] as num?)?.toInt() ?? 0,
      minSdkVersion: (map['minSdkVersion'] as num?)?.toInt() ?? -1,
      deviceSdkVersion: (map['deviceSdkVersion'] as num?)?.toInt() ?? 0,
      isOwnPackage: map['isOwnPackage'] == true,
      iconBytes: map['iconBytes'] is Uint8List
          ? map['iconBytes'] as Uint8List
          : (map['iconBytes'] is List
                ? Uint8List.fromList((map['iconBytes'] as List).cast<int>())
                : null),
      isInstalled: map['isInstalled'] == true,
      pubspecBuildNumber: (map['pubspecBuildNumber'] as num?)?.toInt(),
      installedVersionName: map['installedVersionName']?.toString(),
      installedVersionCode: (map['installedVersionCode'] as num?)?.toInt(),
    );
  }

  /// Derived from [versionName]: DropNet's own build system maps
  /// pubspec.yaml's `version:` string directly to the APK's versionName, so
  /// `2.5.0` -> Stable, `2.5.0-Beta` -> Beta, `2.5.0-<Anything>` -> Anything.
  /// No package name or version format is hardcoded here.
  String get buildStatus {
    final dashIndex = versionName.indexOf('-');
    if (dashIndex < 0) {
      return 'Stable';
    }
    final suffix = versionName.substring(dashIndex + 1).trim();
    return suffix.isEmpty ? 'Stable' : suffix;
  }

  bool get isSdkSupported => minSdkVersion < 0 || minSdkVersion <= deviceSdkVersion;

  bool get isNewerThanInstalled {
    if (!isInstalled) {
      return true;
    }
    final installedCode = installedVersionCode ?? -1;
    if (versionCode != installedCode) {
      return versionCode > installedCode;
    }
    // Same build number: fall back to comparing version names so a same
    // build-number re-send of a strictly newer semantic version still
    // counts (defensive; in practice build numbers should be monotonic).
    return _compareVersionNames(versionName, installedVersionName ?? '') > 0;
  }

  /// Whether the Install button should be offered at all, and if not, why.
  ({bool canInstall, String? reason}) get installEligibility {
    if (!isSdkSupported) {
      return (
        canInstall: false,
        reason:
            'This app requires Android API $minSdkVersion or higher; this device is on API $deviceSdkVersion.',
      );
    }
    if (isInstalled && !isNewerThanInstalled) {
      return (
        canInstall: false,
        reason: 'A version of this app that is the same or newer is already installed.',
      );
    }
    return (canInstall: true, reason: null);
  }
}

int _compareVersionNames(String a, String b) {
  int coreValue(String version) {
    final core = version.split('-').first;
    final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    var value = 0;
    for (final part in parts.take(4)) {
      value = value * 1000 + part;
    }
    return value;
  }

  return coreValue(a).compareTo(coreValue(b));
}
