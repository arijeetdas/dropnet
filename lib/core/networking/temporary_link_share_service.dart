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
import 'web_portal_kit.dart';

class TempShareClient {
  const TempShareClient({required this.ip, required this.connectedAt});
  final String ip;
  final DateTime connectedAt;
}

class TemporaryLinkShareState {
  const TemporaryLinkShareState({
    required this.running,
    required this.host,
    required this.hosts,
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
  /// Primary display host (first eligible adapter).
  final String host;
  /// All adapter IPs on which the server is reachable.
  final List<String> hosts;
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

  String get url => running && host.isNotEmpty ? 'https://$host:$port/' : '';
  List<String> get urls =>
      running ? hosts.map((h) => 'https://$h:$port/').toList(growable: false) : const [];

  TemporaryLinkShareState copyWith({
    bool? running,
    String? host,
    List<String>? hosts,
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
      hosts: hosts ?? this.hosts,
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
    hosts: [],
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
    : _tlsCertificates = tlsCertificateService ?? LocalTlsCertificateService();

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
      ..get('/', (Request request) async {
        if (!_isAccessAllowed()) {
          return Response.forbidden('Invalid or expired link');
        }
        final version = await WebPortalKit.versionName();
        if (_pin.isNotEmpty) {
          final cookie = request.headers['cookie'] ?? '';
          if (!_isValidSession(cookie)) {
            return Response.ok(
              _renderPinGatePage(version),
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
        }
        _trackConnection(request);
        final html = _renderSharePage(version);
        return Response.ok(
          html,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      })
      ..post('/verify', (Request request) async {
        if (!_isAccessAllowed()) {
          return Response.forbidden('Invalid or expired link');
        }
        final body = await request.readAsString();
        final submittedPin = Uri.splitQueryString(body)['pin'] ?? '';
        if (!_constantTimeEquals(submittedPin, _pin)) {
          return Response.ok(
            _renderPinGatePage(await WebPortalKit.versionName(), error: true),
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        final sid = _createSession();
        return Response(
          302,
          headers: {
            'location': '/',
            'set-cookie':
                'dsid=$sid; Path=/; HttpOnly; Secure; SameSite=Strict',
          },
        );
      })
      ..get('/download/<id>', (Request request, String id) async {
        if (!_isAccessAllowed()) {
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
            'content-disposition':
                'attachment; filename="${Uri.encodeComponent(entry.displayName)}"',
          },
        );
      })
      ..get('/share/<token>', (Request request, String tokenParam) {
        if (!_isAccessAllowed() || !_constantTimeEquals(tokenParam, token)) {
          return Response.forbidden('Invalid or expired link');
        }
        return Response.movedPermanently('/');
      })
      ..get(
        '${WebPortalKit.assetBase}/<file>',
        (Request request, String file) => WebPortalKit.serveAsset(file),
      );

    final tlsContext = await _tlsCertificates.createServerContext(
      commonName: 'DropNet Temporary Link Server',
      subjectAlternativeNames: _buildSans(host),
      purpose: TlsCertificatePurpose.webServer,
    );

    _server = await shelf_io.serve(
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call),
      InternetAddress.anyIPv4,
      0,
      securityContext: tlsContext,
      shared: true,
    );

    final allHosts = await _collectAllLocalIps(primary: host);
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
      host: allHosts.isNotEmpty ? allHosts.first : host,
      hosts: allHosts,
      port: _server!.port,
      token: token,
      deviceName: deviceName.trim().isEmpty
          ? 'DropNet Device'
          : deviceName.trim(),
      platformLabel: platformLabel.trim().isEmpty
          ? 'Unknown'
          : platformLabel.trim(),
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

  bool _isAccessAllowed() {
    return _state.running;
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

  /// Returns all eligible local IPv4 addresses, with [primary] first.
  Future<List<String>> _collectAllLocalIps({required String primary}) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final seen = <String>{};
    final result = <String>[];
    if (_isUsableIpv4(primary)) {
      seen.add(primary);
      result.add(primary);
    }
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final ip = address.address.trim();
        if (address.isLoopback || !_isUsableIpv4(ip) || seen.contains(ip)) {
          continue;
        }
        seen.add(ip);
        result.add(ip);
      }
    }
    if (result.isEmpty && primary.isNotEmpty) {
      result.add(primary);
    }
    return result;
  }

  List<String> _buildSans(String primary) {
    return <String>[
      if (_isUsableIpv4(primary)) primary,
      'localhost',
      '127.0.0.1',
    ];
  }

  bool _isUsableIpv4(String value) {
    if (value.isEmpty || value == '0.0.0.0') return false;
    final address = InternetAddress.tryParse(value);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final octets = address.rawAddress;
    if (octets[0] == 127) return false;
    if (octets[0] == 169 && octets[1] == 254) return false;
    return true;
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
          c.ip == ip && DateTime.now().difference(c.connectedAt).inSeconds < 30,
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
    final stem = ext.isEmpty
        ? name
        : name.substring(0, name.length - ext.length);
    return '$stem ($count)$ext';
  }

  String _renderPinGatePage(String version, {bool error = false}) {
    return WebPortalKit.renderPinGate(
      version: version,
      section: 'Temporary Share',
      action: '/verify',
      message: 'This share is PIN-protected. Enter the PIN to access the files.',
      error: error,
    );
  }

  String _renderSharePage(String version) {
    final esc = WebPortalKit.esc;
    final totalBytes = _entries.fold<int>(0, (sum, entry) => sum + entry.size);
    final startedMs = _state.startedAt?.millisecondsSinceEpoch;
    final expiryMs = _state.expiresAt?.millisecondsSinceEpoch;
    final suffixChip = _state.idSuffix.isEmpty
        ? ''
        : '<span class="dn-chip dn-chip--mono">${esc(_state.idSuffix)}</span>';
    final expiryStat = expiryMs != null
        ? '<div><dt>Expires in</dt><dd data-countdown data-expires-at="$expiryMs" '
              'data-started-at="${startedMs ?? ''}">--:--</dd></div>'
        : '<div><dt>Link</dt><dd>Active</dd></div>';
    final expiryBar = expiryMs != null
        ? '<div class="dn-expiry" aria-hidden="true"><span data-countdown-bar></span></div>'
        : '';
    final filesHtml = StringBuffer();
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      final name = esc(entry.displayName);
      final kind = WebPortalKit.fileKind(entry.displayName);
      filesHtml.write(
        '<li class="dn-file" style="--i:${index < 16 ? index : 16}">'
        '<span class="dn-file-icon kind-$kind">${WebPortalKit.fileIcon(kind)}</span>'
        '<span class="dn-file-copy">'
        '<span class="dn-file-name" title="$name">$name</span>'
        '<span class="dn-file-meta">${_fileTypeLabel(entry.displayName)} • ${_formatBytes(entry.size)}</span>'
        '</span>'
        '<a class="dn-btn dn-btn--tonal dn-btn--sm" href="/download/${entry.id}" data-download aria-label="Download $name">'
        '<span class="dn-dl">${WebPortalKit.downloadSvg}</span><span class="dn-check">${WebPortalKit.checkSvg}</span>'
        '<span class="dn-btn-label">Download</span></a>'
        '</li>',
      );
    }

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
${WebPortalKit.head(title: '${_state.deviceName} · DropNet Temporary Share', version: version)}
</head>
<body class="dn-page">
  ${WebPortalKit.backdrop}
  ${WebPortalKit.header(version: version, section: 'Temporary Share')}
  <main class="dn-main dn-share">
    <section class="dn-card dn-share-hero dn-rise">
      ${WebPortalKit.orb(version)}
      <p class="dn-eyebrow"><span class="dn-live-dot"></span>Shared with you</p>
      <h1 class="dn-title dn-title--xl">${esc(_state.deviceName)}</h1>
      <div class="dn-chips">
        <span class="dn-chip">${WebPortalKit.platformLogo(version)}${esc(_state.platformLabel)}</span>
        $suffixChip
      </div>
      <dl class="dn-stats">
        <div><dt>Files</dt><dd>${_entries.length}</dd></div>
        <div><dt>Size</dt><dd>${_formatBytes(totalBytes)}</dd></div>
        $expiryStat
      </dl>
      $expiryBar
      <p class="dn-note">${WebPortalKit.shieldSvg}<span>Files download straight from this device over your local network, encrypted with HTTPS.</span></p>
    </section>
    <section class="dn-card dn-share-files dn-rise" style="--d:1" aria-labelledby="filesHeading">
      <header class="dn-section-head">
        <h2 id="filesHeading">Shared files</h2>
        <span class="dn-count">${_entries.length}</span>
      </header>
      <ul class="dn-file-list">$filesHtml</ul>
    </section>
  </main>
  ${WebPortalKit.footer(version: version)}
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
    final fixed = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$fixed ${units[unitIndex]}';
  }

  String _fileTypeLabel(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext.isEmpty) {
      return 'File';
    }
    if ({'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif'}.contains(ext)) return 'Image';
    if ({'.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v', '.3gp'}.contains(ext)) return 'Video';
    if ({'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus'}.contains(ext)) return 'Audio';
    if ({'.pdf'}.contains(ext)) return 'PDF';
    if ({'.doc', '.docx', '.odt', '.rtf'}.contains(ext)) return 'Document';
    if ({'.xls', '.xlsx', '.csv', '.ods'}.contains(ext)) return 'Spreadsheet';
    if ({'.ppt', '.pptx', '.odp'}.contains(ext)) return 'Presentation';
    if ({'.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.ini', '.log'}.contains(ext)) return 'Text';
    if ({'.dart', '.js', '.ts', '.tsx', '.jsx', '.py', '.java', '.kt', '.cpp', '.c', '.h', '.hpp', '.cs', '.php', '.go', '.rs', '.swift', '.html', '.css', '.scss', '.sql', '.sh', '.bat', '.ps1'}.contains(ext)) return 'Code';
    if ({'.zip', '.rar', '.7z', '.tar', '.gz'}.contains(ext)) return 'Archive';
    return ext.substring(1).toUpperCase();
  }

  void _emit() {
    _controller.add(_state);
  }
}
