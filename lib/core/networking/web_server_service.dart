import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../models/transfer_model.dart';
import '../utils/file_utils.dart';

class WebPeer {
  const WebPeer({
    required this.id,
    required this.name,
    required this.ip,
    required this.connectedAt,
  });

  final String id;
  final String name;
  final String ip;
  final DateTime connectedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'connectedAt': connectedAt.toIso8601String(),
      };
}

class WebPeerConnectRequest {
  const WebPeerConnectRequest({
    required this.id,
    required this.name,
    required this.ip,
    required this.requestedAt,
  });

  final String id;
  final String name;
  final String ip;
  final DateTime requestedAt;
}

class WebIncomingUploadRequest {
  const WebIncomingUploadRequest({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.ip,
    required this.fileName,
    required this.size,
    required this.requestedAt,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String ip;
  final String fileName;
  final int size;
  final DateTime requestedAt;
}

class WebShareState {
  const WebShareState({
    required this.running,
    required this.host,
    required this.port,
    required this.token,
  });

  final bool running;
  final String host;
  final int port;
  final String token;

  String get url => running ? 'http://$host:$port/?token=$token' : '';

  WebShareState copyWith({
    bool? running,
    String? host,
    int? port,
    String? token,
  }) {
    return WebShareState(
      running: running ?? this.running,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
    );
  }

  static WebShareState initial() => const WebShareState(
        running: false,
        host: '',
        port: 8080,
        token: '',
      );
}

class _WebOutgoingSession {
  const _WebOutgoingSession({
    required this.id,
    required this.directory,
    required this.files,
    required this.pendingDecision,
    required this.active,
  });

  final String id;
  final String directory;
  final List<String> files;
  final bool pendingDecision;
  final bool active;

  _WebOutgoingSession copyWith({
    String? id,
    String? directory,
    List<String>? files,
    bool? pendingDecision,
    bool? active,
  }) {
    return _WebOutgoingSession(
      id: id ?? this.id,
      directory: directory ?? this.directory,
      files: files ?? this.files,
      pendingDecision: pendingDecision ?? this.pendingDecision,
      active: active ?? this.active,
    );
  }
}

class _PendingUploadPayload {
  const _PendingUploadPayload({
    required this.request,
    required this.tempPath,
    required this.decision,
  });

  final WebIncomingUploadRequest request;
  final String tempPath;
  final Completer<bool> decision;
}

class WebServerService {
  final _controller = StreamController<WebShareState>.broadcast();
  final _pendingPeerRequestsController = StreamController<List<WebPeerConnectRequest>>.broadcast();
  final _connectedPeersController = StreamController<List<WebPeer>>.broadcast();
  final _incomingUploadRequestsController = StreamController<List<WebIncomingUploadRequest>>.broadcast();
  final _historyController = StreamController<List<TransferHistoryEntry>>.broadcast();

  WebShareState _state = WebShareState.initial();
  HttpServer? _server;
  String _rootDirectory = '';
  String _hostDeviceName = 'DropNet Device';

  final Map<String, WebPeerConnectRequest> _pendingPeerRequests = {};
  final Map<String, Completer<bool>> _pendingPeerDecisions = {};
  final Map<String, WebPeer> _connectedPeers = {};
  final Map<String, _WebOutgoingSession> _outgoingSessionsByPeer = {};
  final Map<String, _PendingUploadPayload> _pendingIncomingUploads = {};
  final List<Map<String, dynamic>> _requestLogs = [];
  final List<TransferHistoryEntry> _history = [];

  Stream<WebShareState> get stateStream => _controller.stream;
  Stream<List<WebPeerConnectRequest>> get pendingPeerRequestsStream => _pendingPeerRequestsController.stream;
  Stream<List<WebPeer>> get connectedPeersStream => _connectedPeersController.stream;
  Stream<List<WebIncomingUploadRequest>> get incomingUploadRequestsStream => _incomingUploadRequestsController.stream;
  Stream<List<TransferHistoryEntry>> get historyStream => _historyController.stream;

  WebShareState get currentState => _state;

  Future<void> start({
    required String rootDirectory,
    required String hostDeviceName,
    int port = 8080,
  }) async {
    await stop();
    _rootDirectory = rootDirectory;
    _hostDeviceName = hostDeviceName.trim().isEmpty ? 'DropNet Device' : hostDeviceName.trim();

    final host = await _resolveLocalIp();
    final token = _generateToken();

    final router = Router()
      ..get('/', (Request request) async {
        if (!_isTokenValid(request.url.queryParameters['token'])) {
          return Response.forbidden('Invalid token');
        }
        final html = await rootBundle.loadString('assets/web/index.html');
        return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
      })
      ..get('/api/available-devices', (Request request) async {
        if (!_isTokenValid(request.url.queryParameters['token'])) {
          return Response.forbidden('Invalid token');
        }
        return Response.ok(
          jsonEncode({
            'devices': [
              {'id': 'host', 'name': _hostDeviceName, 'type': 'app'}
            ]
          }),
          headers: {'content-type': 'application/json'},
        );
      })
      ..post('/api/connect-request', (Request request) async {
        if (!_isTokenValid(request.url.queryParameters['token'])) {
          return Response.forbidden('Invalid token');
        }

        final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final targetDeviceId = payload['targetDeviceId']?.toString().trim() ?? '';
        if (targetDeviceId != 'host') {
          return Response.forbidden(jsonEncode({'connected': false, 'reason': 'invalid_target'}));
        }

        final requestedName = (payload['name']?.toString().trim().isNotEmpty ?? false) ? payload['name'].toString().trim() : 'Web Peer';
        final peerName = _normalizePeerName(requestedName);
        final ip = _remoteIp(request);

        final id = const Uuid().v4();
        final webRequest = WebPeerConnectRequest(
          id: id,
          name: peerName,
          ip: ip,
          requestedAt: DateTime.now(),
        );

        _pendingPeerRequests[id] = webRequest;
        final decision = Completer<bool>();
        _pendingPeerDecisions[id] = decision;
        _emitPendingPeerRequests();

        final accepted = await decision.future.timeout(const Duration(minutes: 2), onTimeout: () => false);
        _pendingPeerRequests.remove(id);
        _pendingPeerDecisions.remove(id);
        _emitPendingPeerRequests();

        if (!accepted) {
          return Response.forbidden(jsonEncode({'connected': false}));
        }

        final peer = WebPeer(id: id, name: peerName, ip: ip, connectedAt: DateTime.now());
        _connectedPeers[id] = peer;
        _emitConnectedPeers();
        return Response.ok(jsonEncode({'connected': true, 'peerId': id}), headers: {'content-type': 'application/json'});
      })
      ..get('/api/session', (Request request) async {
        final peerId = request.url.queryParameters['peerId'];
        if (!_isTokenValid(request.url.queryParameters['token']) || peerId == null || !_connectedPeers.containsKey(peerId)) {
          return Response.forbidden('Not connected');
        }
        return Response.ok(jsonEncode({'connected': true}), headers: {'content-type': 'application/json'});
      })
      ..get('/api/incoming-offer', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final session = _outgoingSessionsByPeer[peerId];
        if (session == null) {
          return Response.ok(jsonEncode({'hasOffer': false}), headers: {'content-type': 'application/json'});
        }
        if (session.files.isEmpty) {
          await _clearOutgoingSession(peerId);
          return Response.ok(jsonEncode({'hasOffer': false}), headers: {'content-type': 'application/json'});
        }
        return Response.ok(
          jsonEncode({
            'hasOffer': true,
            'offerId': session.id,
            'pendingDecision': session.pendingDecision,
            'active': session.active,
            'files': session.files,
          }),
          headers: {'content-type': 'application/json'},
        );
      })
      ..post('/api/incoming-offer/decision', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final offerId = payload['offerId']?.toString() ?? '';
        final accepted = payload['accepted'] == true;

        final session = _outgoingSessionsByPeer[peerId];
        if (session == null || session.id != offerId) {
          return Response.notFound('Offer not found');
        }

        if (!accepted) {
          await _clearOutgoingSession(peerId);
          return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
        }

        _outgoingSessionsByPeer[peerId] = session.copyWith(pendingDecision: false, active: true);
        return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
      })
      ..post('/api/end-session', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        await _clearOutgoingSession(peerId);
        return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
      })
      ..get('/api/files', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final session = _outgoingSessionsByPeer[peerId];
        if (session == null || !session.active || session.pendingDecision) {
          return Response.ok(jsonEncode({'files': <String>[]}), headers: {'content-type': 'application/json'});
        }
        return Response.ok(jsonEncode({'files': session.files}), headers: {'content-type': 'application/json'});
      })
      ..post('/api/upload', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final peer = _connectedPeers[peerId];
        if (peer == null) {
          return Response.forbidden('Not connected');
        }

        final fileName = request.url.queryParameters['name'];
        if (fileName == null || fileName.isEmpty) {
          return Response.badRequest(body: 'Missing name query parameter');
        }

        final bytes = await request.read().expand((chunk) => chunk).toList();
        final accepted = await _queueIncomingUpload(
          peer: peer,
          requestedName: fileName,
          bytes: bytes,
          kind: 'upload',
          fromIp: _remoteIp(request),
        );

        if (!accepted) {
          return Response.forbidden(jsonEncode({'ok': false, 'reason': 'rejected'}));
        }

        final digest = sha256.convert(bytes).toString();
        return Response.ok(jsonEncode({'ok': true, 'sha256': digest}), headers: {'content-type': 'application/json'});
      })
      ..post('/api/upload_text', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final peer = _connectedPeers[peerId];
        if (peer == null) {
          return Response.forbidden('Not connected');
        }

        final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final text = body['text']?.toString() ?? '';
        if (text.trim().isEmpty) {
          return Response.badRequest(body: 'Text is empty');
        }

        final name = body['name']?.toString().trim().isNotEmpty == true
            ? body['name'].toString().trim()
            : 'message_${DateTime.now().millisecondsSinceEpoch}.txt';
        final fileName = name.endsWith('.txt') ? name : '$name.txt';

        final accepted = await _queueIncomingUpload(
          peer: peer,
          requestedName: fileName,
          bytes: utf8.encode(text.trim()),
          kind: 'upload_text',
          fromIp: _remoteIp(request),
        );

        if (!accepted) {
          return Response.forbidden(jsonEncode({'ok': false, 'reason': 'rejected'}));
        }

        return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
      })
      ..get('/api/download', (Request request) async {
        if (!_isAuthorizedPeer(request)) {
          return Response.forbidden('Invalid token');
        }
        final peerId = request.url.queryParameters['peerId']!;
        final name = request.url.queryParameters['name'];
        if (name == null || name.isEmpty) {
          return Response.badRequest(body: 'Missing name query parameter');
        }

        final session = _outgoingSessionsByPeer[peerId];
        if (session == null || !session.active || !session.files.contains(name)) {
          return Response.notFound('Not found');
        }

        final peer = _connectedPeers[peerId];
        final peerName = peer?.name ?? 'Web Peer';

        final filePath = FileUtils.safeJoin(session.directory, name);
        final file = File(filePath);
        if (!await file.exists()) {
          return Response.notFound('Not found');
        }

        _appendRequestLog(
          kind: 'download',
          fileName: p.basename(filePath),
          size: await file.length(),
          from: _remoteIp(request),
          status: 'sent',
        );
        _appendHistory(
          fileName: p.basename(filePath),
          size: await file.length(),
          deviceName: peerName,
          direction: TransferDirection.sent,
          status: TransferStatus.completed,
          duration: const Duration(seconds: 1),
        );

        return Response.ok(
          file.openRead(),
          headers: {
            'content-type': 'application/octet-stream',
            'content-disposition': 'attachment; filename="${p.basename(filePath)}"',
          },
        );
      });

    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    _update(
      _state.copyWith(
        running: true,
        host: host,
        port: port,
        token: token,
      ),
    );
  }

  Future<void> stop() async {
    for (final completer in _pendingPeerDecisions.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }

    for (final upload in _pendingIncomingUploads.values) {
      if (!upload.decision.isCompleted) {
        upload.decision.complete(false);
      }
      final tempFile = File(upload.tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

    for (final peerId in _outgoingSessionsByPeer.keys.toList()) {
      await _clearOutgoingSession(peerId);
    }

    await _server?.close(force: true);
    _server = null;

    _pendingPeerRequests.clear();
    _pendingPeerDecisions.clear();
    _connectedPeers.clear();
    _pendingIncomingUploads.clear();
    _requestLogs.clear();

    _emitPendingPeerRequests();
    _emitConnectedPeers();
    _emitIncomingUploadRequests();
    _update(_state.copyWith(running: false, token: ''));
  }

  Future<int> offerFilesToPeers({required List<String> filePaths, required List<String> peerIds}) async {
    if (!_state.running) {
      return 0;
    }

    var copied = 0;
    final uniquePeers = peerIds.toSet();
    for (final peerId in uniquePeers) {
      if (!_connectedPeers.containsKey(peerId)) {
        continue;
      }

      await _clearOutgoingSession(peerId);

      final sessionId = const Uuid().v4();
      final sessionDir = Directory(FileUtils.safeJoin(_rootDirectory, 'web_sessions/$peerId/$sessionId'));
      await sessionDir.create(recursive: true);

      final names = <String>[];
      for (final sourcePath in filePaths) {
        final source = File(sourcePath);
        if (!await source.exists()) {
          continue;
        }
        final name = await _uniqueNameInDirectory(sessionDir.path, p.basename(sourcePath));
        final targetPath = FileUtils.safeJoin(sessionDir.path, name);
        await source.copy(targetPath);
        names.add(name);
        copied++;
      }

      if (names.isEmpty) {
        if (await sessionDir.exists()) {
          await sessionDir.delete(recursive: true);
        }
        continue;
      }

      _outgoingSessionsByPeer[peerId] = _WebOutgoingSession(
        id: sessionId,
        directory: sessionDir.path,
        files: names,
        pendingDecision: true,
        active: false,
      );
    }

    return copied;
  }

  bool _isAuthorizedPeer(Request request) {
    if (!_isTokenValid(request.url.queryParameters['token'])) {
      return false;
    }
    final peerId = request.url.queryParameters['peerId'];
    return peerId != null && _connectedPeers.containsKey(peerId);
  }

  bool _isTokenValid(String? candidate) {
    if (!_state.running || _state.token.isEmpty) {
      return false;
    }
    return candidate == _state.token;
  }

  void approvePeerRequest(String id) {
    final completer = _pendingPeerDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  void rejectPeerRequest(String id) {
    final completer = _pendingPeerDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  void approveIncomingUploadRequest(String id) {
    final payload = _pendingIncomingUploads[id];
    if (payload != null && !payload.decision.isCompleted) {
      payload.decision.complete(true);
    }
  }

  void rejectIncomingUploadRequest(String id) {
    final payload = _pendingIncomingUploads[id];
    if (payload != null && !payload.decision.isCompleted) {
      payload.decision.complete(false);
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    _historyController.add(const <TransferHistoryEntry>[]);
  }

  Future<void> removeHistoryEntry(TransferHistoryEntry target) async {
    final index = _history.indexWhere((entry) => _sameHistoryEntry(entry, target));
    if (index < 0) {
      return;
    }
    _history.removeAt(index);
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
  }

  Future<void> _clearOutgoingSession(String peerId) async {
    final session = _outgoingSessionsByPeer.remove(peerId);
    if (session == null) {
      return;
    }
    final dir = Directory(session.directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> _queueIncomingUpload({
    required WebPeer peer,
    required String requestedName,
    required List<int> bytes,
    required String kind,
    required String fromIp,
  }) async {
    final id = const Uuid().v4();
    final tempDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_web_pending');
    await tempDir.create(recursive: true);

    final safeBase = p.basename(requestedName.trim().isEmpty ? 'file_${DateTime.now().millisecondsSinceEpoch}' : requestedName);
    final tempPath = FileUtils.safeJoin(tempDir.path, '${id}_$safeBase');
    await File(tempPath).writeAsBytes(bytes);

    final request = WebIncomingUploadRequest(
      id: id,
      peerId: peer.id,
      peerName: peer.name,
      ip: peer.ip,
      fileName: safeBase,
      size: bytes.length,
      requestedAt: DateTime.now(),
    );

    final decision = Completer<bool>();
    _pendingIncomingUploads[id] = _PendingUploadPayload(request: request, tempPath: tempPath, decision: decision);
    _emitIncomingUploadRequests();

    final accepted = await decision.future.timeout(const Duration(minutes: 2), onTimeout: () => false);

    _pendingIncomingUploads.remove(id);
    _emitIncomingUploadRequests();

    final tempFile = File(tempPath);
    if (!accepted) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return false;
    }

    final targetDir = Directory(FileUtils.safeJoin(_rootDirectory, 'web_received/${peer.id}'));
    await targetDir.create(recursive: true);
    final uniqueName = await _uniqueNameInDirectory(targetDir.path, safeBase);
    final targetPath = FileUtils.safeJoin(targetDir.path, uniqueName);
    await tempFile.rename(targetPath);

    _appendRequestLog(
      kind: kind,
      fileName: uniqueName,
      size: bytes.length,
      from: fromIp,
      status: 'received',
    );
    _appendHistory(
      fileName: uniqueName,
      size: bytes.length,
      deviceName: peer.name,
      direction: TransferDirection.received,
      status: TransferStatus.completed,
      duration: DateTime.now().difference(request.requestedAt),
    );
    return true;
  }

  Future<String> _uniqueNameInDirectory(String directoryPath, String desiredName) async {
    final ext = p.extension(desiredName);
    final base = p.basenameWithoutExtension(desiredName);
    var candidate = desiredName;
    var i = 1;
    while (await File(FileUtils.safeJoin(directoryPath, candidate)).exists()) {
      candidate = '${base}_$i$ext';
      i++;
    }
    return candidate;
  }

  String _generateToken() {
    return base64Url.encode(utf8.encode(const Uuid().v4())).replaceAll('=', '').substring(0, 12);
  }

  Future<String> _resolveLocalIp() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (!address.isLoopback) {
          return address.address;
        }
      }
    }
    return '127.0.0.1';
  }

  void _update(WebShareState state) {
    _state = state;
    _controller.add(_state);
  }

  void _appendRequestLog({
    required String kind,
    required String fileName,
    required int size,
    required String from,
    required String status,
  }) {
    _requestLogs.insert(0, {
      'kind': kind,
      'fileName': fileName,
      'size': size,
      'from': from,
      'status': status,
      'at': DateTime.now().toIso8601String(),
    });
    if (_requestLogs.length > 100) {
      _requestLogs.removeLast();
    }
  }

  void _appendHistory({
    required String fileName,
    required int size,
    required String deviceName,
    required TransferDirection direction,
    required TransferStatus status,
    required Duration duration,
  }) {
    _history.insert(
      0,
      TransferHistoryEntry(
        fileName: fileName,
        size: size,
        date: DateTime.now(),
        deviceName: deviceName,
        status: status,
        duration: duration,
        direction: direction,
      ),
    );
    if (_history.length > 400) {
      _history.removeLast();
    }
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
  }

  bool _sameHistoryEntry(TransferHistoryEntry a, TransferHistoryEntry b) {
    return a.fileName == b.fileName &&
        a.size == b.size &&
        a.date == b.date &&
        a.deviceName == b.deviceName &&
        a.status == b.status &&
        a.duration == b.duration &&
        a.direction == b.direction;
  }

  String _remoteIp(Request request) {
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      return info.remoteAddress.address;
    }
    return 'unknown';
  }

  void _emitPendingPeerRequests() {
    _pendingPeerRequestsController.add(List<WebPeerConnectRequest>.unmodifiable(_pendingPeerRequests.values.toList()));
  }

  void _emitConnectedPeers() {
    _connectedPeersController.add(List<WebPeer>.unmodifiable(_connectedPeers.values.toList()));
  }

  void _emitIncomingUploadRequests() {
    _incomingUploadRequestsController.add(
      List<WebIncomingUploadRequest>.unmodifiable(_pendingIncomingUploads.values.map((item) => item.request).toList()),
    );
  }

  String _normalizePeerName(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return 'Web Peer';
    }

    final buildPattern = RegExp(r'Android\s[\d.]+;\s*([^;\)]+?)\s+Build\/', caseSensitive: false);
    final buildMatch = buildPattern.firstMatch(value);
    if (buildMatch != null) {
      final modelPart = (buildMatch.group(1) ?? '').trim();
      final token = _extractDeviceToken(modelPart);
      if (token.isNotEmpty) {
        return token;
      }
      if (modelPart.isNotEmpty) {
        return modelPart;
      }
    }

    return value;
  }

  String _extractDeviceToken(String raw) {
    final segments = raw.split(RegExp(r'[\s,_-]+')).where((part) => part.isNotEmpty);
    for (final part in segments) {
      if (RegExp(r'^[A-Za-z]\d{2,}[A-Za-z0-9]*$').hasMatch(part)) {
        return part;
      }
    }
    return '';
  }

  Future<void> dispose() async {
    await stop();
    await _historyController.close();
    await _incomingUploadRequestsController.close();
    await _pendingPeerRequestsController.close();
    await _connectedPeersController.close();
    await _controller.close();
  }
}
