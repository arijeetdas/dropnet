import 'dart:io';

import 'package:ftp_server/file_operations/file_operations.dart';
import 'package:path/path.dart' as p;

import '../platform/android_saf_service.dart';

enum MixedRootKind { physical, saf }

class MixedRoot {
  const MixedRoot._({
    required this.alias,
    required this.label,
    required this.kind,
    this.physicalPath,
    this.treeUri,
  });

  final String alias;
  final String label;
  final MixedRootKind kind;
  final String? physicalPath;
  final String? treeUri;

  factory MixedRoot.physical({
    required String alias,
    required String label,
    required String physicalPath,
  }) {
    return MixedRoot._(
      alias: alias,
      label: label,
      kind: MixedRootKind.physical,
      physicalPath: physicalPath,
    );
  }

  factory MixedRoot.saf({
    required String alias,
    required String label,
    required String treeUri,
  }) {
    return MixedRoot._(
      alias: alias,
      label: label,
      kind: MixedRootKind.saf,
      treeUri: treeUri,
    );
  }
}

class MixedFileOperations extends FileOperations {
  MixedFileOperations({
    required this.roots,
    required this.safService,
    String startingDirectory = '/',
  }) : super(p.separator) {
    if (roots.isEmpty) {
      throw ArgumentError('Mixed roots cannot be empty.');
    }
    currentDirectory = p.isAbsolute(startingDirectory)
        ? p.normalize(startingDirectory)
        : p.normalize(p.join(rootDirectory, startingDirectory));
    if (currentDirectory.isEmpty) {
      currentDirectory = rootDirectory;
    }
  }

  final List<MixedRoot> roots;
  final AndroidSafService? safService;

  MixedRoot? _rootByAlias(String alias) {
    for (final root in roots) {
      if (root.alias.toLowerCase() == alias.toLowerCase()) {
        return root;
      }
    }
    return null;
  }

  String _virtual(String alias, String relativePath, String name) {
    final base = '/$alias';
    final path = relativePath.trim().isEmpty ? '$base/$name' : '$base/$relativePath/$name';
    return path.replaceAll('//', '/');
  }

  ({MixedRoot root, String relativePath}) _resolve(String path) {
    final cleanPath = p.normalize(path.isEmpty ? '.' : path);
    final absoluteVirtualPath = p.isAbsolute(cleanPath)
        ? cleanPath
        : p.normalize(p.join(currentDirectory, cleanPath));

    if (absoluteVirtualPath == rootDirectory) {
      throw const FileSystemException('Root does not map to a single backend root');
    }

    final parts = p
        .split(absoluteVirtualPath)
        .where((part) => part.isNotEmpty && part != p.separator)
        .toList(growable: false);
    if (parts.isEmpty) {
      throw const FileSystemException('Invalid virtual path');
    }

    final alias = parts.first;
    final root = _rootByAlias(alias);
    if (root == null) {
      throw FileSystemException('Unknown FTP root alias: $alias', absoluteVirtualPath);
    }

    final relativePath = parts.length > 1 ? parts.sublist(1).join('/') : '';
    return (root: root, relativePath: relativePath);
  }

  String _resolvePhysicalPath(MixedRoot root, String relativePath) {
    final base = root.physicalPath!;
    final resolved = relativePath.trim().isEmpty
        ? p.normalize(base)
        : p.normalize(p.join(base, relativePath));

    if (!p.isWithin(base, resolved) && !p.equals(base, resolved)) {
      throw FileSystemException('Path escapes shared root boundary', resolved);
    }
    return resolved;
  }

  @override
  String resolvePath(String path) {
    if (path.trim().isEmpty || path.trim() == '.') {
      return currentDirectory;
    }
    final cleanPath = p.normalize(path);
    return p.isAbsolute(cleanPath) ? cleanPath : p.normalize(p.join(currentDirectory, cleanPath));
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final entries = await listEntries(path);
    return entries
        .map((entry) => entry.isDirectory ? Directory(entry.path) : File(entry.path))
        .toList(growable: false);
  }

