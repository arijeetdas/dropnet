import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/device_model.dart';
import '../../models/transfer_model.dart';
import '../encryption/aes_service.dart';
import '../security/local_tls_certificate_service.dart';
import '../utils/file_utils.dart';
import 'transfer_crypto_isolate.dart';

class TcpTransferService {
  TcpTransferService({
    AesService? aesService,
    LocalTlsCertificateService? tlsCertificateService,
  }) : _aes = aesService ?? AesService(),
       _tlsCertificates = tlsCertificateService ?? LocalTlsCertificateService();

  static const int defaultPort = 45455;
  static const int defaultChunkSize = 512 * 1024;
  static const int _chunkHashBytes = 32;
  static const Duration _sessionDecisionTtl = Duration(minutes: 12);
  static const String _tlsCertCommonName = 'DropNet Local';
  static const List<String> _tlsCertSans = <String>['localhost', '127.0.0.1'];

  /// Wire protocol version this app sends. v2 adds AES-GCM chunk framing (an
  /// isolate-computed authentication tag replaces the old per-chunk SHA-256),
  /// a trailer-carried whole-file checksum (computed incrementally instead of
  /// a redundant upfront file read), and receiver -> sender progress acks.
  /// The receiver still understands v1 (no `protocolVersion` field) for
  /// interop with a peer that hasn't updated yet.
  static const int _protocolVersion = 2;
  static const int _frameTagChunk = 0x01;
  static const int _frameTagTrailer = 0x02;
  static const int _flushEveryNChunks = 16;
  static const int _progressEmitIntervalMs = 150;

  /// How long the receiver lets an incoming-transfer request sit awaiting
  /// the user's accept/reject decision (see the `decisionCompleter.future`
  /// wait in `_handleIncomingSocket`). The sender must wait at least this
  /// long for the accept/reject response too — pairing and manual-connect
  /// requests already do (both wait `Duration(minutes: 2)`); the file
  /// transfer accept-wait previously waited only 60 seconds, which meant any
  /// response the user gave between 60s and 2 minutes arrived after the
  /// sender had already given up and marked the transfer failed, even
  /// though the receiver's own "Accept" tap had genuinely succeeded.
  static const Duration _incomingDecisionTimeout = Duration(minutes: 2);
  static const Duration _senderAcceptResponseTimeout = Duration(minutes: 2, seconds: 15);

  final AesService _aes;
  final LocalTlsCertificateService _tlsCertificates;
  final _uuid = const Uuid();
  final _activeController = StreamController<List<TransferModel>>.broadcast();
  final _completedController = StreamController<TransferModel>.broadcast();
  final _historyController =
      StreamController<List<TransferHistoryEntry>>.broadcast();
  final _incomingRequestsController =
      StreamController<List<IncomingTransferRequest>>.broadcast();
    final _incomingPairingRequestsController =
      StreamController<List<IncomingPairingRequest>>.broadcast();
    final _remoteUnpairNoticesController =
      StreamController<List<RemoteUnpairNotice>>.broadcast();
    final _remoteManualDisconnectNoticesController =
      StreamController<List<RemoteManualDisconnectNotice>>.broadcast();
  final _incomingManualConnectRequestsController =
      StreamController<List<IncomingManualConnectRequest>>.broadcast();
  final Map<String, TransferModel> _active = {};
  final List<TransferHistoryEntry> _history = [];
  final Map<String, IncomingTransferRequest> _incomingRequests = {};
  final Map<String, Completer<bool>> _incomingDecisions = {};
    final Map<String, IncomingPairingRequest> _incomingPairingRequests = {};
    final Map<String, Completer<bool>> _incomingPairingDecisions = {};
  final Map<String, IncomingManualConnectRequest> _incomingManualConnectRequests = {};
  final Map<String, Completer<bool>> _incomingManualConnectDecisions = {};
    final List<RemoteUnpairNotice> _remoteUnpairNotices = [];
    final List<RemoteManualDisconnectNotice> _remoteManualDisconnectNotices = [];
    final Map<String, SecureSocket> _activePairingSockets = {};
  final Map<String, ({bool accepted, DateTime at})> _sessionDecisions = {};
  final Set<String> _canceled = {};
  final Set<String> _canceledSessions = {};
  final Map<String, Socket> _activeReceiverSockets = {};
  final Set<String> _canceledByReceiver = {};

  String _localDeviceName = '';
  String _localDeviceId = '';
  String _localDevicePlatform = '';
  String _customDeviceIconName = '';
  String _localTlsCertificateSha256 = '';

  void setIdentity({
    required String name,
    required String id,
    required String platform,
    required String type,
    required String tls,
  }) {
    _localDeviceName = name;
    _localDeviceId = id;
    _localDevicePlatform = platform;
    _customDeviceIconName = type;
    _localTlsCertificateSha256 = tls;
  }

