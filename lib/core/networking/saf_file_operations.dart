import 'dart:async';
import 'dart:io';

import 'package:ftp_server/file_operations/file_operations.dart';
import 'package:path/path.dart' as p;

import '../platform/android_saf_service.dart';

class SafTreeRoot {
  const SafTreeRoot({
    required this.alias,
    required this.treeUri,
    required this.label,
  });

  final String alias;
  final String treeUri;
  final String label;
}

class SafFileOperations extends FileOperations {
  SafFileOperations({
    required this.roots,
    required this.service,
    String startingDirectory = '/',
  }) : super(p.separator) {
    if (roots.isEmpty) {
      throw ArgumentError('SAF roots cannot be empty.');
    }
    currentDirectory = p.isAbsolute(startingDirectory)
        ? p.normalize(startingDirectory)
        : p.normalize(p.join(rootDirectory, startingDirectory));
    if (currentDirectory.isEmpty) {
      currentDirectory = rootDirectory;
    }
  }

  final List<SafTreeRoot> roots;
  final AndroidSafService service;

  SafTreeRoot? _rootByAlias(String alias) {
    for (final root in roots) {
      if (root.alias.toLowerCase() == alias.toLowerCase()) {
        return root;
      }
    }
    return null;
  }

  ({SafTreeRoot root, String relativePath}) _resolve(String path) {
    final cleanPath = p.normalize(path.isEmpty ? '.' : path);
    final absoluteVirtualPath = p.isAbsolute(cleanPath)
        ? cleanPath
        : p.normalize(p.join(currentDirectory, cleanPath));

    if (absoluteVirtualPath == rootDirectory) {
      throw const FileSystemException('Root does not map to a single SAF tree');
    }

    final parts = p
        .split(absoluteVirtualPath)
        .where((part) => part.isNotEmpty && part != p.separator)
        .toList(growable: false);
    if (parts.isEmpty) {
      throw const FileSystemException('Invalid SAF path');
    }

    final alias = parts.first;
    final root = _rootByAlias(alias);
    if (root == null) {
      throw FileSystemException('Unknown SAF root alias: $alias', absoluteVirtualPath);
    }

    final relativePath = parts.length > 1 ? parts.sublist(1).join('/') : '';
    return (root: root, relativePath: relativePath);
  }

  @override
  String resolvePath(String path) {
    if (path.trim().isEmpty || path.trim() == '.') {
      return currentDirectory;
    }
    final cleanPath = p.normalize(path);
    final absoluteVirtualPath = p.isAbsolute(cleanPath)
        ? cleanPath
        : p.normalize(p.join(currentDirectory, cleanPath));
    return absoluteVirtualPath;
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
    final entries = await service.listTreeEntries(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    return entries
        .map(
          (entry) => FtpFileEntry(
            name: entry.name,
            path: '/${mapping.root.alias}${mapping.relativePath.isEmpty ? '' : '/${mapping.relativePath}'}/${entry.name}'
                .replaceAll('//', '/'),
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
    final tmpDir = await Directory.systemTemp.createTemp('dropnet_saf_file_');
    final file = File('${tmpDir.path}${Platform.pathSeparator}placeholder.bin');
    return file;
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final mapping = _resolve(path);
    final ok = await service.writeFileToTree(
      treeUri: mapping.root.treeUri,
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
    final bytes = await service.readFileFromTree(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    if (bytes == null) {
      throw FileSystemException('Failed to read SAF file', path);
    }
    return bytes;
  }

  @override
  Stream<List<int>> openRead(String path) async* {
    final bytes = await readFile(path);
    const chunk = 64 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunk) {
      final end = (offset + chunk) > bytes.length ? bytes.length : (offset + chunk);
      yield bytes.sublist(offset, end);
    }
  }

  @override
  Future<void> writeFromStream(String path, Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    await writeFile(path, bytes);
  }

  @override
  Future<void> createDirectory(String path) async {
    final mapping = _resolve(path);
    final ok = await service.createDirectoryInTree(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    if (!ok) {
      throw FileSystemException('Failed to create SAF directory', path);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final mapping = _resolve(path);
    final ok = await service.deleteFromTree(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    if (!ok) {
      throw FileSystemException('Failed to delete SAF file', path);
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    await deleteFile(path);
  }

  @override
  Future<int> fileSize(String path) async {
    final mapping = _resolve(path);
    final size = await service.fileSizeInTree(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    if (size < 0) {
      throw FileSystemException('Failed to read SAF file size', path);
    }
    return size;
  }

  @override
  bool exists(String path) {
    return true;
  }

  @override
  Future<DateTime> modificationTime(String path) async {
    final mapping = _resolve(path);
    final time = await service.modificationTimeInTree(
      treeUri: mapping.root.treeUri,
      relativePath: mapping.relativePath,
    );
    if (time <= 0) {
      return DateTime.now();
    }
    return DateTime.fromMillisecondsSinceEpoch(time);
  }

  @override
  void changeDirectory(String path) {
    final resolved = resolvePath(path);
    if (resolved == rootDirectory) {
      currentDirectory = rootDirectory;
      return;
    }
    _resolve(path);
    currentDirectory = resolved;
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException('Cannot navigate above root', currentDirectory);
    }
    currentDirectory = p.dirname(currentDirectory);
    if (currentDirectory.isEmpty) {
      currentDirectory = rootDirectory;
    }
  }

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final from = _resolve(oldPath);
    final to = p.basename(p.normalize(newPath));
    final ok = await service.renameInTree(
      treeUri: from.root.treeUri,
      fromRelativePath: from.relativePath,
      toName: to,
    );
    if (!ok) {
      throw FileSystemException('Failed to rename SAF entry', oldPath);
    }
  }

  @override
  FileOperations copy() {
    return SafFileOperations(
      roots: roots,
      service: service,
      startingDirectory: currentDirectory,
    );
  }
}
