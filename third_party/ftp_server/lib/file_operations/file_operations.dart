import 'dart:async';
import 'dart:io';

class FtpFileEntry {
  const FtpFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
}

/// Interface defining common file operations for both physical and virtual file systems.
abstract class FileOperations {
  String rootDirectory;
  late String currentDirectory;

  FileOperations(this.rootDirectory) {
    currentDirectory = rootDirectory;
  }

  /// Lists the contents of the directory at the given path.
  Future<List<FileSystemEntity>> listDirectory(String path);

  /// Lists entries for FTP listing/MLSD in a backend-agnostic way.
  Future<List<FtpFileEntry>> listEntries(String path) async {
    final entities = await listDirectory(path);
    final entries = <FtpFileEntry>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final entityPath = entity.path;
      final parts = entityPath.replaceAll('\\', '/').split('/');
      final name = parts.isEmpty ? entityPath : parts.last;
      entries.add(
        FtpFileEntry(
          name: name,
          path: entityPath,
          isDirectory: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    return entries;
  }

  /// Retrieves a [File] object for the given path.
  Future<File> getFile(String path);

  /// Writes data to a file at the specified path.
  Future<void> writeFile(String path, List<int> data);

  /// Reads and returns the data from the file at the specified path.
  Future<List<int>> readFile(String path);

  /// Opens a file for streaming reads.
  Stream<List<int>> openRead(String path) async* {
    final bytes = await readFile(path);
    yield bytes;
  }

  /// Writes a file from streamed bytes.
  Future<void> writeFromStream(String path, Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final data in stream) {
      chunks.addAll(data);
    }
    await writeFile(path, chunks);
  }

  /// Returns last modification time if available.
  Future<DateTime> modificationTime(String path) async {
    final file = await getFile(path);
    final stat = await file.stat();
    return stat.modified;
  }

  /// Creates a directory at the specified path.
  Future<void> createDirectory(String path);

  /// Deletes the file at the specified path.
  Future<void> deleteFile(String path);

  /// Deletes the directory at the specified path.
  Future<void> deleteDirectory(String path);

  /// Returns the size of the file at the specified path.
  Future<int> fileSize(String path);

  /// Checks if a file or directory exists at the specified path.
  bool exists(String path);

  /// Resolves the given [path] relative to the [currentDirectory] and the specific file system rules (physical or virtual).
  ///
  /// Implementations must handle normalization, security checks (staying within allowed boundaries),
  /// and mapping (for virtual systems).
  String resolvePath(String path);

  /// Returns the current working directory.
  String getCurrentDirectory() {
    return currentDirectory;
  }

  /// Changes the current working directory to the specified path.
  /// Implementations must handle path resolution and update the internal state correctly.
  void changeDirectory(String path);

  /// Changes the current working directory to the parent directory.
  /// Implementations must handle path resolution and update the internal state correctly,
  /// including checks for navigating above the root.
  void changeToParentDirectory();

  /// Renames a file or directory from the old path to the new path.
  /// Both paths are relative to the current working directory.
  /// Implementations must handle path resolution and ensure the operation stays within allowed boundaries.
  Future<void> renameFileOrDirectory(String oldPath, String newPath);

  FileOperations copy();
}