  Future<DeviceModel> checkDirectDevice(
    String ip,
    int port, {
    Duration connectTimeout = const Duration(seconds: 8),
    Duration responseTimeout = const Duration(seconds: 8),
  }) async {
    SecureSocket? socket;
    StreamIterator<String>? lineIterator;
    try {
      final rawSocket = await Socket.connect(
        ip,
        port,
        timeout: connectTimeout,
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      socket = await SecureSocket.secure(
        rawSocket,
        host: ip,
        onBadCertificate: (certificate) => true,
      );

      final peerFingerprint = _fingerprintFromCertificate(
        socket.peerCertificate,
      );

      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final header = {
        'kind': 'dropnet_info_request',
      };
      socket.add(utf8.encode('${jsonEncode(header)}\n'));
      await socket.flush();

      // Read response
      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: responseTimeout,
      );

      if (response['ok'] == true) {
        final typeStr = response['type']?.toString() ?? 'other';
        final deviceType = DeviceType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => DeviceType.other,
        );
        return DeviceModel(
          deviceId: response['id']?.toString() ?? 'manual_${DateTime.now().millisecondsSinceEpoch}',
          deviceName: response['name']?.toString() ?? 'Manual Peer',
          manufacturer: 'Direct IP Connection',
          platform: response['platform']?.toString() ?? 'other',
          ipAddress: ip,
          deviceType: deviceType,
          isOnline: true,
          lastSeen: DateTime.now(),
          tlsCertificateSha256: response['tls']?.toString() ?? peerFingerprint,
          port: port,
        );
      }
      throw Exception('Invalid response from target device.');
    } finally {
      await lineIterator?.cancel();
      await socket?.close();
    }
  }

  ServerSocket? _server;
  String? _saveDirectory;
  bool _categorizeFiles = true;
  int _chunkSize = defaultChunkSize;
  int _speedLimitBytesPerSec = 0;

  Stream<List<TransferModel>> get activeTransfersStream =>
      _activeController.stream;
  Stream<TransferModel> get completedTransfersStream =>
      _completedController.stream;
  Stream<List<TransferHistoryEntry>> get historyStream =>
      _historyController.stream;
  Stream<List<IncomingTransferRequest>> get incomingRequestsStream =>
      _incomingRequestsController.stream;
    Stream<List<IncomingPairingRequest>> get incomingPairingRequestsStream =>
      _incomingPairingRequestsController.stream;
    Stream<List<RemoteUnpairNotice>> get remoteUnpairNoticesStream =>
      _remoteUnpairNoticesController.stream;
    Stream<List<RemoteManualDisconnectNotice>> get remoteManualDisconnectNoticesStream =>
      _remoteManualDisconnectNoticesController.stream;
  Stream<List<IncomingManualConnectRequest>> get incomingManualConnectRequestsStream =>
      _incomingManualConnectRequestsController.stream;
  bool get isReceiverRunning => _server != null;

  void configure({int? chunkSize, int? speedLimitBytesPerSec}) {
    if (chunkSize != null && chunkSize > 1024) {
      _chunkSize = chunkSize;
    }
    if (speedLimitBytesPerSec != null && speedLimitBytesPerSec >= 0) {
      _speedLimitBytesPerSec = speedLimitBytesPerSec;
    }
  }

  Future<void> startReceiver({
    required String saveDirectory,
    int port = defaultPort,
    bool categorizeFiles = true,
  }) async {
    if (kDebugMode) {
      print('[TcpTransferService] startReceiver called on port $port');
    }
    if (_server != null) {
      if (kDebugMode) {
        print('[TcpTransferService] startReceiver aborted: server already active on ${_server!.port}');
      }
      return;
    }
    _saveDirectory = saveDirectory;
    _categorizeFiles = categorizeFiles;
    try {
      final tlsContext = await _tlsCertificates.createServerContext(
        commonName: _tlsCertCommonName,
        subjectAlternativeNames: _tlsCertSans,
      );
      if (kDebugMode) {
        print('[TcpTransferService] Binding ServerSocket on port $port');
      }
      ServerSocket? boundServer;
      int attempts = 0;
      while (attempts < 5) {
        try {
          boundServer = await ServerSocket.bind(
            InternetAddress.anyIPv4,
            port,
            shared: true,
          );
          break;
        } on SocketException catch (_) {
          attempts++;
          if (attempts >= 5) {
            rethrow;
          }
          await Future<void>.delayed(Duration(milliseconds: 200 * attempts));
        }
      }
      _server = boundServer;
      if (kDebugMode) {
        print('[TcpTransferService] TCP ServerSocket successfully bound on port ${_server!.port}');
      }
      _server!.listen((rawSocket) async {
        rawSocket.setOption(SocketOption.tcpNoDelay, true);
        try {
          final secureSocket = await SecureSocket.secureServer(
            rawSocket,
            tlsContext,
          );
          _handleIncomingSocket(secureSocket);
        } catch (e) {
          await rawSocket.close();
        }
      });
    } on SocketException catch (e) {
      _server = null;
      if (kDebugMode) {
        print('[TcpTransferService] SocketException in startReceiver on port $port: $e');
      }
      return;
    }
  }

  Future<void> stopReceiver() async {
    if (kDebugMode) {
      print('[TcpTransferService] stopReceiver called (server active: ${_server != null})');
    }
    await _server?.close();
    _server = null;
    if (kDebugMode) {
      print('[TcpTransferService] TCP ServerSocket closed');
    }
  }

  Future<void> sendFiles({
    required DeviceModel target,
    required List<String> filePaths,
    required String senderDeviceName,
    String senderDeviceId = '',
    String senderTlsCertificateSha256 = '',
    int port = defaultPort,
    String? pairingCode,
  }) async {
    final candidates = <String>[];
    var totalBytes = 0;
    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      candidates.add(path);
      totalBytes += await file.length();
    }
    if (candidates.isEmpty) {
      return;
    }

    final sessionId = _uuid.v4();
    for (var index = 0; index < candidates.length; index++) {
      // Stop sending remaining files if the session was cancelled
      if (_canceledSessions.contains(sessionId)) {
        break;
      }
      final path = candidates[index];
      final outcome = await _sendSingleFileWithRetry(
        target: target,
        filePath: path,
        port: port,
        senderDeviceName: senderDeviceName,
        senderDeviceId: senderDeviceId,
        senderTlsCertificateSha256: senderTlsCertificateSha256,
        sessionId: sessionId,
        sessionFileCount: candidates.length,
        sessionFileIndex: index,
        sessionTotalBytes: totalBytes,
        pairingCode: pairingCode,
      );
      // The receiver said no to this session. Its answer is remembered per
      // session on the receiving side, so offering the remaining files would
      // only produce a string of instant, prompt-less rejections.
      if (outcome == _SendOutcome.rejected) {
        break;
      }
    }
    _canceledSessions.remove(sessionId);
  }

  /// Optional hook the app layer uses to hand the sender the freshest
  /// discovery record for a target (current IP, port and advertised TLS
  /// fingerprint) right before every connection attempt. A long send session
  /// otherwise keeps using the snapshot taken when the user tapped Send, which
  /// goes stale if the receiver's address changes (DHCP renewal, MAC
  /// randomization, switching between Wi-Fi and Ethernet) mid-session.
  /// Returning null keeps the current target.
  DeviceModel? Function(DeviceModel target)? targetResolver;

  /// Snapshot of transfer requests currently awaiting a decision. The request
  /// stream is a broadcast stream without replay, so a listener attached after
  /// a request arrived uses this to catch up instead of never seeing it.
  List<IncomingTransferRequest> get pendingIncomingRequests =>
      List<IncomingTransferRequest>.unmodifiable(_incomingRequests.values);

  Future<({bool accepted, String peerFingerprint})> requestPairing({
    required DeviceModel target,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    required String pairingCode,
    int port = defaultPort,
  }) async {
    final normalizedCode = pairingCode.trim();
    if (normalizedCode.length != 6) {
      throw StateError('Pairing code must be 6 digits.');
    }

    final expectedPeerFingerprint = (target.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    SecureSocket? socket;
    StreamIterator<String>? lineIterator;
    try {
      final rawSocket = await Socket.connect(
        target.ipAddress,
        port,
        timeout: const Duration(seconds: 12),
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      socket = await SecureSocket.secure(
        rawSocket,
        host: target.ipAddress,
        onBadCertificate: (certificate) {
          if (expectedPeerFingerprint.isEmpty) {
            return true;
          }
          return _matchesExpectedCertificateFingerprint(
            certificate,
            expectedPeerFingerprint,
          );
        },
      );
      _activePairingSockets[target.deviceId] = socket;

      final peerFingerprint = _fingerprintFromCertificate(
        socket.peerCertificate,
      );
      if (peerFingerprint.isEmpty) {
        throw const HandshakeException(
          'Peer did not provide a TLS certificate fingerprint.',
        );
      }

      if (expectedPeerFingerprint.isNotEmpty &&
          !_constantTimeEquals(peerFingerprint, expectedPeerFingerprint)) {
        throw const HandshakeException('Peer certificate fingerprint mismatch.');
      }

      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final header = {
        'kind': 'dropnet_pairing_request',
        'requestId': _uuid.v4(),
        'fromDeviceName': senderDeviceName,
        'fromDeviceId': senderDeviceId.trim(),
        'fromTlsCertificateSha256':
            senderTlsCertificateSha256.trim().toLowerCase(),
        'pairingCode': normalizedCode,
      };
      socket.add(utf8.encode('${jsonEncode(header)}\n'));
      await socket.flush();

      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: const Duration(minutes: 2),
      );
      return (
        accepted: response['accepted'] as bool? ?? false,
        peerFingerprint: peerFingerprint,
      );
    } finally {
      _activePairingSockets.remove(target.deviceId);
      await lineIterator?.cancel();
      await socket?.close();
    }
  }

  Future<bool> requestManualConnect({
    required DeviceModel target,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    required String senderDevicePlatform,
    required String senderDeviceType,
    required int senderPort,
    int port = defaultPort,
  }) async {
    final expectedPeerFingerprint = (target.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    SecureSocket? socket;
    StreamIterator<String>? lineIterator;
    try {
      final rawSocket = await Socket.connect(
        target.ipAddress,
        port,
        timeout: const Duration(seconds: 12),
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      socket = await SecureSocket.secure(
        rawSocket,
        host: target.ipAddress,
        onBadCertificate: (certificate) {
          if (expectedPeerFingerprint.isEmpty) {
            return true;
          }
          return _matchesExpectedCertificateFingerprint(
            certificate,
            expectedPeerFingerprint,
          );
        },
      );

      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final header = {
        'kind': 'dropnet_manual_connect_request',
        'requestId': _uuid.v4(),
        'fromDeviceName': senderDeviceName,
        'fromDeviceId': senderDeviceId.trim(),
        'fromTlsCertificateSha256':
            senderTlsCertificateSha256.trim().toLowerCase(),
        'fromDevicePlatform': senderDevicePlatform,
        'fromDeviceType': senderDeviceType,
        'fromPort': senderPort,
      };
      socket.add(utf8.encode('${jsonEncode(header)}\n'));
      await socket.flush();

      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: const Duration(minutes: 2),
      );
      return response['accepted'] as bool? ?? false;
    } finally {
      await lineIterator?.cancel();
      await socket?.close();
    }
  }

  Future<void> requestManualDisconnect({
    required DeviceModel target,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    int port = defaultPort,
  }) async {
    final expectedPeerFingerprint = (target.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    SecureSocket? socket;
    try {
      final rawSocket = await Socket.connect(
        target.ipAddress,
        port,
        timeout: const Duration(seconds: 5),
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      if (expectedPeerFingerprint.isEmpty) {
        socket = await SecureSocket.secure(
          rawSocket,
          host: target.ipAddress,
          onBadCertificate: (cert) => true,
        );
      } else {
        socket = await SecureSocket.secure(
          rawSocket,
          host: target.ipAddress,
          onBadCertificate: (certificate) => _matchesExpectedCertificateFingerprint(
            certificate,
            expectedPeerFingerprint,
          ),
        );
      }

      final header = {
        'kind': 'dropnet_manual_disconnect_request',
        'requestId': _uuid.v4(),
        'fromDeviceName': senderDeviceName,
        'fromDeviceId': senderDeviceId.trim(),
        'fromTlsCertificateSha256': senderTlsCertificateSha256.trim().toLowerCase(),
      };
      socket.add(utf8.encode('${jsonEncode(header)}\n'));
      await socket.flush();
    } catch (_) {
      // Ignored since we are disconnecting anyway
    } finally {
      await socket?.close();
    }
  }

  Future<bool> requestUnpair({
    required DeviceModel target,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    int port = defaultPort,
  }) async {
    final expectedPeerFingerprint = (target.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    if (expectedPeerFingerprint.isEmpty) {
      throw const HandshakeException(
        'Target does not advertise a TLS certificate fingerprint.',
      );
    }

    SecureSocket? socket;
    StreamIterator<String>? lineIterator;
    try {
      final rawSocket = await Socket.connect(
        target.ipAddress,
        port,
        timeout: const Duration(seconds: 12),
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      socket = await SecureSocket.secure(
        rawSocket,
        host: target.ipAddress,
        onBadCertificate: (certificate) {
          return _matchesExpectedCertificateFingerprint(
            certificate,
            expectedPeerFingerprint,
          );
        },
      );

      if (!_matchesExpectedCertificateFingerprint(
        socket.peerCertificate,
        expectedPeerFingerprint,
      )) {
        throw const HandshakeException(
          'Peer certificate fingerprint mismatch.',
        );
      }

      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final header = {
        'kind': 'dropnet_unpair_request',
        'requestId': _uuid.v4(),
        'fromDeviceName': senderDeviceName,
        'fromDeviceId': senderDeviceId.trim(),
        'fromTlsCertificateSha256':
            senderTlsCertificateSha256.trim().toLowerCase(),
      };
      socket.add(utf8.encode('${jsonEncode(header)}\n'));
      await socket.flush();

      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: const Duration(seconds: 30),
      );
      return response['accepted'] as bool? ?? false;
    } finally {
      await lineIterator?.cancel();
      await socket?.close();
    }
  }

  Future<_SendOutcome> _sendSingleFileWithRetry({
    required DeviceModel target,
    required String filePath,
    required int port,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    required String sessionId,
    required int sessionFileCount,
    required int sessionFileIndex,
    required int sessionTotalBytes,
    String? pairingCode,
  }) async {
    const maxAttempts = 3;
    var currentTarget = target;
    var currentPort = port;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // Always connect using the freshest discovery data for this device.
      final resolved = _resolveTarget(currentTarget);
      if (resolved != null) {
        currentTarget = resolved;
        currentPort = resolved.port ?? currentPort;
      }
      final outcome = await _sendSingleFile(
        target: currentTarget,
        filePath: filePath,
        port: currentPort,
        senderDeviceName: senderDeviceName,
        senderDeviceId: senderDeviceId,
        senderTlsCertificateSha256: senderTlsCertificateSha256,
        sessionId: sessionId,
        sessionFileCount: sessionFileCount,
        sessionFileIndex: sessionFileIndex,
        sessionTotalBytes: sessionTotalBytes,
        attempt: attempt,
        maxAttempts: maxAttempts,
        pairingCode: pairingCode,
      );
      if (outcome != _SendOutcome.retry) {
        return outcome;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
    }
    return _SendOutcome.finished;
  }

  DeviceModel? _resolveTarget(DeviceModel target) {
    final resolver = targetResolver;
    if (resolver == null) {
      return null;
    }
    try {
      return resolver(target);
    } catch (_) {
      return null;
    }
  }

  Future<_SendOutcome> _sendSingleFile({
    required DeviceModel target,
    required String filePath,
    required int port,
    required String senderDeviceName,
    required String senderDeviceId,
    required String senderTlsCertificateSha256,
    required String sessionId,
    required int sessionFileCount,
    required int sessionFileIndex,
    required int sessionTotalBytes,
    required int attempt,
    required int maxAttempts,
    String? pairingCode,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _SendOutcome.finished;
    }

    // Set when the TLS handshake reached the certificate check and the
    // presented certificate was not the one discovery advertised. Lets the
    // error handler tell "wrong/changed identity" apart from an ordinary
    // network drop that merely happened during the handshake.
    var certificateMismatch = false;
    final transferId = _uuid.v4();
    final totalSize = await file.length();
    final startedAt = DateTime.now();
    _active[transferId] = TransferModel(
      id: transferId,
      fileName: p.basename(filePath),
      size: totalSize,
      progress: 0,
      speed: 0,
      status: TransferStatus.connecting,
      deviceName: target.deviceName,
      startedAt: startedAt,
      direction: TransferDirection.sent,
      localPath: filePath,
      sessionId: sessionId,
      sessionFileCount: sessionFileCount,
      sessionFileIndex: sessionFileIndex,
      sessionTotalBytes: sessionTotalBytes,
    );
    _emitActive();

    SecureSocket? socket;
    RandomAccessFile? reader;
    StreamIterator<String>? lineIterator;
    try {
      final expectedPeerFingerprint = (target.tlsCertificateSha256 ?? '')
          .trim()
          .toLowerCase();
      if (expectedPeerFingerprint.isEmpty) {
        throw const HandshakeException(
          'Target does not advertise a TLS certificate fingerprint.',
        );
      }

      final rawSocket = await Socket.connect(
        target.ipAddress,
        port,
        timeout: const Duration(seconds: 12),
      );
      rawSocket.setOption(SocketOption.tcpNoDelay, true);
      socket = await SecureSocket.secure(
        rawSocket,
        host: target.ipAddress,
        onBadCertificate: (certificate) {
          final matches = _matchesExpectedCertificateFingerprint(
            certificate,
            expectedPeerFingerprint,
          );
          if (!matches) {
            certificateMismatch = true;
          }
          return matches;
        },
      );

      if (!_matchesExpectedCertificateFingerprint(
        socket.peerCertificate,
        expectedPeerFingerprint,
      )) {
        certificateMismatch = true;
        throw const HandshakeException(
          'Peer certificate fingerprint mismatch.',
        );
      }

      reader = await file.open();
      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final sessionKey = _aes.generateSessionKey();
      final wrapped = _aes.wrapSessionKey(sessionKey);
      final normalizedSenderDeviceId = senderDeviceId.trim();
      final normalizedSenderFingerprint = senderTlsCertificateSha256
          .trim()
          .toLowerCase();
      final header = {
        'kind': 'dropnet_transfer',
        'transferId': transferId,
        'fileName': p.basename(file.path),
        'size': totalSize,
        'fromDeviceName': senderDeviceName,
        'fromDeviceId': normalizedSenderDeviceId,
        'fromTlsCertificateSha256': normalizedSenderFingerprint,
        'sessionId': sessionId,
        'sessionFileCount': sessionFileCount,
        'sessionFileIndex': sessionFileIndex,
        'sessionTotalBytes': sessionTotalBytes,
        'wrappedKey': wrapped['wrappedKey'],
        'wrappedIv': wrapped['wrappedIv'],
        // v2: checksum travels in a trailer frame after the last chunk
        // (computed incrementally during the send loop below) instead of
        // here, so the sender no longer has to read the whole file twice.
        'protocolVersion': _protocolVersion,
      };
      if (pairingCode != null) {
        header['pairingCode'] = pairingCode;
      }
      socket.add(utf8.encode('${jsonEncode(header)}\n'));

      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: _senderAcceptResponseTimeout,
      );
      final accepted = response['accepted'] as bool? ?? false;
      if (!accepted) {
        _updateTransfer(
          transferId,
          (t) => t.copyWith(
            status: TransferStatus.canceled,
            errorMessage: 'Rejected by receiver.',
          ),
        );
        _archiveTransfer(transferId);
        return _SendOutcome.rejected;
      }

      // Receiver -> sender messages keep arriving on this same line stream
      // for the rest of the connection: periodic {"kind":"progress_ack",...}
      // lines (consumed here to drive real-time, receiver-confirmed
      // progress) and finally either a plain {"ok":...} result or a
      // connection-closed/error signal, which completes [receiverResponse].
      final receiverResponse = Completer<Map<String, dynamic>>();
      var usingReceiverProgress = false;
      var lastAckBytes = 0;
      var lastAckTime = startedAt;
      final ackThrottle = _ProgressThrottle();
      unawaited(() async {
        try {
          while (await lineIterator!.moveNext()) {
            final line = lineIterator!.current;
            Map<String, dynamic> map;
            try {
              map = jsonDecode(line) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }
            if (map['kind'] == 'progress_ack') {
              final written = (map['written'] as num?)?.toInt() ?? 0;
              usingReceiverProgress = true;
              if (ackThrottle.due()) {
                final now = DateTime.now();
                final elapsedMs = now.difference(lastAckTime).inMilliseconds;
                final speed = elapsedMs > 0
                    ? (written - lastAckBytes) / (elapsedMs / 1000)
                    : 0.0;
                final remain = totalSize - written;
                final eta = speed > 0
                    ? Duration(seconds: (remain / speed).round())
                    : null;
                _updateTransfer(
                  transferId,
                  (t) => t.copyWith(
                    progress: totalSize == 0 ? 1 : written / totalSize,
                    speed: speed,
                    eta: eta,
                  ),
                );
                lastAckBytes = written;
                lastAckTime = now;
              }
              continue;
            }
            if (!receiverResponse.isCompleted) {
              receiverResponse.complete(map);
            }
            return;
          }
          if (!receiverResponse.isCompleted) {
            receiverResponse.complete({'ok': false, 'error': 'Connection closed by peer.'});
          }
        } catch (e) {
          if (!receiverResponse.isCompleted) {
            receiverResponse.complete({'ok': false, 'error': e.toString()});
          }
        }
      }());

      int sentBytes = 0;
      var sentSinceLastSample = 0;
      var speedSampleTime = DateTime.now();
      final sendThrottle = _ProgressThrottle();
      var chunksSent = 0;
      final hashSink = _IncrementalDigestSink();
      final hashInput = sha256.startChunkedConversion(hashSink);

      _updateTransfer(
        transferId,
        (t) => t.copyWith(status: TransferStatus.transferring),
      );

      // 1-chunk-ahead prefetch: kick off the next disk read while the
      // current chunk's encryption (on a worker isolate) and socket write
      // are still in flight, so disk I/O and crypto overlap.
      Future<Uint8List>? pendingRead = totalSize > 0
          ? reader.read(min(totalSize, _chunkSize))
          : null;

      while (sentBytes < totalSize && !_canceled.contains(transferId)) {
        if (receiverResponse.isCompleted) {
          final res = await receiverResponse.future;
          final err = res['error']?.toString() ?? 'cancelled_by_recipient';
          throw SocketException(err);
        }

        final plain = await pendingRead!;
        if (plain.isEmpty) {
          throw const FileSystemException(
            'Unexpected EOF while reading source file during transfer.',
          );
        }
        hashInput.add(plain);

        final nextRemain = totalSize - sentBytes - plain.length;
        pendingRead = nextRemain > 0
            ? reader.read(min(nextRemain, _chunkSize))
            : null;

        final iv = _aes.generateIvBytes();
        final chunkBody = await CryptoIsolatePool.instance.encryptCbcWithHash(
          plain: plain,
          key: sessionKey,
          iv: iv,
        );
        socket.add(_buildFrame(_frameTagChunk, chunkBody));

        sentBytes += plain.length;
        sentSinceLastSample += plain.length;
        chunksSent++;
        if (chunksSent % _flushEveryNChunks == 0) {
          await socket.flush();
        }

        // Local, buffer-based progress: only used as a fallback until the
        // first receiver-confirmed progress_ack arrives (see above), after
        // which the receiver's actual written-bytes count takes over so the
        // sender's display can't race ahead of what's really been received.
        if (!usingReceiverProgress && sendThrottle.due()) {
          final now = DateTime.now();
          final elapsedMs = now.difference(speedSampleTime).inMilliseconds;
          final speed = elapsedMs > 0 ? sentSinceLastSample / (elapsedMs / 1000) : 0.0;
          final remainBytes = totalSize - sentBytes;
          final eta = speed > 0
              ? Duration(seconds: (remainBytes / speed).round())
              : null;
          _updateTransfer(
            transferId,
            (t) => t.copyWith(
              progress: sentBytes / totalSize,
              speed: speed,
              eta: eta,
            ),
          );
          sentSinceLastSample = 0;
          speedSampleTime = now;
        }

        if (_speedLimitBytesPerSec > 0) {
          final waitMs = (plain.length / _speedLimitBytesPerSec * 1000).round();
          if (waitMs > 1) {
            await Future<void>.delayed(Duration(milliseconds: waitMs));
          }
        }
      }

      hashInput.close();
      final checksum = hashSink.digest.toString();
      final trailerBody = Uint8List.fromList(
        utf8.encode(jsonEncode({'sha256': checksum})),
      );
      socket.add(_buildFrame(_frameTagTrailer, trailerBody));

      await socket.flush();

      if (_canceled.remove(transferId)) {
        _updateTransfer(
          transferId,
          (t) => t.copyWith(
            status: TransferStatus.canceled,
            errorMessage: 'Canceled by sender.',
          ),
        );
      } else {
        final completion = await receiverResponse.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => {'ok': false, 'error': 'Timeout waiting for receiver confirmation.'},
        );
        final ok = completion['ok'] == true;
        if (!ok) {
          final reason = (completion['error']?.toString().trim() ?? 'Receiver reported transfer failure.');
          final isCancelled = reason.contains('cancelled_by_recipient') || completion['error'] == 'cancelled_by_recipient';
          final willRetry = !isCancelled && maxAttempts > attempt;
          _updateTransfer(
            transferId,
            (t) => t.copyWith(
              status: isCancelled ? TransferStatus.canceled : TransferStatus.failed,
              errorMessage: isCancelled
                  ? 'Cancelled by recipient.'
                  : (willRetry ? '$reason Retrying...' : reason),
            ),
          );
          _archiveTransfer(transferId);
          return willRetry ? _SendOutcome.retry : _SendOutcome.finished;
        }
        _updateTransfer(
          transferId,
          (t) => t.copyWith(
            progress: 1,
            status: TransferStatus.completed,
            sha256: checksum,
            verified: true,
            errorMessage: null,
          ),
        );
      }
      _archiveTransfer(transferId);
      return _SendOutcome.finished;
    } catch (error) {
      final isCancelled = error.toString().contains('cancelled_by_recipient');

      // A certificate mismatch is only worth retrying if discovery now has
      // different data for this device (it re-announced with a new address
      // or identity). Retrying with the same stale data would fail the same
      // way, so in that case surface the real cause instead.
      var identityRefreshed = false;
      if (certificateMismatch) {
        final fresh = _resolveTarget(target);
        if (fresh != null) {
          final freshFingerprint = (fresh.tlsCertificateSha256 ?? '')
              .trim()
              .toLowerCase();
          final staleFingerprint = (target.tlsCertificateSha256 ?? '')
              .trim()
              .toLowerCase();
          identityRefreshed =
              freshFingerprint.isNotEmpty &&
              (freshFingerprint != staleFingerprint ||
                  fresh.ipAddress != target.ipAddress);
        }
      }

      // TLS errors that are NOT a certificate mismatch are transport
      // failures that happened to occur during the handshake (Wi-Fi power
      // save, a router dropping an idle flow, the peer app being briefly
      // suspended). They are as transient as any other socket error.
      final transientTlsFailure =
          !certificateMismatch && error is TlsException;
      final retryable =
          !isCancelled &&
          (error is SocketException ||
              error is TimeoutException ||
              transientTlsFailure ||
              identityRefreshed ||
              (error is FileSystemException &&
                  error.message.contains('Unexpected EOF')));
      final willRetry = retryable && maxAttempts > attempt;

      final reason = certificateMismatch
          ? 'Security check failed: the device at ${target.ipAddress} did not '
                'present the identity DropNet discovered for '
                '${target.deviceName}. Wait for the device list to refresh and '
                'try again.'
          : transientTlsFailure
          ? 'The secure connection was interrupted by the network.'
          : _humanizeTransferError(error);
      _updateTransfer(
        transferId,
        (t) => t.copyWith(
          status: isCancelled ? TransferStatus.canceled : TransferStatus.failed,
          errorMessage: isCancelled
              ? 'Cancelled by recipient.'
              : (willRetry ? '$reason Retrying...' : reason),
        ),
      );
      _archiveTransfer(transferId);
      return willRetry ? _SendOutcome.retry : _SendOutcome.finished;
    } finally {
      await lineIterator?.cancel();
      await reader?.close();
      await socket?.close();
    }
  }

  void cancelTransfer(String transferId) {
    _canceled.add(transferId);
  }

  void cancelTransferSession(String sessionId) {
    _canceledSessions.add(sessionId);
  }

  Future<void> cancelTransferByReceiver(String transferId) async {
    _canceledByReceiver.add(transferId);
    final socket = _activeReceiverSockets.remove(transferId);
    if (socket != null) {
      try {
        socket.add(utf8.encode('${jsonEncode({'ok': false, 'error': 'cancelled_by_recipient'})}\n'));
        await socket.flush();
      } catch (_) {}
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  void _handleIncomingSocket(Socket socket) {
    String headerLine = '';
    bool headerParsed = false;
    String? requestId;
    _IncomingTransfer? transfer;
    bool transferFinalized = false;
    final accumulator = BytesBuilder(copy: false);
    int? expectedPayloadLen;
    // Defaults to legacy v1 (no `protocolVersion` field) for interop with a
    // sender that hasn't updated yet; set from the header once parsed.
    int protocolVersion = 1;
    final ackThrottle = _ProgressThrottle();
    late final StreamSubscription<List<int>> subscription;

    Future<void> abortInvalidFrame(String message) async {
      try {
        await transfer!.close();
        if (await transfer!.file.exists()) {
          await transfer!.file.delete();
        }
      } catch (_) {}
      _updateTransfer(
        transfer!.id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          errorMessage: message,
        ),
      );
      transferFinalized = true;
      _archiveTransfer(transfer!.id);
      await socket.close();
    }

    Future<void> abortCorruptChunk() async {
      try {
        await transfer!.close();
        if (await transfer!.file.exists()) {
          await transfer!.file.delete();
        }
      } catch (_) {}
      _updateTransfer(
        transfer!.id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          errorMessage: 'Corrupted chunk detected during transfer.',
        ),
      );
      socket.add(
        utf8.encode(
          '${jsonEncode({'ok': false, 'error': 'Corrupted chunk detected by receiver.'})}\n',
        ),
      );
      await socket.flush();
      transferFinalized = true;
      _archiveTransfer(transfer!.id);
      await socket.close();
    }

    Future<void> finalizeTransfer() async {
      await transfer!.close();
      final verified = await transfer!.verifySha();
      if (!verified) {
        try {
          if (await transfer!.file.exists()) {
            await transfer!.file.delete();
          }
        } catch (_) {}
        _updateTransfer(
          transfer!.id,
          (t) => t.copyWith(
            progress: 1,
            status: TransferStatus.failed,
            verified: false,
            sha256: transfer!.actualSha,
            errorMessage:
                'Checksum mismatch. File was deleted to prevent corrupted data.',
          ),
        );
        socket.add(
          utf8.encode(
            '${jsonEncode({'ok': false, 'error': 'Checksum mismatch. Receiver rejected corrupted file.'})}\n',
          ),
        );
        await socket.flush();
      } else {
        _updateTransfer(
          transfer!.id,
          (t) => t.copyWith(
            progress: 1,
            status: TransferStatus.completed,
            verified: true,
            sha256: transfer!.actualSha,
            errorMessage: null,
          ),
        );
        socket.add(utf8.encode('${jsonEncode({'ok': true})}\n'));
        await socket.flush();
      }
      transferFinalized = true;
      _archiveTransfer(transfer!.id);
      await socket.close();
    }

    subscription = socket.listen(
      (data) async {
        subscription.pause();
        try {
          accumulator.add(data);
          var buffer = accumulator.toBytes();
          accumulator.clear();

          while (buffer.isNotEmpty) {
            if (!headerParsed) {
              final nl = buffer.indexOf(10);
              if (nl < 0) {
                headerLine += utf8.decode(buffer, allowMalformed: true);
                buffer = Uint8List(0);
                continue;
              }
              headerLine += utf8.decode(
                buffer.sublist(0, nl),
                allowMalformed: true,
              );
              final remaining = buffer.sublist(nl + 1);
              buffer = remaining;

              Map<String, dynamic> header;
              try {
                header = jsonDecode(headerLine) as Map<String, dynamic>;
              } catch (_) {
                await socket.close();
                return;
              }
              final kind = (header['kind']?.toString() ?? '').trim();
              if (kind == 'dropnet_info_request') {
                transferFinalized = true;
                final response = {
                  'ok': true,
                  'name': _localDeviceName,
                  'id': _localDeviceId,
                  'platform': _localDevicePlatform,
                  'type': _customDeviceIconName,
                  'tls': _localTlsCertificateSha256,
                };
                try {
                  socket.add(utf8.encode('${jsonEncode(response)}\n'));
                  await socket.flush();
                } catch (_) {}
                try {
                  await socket.close();
                } catch (_) {}
                return;
              }
              if (kind == 'dropnet_pairing_request') {
                transferFinalized = true;
                await _handleIncomingPairingRequest(
                  socket: socket,
                  header: header,
                  subscription: subscription,
                );
                return;
              }
              if (kind == 'dropnet_unpair_request') {
                transferFinalized = true;
                await _handleIncomingUnpairRequest(socket: socket, header: header);
                return;
              }
              if (kind == 'dropnet_manual_disconnect_request') {
                transferFinalized = true;
                await _handleIncomingManualDisconnectRequest(socket: socket, header: header);
                return;
              }
              if (kind == 'dropnet_manual_connect_request') {
                transferFinalized = true;
                await _handleIncomingManualConnectRequest(
                  socket: socket,
                  header: header,
                  subscription: subscription,
                );
                return;
              }
              if (kind != 'dropnet_transfer') {
                await socket.close();
                return;
              }
              final fileName = FileUtils.sanitizeFileName(
                header['fileName'] as String? ?? 'incoming.bin',
              );
              final size = header['size'] as int? ?? 0;
              final wrappedKey = header['wrappedKey'] as String;
              final wrappedIv = header['wrappedIv'] as String;
              protocolVersion = (header['protocolVersion'] as num?)?.toInt() ?? 1;
              // v1 carries the checksum in the header; v2 sends it in a
              // trailer frame after the last chunk (set on transfer below).
              final checksum = protocolVersion >= 2 ? null : header['checksum'] as String?;
              final fromDeviceName =
                  header['fromDeviceName'] as String? ??
                  socket.remoteAddress.address;
                final fromDeviceId =
                  (header['fromDeviceId']?.toString() ?? '').trim();
                final advertisedSenderFingerprint =
                  (header['fromTlsCertificateSha256']?.toString() ?? '')
                    .trim()
                    .toLowerCase();
                final peerCertificateFingerprint =
                  socket is SecureSocket
                  ? _fingerprintFromCertificate(socket.peerCertificate)
                  : '';
                if (advertisedSenderFingerprint.isNotEmpty &&
                  peerCertificateFingerprint.isNotEmpty &&
                  !_constantTimeEquals(
                  advertisedSenderFingerprint,
                  peerCertificateFingerprint,
                  )) {
                socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
                await socket.flush();
                await socket.close();
                return;
                }
                final effectiveSenderFingerprint =
                  advertisedSenderFingerprint.isNotEmpty
                  ? advertisedSenderFingerprint
                  : peerCertificateFingerprint;
              final sessionId = (header['sessionId']?.toString() ?? '').trim();
              final sessionFileCount = (header['sessionFileCount'] as num?)
                  ?.toInt();
              final sessionFileIndex = (header['sessionFileIndex'] as num?)
                  ?.toInt();
              final sessionTotalBytes = (header['sessionTotalBytes'] as num?)
                  ?.toInt();
              final pairingCode = header['pairingCode'] as String?;
              final sessionKey = _aes.unwrapSessionKey(
                wrappedKey: wrappedKey,
                wrappedIv: wrappedIv,
              );
              final transferId = header['transferId'] as String? ?? _uuid.v4();
              requestId = transferId;

              final decisionKey = _sessionDecisionKey(
                fromAddress: socket.remoteAddress.address,
                fromDeviceName: fromDeviceName,
                fromDeviceId: fromDeviceId,
                sessionId: sessionId,
              );

              bool accepted;
              // Only a decision the user (or an auto-accept policy) actually
              // made is remembered for the rest of the session. A request
              // that simply expired — the app was in the background, the
              // dialog never got a chance to show — must not silently
              // auto-reject every later file of the same session.
              var decidedExplicitly = true;
              final remembered = _readSessionDecision(decisionKey);
              if (remembered != null) {
                accepted = remembered;
              } else {
                final request = IncomingTransferRequest(
                  id: transferId,
                  fileName: fileName,
                  size: size,
                  fromAddress: socket.remoteAddress.address,
                  fromDeviceName: fromDeviceName,
                  requestedAt: DateTime.now(),
                    fromDeviceId: fromDeviceId.isEmpty ? null : fromDeviceId,
                    fromTlsCertificateSha256: effectiveSenderFingerprint.isEmpty
                      ? null
                      : effectiveSenderFingerprint,
                  batchId: sessionId.isEmpty ? null : sessionId,
                  batchFileCount: sessionFileCount,
                  batchIndex: sessionFileIndex,
                  batchTotalBytes: sessionTotalBytes,
                  pairingCode: pairingCode,
                );
                _incomingRequests[transferId] = request;
                final decisionCompleter = Completer<bool>();
                _incomingDecisions[transferId] = decisionCompleter;
                _emitIncomingRequests();

                accepted = await decisionCompleter.future.timeout(
                  _incomingDecisionTimeout,
                  onTimeout: () {
                    decidedExplicitly = false;
                    return false;
                  },
                );
                _incomingDecisions.remove(transferId);
                _incomingRequests.remove(transferId);
                _emitIncomingRequests();
              }

              if (sessionId.isNotEmpty && decidedExplicitly) {
                _rememberSessionDecision(decisionKey, accepted);
              }

              socket.add(
                utf8.encode('${jsonEncode({'accepted': accepted})}\n'),
              );
              if (!accepted) {
                await socket.close();
                return;
              }
              _activeReceiverSockets[transferId] = socket;

              final saveDir = _saveDirectory;
              if (saveDir == null || saveDir.isEmpty) {
                socket.destroy();
                return;
              }
              final savePath = FileUtils.resolveReceivedFileSavePath(
                saveDir: saveDir,
                fileName: fileName,
                categorize: _categorizeFiles,
              );
              final outFile = File(savePath);
              transfer = await _IncomingTransfer.create(
                id: transferId,
                file: outFile,
                originalFileName: fileName,
                expectedSize: size,
                sessionKey: sessionKey,
                expectedSha: checksum,
              );
              _active[transfer!.id] = TransferModel(
                id: transfer!.id,
                fileName: transfer!.originalFileName,
                size: transfer!.expectedSize,
                progress: 0,
                speed: 0,
                status: TransferStatus.transferring,
                deviceName: fromDeviceName,
                startedAt: DateTime.now(),
                direction: TransferDirection.received,
                localPath: transfer!.file.path,
                sessionId: sessionId.isEmpty ? null : sessionId,
                sessionFileCount: sessionFileCount,
                sessionFileIndex: sessionFileIndex,
                sessionTotalBytes: sessionTotalBytes,
              );
              _emitActive();
              headerParsed = true;
              expectedPayloadLen = null;
            } else {
              if (expectedPayloadLen == null) {
                if (buffer.length < 4) {
                  accumulator.add(buffer);
                  buffer = Uint8List(0);
                  continue;
                }
                expectedPayloadLen = ByteData.sublistView(
                  buffer,
                  0,
                  4,
                ).getUint32(0, Endian.big);
                buffer = buffer.sublist(4);
              }

              if (buffer.length < expectedPayloadLen!) {
                final lengthPrefix = ByteData(4)
                  ..setUint32(0, expectedPayloadLen!, Endian.big);
                accumulator.add(lengthPrefix.buffer.asUint8List());
                accumulator.add(buffer);
                buffer = Uint8List(0);
                expectedPayloadLen = null;
                continue;
              }

              final payload = buffer.sublist(0, expectedPayloadLen);
              buffer = buffer.sublist(expectedPayloadLen!);
              expectedPayloadLen = null;

              if (transfer == null) {
                await socket.close();
                break;
              }

              if (protocolVersion >= 2) {
                if (payload.isEmpty) {
                  await abortInvalidFrame('Invalid payload frame received.');
                  break;
                }
                final tag = payload[0];
                if (tag == _frameTagTrailer) {
                  Map<String, dynamic> trailer;
                  try {
                    trailer = jsonDecode(utf8.decode(payload.sublist(1))) as Map<String, dynamic>;
                  } catch (_) {
                    await abortInvalidFrame('Invalid trailer frame received.');
                    break;
                  }
                  if (transfer!.writtenBytes != transfer!.expectedSize) {
                    await abortInvalidFrame(
                      'Transfer ended before all data was received.',
                    );
                    break;
                  }
                  transfer!.expectedSha = trailer['sha256'] as String?;
                  await finalizeTransfer();
                  break;
                }
                if (tag != _frameTagChunk || payload.length < 1 + 16 + _chunkHashBytes + 1) {
                  await abortInvalidFrame('Invalid payload frame received.');
                  break;
                }
                final iv = Uint8List.fromList(payload.sublist(1, 17));
                final expectedHash = Uint8List.fromList(
                  payload.sublist(17, 17 + _chunkHashBytes),
                );
                final cipher = Uint8List.fromList(
                  payload.sublist(17 + _chunkHashBytes),
                );
                Uint8List plain;
                try {
                  plain = await CryptoIsolatePool.instance.decryptCbcAndVerify(
                    cipher: cipher,
                    key: transfer!.sessionKey,
                    iv: iv,
                    expectedHash: expectedHash,
                  );
                } on GcmAuthenticationException {
                  await abortCorruptChunk();
                  break;
                }

                await transfer!.write(plain);
                if (ackThrottle.due()) {
                  _updateTransfer(
                    transfer!.id,
                    (t) => t.copyWith(
                      progress: t.size == 0 ? 0 : transfer!.writtenBytes / t.size,
                      speed: transfer!.speedBytesPerSec,
                      eta: transfer!.eta,
                    ),
                  );
                  socket.add(utf8.encode('${jsonEncode({
                    'kind': 'progress_ack',
                    'transferId': transfer!.id,
                    'written': transfer!.writtenBytes,
                  })}\n'));
                }
                continue;
              }

              // ── Legacy v1: AES-CBC chunk with a separate plaintext SHA-256 ──
              if (payload.length < (16 + _chunkHashBytes + 1)) {
                await abortInvalidFrame('Invalid payload frame received.');
                break;
              }

              final iv = Uint8List.fromList(payload.sublist(0, 16));
              final expectedPlainHash = Uint8List.fromList(
                payload.sublist(16, 16 + _chunkHashBytes),
              );
              final cipher = Uint8List.fromList(
                payload.sublist(16 + _chunkHashBytes),
              );
              Uint8List plain;
              try {
                plain = await CryptoIsolatePool.instance.decryptCbcAndVerify(
                  cipher: cipher,
                  key: transfer!.sessionKey,
                  iv: iv,
                  expectedHash: expectedPlainHash,
                );
              } on GcmAuthenticationException {
                await abortCorruptChunk();
                break;
              }

              await transfer!.write(plain);
              _updateTransfer(
                transfer!.id,
                (t) => t.copyWith(
                  progress: t.size == 0 ? 0 : transfer!.writtenBytes / t.size,
                  speed: transfer!.speedBytesPerSec,
                  eta: transfer!.eta,
                ),
              );

              if (transfer!.writtenBytes >= transfer!.expectedSize) {
                await finalizeTransfer();
                break;
              }
            }
          }
        } finally {
          if (!transferFinalized) {
            subscription.resume();
          }
        }
      },
      onDone: () async {
        if (transferFinalized) {
          return;
        }
        if (!headerParsed && requestId != null) {
          _rejectPendingDecision(requestId!);
        }
        if (transfer != null) {
          await transfer!.close();
          try {
            if (await transfer!.file.exists()) {
              await transfer!.file.delete();
            }
          } catch (_) {}
          final isByReceiver = _canceledByReceiver.remove(transfer!.id);
          _updateTransfer(
            transfer!.id,
            (t) => t.copyWith(
              status: isByReceiver ? TransferStatus.canceled : TransferStatus.failed,
              errorMessage: isByReceiver
                  ? 'Cancelled by recipient.'
                  : 'Connection closed before transfer completed.',
            ),
          );
          transferFinalized = true;
          _archiveTransfer(transfer!.id);
        }
      },
      onError: (error) async {
        if (transferFinalized) {
          return;
        }
        if (!headerParsed && requestId != null) {
          _rejectPendingDecision(requestId!);
        }
        if (transfer != null) {
          await transfer!.close();
          try {
            if (await transfer!.file.exists()) {
              await transfer!.file.delete();
            }
          } catch (_) {}
          final isByReceiver = _canceledByReceiver.remove(transfer!.id);
          _updateTransfer(
            transfer!.id,
            (t) => t.copyWith(
              status: isByReceiver ? TransferStatus.canceled : TransferStatus.failed,
              errorMessage: isByReceiver
                  ? 'Cancelled by recipient.'
                  : _humanizeTransferError(error),
            ),
          );
          transferFinalized = true;
          _archiveTransfer(transfer!.id);
        }
      },
    );
  }

  Future<void> _handleIncomingPairingRequest({
    required Socket socket,
    required Map<String, dynamic> header,
    required StreamSubscription<List<int>> subscription,
  }) async {
    final requestId = (header['requestId']?.toString() ?? '').trim().isEmpty
        ? _uuid.v4()
        : (header['requestId']?.toString() ?? '').trim();
    final fromDeviceName =
        (header['fromDeviceName']?.toString() ?? '').trim().isEmpty
        ? socket.remoteAddress.address
        : (header['fromDeviceName']?.toString() ?? '').trim();
    final fromDeviceId = (header['fromDeviceId']?.toString() ?? '').trim();
    final pairingCode = (header['pairingCode']?.toString() ?? '').trim();
    final advertisedSenderFingerprint =
        (header['fromTlsCertificateSha256']?.toString() ?? '')
            .trim()
            .toLowerCase();
    final peerCertificateFingerprint = socket is SecureSocket
        ? _fingerprintFromCertificate(socket.peerCertificate)
        : '';

    if (advertisedSenderFingerprint.isNotEmpty &&
        peerCertificateFingerprint.isNotEmpty &&
        !_constantTimeEquals(
          advertisedSenderFingerprint,
          peerCertificateFingerprint,
        )) {
      try {
        socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
        await socket.flush();
        await socket.close();
      } catch (_) {}
      return;
    }

    final effectiveSenderFingerprint = advertisedSenderFingerprint.isNotEmpty
        ? advertisedSenderFingerprint
        : peerCertificateFingerprint;

    if (fromDeviceId.isEmpty ||
        effectiveSenderFingerprint.isEmpty ||
        pairingCode.length != 6) {
      try {
        socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
        await socket.flush();
        await socket.close();
      } catch (_) {}
      return;
    }

    final request = IncomingPairingRequest(
      id: requestId,
      fromAddress: socket.remoteAddress.address,
      fromDeviceName: fromDeviceName,
      fromDeviceId: fromDeviceId,
      fromTlsCertificateSha256: effectiveSenderFingerprint,
      pairingCode: pairingCode,
      requestedAt: DateTime.now(),
    );
    _incomingPairingRequests[requestId] = request;
    final decisionCompleter = Completer<bool>();
    _incomingPairingDecisions[requestId] = decisionCompleter;
    _emitIncomingPairingRequests();

    // Listen for socket closure (cancellation) or error
    subscription.onData((_) {});
    subscription.onDone(() {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    });
    subscription.onError((_) {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    });
    subscription.resume();

    unawaited(socket.done.then((_) {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    }).catchError((_) {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    }));

    final accepted = await decisionCompleter.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
    _incomingPairingDecisions.remove(requestId);
    _incomingPairingRequests.remove(requestId);
    _emitIncomingPairingRequests();

    try {
      await subscription.cancel();
    } catch (_) {}

    try {
      socket.add(utf8.encode('${jsonEncode({'accepted': accepted})}\n'));
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }

  Future<void> _handleIncomingUnpairRequest({
    required Socket socket,
    required Map<String, dynamic> header,
  }) async {
    final requestId = (header['requestId']?.toString() ?? '').trim().isEmpty
        ? _uuid.v4()
        : (header['requestId']?.toString() ?? '').trim();
    final fromDeviceName =
        (header['fromDeviceName']?.toString() ?? '').trim().isEmpty
        ? socket.remoteAddress.address
        : (header['fromDeviceName']?.toString() ?? '').trim();
    final fromDeviceId = (header['fromDeviceId']?.toString() ?? '').trim();
    final advertisedSenderFingerprint =
        (header['fromTlsCertificateSha256']?.toString() ?? '')
            .trim()
            .toLowerCase();
    final peerCertificateFingerprint = socket is SecureSocket
        ? _fingerprintFromCertificate(socket.peerCertificate)
        : '';

    if (advertisedSenderFingerprint.isNotEmpty &&
        peerCertificateFingerprint.isNotEmpty &&
        !_constantTimeEquals(
          advertisedSenderFingerprint,
          peerCertificateFingerprint,
        )) {
      socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
      await socket.flush();
      await socket.close();
      return;
    }

    final effectiveSenderFingerprint = advertisedSenderFingerprint.isNotEmpty
        ? advertisedSenderFingerprint
        : peerCertificateFingerprint;

    if (fromDeviceId.isEmpty || effectiveSenderFingerprint.isEmpty) {
      socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
      await socket.flush();
      await socket.close();
      return;
    }

    _remoteUnpairNotices.insert(
      0,
      RemoteUnpairNotice(
        id: requestId,
        fromAddress: socket.remoteAddress.address,
        fromDeviceName: fromDeviceName,
        fromDeviceId: fromDeviceId,
        fromTlsCertificateSha256: effectiveSenderFingerprint,
        notifiedAt: DateTime.now(),
      ),
    );
    if (_remoteUnpairNotices.length > 64) {
      _remoteUnpairNotices.removeRange(64, _remoteUnpairNotices.length);
    }
    _emitRemoteUnpairNotices();

    socket.add(utf8.encode('${jsonEncode({'accepted': true})}\n'));
    await socket.flush();
    await socket.close();
  }

  Future<void> _handleIncomingManualDisconnectRequest({
    required Socket socket,
    required Map<String, dynamic> header,
  }) async {
    final requestId = (header['requestId']?.toString() ?? '').trim().isEmpty
        ? _uuid.v4()
        : (header['requestId']?.toString() ?? '').trim();
    final fromDeviceName = (header['fromDeviceName']?.toString() ?? '').trim().isEmpty
        ? socket.remoteAddress.address
        : (header['fromDeviceName']?.toString() ?? '').trim();
    final fromDeviceId = (header['fromDeviceId']?.toString() ?? '').trim();
    final advertisedSenderFingerprint = (header['fromTlsCertificateSha256']?.toString() ?? '').trim().toLowerCase();
    final peerCertificateFingerprint = socket is SecureSocket ? _fingerprintFromCertificate(socket.peerCertificate) : '';

    final effectiveSenderFingerprint = advertisedSenderFingerprint.isNotEmpty
        ? advertisedSenderFingerprint
        : peerCertificateFingerprint;

    _remoteManualDisconnectNotices.insert(
      0,
      RemoteManualDisconnectNotice(
        id: requestId,
        fromAddress: socket.remoteAddress.address,
        fromDeviceName: fromDeviceName,
        fromDeviceId: fromDeviceId,
        fromTlsCertificateSha256: effectiveSenderFingerprint,
        notifiedAt: DateTime.now(),
      ),
    );
    if (_remoteManualDisconnectNotices.length > 64) {
      _remoteManualDisconnectNotices.removeRange(64, _remoteManualDisconnectNotices.length);
    }
    _emitRemoteManualDisconnectNotices();

    try {
      socket.add(utf8.encode('${jsonEncode({'accepted': true})}\n'));
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }

  void _emitRemoteManualDisconnectNotices() {
    _remoteManualDisconnectNoticesController.add(
      List<RemoteManualDisconnectNotice>.unmodifiable(_remoteManualDisconnectNotices),
    );
  }

  void _rejectPendingDecision(String id) {
    final transferDecision = _incomingDecisions[id];
    if (transferDecision != null && !transferDecision.isCompleted) {
      transferDecision.complete(false);
    }
    final pairingDecision = _incomingPairingDecisions[id];
    if (pairingDecision != null && !pairingDecision.isCompleted) {
      pairingDecision.complete(false);
    }
  }

  String _humanizeTransferError(Object error) {
    final raw = error.toString();
    if (raw.contains('Unexpected EOF while reading source file')) {
      return 'Source file became unavailable while sending. Please reselect the file and try again.';
    }
    if (raw.contains('SocketException')) {
      return 'Network error while transferring file.';
    }
    if (raw.contains('HandshakeException') || raw.contains('TlsException')) {
      return 'Secure channel verification failed. Re-discover the device and try again.';
    }
    if (raw.contains('TimeoutException')) {
      return 'Transfer timed out.';
    }
    return raw;
  }

  bool _matchesExpectedCertificateFingerprint(
    X509Certificate? certificate,
    String expectedFingerprint,
  ) {
    final normalizedExpected = expectedFingerprint.trim().toLowerCase();
    if (certificate == null || normalizedExpected.isEmpty) {
      return false;
    }

    final actualFingerprint = _fingerprintFromCertificate(certificate);
    if (actualFingerprint.isEmpty) {
      return false;
    }
    return _constantTimeEquals(actualFingerprint, normalizedExpected);
  }

  String _fingerprintFromCertificate(X509Certificate? certificate) {
    if (certificate == null) {
      return '';
    }
    final normalizedPem = certificate.pem.replaceAll(RegExp(r'\s+'), '');
    return sha256.convert(utf8.encode(normalizedPem)).toString().toLowerCase();
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

  String _sessionDecisionKey({
    required String fromAddress,
    required String fromDeviceName,
    required String fromDeviceId,
    required String sessionId,
  }) {
    final normalizedDeviceId = fromDeviceId.trim().toLowerCase();
    final normalizedSession = sessionId.trim().toLowerCase();
    final normalizedDevice = fromDeviceName.trim().toLowerCase();
    final identityPart = normalizedDeviceId.isEmpty
        ? fromAddress
        : normalizedDeviceId;
    return '$identityPart|$normalizedDevice|$normalizedSession';
  }

  bool? _readSessionDecision(String key) {
    _pruneExpiredSessionDecisions();
    final entry = _sessionDecisions[key];
    if (entry == null) {
      return null;
    }
    return entry.accepted;
  }

  void _rememberSessionDecision(String key, bool accepted) {
    _pruneExpiredSessionDecisions();
    _sessionDecisions[key] = (accepted: accepted, at: DateTime.now());
  }

  void _pruneExpiredSessionDecisions() {
    final now = DateTime.now();
    _sessionDecisions.removeWhere(
      (_, entry) => now.difference(entry.at) > _sessionDecisionTtl,
    );
  }

  Future<Map<String, dynamic>> _readJsonLineFromIterator(
    StreamIterator<String> iterator, {
    required Duration timeout,
  }) async {
    final moved = await iterator.moveNext().timeout(timeout);
    if (!moved) {
      throw const SocketException(
        'Connection closed while waiting for response',
      );
    }
    final line = iterator.current;
    return jsonDecode(line) as Map<String, dynamic>;
  }

  /// Builds `[4-byte big-endian length][1-byte frame tag][body]` as one
  /// contiguous buffer so callers only need a single `socket.add()`.
  Uint8List _buildFrame(int tag, Uint8List body) {
    final frame = Uint8List(4 + 1 + body.length);
    ByteData.sublistView(frame).setUint32(0, 1 + body.length, Endian.big);
    frame[4] = tag;
    frame.setRange(5, 5 + body.length, body);
    return frame;
  }

  void _updateTransfer(
    String id,
    TransferModel Function(TransferModel current) updater,
  ) {
    final current = _active[id];
    if (current == null) {
      return;
    }
    _active[id] = updater(current);
    _emitActive();
  }

  void _archiveTransfer(String id) {
    _activeReceiverSockets.remove(id);
    final transfer = _active.remove(id);
    if (transfer == null) {
      return;
    }
    _completedController.add(transfer);
    final duration = DateTime.now().difference(transfer.startedAt);
    _history.insert(
      0,
      TransferHistoryEntry(
        fileName: transfer.fileName,
        size: transfer.size,
        date: DateTime.now(),
        deviceName: transfer.deviceName,
        status: transfer.status,
        duration: duration,
        direction: transfer.direction,
        localPath: transfer.localPath,
      ),
    );
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
    _emitActive();
  }

  void _emitActive() {
    _activeController.add(
      List<TransferModel>.unmodifiable(_active.values.toList()),
    );
  }

  void approveIncomingRequest(String id) {
    final completer = _incomingDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  void rejectIncomingRequest(String id) {
    final completer = _incomingDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  void approveIncomingPairingRequest(String id) {
    final completer = _incomingPairingDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  void rejectIncomingPairingRequest(String id) {
    final completer = _incomingPairingDecisions[id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  void cancelPairing(String targetDeviceId) {
    final socket = _activePairingSockets.remove(targetDeviceId);
    socket?.close();
  }

  void _emitIncomingRequests() {
    _incomingRequestsController.add(
      List<IncomingTransferRequest>.unmodifiable(
        _incomingRequests.values.toList(),
      ),
    );
  }

  void _emitIncomingPairingRequests() {
    _incomingPairingRequestsController.add(
      List<IncomingPairingRequest>.unmodifiable(
        _incomingPairingRequests.values.toList(),
      ),
    );
  }

  void _emitRemoteUnpairNotices() {
    _remoteUnpairNoticesController.add(
      List<RemoteUnpairNotice>.unmodifiable(_remoteUnpairNotices),
    );
  }

  void updateSaveDirectory(String path, {bool? categorizeFiles}) {
    _saveDirectory = path;
    if (categorizeFiles != null) {
      _categorizeFiles = categorizeFiles;
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    _historyController.add(const <TransferHistoryEntry>[]);
  }

  Future<void> clearHistoryByDirection(TransferDirection direction) async {
    _history.removeWhere((entry) => entry.direction == direction);
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
  }

  Future<void> removeHistoryEntry(TransferHistoryEntry target) async {
    final index = _history.indexWhere(
      (entry) => _sameHistoryEntry(entry, target),
    );
    if (index < 0) {
      return;
    }
    _history.removeAt(index);
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

  Future<void> dispose() async {
    for (final completer in _incomingDecisions.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    for (final completer in _incomingPairingDecisions.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    for (final completer in _incomingManualConnectDecisions.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    await stopReceiver();
    await _activeController.close();
    await _completedController.close();
    await _historyController.close();
    await _incomingRequestsController.close();
    await _incomingPairingRequestsController.close();
    await _remoteUnpairNoticesController.close();
    await _remoteManualDisconnectNoticesController.close();
    await _incomingManualConnectRequestsController.close();
  }

  Future<void> _handleIncomingManualConnectRequest({
    required Socket socket,
    required Map<String, dynamic> header,
    required StreamSubscription<List<int>> subscription,
  }) async {
    final requestId = (header['requestId']?.toString() ?? '').trim().isEmpty
        ? _uuid.v4()
        : (header['requestId']?.toString() ?? '').trim();
    final fromDeviceName =
        (header['fromDeviceName']?.toString() ?? '').trim().isEmpty
        ? socket.remoteAddress.address
        : (header['fromDeviceName']?.toString() ?? '').trim();
    final fromDeviceId = (header['fromDeviceId']?.toString() ?? '').trim();
    final advertisedSenderFingerprint =
        (header['fromTlsCertificateSha256']?.toString() ?? '')
            .trim()
            .toLowerCase();
    final peerCertificateFingerprint = socket is SecureSocket
        ? _fingerprintFromCertificate(socket.peerCertificate)
        : '';

    final effectiveSenderFingerprint = advertisedSenderFingerprint.isNotEmpty
        ? advertisedSenderFingerprint
        : peerCertificateFingerprint;

    final fromDevicePlatform = header['fromDevicePlatform']?.toString() ?? 'other';
    final fromDeviceType = header['fromDeviceType']?.toString() ?? 'other';
    final fromPort = (header['fromPort'] as num?)?.toInt();

    if (fromDeviceId.isEmpty || effectiveSenderFingerprint.isEmpty) {
      try {
        socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
        await socket.flush();
        await socket.close();
      } catch (_) {}
      return;
    }

    // Deduplicate: if a request from the same device is already pending, reject the new one
    final alreadyPending = _incomingManualConnectRequests.values
        .any((r) => r.fromDeviceId == fromDeviceId);
    if (alreadyPending) {
      try {
        socket.add(utf8.encode('${jsonEncode({'accepted': false})}\n'));
        await socket.flush();
        await socket.close();
      } catch (_) {}
      return;
    }

    final request = IncomingManualConnectRequest(
      id: requestId,
      fromAddress: socket.remoteAddress.address,
      fromDeviceName: fromDeviceName,
      fromDeviceId: fromDeviceId,
      fromTlsCertificateSha256: effectiveSenderFingerprint,
      fromDevicePlatform: fromDevicePlatform,
      fromDeviceType: fromDeviceType,
      requestedAt: DateTime.now(),
      fromPort: fromPort,
    );
    _incomingManualConnectRequests[requestId] = request;
    final decisionCompleter = Completer<bool>();
    _incomingManualConnectDecisions[requestId] = decisionCompleter;
    _emitIncomingManualConnectRequests();

    // Listen for socket closure (cancellation) or error
    subscription.onData((_) {});
    subscription.onDone(() {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    });
    subscription.onError((_) {
      if (!decisionCompleter.isCompleted) {
        decisionCompleter.complete(false);
      }
    });
    subscription.resume();

    final approved = await decisionCompleter.future;
    _incomingManualConnectRequests.remove(requestId);
    _incomingManualConnectDecisions.remove(requestId);
    _emitIncomingManualConnectRequests();

    try {
      socket.add(utf8.encode('${jsonEncode({'accepted': approved})}\n'));
      await socket.flush();
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
  }

  void _emitIncomingManualConnectRequests() {
    _incomingManualConnectRequestsController.add(
      _incomingManualConnectRequests.values.toList(),
    );
  }

  void approveIncomingManualConnectRequest(String requestId) {
    final completer = _incomingManualConnectDecisions[requestId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  void rejectIncomingManualConnectRequest(String requestId) {
    final completer = _incomingManualConnectDecisions[requestId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }
}

class _IncomingTransfer {
  _IncomingTransfer._({
    required this.id,
    required this.file,
    required this.originalFileName,
    required this.expectedSize,
    required this.sessionKey,
    required this.expectedSha,
    required this._sink,
  });

  final String id;
  final File file;
  final String originalFileName;
  final int expectedSize;
  final Uint8List sessionKey;
  /// For protocol v1 this is known up front (from the header). For v2 it
  /// arrives in a trailer frame after the last chunk, so it's settable.
  String? expectedSha;
  final RandomAccessFile _sink;
  int writtenBytes = 0;
  DateTime _speedTs = DateTime.now();
  int _speedAccumulator = 0;
  double speedBytesPerSec = 0;
  String? actualSha;
  final _IncrementalDigestSink _hashSink = _IncrementalDigestSink();
  late final ByteConversionSink _hashInput = sha256.startChunkedConversion(_hashSink);

  Duration? get eta {
    if (speedBytesPerSec <= 0) {
      return null;
    }
    final remain = expectedSize - writtenBytes;
    return Duration(seconds: (remain / speedBytesPerSec).round());
  }

  static Future<_IncomingTransfer> create({
    required String id,
    required File file,
    required String originalFileName,
    required int expectedSize,
    required Uint8List sessionKey,
    required String? expectedSha,
  }) async {
    await file.parent.create(recursive: true);
    final sink = await file.open(mode: FileMode.writeOnly);
    return _IncomingTransfer._(
      id: id,
      file: file,
      originalFileName: originalFileName,
      expectedSize: expectedSize,
      sessionKey: sessionKey,
      expectedSha: expectedSha,
      sink: sink,
    );
  }

  Future<void> write(Uint8List bytes) async {
    await _sink.writeFrom(bytes);
    _hashInput.add(bytes);
    writtenBytes += bytes.length;
    _speedAccumulator += bytes.length;
    final now = DateTime.now();
    final ms = now.difference(_speedTs).inMilliseconds;
    if (ms >= 500) {
      speedBytesPerSec = _speedAccumulator / (ms / 1000);
      _speedAccumulator = 0;
      _speedTs = now;
    }
  }

  Future<bool> verifySha() async {
    _hashInput.close();
    actualSha = _hashSink.digest.toString();
    return expectedSha == null || actualSha == expectedSha;
  }

  Future<void> close() async {
    await _sink.close();
  }
}

/// Minimal `Sink<Digest>` for `Hash.startChunkedConversion` — not exported
/// by `package:crypto`, so implemented locally rather than reaching into its
/// internals.
class _IncrementalDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest!;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}
}

/// Gates how often a progress update fires, shared by the same constant
/// interval on both the sender and receiver so their emission cadence — not
/// just their byte source — is aligned.
/// Result of one attempt to send a single file.
enum _SendOutcome {
  /// Done with this file (sent, failed for good, or cancelled).
  finished,

  /// A transient failure; try this file again.
  retry,

  /// The receiver rejected the session; don't offer the remaining files.
  rejected,
}

class _ProgressThrottle {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  bool due() {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds >= TcpTransferService._progressEmitIntervalMs) {
      _last = now;
      return true;
    }
    return false;
  }
}
