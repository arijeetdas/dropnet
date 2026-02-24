import 'package:flutter/services.dart';

class AndroidSafTree {
  const AndroidSafTree({
    required this.uri,
    required this.name,
    required this.read,
    required this.write,
  });

  final String uri;
  final String name;
  final bool read;
  final bool write;

  factory AndroidSafTree.fromMap(Map<Object?, Object?> raw) {
    return AndroidSafTree(
      uri: (raw['uri']?.toString() ?? '').trim(),
      name: (raw['name']?.toString() ?? '').trim(),
      read: raw['read'] == true,
      write: raw['write'] == true,
    );
  }
}

class AndroidSafEntry {
  const AndroidSafEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  final String name;
  final bool isDirectory;
  final int size;
  final int modifiedAt;

  factory AndroidSafEntry.fromMap(Map<Object?, Object?> raw) {
    return AndroidSafEntry(
      name: (raw['name']?.toString() ?? '').trim(),
      isDirectory: raw['isDirectory'] == true,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      modifiedAt: (raw['modifiedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class AndroidSafService {
  static const MethodChannel _channel = MethodChannel('dropnet/android_saf');

  Future<AndroidSafTree?> pickDirectoryTree() async {
    final result = await _channel.invokeMethod<dynamic>('pickDirectoryTree');
    if (result is! Map) {
      return null;
    }
    final tree = AndroidSafTree.fromMap(result.cast<Object?, Object?>());
    if (tree.uri.isEmpty) {
      return null;
    }
    return tree;
  }

  Future<List<AndroidSafTree>> listPersistedTrees() async {
    final result = await _channel.invokeMethod<List<dynamic>>('listPersistedTrees');
    if (result == null || result.isEmpty) {
      return const <AndroidSafTree>[];
    }
    return result
        .whereType<Map>()
        .map((raw) => AndroidSafTree.fromMap(raw.cast<Object?, Object?>()))
        .where((tree) => tree.uri.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> releasePersistedTree(String uri) async {
    final ok = await _channel.invokeMethod<bool>('releasePersistedTree', {'uri': uri});
    return ok == true;
  }

  Future<List<AndroidSafEntry>> listTreeEntries({required String treeUri, required String relativePath}) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listTreeEntries',
      {
        'treeUri': treeUri,
        'relativePath': relativePath,
      },
    );
    if (result == null || result.isEmpty) {
      return const <AndroidSafEntry>[];
    }
    return result
        .whereType<Map>()
        .map((raw) => AndroidSafEntry.fromMap(raw.cast<Object?, Object?>()))
        .toList(growable: false);
  }

  Future<bool> existsInTree({required String treeUri, required String relativePath}) async {
    final ok = await _channel.invokeMethod<bool>('existsInTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return ok == true;
  }

  Future<int> fileSizeInTree({required String treeUri, required String relativePath}) async {
    final size = await _channel.invokeMethod<num>('fileSizeInTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return size?.toInt() ?? -1;
  }

  Future<int> modificationTimeInTree({required String treeUri, required String relativePath}) async {
    final time = await _channel.invokeMethod<num>('modificationTimeInTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return time?.toInt() ?? 0;
  }

  Future<List<int>?> readFileFromTree({required String treeUri, required String relativePath}) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readFileFromTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return bytes?.toList(growable: false);
  }

  Future<bool> writeFileToTree({required String treeUri, required String relativePath, required List<int> bytes}) async {
    final ok = await _channel.invokeMethod<bool>('writeFileToTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
      'bytes': Uint8List.fromList(bytes),
    });
    return ok == true;
  }

  Future<bool> createDirectoryInTree({required String treeUri, required String relativePath}) async {
    final ok = await _channel.invokeMethod<bool>('createDirectoryInTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return ok == true;
  }

  Future<bool> deleteFromTree({required String treeUri, required String relativePath}) async {
    final ok = await _channel.invokeMethod<bool>('deleteFromTree', {
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return ok == true;
  }

  Future<bool> renameInTree({required String treeUri, required String fromRelativePath, required String toName}) async {
    final ok = await _channel.invokeMethod<bool>('renameInTree', {
      'treeUri': treeUri,
      'fromRelativePath': fromRelativePath,
      'toName': toName,
    });
    return ok == true;
  }
}
