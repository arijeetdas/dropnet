import 'dart:async';

import 'package:flutter/services.dart';

class SharedIntentPayload {
  const SharedIntentPayload({
    this.filePaths = const <String>[],
    this.texts = const <String>[],
    this.importing = false,
    this.failedCount = 0,
  });

  final List<String> filePaths;
  final List<String> texts;

  /// Android only: the native side is still copying shared content into the
  /// app (e.g. a large video shared from WhatsApp). More files will follow
  /// through [ShareIntentService.sharedPayloadStream] once it finishes.
  final bool importing;

  /// Android only: shared items the native side could not read or copy
  /// (revoked access, not enough storage, provider error).
  final int failedCount;

  bool get isEmpty => filePaths.isEmpty && texts.isEmpty;

  /// Worth handing to the app: something to import or a failure to report.
  bool get hasContent => !isEmpty || failedCount > 0;
}

class ShareIntentService {
  static const MethodChannel _channel = MethodChannel('dropnet/share_intent');

  late final StreamController<SharedIntentPayload> _sharedPayloadController =
      StreamController<SharedIntentPayload>.broadcast(
        onListen: _flushUndelivered,
      );

  // Payloads pulled from the native queue while nobody was listening yet.
  // Pulling empties that queue, so dropping them here would lose the share.
  final List<SharedIntentPayload> _undelivered = <SharedIntentPayload>[];
  final StreamController<bool> _importingController =
      StreamController<bool>.broadcast();

  bool _initialized = false;

  Stream<SharedIntentPayload> get sharedPayloadStream =>
      _sharedPayloadController.stream;

  /// Android only: whether shared content is currently being copied in.
  Stream<bool> get importInProgressStream => _importingController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      // Android: the native side holds shared items in a pending queue and
      // only signals that something is ready. Pulling through the same
      // consume call used at startup means every item is delivered exactly
      // once, whichever of the two paths gets to it first — no lost cold
      // start shares, no duplicates.
      if (call.method == 'sharedPayloadAvailable') {
        final payload = await consumePendingSharedPayload();
        _emitImporting(payload.importing);
        if (payload.hasContent) {
          _deliver(payload);
        }
        return;
      }

      if (call.method == 'sharedImportStateChanged') {
        final args = call.arguments;
        final importing = args is Map
            ? args['importing'] == true
            : args == true;
        _emitImporting(importing);
        return;
      }

      // iOS / macOS push the payload itself.
      if (call.method == 'sharedPayloadUpdated') {
        final payload = _normalizePayload(call.arguments);
        if (!payload.isEmpty && !_sharedPayloadController.isClosed) {
          _sharedPayloadController.add(payload);
        }
        return;
      }

      // Backward compatibility for older native integrations.
      if (call.method == 'sharedFilesUpdated') {
        final paths = _normalizeList(call.arguments);
        if (paths.isNotEmpty && !_sharedPayloadController.isClosed) {
          _sharedPayloadController.add(SharedIntentPayload(filePaths: paths));
        }
      }
    });
  }

  void _deliver(SharedIntentPayload payload) {
    if (_sharedPayloadController.isClosed) {
      return;
    }
    if (_sharedPayloadController.hasListener) {
      _sharedPayloadController.add(payload);
    } else {
      _undelivered.add(payload);
    }
  }

  void _flushUndelivered() {
    if (_undelivered.isEmpty) {
      return;
    }
    final pending = List<SharedIntentPayload>.of(_undelivered);
    _undelivered.clear();
    // Deferred so the new listener's subscription is fully set up first.
    scheduleMicrotask(() {
      for (final payload in pending) {
        _deliver(payload);
      }
    });
  }

  void _emitImporting(bool importing) {
    if (!_importingController.isClosed) {
      _importingController.add(importing);
    }
  }

  /// iOS only: the Share Extension's staging directory inside the shared App
  /// Group container, so it can be swept like any other transient temp/cache
  /// location instead of accumulating forever. Null on every other platform.
  Future<String?> getShareExtensionInboxPath() async {
    try {
      return await _channel.invokeMethod<String>('getShareExtensionInboxPath');
    } catch (_) {
      return null;
    }
  }

  Future<SharedIntentPayload> consumePendingSharedPayload() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'consumePendingSharedPayload',
      );
      final payload = _normalizePayload(result);
      if (payload.hasContent || payload.importing) {
        return payload;
      }
    } catch (_) {}

    // Backward compatibility for older native integrations.
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingSharedFiles',
      );
      return SharedIntentPayload(filePaths: _normalizeList(result));
    } catch (_) {
      return const SharedIntentPayload();
    }
  }

  SharedIntentPayload _normalizePayload(dynamic raw) {
    if (raw is List) {
      return SharedIntentPayload(filePaths: _normalizeList(raw));
    }
    if (raw is! Map) {
      return const SharedIntentPayload();
    }

    final files = _normalizeList(raw['files']);
    final texts = _normalizeList(raw['texts']);
    return SharedIntentPayload(
      filePaths: files,
      texts: texts,
      importing: raw['importing'] == true,
      failedCount: (raw['failed'] as num?)?.toInt() ?? 0,
    );
  }

  List<String> _normalizeList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final deduped = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isEmpty) {
        continue;
      }
      if (!seen.add(normalized)) {
        continue;
      }
      deduped.add(normalized);
    }
    return deduped;
  }

  Future<void> dispose() async {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
    }
    await _sharedPayloadController.close();
    await _importingController.close();
  }
}
