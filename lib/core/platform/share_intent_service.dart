import 'dart:async';

import 'package:flutter/services.dart';

class ShareIntentService {
  static const MethodChannel _channel = MethodChannel('dropnet/share_intent');

  final StreamController<List<String>> _sharedFilesController = StreamController<List<String>>.broadcast();

  bool _initialized = false;

  Stream<List<String>> get sharedFilesStream => _sharedFilesController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedFilesUpdated') {
        return;
      }
      final paths = _normalize(call.arguments);
      if (paths.isNotEmpty && !_sharedFilesController.isClosed) {
        _sharedFilesController.add(paths);
      }
    });
  }

  Future<List<String>> consumePendingSharedFiles() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('consumePendingSharedFiles');
      return _normalize(result);
    } catch (_) {
      return const <String>[];
    }
  }

  List<String> _normalize(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final deduped = <String>{};
    for (final value in raw) {
      final path = value?.toString().trim() ?? '';
      if (path.isNotEmpty) {
        deduped.add(path);
      }
    }
    return deduped.toList(growable: false);
  }

  Future<void> dispose() async {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
    }
    await _sharedFilesController.close();
  }
}
