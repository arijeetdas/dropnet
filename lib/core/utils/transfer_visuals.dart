import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum TransferFileKind {
  image,
  video,
  audio,
  pdf,
  text,
  archive,
  code,
  document,
  generic,
}

class TransferVisuals {
  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
  };

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.webm',
    '.m4v',
  };

  static const Set<String> _audioExtensions = {
    '.mp3',
    '.wav',
    '.aac',
    '.flac',
    '.ogg',
    '.m4a',
  };

  static const Set<String> _archiveExtensions = {
    '.zip',
    '.rar',
    '.7z',
    '.tar',
    '.gz',
  };

  static const Set<String> _codeExtensions = {
    '.dart',
    '.js',
    '.ts',
    '.kt',
    '.swift',
    '.java',
    '.cpp',
    '.c',
    '.py',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.css',
    '.md',
  };

  static const Set<String> _documentExtensions = {
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.odt',
    '.ods',
    '.odp',
    '.csv',
    '.rtf',
  };

  static const Set<String> _textPreviewExtensions = {
    '.txt',
    '.text',
    '.url',
    '.webloc',
  };

  static String extensionOf(String fileNameOrPath) {
    return p.extension(fileNameOrPath).toLowerCase();
  }

  static TransferFileKind kindForName(String fileNameOrPath) {
    final extension = extensionOf(fileNameOrPath);
    if (_imageExtensions.contains(extension)) {
      return TransferFileKind.image;
    }
    if (_videoExtensions.contains(extension)) {
      return TransferFileKind.video;
    }
    if (_audioExtensions.contains(extension)) {
      return TransferFileKind.audio;
    }
    if (extension == '.pdf') {
      return TransferFileKind.pdf;
    }
    if (_textPreviewExtensions.contains(extension)) {
      return TransferFileKind.text;
    }
    if (_archiveExtensions.contains(extension)) {
      return TransferFileKind.archive;
    }
    if (_codeExtensions.contains(extension)) {
      return TransferFileKind.code;
    }
    if (_documentExtensions.contains(extension)) {
      return TransferFileKind.document;
    }
    return TransferFileKind.generic;
  }

  static bool isTextPreviewType(String fileNameOrPath) {
    return kindForName(fileNameOrPath) == TransferFileKind.text;
  }

  static bool supportsImagePreview(String fileNameOrPath) {
    return kindForName(fileNameOrPath) == TransferFileKind.image;
  }

  static bool supportsReceivedPreview(String fileNameOrPath) {
    final kind = kindForName(fileNameOrPath);
    return kind == TransferFileKind.image ||
        kind == TransferFileKind.video ||
        kind == TransferFileKind.pdf ||
        kind == TransferFileKind.document;
  }

  static String kindLabel(String fileNameOrPath) {
    return switch (kindForName(fileNameOrPath)) {
      TransferFileKind.image => 'Image',
      TransferFileKind.video => 'Video',
      TransferFileKind.audio => 'Audio',
      TransferFileKind.pdf => 'PDF',
      TransferFileKind.text => 'Text',
      TransferFileKind.archive => 'Archive',
      TransferFileKind.code => 'Code',
      TransferFileKind.document => 'Document',
      TransferFileKind.generic => 'File',
    };
  }

  static IconData iconForName(String fileNameOrPath) {
    return switch (kindForName(fileNameOrPath)) {
      TransferFileKind.image => Icons.image_rounded,
      TransferFileKind.video => Icons.movie_rounded,
      TransferFileKind.audio => Icons.music_note_rounded,
      TransferFileKind.pdf => Icons.picture_as_pdf_rounded,
      TransferFileKind.text => Icons.description_rounded,
      TransferFileKind.archive => Icons.folder_zip_rounded,
      TransferFileKind.code => Icons.code_rounded,
      TransferFileKind.document => Icons.article_rounded,
      TransferFileKind.generic => Icons.insert_drive_file_rounded,
    };
  }

  static Color accentColor(BuildContext context, String fileNameOrPath) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (kindForName(fileNameOrPath)) {
      TransferFileKind.image => colorScheme.primary,
      TransferFileKind.video => colorScheme.secondary,
      TransferFileKind.audio => colorScheme.tertiary,
      TransferFileKind.pdf => const Color(0xFFB3261E),
      TransferFileKind.text => colorScheme.primary,
      TransferFileKind.archive => const Color(0xFF8A5A00),
      TransferFileKind.code => const Color(0xFF00658F),
      TransferFileKind.document => const Color(0xFF386A20),
      TransferFileKind.generic => colorScheme.outline,
    };
  }
}