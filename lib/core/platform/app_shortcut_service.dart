import 'dart:async';

import 'package:flutter/services.dart';

/// The two launcher/home-screen quick actions DropNet exposes on Android and
/// iOS: "Settings" and "History".
enum AppShortcutAction { settings, history }

AppShortcutAction? _shortcutActionFromId(String? id) {
  switch (id) {
    case 'settings':
      return AppShortcutAction.settings;
    case 'history':
      return AppShortcutAction.history;
    default:
      return null;
  }
}

/// Bridges native Android app-shortcut / iOS home-screen quick-action taps
/// into the Flutter navigation layer.
class AppShortcutService {
  static const MethodChannel _channel = MethodChannel('dropnet/app_shortcuts');

  final StreamController<AppShortcutAction> _shortcutController =
      StreamController<AppShortcutAction>.broadcast();

  bool _initialized = false;

  /// Fires when a shortcut is tapped while the app is already running.
  Stream<AppShortcutAction> get shortcutStream => _shortcutController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shortcutTapped') {
        final action = _shortcutActionFromId(call.arguments?.toString());
        if (action != null && !_shortcutController.isClosed) {
          _shortcutController.add(action);
        }
      }
    });
  }

  /// Consumes the shortcut (if any) that cold-launched the app.
  Future<AppShortcutAction?> consumePendingShortcut() async {
    try {
      final result = await _channel.invokeMethod<String>('consumePendingShortcut');
      return _shortcutActionFromId(result);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
    }
    await _shortcutController.close();
  }
}
