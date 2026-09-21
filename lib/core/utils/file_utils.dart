import 'dart:io';

import 'package:path/path.dart' as p;

/// The category subfolder an incoming file is sorted into when the user's
/// save location has folder categorization enabled.
enum ReceivedFileCategory {
  documents,
  image,
  audio,
  video,
  programs,
  code,
  text,
  compressed,
  others,
}

extension ReceivedFileCategoryFolder on ReceivedFileCategory {
  String get folderName => switch (this) {
    ReceivedFileCategory.documents => 'Documents',
    ReceivedFileCategory.image => 'Image',
    ReceivedFileCategory.audio => 'Audio',
    ReceivedFileCategory.video => 'Video',
    ReceivedFileCategory.programs => 'Programs',
    ReceivedFileCategory.code => 'Code',
    ReceivedFileCategory.text => 'Text',
    ReceivedFileCategory.compressed => 'Compressed',
    ReceivedFileCategory.others => 'Others',
  };
}

class FileUtils {
  static const List<String> categoryFolderNames = [
    'Documents',
    'Image',
    'Audio',
    'Video',
    'Programs',
    'Code',
    'Text',
    'Compressed',
    'Others',
  ];

  static const Map<String, ReceivedFileCategory> _extensionCategories = {
    // Documents
    'pdf': ReceivedFileCategory.documents,
    'doc': ReceivedFileCategory.documents,
    'docx': ReceivedFileCategory.documents,
    'ppt': ReceivedFileCategory.documents,
    'pptx': ReceivedFileCategory.documents,
    'xls': ReceivedFileCategory.documents,
    'xlsx': ReceivedFileCategory.documents,
    'odt': ReceivedFileCategory.documents,
    'ods': ReceivedFileCategory.documents,
    'odp': ReceivedFileCategory.documents,
    'rtf': ReceivedFileCategory.documents,
    'epub': ReceivedFileCategory.documents,
    'csv': ReceivedFileCategory.documents,
    // Image
    'jpg': ReceivedFileCategory.image,
    'jpeg': ReceivedFileCategory.image,
    'png': ReceivedFileCategory.image,
    'gif': ReceivedFileCategory.image,
    'bmp': ReceivedFileCategory.image,
    'webp': ReceivedFileCategory.image,
    'svg': ReceivedFileCategory.image,
    'heic': ReceivedFileCategory.image,
    'heif': ReceivedFileCategory.image,
    'tiff': ReceivedFileCategory.image,
    'tif': ReceivedFileCategory.image,
    'ico': ReceivedFileCategory.image,
    'raw': ReceivedFileCategory.image,
    'cr2': ReceivedFileCategory.image,
    'nef': ReceivedFileCategory.image,
    'dng': ReceivedFileCategory.image,
    // Audio
    'mp3': ReceivedFileCategory.audio,
    'wav': ReceivedFileCategory.audio,
    'flac': ReceivedFileCategory.audio,
    'aac': ReceivedFileCategory.audio,
    'ogg': ReceivedFileCategory.audio,
    'm4a': ReceivedFileCategory.audio,
    'wma': ReceivedFileCategory.audio,
    'opus': ReceivedFileCategory.audio,
    'aiff': ReceivedFileCategory.audio,
    // Video
    'mp4': ReceivedFileCategory.video,
    'mkv': ReceivedFileCategory.video,
    'mov': ReceivedFileCategory.video,
    'avi': ReceivedFileCategory.video,
    'wmv': ReceivedFileCategory.video,
    'flv': ReceivedFileCategory.video,
    'webm': ReceivedFileCategory.video,
    'm4v': ReceivedFileCategory.video,
    '3gp': ReceivedFileCategory.video,
    'mpeg': ReceivedFileCategory.video,
    'mpg': ReceivedFileCategory.video,
    // Programs
    'exe': ReceivedFileCategory.programs,
    'msi': ReceivedFileCategory.programs,
    'apk': ReceivedFileCategory.programs,
    'dmg': ReceivedFileCategory.programs,
    'pkg': ReceivedFileCategory.programs,
    'deb': ReceivedFileCategory.programs,
    'rpm': ReceivedFileCategory.programs,
    'appimage': ReceivedFileCategory.programs,
    'ipa': ReceivedFileCategory.programs,
    // Code
    'dart': ReceivedFileCategory.code,
    'py': ReceivedFileCategory.code,
    'js': ReceivedFileCategory.code,
    'ts': ReceivedFileCategory.code,
    'jsx': ReceivedFileCategory.code,
    'tsx': ReceivedFileCategory.code,
    'java': ReceivedFileCategory.code,
    'kt': ReceivedFileCategory.code,
    'kts': ReceivedFileCategory.code,
    'swift': ReceivedFileCategory.code,
    'c': ReceivedFileCategory.code,
    'cpp': ReceivedFileCategory.code,
    'h': ReceivedFileCategory.code,
    'hpp': ReceivedFileCategory.code,
    'cs': ReceivedFileCategory.code,
    'go': ReceivedFileCategory.code,
    'rs': ReceivedFileCategory.code,
    'rb': ReceivedFileCategory.code,
    'php': ReceivedFileCategory.code,
    'html': ReceivedFileCategory.code,
    'htm': ReceivedFileCategory.code,
    'css': ReceivedFileCategory.code,
    'json': ReceivedFileCategory.code,
    'xml': ReceivedFileCategory.code,
    'yaml': ReceivedFileCategory.code,
    'yml': ReceivedFileCategory.code,
    'sh': ReceivedFileCategory.code,
    'bat': ReceivedFileCategory.code,
    'ps1': ReceivedFileCategory.code,
    'sql': ReceivedFileCategory.code,
    // Text
    'txt': ReceivedFileCategory.text,
    'md': ReceivedFileCategory.text,
    'log': ReceivedFileCategory.text,
    'ini': ReceivedFileCategory.text,
    'cfg': ReceivedFileCategory.text,
    'conf': ReceivedFileCategory.text,
    // Compressed
    'zip': ReceivedFileCategory.compressed,
    'rar': ReceivedFileCategory.compressed,
    '7z': ReceivedFileCategory.compressed,
    'tar': ReceivedFileCategory.compressed,
    'gz': ReceivedFileCategory.compressed,
    'tgz': ReceivedFileCategory.compressed,
    'bz2': ReceivedFileCategory.compressed,
    'xz': ReceivedFileCategory.compressed,
  };

