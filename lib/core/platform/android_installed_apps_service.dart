import 'package:flutter/services.dart';

class AndroidInstalledApp {
  const AndroidInstalledApp({
    required this.name,
    required this.packageName,
    required this.apkPath,
    required this.isSystemApp,
    required this.iconBytes,
  });

  final String name;
  final String packageName;
  final String apkPath;
  final bool isSystemApp;
  final Uint8List? iconBytes;
}

class AndroidInstalledAppsService {
  static const MethodChannel _channel = MethodChannel('dropnet/android_apps');

  Future<List<AndroidInstalledApp>> listInstalledApps({required bool includeSystemApps}) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listInstalledApps',
      {'includeSystemApps': includeSystemApps},
    );

    if (result == null || result.isEmpty) {
      return const [];
    }

    return result
        .whereType<Map>()
        .map((raw) {
          final map = raw.cast<Object?, Object?>();
          final name = (map['name']?.toString() ?? '').trim();
          final packageName = (map['packageName']?.toString() ?? '').trim();
          final apkPath = (map['apkPath']?.toString() ?? '').trim();
          final isSystem = map['isSystemApp'] == true;
          final rawIcon = map['iconBytes'];
          final iconBytes = rawIcon is Uint8List
              ? rawIcon
              : rawIcon is List
                  ? Uint8List.fromList(rawIcon.whereType<int>().toList(growable: false))
                  : null;
          if (name.isEmpty || packageName.isEmpty || apkPath.isEmpty) {
            return null;
          }
          return AndroidInstalledApp(
            name: name,
            packageName: packageName,
            apkPath: apkPath,
            isSystemApp: isSystem,
            iconBytes: iconBytes,
          );
        })
        .whereType<AndroidInstalledApp>()
        .toList(growable: false);
  }
}
