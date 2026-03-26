import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../security/local_tls_certificate_service.dart';

class TempShareClient {
  const TempShareClient({required this.ip, required this.connectedAt});
  final String ip;
  final DateTime connectedAt;
}

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
    required this.pin,
    required this.connectedClients,
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
  final String pin; // empty = no pin required
  final List<TempShareClient> connectedClients;

  String get url => running ? 'https://$host:$port/share/$token' : '';

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
    String? pin,
    List<TempShareClient>? connectedClients,
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
      pin: pin ?? this.pin,
      connectedClients: connectedClients ?? this.connectedClients,
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
        pin: '',
        connectedClients: [],
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
  TemporaryLinkShareService({LocalTlsCertificateService? tlsCertificateService})
    : _tlsCertificates =
          tlsCertificateService ?? LocalTlsCertificateService();

  final LocalTlsCertificateService _tlsCertificates;
  final _controller = StreamController<TemporaryLinkShareState>.broadcast();
  final _random = Random.secure();

  TemporaryLinkShareState _state = TemporaryLinkShareState.initial();
  HttpServer? _server;
  Timer? _expiryTimer;
  List<_SharedFileEntry> _entries = const [];
  String _pin = '';
  final Set<String> _validSessions = {};
  final List<TempShareClient> _connectedClientsList = [];

  Stream<TemporaryLinkShareState> get stateStream => _controller.stream;
  TemporaryLinkShareState get currentState => _state;

  static String generatePin() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$%&*';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> start({
    required List<String> filePaths,
    required String host,
    required String deviceName,
    required String platformLabel,
    required String idSuffix,
    Duration? ttl,
    String pin = '',
  }) async {
    await stop();

    _pin = pin.trim();
    _validSessions.clear();
    _connectedClientsList.clear();

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
        if (_pin.isNotEmpty) {
          final cookie = request.headers['cookie'] ?? '';
          if (!_isValidSession(cookie)) {
            return Response.ok(
              _renderPinGatePage(token: tokenParam),
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
        }
        _trackConnection(request);
        final html = _renderSharePage();
        return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
      })
      ..post('/share/<token>/verify', (Request request, String tokenParam) async {
        if (!_isAccessAllowed(tokenParam)) {
          return Response.forbidden('Invalid or expired link');
        }
        final body = await request.readAsString();
        final submittedPin = Uri.splitQueryString(body)['pin'] ?? '';
        if (!_constantTimeEquals(submittedPin, _pin)) {
          return Response.ok(
            _renderPinGatePage(token: tokenParam, error: true),
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        final sid = _createSession();
        return Response(
          302,
          headers: {
            'location': '/share/$tokenParam',
            'set-cookie':
                'dsid=$sid; Path=/share/$tokenParam; HttpOnly; Secure; SameSite=Strict',
          },
        );
      })
      ..get('/share/<token>/download/<id>', (Request request, String tokenParam, String id) async {
        if (!_isAccessAllowed(tokenParam)) {
          return Response.forbidden('Invalid or expired link');
        }
        if (_pin.isNotEmpty) {
          final cookie = request.headers['cookie'] ?? '';
          if (!_isValidSession(cookie)) {
            return Response.forbidden('Pin required');
          }
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

    final tlsContext = await _tlsCertificates.createServerContext(
      commonName: 'DropNet Temporary Link Server',
      subjectAlternativeNames: <String>[host],
    );

    _server = await shelf_io.serve(
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call),
      InternetAddress.anyIPv4,
      0,
      securityContext: tlsContext,
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
      pin: _pin,
      connectedClients: const [],
    );
    _emit();
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _server?.close(force: true);
    _server = null;
    _entries = const [];
    _pin = '';
    _validSessions.clear();
    _connectedClientsList.clear();
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
    return _state.running && _constantTimeEquals(tokenFromUrl, _state.token);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    var diff = 0;
    for (var index = 0; index < a.length; index++) {
      diff |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return diff == 0;
  }

  String _createSession() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    final sid = base64Url.encode(bytes);
    _validSessions.add(sid);
    return sid;
  }

  bool _isValidSession(String cookieHeader) {
    for (final segment in cookieHeader.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.startsWith('dsid=')) {
        return _validSessions.contains(trimmed.substring(5));
      }
    }
    return false;
  }

  void _trackConnection(Request request) {
    final connInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final ip = connInfo?.remoteAddress.address ?? 'Unknown';
    final alreadyTracked = _connectedClientsList.any(
      (c) =>
          c.ip == ip &&
          DateTime.now().difference(c.connectedAt).inSeconds < 30,
    );
    if (!alreadyTracked) {
      _connectedClientsList.add(
        TempShareClient(ip: ip, connectedAt: DateTime.now()),
      );
      _state = _state.copyWith(
        connectedClients: List.unmodifiable(_connectedClientsList),
      );
      _emit();
    }
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

  String _renderPinGatePage({required String token, bool error = false}) {
    final errorHtml = error
        ? '<p class="err">Incorrect PIN. Please try again.</p>'
        : '';
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>DropNet — PIN Required</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap');
    :root{--bg:#030712;--card:rgba(17,24,39,0.7);--border:rgba(255,255,255,0.08);--text:#f9fafb;--muted:#9ca3af;--accent:#2dd4bf;}
    *{box-sizing:border-box;}
    body{font-family:'Plus Jakarta Sans',sans-serif;margin:0;background-color:var(--bg);color:var(--text);min-height:100vh;display:flex;align-items:center;justify-content:center;}
    .card{background:var(--card);backdrop-filter:blur(20px);border-radius:28px;padding:40px;border:1px solid var(--border);box-shadow:0 25px 50px -12px rgba(0,0,0,.5);width:100%;max-width:400px;margin:24px;}
    h1{margin:0 0 8px;font-size:1.5rem;font-weight:800;letter-spacing:-0.03em;}
    .sub{color:var(--muted);margin:0 0 24px;font-size:.9rem;}
    label{display:block;font-size:.85rem;color:var(--muted);margin-bottom:8px;}
    input[type=password]{width:100%;background:rgba(255,255,255,.06);border:1px solid var(--border);border-radius:12px;padding:12px 16px;color:var(--text);font-size:1.1rem;font-family:inherit;outline:none;letter-spacing:.18em;}
    input:focus{border-color:var(--accent);}
    button{margin-top:16px;width:100%;background:var(--accent);color:#003d35;border:none;border-radius:12px;padding:13px;font-size:1rem;font-weight:700;font-family:inherit;cursor:pointer;transition:filter .2s;}
    button:hover{filter:brightness(1.1);}
    .lock{font-size:2.5rem;margin-bottom:16px;user-select:none;}
    .err{color:#f87171;margin-top:10px;font-size:.88rem;}
  </style>
</head>
<body>
  <div class="card">
    <div class="lock">🔒</div>
    <h1>PIN Required</h1>
    <p class="sub">This share is PIN-protected. Enter the PIN to access files.</p>
    <form method="POST" action="/share/$token/verify">
      <label for="pin">PIN</label>
      <input type="password" id="pin" name="pin" autocomplete="one-time-code" autofocus required />
      $errorHtml
      <button type="submit">Unlock</button>
    </form>
  </div>
</body>
</html>
''';
  }

  String _renderSharePage() {
    final escape = const HtmlEscape(HtmlEscapeMode.element);
    final suffix = _state.idSuffix.isEmpty ? '' : ' • ${escape.convert(_state.idSuffix)}';
    final expiryMs = _state.expiresAt?.millisecondsSinceEpoch;
    final expiryScript = expiryMs != null
        ? '<script>!function(){var e=$expiryMs,el=document.getElementById("exp");'
            'function t(){var r=Math.max(0,Math.round((e-Date.now())/1000)),m=Math.floor(r/60),s=r%60;'
            'if(el)el.textContent=m+":"+String(s).padStart(2,"0");if(r>0)setTimeout(t,1000);}t();}();</script>'
        : '';
    final expiryBadge = expiryMs != null
        ? '<span id="exp" style="font-size:.78rem;background:rgba(45,212,191,.12);color:var(--accent);'
            'padding:3px 10px;border-radius:999px;border:1px solid rgba(45,212,191,.25);margin-left:10px;">--:--</span>'
        : '';
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
    @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap');

    :root {
      --bg: #030712;
      --card: rgba(17, 24, 39, 0.7);
      --card-border: rgba(255, 255, 255, 0.08);
      --text: #f9fafb;
      --text-muted: #9ca3af;
      --accent: #2dd4bf;
      --accent-soft: rgba(45, 212, 191, 0.1);
      --radius-xl: 28px;
      --radius-lg: 18px;
      --radius-md: 12px;
      --ease: cubic-bezier(0.4, 0, 0.2, 1);
    }

    * { box-sizing: border-box; }

    body { 
      font-family: 'Plus Jakarta Sans', sans-serif; 
      margin: 0; 
      background-color: var(--bg);
      background-image: 
        radial-gradient(circle at 10% 20%, rgba(45, 212, 191, 0.05) 0%, transparent 40%),
        radial-gradient(circle at 90% 80%, rgba(99, 102, 241, 0.05) 0%, transparent 40%);
      background-attachment: fixed;
      color: var(--text); 
      line-height: 1.6;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .wrap { 
      width: 100%;
      max-width: 600px; 
      margin: 40px auto; 
      padding: 24px; 
      animation: slideUp 0.8s var(--ease);
    }

    @keyframes slideUp {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .card { 
      background: var(--card); 
      backdrop-filter: blur(20px) saturate(160%);
      -webkit-backdrop-filter: blur(20px) saturate(160%);
      border-radius: var(--radius-xl); 
      padding: 40px; 
      border: 1px solid var(--card-border); 
      box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
    }

    h1 { 
      margin: 0 0 4px 0; 
      font-size: 1.8rem; 
      font-weight: 800;
      letter-spacing: -0.04em;
      background: linear-gradient(to right, #fff, #9ca3af);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    h2 {
      font-size: 1.1rem;
      font-weight: 600;
      margin-top: 32px;
      margin-bottom: 16px;
      color: var(--text);
      display: flex;
      align-items: center;
      gap: 10px;
    }

    h2::before {
      content: '';
      width: 4px;
      height: 18px;
      background: var(--accent);
      border-radius: 4px;
      display: inline-block;
    }

    .meta { 
      color: var(--text-muted); 
      margin-bottom: 24px; 
      font-size: 0.95rem;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    /* File List Styling */
    ul { 
      padding: 0; 
      margin: 0; 
      list-style: none; 
    }

    li { 
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 16px 20px;
      margin-bottom: 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      transition: all 0.3s var(--ease);
    }

    li:hover {
      background: rgba(255, 255, 255, 0.05);
      border-color: var(--accent);
      transform: translateX(4px);
    }

    /* Container for the filename and size */
    li div.file-info {
      display: flex;
      flex-direction: column;
      gap: 2px;
      max-width: 60%;
    }

    /* Styling the dynamic span (size) */
    li span { 
      color: var(--text-muted); 
      font-size: 0.8rem; 
      font-weight: 500;
    }

    /* The Link transformed into a Download Button */
    li a { 
      background: var(--accent);
      color: #003d35;
      text-decoration: none; 
      padding: 8px 18px;
      border-radius: var(--radius-md);
      font-size: 0.85rem;
      font-weight: 700;
      transition: all 0.3s var(--ease);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 12px rgba(45, 212, 191, 0.2);
    }

    li a:hover { 
      transform: translateY(-2px);
      filter: brightness(1.1);
      box-shadow: 0 6px 18px rgba(45, 212, 191, 0.3);
      text-decoration: none;
    }

    /* Responsive Adjustments */
    @media (max-width: 640px) {
      .wrap { padding: 16px; }
      .card { padding: 24px; }
      li { flex-direction: column; align-items: flex-start; gap: 16px; }
      li a { width: 100%; }
      h1 { font-size: 1.5rem; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>${escape.convert(_state.deviceName)}</h1>
      <div class="meta">
        <span style="display:inline-block; width:8px; height:8px; background:var(--accent); border-radius:50%; box-shadow:0 0 10px var(--accent);"></span>
        ${escape.convert(_state.platformLabel)}$suffix$expiryBadge
      </div>
      
      <h2>Shared Files</h2>
      <ul>$filesHtml</ul>
    </div>
  </div>
  $expiryScript
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
