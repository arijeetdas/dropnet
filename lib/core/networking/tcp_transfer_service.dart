import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/device_model.dart';
import '../../models/transfer_model.dart';
import '../encryption/aes_service.dart';
import '../security/local_tls_certificate_service.dart';
import '../utils/file_utils.dart';

class TcpTransferService {
  TcpTransferService({
    AesService? aesService,
    LocalTlsCertificateService? tlsCertificateService,
  }) : _aes = aesService ?? AesService(),
       _tlsCertificates = tlsCertificateService ?? LocalTlsCertificateService();

  static const int defaultPort = 45455;
  static const int defaultChunkSize = 64 * 1024;
  static const int _chunkHashBytes = 32;
  static const Duration _sessionDecisionTtl = Duration(minutes: 12);
  static const String _tlsCertCommonName = 'DropNet Local';
  static const List<String> _tlsCertSans = <String>['localhost', '127.0.0.1'];

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
  final Map<String, TransferModel> _active = {};
  final List<TransferHistoryEntry> _history = [];
  final Map<String, IncomingTransferRequest> _incomingRequests = {};
  final Map<String, Completer<bool>> _incomingDecisions = {};
    final Map<String, IncomingPairingRequest> _incomingPairingRequests = {};
    final Map<String, Completer<bool>> _incomingPairingDecisions = {};
    final List<RemoteUnpairNotice> _remoteUnpairNotices = [];
    final Map<String, SecureSocket> _activePairingSockets = {};
  final Map<String, ({bool accepted, DateTime at})> _sessionDecisions = {};
  final Set<String> _canceled = {};
  ServerSocket? _server;
  String? _saveDirectory;
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
  }) async {
    if (_server != null) {
      return;
    }
    _saveDirectory = saveDirectory;
    try {
      final tlsContext = await _tlsCertificates.createServerContext(
        commonName: _tlsCertCommonName,
        subjectAlternativeNames: _tlsCertSans,
      );
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
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
    } on SocketException {
      _server = null;
      return;
    }
  }

  Future<void> stopReceiver() async {
    await _server?.close();
    _server = null;
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
      final path = candidates[index];
      await _sendSingleFileWithRetry(
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
    }
  }

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

  Future<void> _sendSingleFileWithRetry({
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
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final shouldRetry = await _sendSingleFile(
        target: target,
        filePath: filePath,
        port: port,
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
      if (!shouldRetry) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<bool> _sendSingleFile({
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
      return false;
    }

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

      reader = await file.open();
      lineIterator = StreamIterator<String>(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

      final sessionKey = _aes.generateSessionKey();
      final wrapped = _aes.wrapSessionKey(sessionKey);
      final checksum = await _sha256(file);
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
        'checksum': checksum,
      };
      if (pairingCode != null) {
        header['pairingCode'] = pairingCode;
      }
      socket.add(utf8.encode('${jsonEncode(header)}\n'));

      final response = await _readJsonLineFromIterator(
        lineIterator,
        timeout: const Duration(seconds: 60),
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
        return false;
      }

      int sentBytes = 0;
      var sentSinceLastSample = 0;
      var speedSampleTime = DateTime.now();

      _updateTransfer(
        transferId,
        (t) => t.copyWith(status: TransferStatus.transferring),
      );

      while (sentBytes < totalSize && !_canceled.contains(transferId)) {
        final remain = totalSize - sentBytes;
        final toRead = min(remain, _chunkSize);
        final plain = await reader.read(toRead);
        if (plain.isEmpty) {
          throw const FileSystemException(
            'Unexpected EOF while reading source file during transfer.',
          );
        }
        final iv = _aes.generateIvBytes();
        final encrypted = _aes.encryptChunk(
          Uint8List.fromList(plain),
          sessionKey,
          iv,
        );
        final plainHash = sha256.convert(plain).bytes;
        final payload =
            Uint8List(iv.length + _chunkHashBytes + encrypted.length)
              ..setRange(0, iv.length, iv)
              ..setRange(iv.length, iv.length + _chunkHashBytes, plainHash)
              ..setRange(
                iv.length + _chunkHashBytes,
                iv.length + _chunkHashBytes + encrypted.length,
                encrypted,
              );
        final lengthPrefix = ByteData(4)
          ..setUint32(0, payload.length, Endian.big);
        socket.add(lengthPrefix.buffer.asUint8List());
        socket.add(payload);

        sentBytes += plain.length;
        sentSinceLastSample += plain.length;
        final now = DateTime.now();
        final elapsedMs = now.difference(speedSampleTime).inMilliseconds;
        if (elapsedMs >= 500) {
          final speed = sentSinceLastSample / (elapsedMs / 1000);
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
        final completion = await _readJsonLineFromIterator(
          lineIterator,
          timeout: const Duration(seconds: 30),
        );
        final ok = completion['ok'] == true;
        if (!ok) {
          final reason =
              (completion['error']?.toString().trim() ??
              'Receiver reported transfer failure.');
          _updateTransfer(
            transferId,
            (t) => t.copyWith(
              status: TransferStatus.failed,
              errorMessage: maxAttempts > attempt
                  ? '$reason Retrying...'
                  : reason,
            ),
          );
          _archiveTransfer(transferId);
          return maxAttempts > attempt;
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
      return false;
    } catch (error) {
      final reason = _humanizeTransferError(error);
      _updateTransfer(
        transferId,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          errorMessage: maxAttempts > attempt ? '$reason Retrying...' : reason,
        ),
      );
      _archiveTransfer(transferId);
      final retryable =
          error is SocketException ||
          error is TimeoutException ||
          (error is FileSystemException &&
              error.message.contains('Unexpected EOF'));
      return retryable && maxAttempts > attempt;
    } finally {
      await lineIterator?.cancel();
      await reader?.close();
      await socket?.close();
    }
  }

  void cancelTransfer(String transferId) {
    _canceled.add(transferId);
  }

  void _handleIncomingSocket(Socket socket) {
    String headerLine = '';
    bool headerParsed = false;
    String? requestId;
    _IncomingTransfer? transfer;
    bool transferFinalized = false;
    final accumulator = BytesBuilder(copy: false);
    int? expectedPayloadLen;
    late final StreamSubscription<List<int>> subscription;

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
              final checksum = header['checksum'] as String?;
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
                  const Duration(minutes: 2),
                  onTimeout: () => false,
                );
                _incomingDecisions.remove(transferId);
                _incomingRequests.remove(transferId);
                _emitIncomingRequests();
              }

              if (sessionId.isNotEmpty) {
                _rememberSessionDecision(decisionKey, accepted);
              }

              socket.add(
                utf8.encode('${jsonEncode({'accepted': accepted})}\n'),
              );
              if (!accepted) {
                await socket.close();
                return;
              }

              final saveDir = _saveDirectory;
              if (saveDir == null || saveDir.isEmpty) {
                socket.destroy();
                return;
              }
              final savePath = FileUtils.safeJoin(saveDir, fileName);
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

              if (payload.length < (16 + _chunkHashBytes + 1)) {
                if (transfer != null) {
                  _updateTransfer(
                    transfer!.id,
                    (t) => t.copyWith(
                      status: TransferStatus.failed,
                      errorMessage: 'Invalid payload frame received.',
                    ),
                  );
                  transferFinalized = true;
                  _archiveTransfer(transfer!.id);
                }
                await socket.close();
                break;
              }

              if (transfer == null) {
                await socket.close();
                break;
              }

              final iv = Uint8List.fromList(payload.sublist(0, 16));
              final expectedPlainHash = Uint8List.fromList(
                payload.sublist(16, 16 + _chunkHashBytes),
              );
              final cipher = Uint8List.fromList(
                payload.sublist(16 + _chunkHashBytes),
              );
              final plain = _aes.decryptChunk(cipher, transfer!.sessionKey, iv);
              final actualPlainHash = Uint8List.fromList(
                sha256.convert(plain).bytes,
              );
              if (!_bytesEqual(expectedPlainHash, actualPlainHash)) {
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
        if (transfer != null &&
            transfer!.writtenBytes < transfer!.expectedSize) {
          await transfer!.close();
          _updateTransfer(
            transfer!.id,
            (t) => t.copyWith(
              status: TransferStatus.failed,
              errorMessage: 'Connection closed before transfer completed.',
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
          _updateTransfer(
            transfer!.id,
            (t) => t.copyWith(
              status: TransferStatus.failed,
              errorMessage: _humanizeTransferError(error),
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

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
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

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
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

  void updateSaveDirectory(String path) {
    _saveDirectory = path;
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
    await stopReceiver();
    await _activeController.close();
    await _completedController.close();
    await _historyController.close();
    await _incomingRequestsController.close();
    await _incomingPairingRequestsController.close();
    await _remoteUnpairNoticesController.close();
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
    required RandomAccessFile sink,
  }) : _sink = sink;

  final String id;
  final File file;
  final String originalFileName;
  final int expectedSize;
  final Uint8List sessionKey;
  final String? expectedSha;
  final RandomAccessFile _sink;
  int writtenBytes = 0;
  DateTime _speedTs = DateTime.now();
  int _speedAccumulator = 0;
  double speedBytesPerSec = 0;
  String? actualSha;

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
    actualSha = (await sha256.bind(file.openRead()).first).toString();
    return expectedSha == null || actualSha == expectedSha;
  }

  Future<void> close() async {
    await _sink.close();
  }
}
