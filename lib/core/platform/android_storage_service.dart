import 'package:flutter/services.dart';

class AndroidStorageRoot {
  const AndroidStorageRoot({
    required this.path,
    required this.label,
    required this.isRemovable,
    required this.isPrimary,
    required this.state,
  });

  final String path;
  final String label;
  final bool isRemovable;
  final bool isPrimary;
  final String state;

  factory AndroidStorageRoot.fromMap(Map<Object?, Object?> raw) {
    return AndroidStorageRoot(
      path: (raw['path']?.toString() ?? '').trim(),
      label: (raw['label']?.toString() ?? '').trim(),
      isRemovable: raw['isRemovable'] == true,
      isPrimary: raw['isPrimary'] == true,
      state: (raw['state']?.toString() ?? '').trim(),
    );
  }
}

class AndroidStorageService {
  static const MethodChannel _channel = MethodChannel('dropnet/android_storage');

  Future<List<AndroidStorageRoot>> listStorageRoots() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listStorageRoots');
      if (result == null || result.isEmpty) {
        return const <AndroidStorageRoot>[];
      }
      final roots = result
          .whereType<Map>()
          .map((raw) => AndroidStorageRoot.fromMap(raw.cast<Object?, Object?>()))
          .where((root) => root.path.isNotEmpty)
          .toList(growable: false);
      final deduped = <String, AndroidStorageRoot>{};
      for (final root in roots) {
        deduped[root.path] = root;
      }
      return deduped.values.toList(growable: false);
    } catch (_) {
      return const <AndroidStorageRoot>[];
    }
  }
}