  /// Determines which category subfolder a received file belongs in, based
  /// on its extension. Unknown or missing extensions fall back to "Others".
  static ReceivedFileCategory categorizeReceivedFile(String fileName) {
    final base = p.basename(fileName);
    final dotIndex = base.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == base.length - 1) {
      return ReceivedFileCategory.others;
    }
    final extension = base.substring(dotIndex + 1).toLowerCase();
    return _extensionCategories[extension] ?? ReceivedFileCategory.others;
  }

  /// Creates any of the category subfolders that don't already exist inside
  /// [rootDir]. Existing subfolders are left untouched.
  static Future<void> ensureCategoryFoldersExist(String rootDir) async {
    for (final name in categoryFolderNames) {
      final dir = Directory(p.join(rootDir, name));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Returns which category subfolders already exist inside [rootDir].
  static Future<Set<String>> existingCategoryFolders(String rootDir) async {
    final found = <String>{};
    for (final name in categoryFolderNames) {
      if (await Directory(p.join(rootDir, name)).exists()) {
        found.add(name);
      }
    }
    return found;
  }

  /// Resolves the on-disk path a received file should be written to.
  /// When [categorize] is true, the file is routed into its category
  /// subfolder (created on demand); otherwise it's saved directly in
  /// [saveDir].
  static String resolveReceivedFileSavePath({
    required String saveDir,
    required String fileName,
    required bool categorize,
  }) {
    if (!categorize) {
      return safeJoin(saveDir, fileName);
    }
    final category = categorizeReceivedFile(fileName);
    final categoryDir = p.join(saveDir, category.folderName);
    return safeJoin(categoryDir, fileName);
  }

  /// Whether [path] points to a folder named exactly "DropNet" — the app's
  /// own default save location. Used to gate destructive folder-maintenance
  /// actions that assume the app owns everything inside it.
  static bool isDropNetFolder(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return p.basename(p.normalize(trimmed)) == 'DropNet';
  }

  /// Deletes every file directly inside [rootDir] (the DropNet save folder)
  /// and every file inside its recognized category subfolders, without
  /// deleting [rootDir] or those category subfolders themselves. Any other
  /// subfolder inside [rootDir] — one the app didn't create — is removed
  /// entirely, contents included.
  static Future<void> clearDropNetFolder(String rootDir) async {
    final root = Directory(rootDir);
    if (!await root.exists()) {
      return;
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (categoryFolderNames.contains(name)) {
          await _clearDirectoryContents(entity);
        } else {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      } else {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> _clearDirectoryContents(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  static String sanitizeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'file_${DateTime.now().millisecondsSinceEpoch}';
    }
    return cleaned;
  }

  static String safeJoin(String root, String fileName) {
    final candidate = p.normalize(p.join(root, sanitizeFileName(fileName)));
    final normalizedRoot = p.normalize(root);
    final isInside = p.isWithin(normalizedRoot, candidate) || candidate == normalizedRoot;
    if (!isInside) {
      throw const FileSystemException('Directory traversal blocked');
    }
    return candidate;
  }

  static String formatBytes(num bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(double bytesPerSecond) {
    return '${formatBytes(bytesPerSecond)}/s';
  }
}
