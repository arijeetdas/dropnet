import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

class TemporaryLinkShareState {
  const TemporaryLinkShareState({
    required this.running,
    required this.host,
    required this.port,
    required this.token,
    required this.deviceName,
    required this.platformLabel,
    required this.idSuffix,
    required this.fileCount,
    required this.startedAt,
    required this.expiresAt,
  });

  final bool running;
  final String host;
  final int port;
  final String token;
  final String deviceName;
  final String platformLabel;
  final String idSuffix;
  final int fileCount;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  String get url => running ? 'http://$host:$port/share/$token' : '';

  TemporaryLinkShareState copyWith({
    bool? running,
    String? host,
    int? port,
    String? token,
    String? deviceName,
    String? platformLabel,
    String? idSuffix,
    int? fileCount,
    DateTime? startedAt,
    DateTime? expiresAt,
  }) {
    return TemporaryLinkShareState(
      running: running ?? this.running,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      deviceName: deviceName ?? this.deviceName,
      platformLabel: platformLabel ?? this.platformLabel,
      idSuffix: idSuffix ?? this.idSuffix,
      fileCount: fileCount ?? this.fileCount,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  static TemporaryLinkShareState initial() => const TemporaryLinkShareState(
        running: false,
        host: '',
        port: 0,
        token: '',
        deviceName: '',
        platformLabel: '',
        idSuffix: '',
        fileCount: 0,
        startedAt: null,
        expiresAt: null,
      );
}

class _SharedFileEntry {
  const _SharedFileEntry({
    required this.id,
    required this.path,
    required this.displayName,
    required this.size,
  });

  final String id;
  final String path;
  final String displayName;
  final int size;
}

class TemporaryLinkShareService {
  final _controller = StreamController<TemporaryLinkShareState>.broadcast();

  TemporaryLinkShareState _state = TemporaryLinkShareState.initial();
  HttpServer? _server;
  Timer? _expiryTimer;
  List<_SharedFileEntry> _entries = const [];

  Stream<TemporaryLinkShareState> get stateStream => _controller.stream;
  TemporaryLinkShareState get currentState => _state;

  Future<void> start({
    required List<String> filePaths,
    required String host,
    required String deviceName,
    required String platformLabel,
    required String idSuffix,
    Duration? ttl,
  }) async {
    await stop();

    final entries = await _prepareEntries(filePaths);
    if (entries.isEmpty) {
      throw StateError('No files available for temporary sharing.');
    }

    final token = const Uuid().v4().replaceAll('-', '');
    final router = Router()
      ..get('/share/<token>', (Request request, String tokenParam) async {
        if (!_isAccessAllowed(tokenParam)) {
          return Response.forbidden('Invalid or expired link');
        }
        final html = _renderSharePage();
        return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
      })
      ..get('/share/<token>/download/<id>', (Request request, String tokenParam, String id) async {
        if (!_isAccessAllowed(tokenParam)) {
          return Response.forbidden('Invalid or expired link');
        }

        final entry = _entries.where((item) => item.id == id).firstOrNull;
        if (entry == null) {
          return Response.notFound('File not found');
        }

        final file = File(entry.path);
        if (!await file.exists()) {
          return Response.notFound('File no longer available');
        }

        return Response.ok(
          file.openRead(),
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': entry.size.toString(),
            'content-disposition': 'attachment; filename="${Uri.encodeComponent(entry.displayName)}"',
          },
        );
      })
      ..get('/', (Request request) => Response.forbidden('Invalid or expired link'));

    _server = await shelf_io.serve(
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call),
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );

    final now = DateTime.now();
    final expiresAt = ttl == null ? null : now.add(ttl);

    if (ttl != null) {
      _expiryTimer = Timer(ttl, () {
        unawaited(stop());
      });
    }

    _entries = entries;
    _state = TemporaryLinkShareState(
      running: true,
      host: host,
      port: _server!.port,
      token: token,
      deviceName: deviceName.trim().isEmpty ? 'DropNet Device' : deviceName.trim(),
      platformLabel: platformLabel.trim().isEmpty ? 'Unknown' : platformLabel.trim(),
      idSuffix: idSuffix.trim(),
      fileCount: entries.length,
      startedAt: now,
      expiresAt: expiresAt,
    );
    _emit();
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _server?.close(force: true);
    _server = null;
    _entries = const [];
    if (_state.running) {
      _state = TemporaryLinkShareState.initial();
      _emit();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  bool _isAccessAllowed(String tokenFromUrl) {
    return _state.running && tokenFromUrl == _state.token;
  }

  Future<List<_SharedFileEntry>> _prepareEntries(List<String> filePaths) async {
    final uniquePaths = <String>{};
    final usedNames = <String, int>{};
    final entries = <_SharedFileEntry>[];

    for (final rawPath in filePaths) {
      final path = rawPath.trim();
      if (path.isEmpty || uniquePaths.contains(path)) {
        continue;
      }
      uniquePaths.add(path);

      final file = File(path);
      if (!await file.exists()) {
        continue;
      }

      final size = await file.length();
      final baseName = p.basename(path);
      final normalized = _dedupeName(baseName, usedNames);
      entries.add(
        _SharedFileEntry(
          id: const Uuid().v4().replaceAll('-', ''),
          path: path,
          displayName: normalized,
          size: size,
        ),
      );
    }

    return entries;
  }

  String _dedupeName(String name, Map<String, int> used) {
    final lower = name.toLowerCase();
    final count = (used[lower] ?? 0) + 1;
    used[lower] = count;
    if (count == 1) {
      return name;
    }

    final ext = p.extension(name);
    final stem = ext.isEmpty ? name : name.substring(0, name.length - ext.length);
    return '$stem ($count)$ext';
  }

  String _renderSharePage() {
    final escape = const HtmlEscape(HtmlEscapeMode.element);
    final suffix = _state.idSuffix.isEmpty ? '' : ' • ${escape.convert(_state.idSuffix)}';
    final filesHtml = _entries
        .map(
          (entry) =>
              '<li><a href="/share/${_state.token}/download/${entry.id}">${escape.convert(entry.displayName)}</a> '
              '<span>(${_formatBytes(entry.size)})</span></li>',
        )
        .join();

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>DropNet Temporary Share</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #0f172a; color: #e2e8f0; }
    .wrap { max-width: 760px; margin: 40px auto; padding: 24px; }
    .card { background: #111827; border-radius: 12px; padding: 20px; border: 1px solid #1f2937; }
    h1 { margin-top: 0; font-size: 1.4rem; }
    .meta { color: #94a3b8; margin-bottom: 18px; }
    ul { padding-left: 18px; }
    li { margin-bottom: 12px; }
    a { color: #93c5fd; text-decoration: none; }
    a:hover { text-decoration: underline; }
    span { color: #9ca3af; font-size: .9rem; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>${escape.convert(_state.deviceName)}</h1>
      <div class="meta">${escape.convert(_state.platformLabel)}$suffix</div>
      <h2>Shared Files</h2>
      <ul>$filesHtml</ul>
    </div>
  </div>
</body>
</html>
''';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fixed = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$fixed ${units[unitIndex]}';
  }

  void _emit() {
    _controller.add(_state);
  }
}
