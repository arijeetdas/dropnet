import 'dart:async';

import 'package:flutter/services.dart';

class SharedIntentPayload {
  const SharedIntentPayload({
    this.filePaths = const <String>[],
    this.texts = const <String>[],
  });

  final List<String> filePaths;
  final List<String> texts;

  bool get isEmpty => filePaths.isEmpty && texts.isEmpty;
}

class ShareIntentService {
  static const MethodChannel _channel = MethodChannel('dropnet/share_intent');

  final StreamController<SharedIntentPayload> _sharedPayloadController =
      StreamController<SharedIntentPayload>.broadcast();

  bool _initialized = false;

  Stream<SharedIntentPayload> get sharedPayloadStream =>
      _sharedPayloadController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
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

  Future<SharedIntentPayload> consumePendingSharedPayload() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'consumePendingSharedPayload',
      );
      final payload = _normalizePayload(result);
      if (!payload.isEmpty) {
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
    return SharedIntentPayload(filePaths: files, texts: texts);
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
  }
}
