import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort, non-fatal cleanup of temporary/junk files DropNet creates but
/// never needs again — never the user's actual received files.
///
/// Two sweeps, matched to when it's actually safe to run them:
/// - [sweepColdStart]: a full wipe of the OS temp/cache directory. Only safe
///   right after app launch, before any screen (e.g. Send) could be holding
///   a reference to a temp file it just created (its selection state lives
///   in local widget state, invisible to this service).
/// - [sweepOnResumeIfDue]: a narrower, age-gated sweep of specific
///   self-cleaning locations (web-share staging folders), safe to run at any
///   time since anything old enough to still be there is a crash/kill
///   orphan, not something in active use. Rate-limited so it doesn't rescan
///   the filesystem on every single foreground return.
class CacheCleanupService {
  CacheCleanupService._();

  static const _lastResumeSweepKey = 'cache_cleanup.last_resume_sweep_ms';
  static const Duration _resumeSweepMinInterval = Duration(hours: 6);
  static const Duration _webPendingMaxAge = Duration(minutes: 30);
  static const Duration _webSessionsMaxAge = Duration(minutes: 30);

  /// Wipes the app's OS temp/cache directory. Safe only at cold start, before
  /// any screen could be holding a path into it as a pending selection.
  /// [excludePaths] protects files a share-intent cold launch just staged
  /// into this same directory (consumed moments later by the app).
  static Future<void> sweepColdStart({List<String> excludePaths = const []}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      await _clearDirectoryContents(tempDir, excludePaths: excludePaths);
    } catch (_) {}
  }

  /// Age-gated sweep of self-cleaning staging locations, safe to run any
  /// time. Rate-limited to at most once per [_resumeSweepMinInterval].
  static Future<void> sweepOnResumeIfDue({String? dropNetRootDirectory}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRunMs = prefs.getInt(_lastResumeSweepKey) ?? 0;
      final lastRun = DateTime.fromMillisecondsSinceEpoch(lastRunMs);
      if (DateTime.now().difference(lastRun) < _resumeSweepMinInterval) {
        return;
      }
      await _sweepStaleWebPending();
      if (dropNetRootDirectory != null && dropNetRootDirectory.isNotEmpty) {
        await _sweepStaleWebSessions(dropNetRootDirectory);
      }
      await prefs.setInt(_lastResumeSweepKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// User-triggered "Clear App Cache" action: unconditional, no age gating,
  /// since the user explicitly confirmed it.
  static Future<void> clearAllNow({String? dropNetRootDirectory}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      await _clearDirectoryContents(tempDir);
    } catch (_) {}
    try {
      final pending = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_web_pending',
      );
      if (await pending.exists()) {
        await pending.delete(recursive: true);
      }
    } catch (_) {}
    if (dropNetRootDirectory != null && dropNetRootDirectory.isNotEmpty) {
      try {
        final sessions = Directory(
          p.join(dropNetRootDirectory, 'web_sessions'),
        );
        if (await sessions.exists()) {
          await sessions.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<void> _sweepStaleWebPending() async {
    final pending = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_web_pending',
    );
    if (!await pending.exists()) {
      return;
    }
    await for (final entity in pending.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        if (DateTime.now().difference(stat.modified) > _webPendingMaxAge) {
          await entity.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<void> _sweepStaleWebSessions(String rootDirectory) async {
    final sessionsRoot = Directory(p.join(rootDirectory, 'web_sessions'));
    if (!await sessionsRoot.exists()) {
      return;
    }
    // Layout is web_sessions/<peerId>/<sessionId>; only the leaf session
    // directories carry a meaningful modification time to age-check.
    await for (final peerEntity in sessionsRoot.list(followLinks: false)) {
      if (peerEntity is! Directory) continue;
      try {
        await for (final sessionEntity in peerEntity.list(followLinks: false)) {
          try {
            final stat = await sessionEntity.stat();
            if (DateTime.now().difference(stat.modified) > _webSessionsMaxAge) {
              await sessionEntity.delete(recursive: true);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  static Future<void> _clearDirectoryContents(
    Directory dir, {
    List<String> excludePaths = const [],
  }) async {
    if (!await dir.exists()) {
      return;
    }
    final excluded = excludePaths.map((path) => p.normalize(path)).toSet();
    await for (final entity in dir.list(followLinks: false)) {
      if (excluded.contains(p.normalize(entity.path))) {
        continue;
      }
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (_) {}
    }
  }
}
