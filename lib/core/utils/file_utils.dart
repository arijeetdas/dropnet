import 'dart:io';

import 'package:path/path.dart' as p;

class FileUtils {
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