  @override
  Future<List<FtpFileEntry>> listEntries(String path) async {
    final resolvedVirtual = resolvePath(path);
    if (resolvedVirtual == rootDirectory) {
      return roots
          .map(
            (root) => FtpFileEntry(
              name: root.alias,
              path: '/${root.alias}',
              isDirectory: true,
              size: 0,
              modified: DateTime.now(),
            ),
          )
          .toList(growable: false);
    }

    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        throw FileSystemException('Directory does not exist', fullPath);
      }
      final entities = dir.listSync(followLinks: false);
      final output = <FtpFileEntry>[];
      for (final entity in entities) {
        final stat = await entity.stat();
        final name = p.basename(entity.path);
        output.add(
          FtpFileEntry(
            name: name,
            path: _virtual(mapping.root.alias, mapping.relativePath, name),
            isDirectory: stat.type == FileSystemEntityType.directory,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      }
      return output;
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final entries = await service.listTreeEntries(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    return entries
        .map(
          (entry) => FtpFileEntry(
            name: entry.name,
            path: _virtual(mapping.root.alias, mapping.relativePath, entry.name),
            isDirectory: entry.isDirectory,
            size: entry.size,
            modified: entry.modifiedAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(entry.modifiedAt)
                : DateTime.now(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<File> getFile(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      return File(fullPath);
    }
    final tmpDir = await Directory.systemTemp.createTemp('dropnet_saf_file_');
    return File('${tmpDir.path}${Platform.pathSeparator}placeholder.bin');
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      final file = File(fullPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data, flush: true);
      return;
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final ok = await service.writeFileToTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
      bytes: data,
    );
    if (!ok) {
      throw FileSystemException('Failed to write SAF file', path);
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      return File(fullPath).readAsBytes();
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final bytes = await service.readFileFromTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    if (bytes == null) {
      throw FileSystemException('Failed to read SAF file', path);
    }
    return bytes;
  }

  @override
  Stream<List<int>> openRead(String path) async* {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      yield* File(fullPath).openRead();
      return;
    }

    final bytes = await readFile(path);
    const chunk = 64 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunk) {
      final end = (offset + chunk) > bytes.length ? bytes.length : (offset + chunk);
      yield bytes.sublist(offset, end);
    }
  }

  @override
  Future<void> writeFromStream(String path, Stream<List<int>> stream) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      final file = File(fullPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return;
    }

    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    await writeFile(path, bytes);
  }

  @override
  Future<void> createDirectory(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      await Directory(fullPath).create(recursive: true);
      return;
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final ok = await service.createDirectoryInTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    if (!ok) {
      throw FileSystemException('Failed to create SAF directory', path);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      final entityType = FileSystemEntity.typeSync(fullPath);
      if (entityType == FileSystemEntityType.directory) {
        await Directory(fullPath).delete(recursive: true);
      } else {
        await File(fullPath).delete();
      }
      return;
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final ok = await service.deleteFromTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    if (!ok) {
      throw FileSystemException('Failed to delete SAF entry', path);
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    await deleteFile(path);
  }

  @override
  Future<int> fileSize(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      return File(fullPath).length();
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final size = await service.fileSizeInTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    if (size < 0) {
      throw FileSystemException('Failed to get SAF file size', path);
    }
    return size;
  }

  @override
  bool exists(String path) {
    if (path.trim().isEmpty || path.trim() == '/' || path.trim() == '.') {
      return true;
    }

    try {
      final mapping = _resolve(path);
      if (mapping.root.kind == MixedRootKind.physical) {
        final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
        return File(fullPath).existsSync() || Directory(fullPath).existsSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DateTime> modificationTime(String path) async {
    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      return (await File(fullPath).stat()).modified;
    }

    final service = safService;
    if (service == null || mapping.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final modifiedAt = await service.modificationTimeInTree(
      treeUri: mapping.root.treeUri!,
      relativePath: mapping.relativePath,
    );
    if (modifiedAt <= 0) {
      return DateTime.now();
    }
    return DateTime.fromMillisecondsSinceEpoch(modifiedAt);
  }

  @override
  void changeDirectory(String path) {
    final resolved = resolvePath(path);
    if (resolved == rootDirectory) {
      currentDirectory = rootDirectory;
      return;
    }

    final mapping = _resolve(path);
    if (mapping.root.kind == MixedRootKind.physical) {
      final fullPath = _resolvePhysicalPath(mapping.root, mapping.relativePath);
      if (!Directory(fullPath).existsSync()) {
        throw FileSystemException('Directory not found', fullPath);
      }
    }

    currentDirectory = resolved;
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException('Cannot navigate above root', currentDirectory);
    }
    currentDirectory = p.dirname(currentDirectory);
    if (currentDirectory.isEmpty || currentDirectory == '.') {
      currentDirectory = rootDirectory;
    }
  }

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final from = _resolve(oldPath);
    final to = _resolve(newPath);
    if (from.root.alias.toLowerCase() != to.root.alias.toLowerCase()) {
      throw const FileSystemException('Renaming across different roots is not supported.');
    }

    if (from.root.kind == MixedRootKind.physical) {
      final fromPhysical = _resolvePhysicalPath(from.root, from.relativePath);
      final toPhysical = _resolvePhysicalPath(to.root, to.relativePath);
      final type = FileSystemEntity.typeSync(fromPhysical);
      if (type == FileSystemEntityType.directory) {
        await Directory(fromPhysical).rename(toPhysical);
      } else {
        await File(fromPhysical).rename(toPhysical);
      }
      return;
    }

    final service = safService;
    if (service == null || from.root.treeUri == null) {
      throw const FileSystemException('SAF service unavailable');
    }
    final ok = await service.renameInTree(
      treeUri: from.root.treeUri!,
      fromRelativePath: from.relativePath,
      toName: p.basename(to.relativePath),
    );
    if (!ok) {
      throw FileSystemException('Failed to rename SAF entry', oldPath);
    }
  }

  @override
  FileOperations copy() {
    return MixedFileOperations(
      roots: roots,
      safService: safService,
      startingDirectory: currentDirectory,
    );
  }
}
