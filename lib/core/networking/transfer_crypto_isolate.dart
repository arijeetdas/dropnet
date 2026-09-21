import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../encryption/aes_service.dart';

/// Runs AES encrypt/decrypt + hashing work for file transfers on a small,
/// persistent pool of background isolates, so the main isolate (which also
/// drives the UI) is never blocked by per-chunk crypto math, and disk I/O,
/// crypto, and socket I/O for different chunks can overlap.
class CryptoIsolatePool {
  CryptoIsolatePool._();

  static final CryptoIsolatePool instance = CryptoIsolatePool._();

  static const int workerCount = 2;

  final List<_CryptoWorker> _workers = [];
  Future<void>? _spawning;
  int _nextWorker = 0;

  Future<void> _ensureSpawned() async {
    if (_workers.length >= workerCount) return;
    _spawning ??= () async {
      for (var i = _workers.length; i < workerCount; i++) {
        _workers.add(await _CryptoWorker.spawn());
      }
    }();
    await _spawning;
    _spawning = null;
  }

  _CryptoWorker _pickWorker() {
    final worker = _workers[_nextWorker % _workers.length];
    _nextWorker++;
    return worker;
  }

  /// Encrypts [plain] with AES-CBC and returns `iv ++ sha256(plain) ++
  /// ciphertext` in one worker round trip.
  Future<Uint8List> encryptCbcWithHash({
    required Uint8List plain,
    required Uint8List key,
    required Uint8List iv,
  }) async {
    await _ensureSpawned();
    return _pickWorker().process(
      op: _CryptoOp.encryptCbcWithHash,
      data: plain,
      key: key,
      ivOrNonce: iv,
    );
  }

  /// Decrypts AES-CBC ciphertext and verifies the plaintext SHA-256 against
  /// [expectedHash] on a worker isolate. Throws [GcmAuthenticationException]
  /// (reused here as a generic "chunk failed verification" signal) on
  /// mismatch.
  Future<Uint8List> decryptCbcAndVerify({
    required Uint8List cipher,
    required Uint8List key,
    required Uint8List iv,
    required Uint8List expectedHash,
  }) async {
    await _ensureSpawned();
    return _pickWorker().process(
      op: _CryptoOp.decryptCbcAndVerify,
      data: cipher,
      key: key,
      ivOrNonce: iv,
      expectedHash: expectedHash,
    );
  }

  Future<void> disposeAll() async {
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
  }
}

enum _CryptoOp { encryptCbcWithHash, decryptCbcAndVerify }

class _CryptoWorker {
  _CryptoWorker._(this._isolate, this._sendPort, this._responses);

  final Isolate _isolate;
  final SendPort _sendPort;
  final Stream<dynamic> _responses;
  int _nextRequestId = 0;

  static Future<_CryptoWorker> spawn() async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(_workerEntry, readyPort.sendPort);
    final broadcast = readyPort.asBroadcastStream();
    final sendPort = await broadcast.first as SendPort;
    return _CryptoWorker._(isolate, sendPort, broadcast);
  }

  Future<Uint8List> process({
    required _CryptoOp op,
    required Uint8List data,
    required Uint8List key,
    required Uint8List ivOrNonce,
    Uint8List? expectedHash,
  }) async {
    final requestId = _nextRequestId++;
    final completer = Completer<Uint8List>();
    late final StreamSubscription sub;
    sub = _responses.listen((message) {
      if (message is! Map || message['requestId'] != requestId) return;
      sub.cancel();
      final error = message['error'] as String?;
      if (error != null) {
        completer.completeError(GcmAuthenticationException(error));
        return;
      }
      final resultData = (message['result'] as TransferableTypedData).materialize().asUint8List();
      completer.complete(resultData);
    });

    _sendPort.send({
      'requestId': requestId,
      'op': op.index,
      'data': TransferableTypedData.fromList([data]),
      'key': key,
      'ivOrNonce': ivOrNonce,
      'expectedHash': expectedHash,
    });

    return completer.future;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _workerEntry(SendPort readyPort) {
    final receivePort = ReceivePort();
    readyPort.send(receivePort.sendPort);
    final aes = AesService();

    receivePort.listen((message) {
      if (message is! Map) return;
      final requestId = message['requestId'] as int;
      final op = _CryptoOp.values[message['op'] as int];
      final data = (message['data'] as TransferableTypedData).materialize().asUint8List();
      final key = message['key'] as Uint8List;
      final ivOrNonce = message['ivOrNonce'] as Uint8List;
      final expectedHash = message['expectedHash'] as Uint8List?;

      try {
        final Uint8List result;
        switch (op) {
          case _CryptoOp.encryptCbcWithHash:
            result = _encryptCbcWithHashSync(aes, data, key, ivOrNonce);
          case _CryptoOp.decryptCbcAndVerify:
            result = _decryptCbcAndVerifySync(aes, data, key, ivOrNonce, expectedHash!);
        }
        readyPort.send({
          'requestId': requestId,
          'result': TransferableTypedData.fromList([result]),
        });
      } catch (e) {
        readyPort.send({'requestId': requestId, 'error': e.toString()});
      }
    });
  }
}

// These run inside the worker isolate; kept as top-level-callable statics so
// they have no dependency on anything outside this file plus AesService.
Uint8List _encryptCbcWithHashSync(AesService aes, Uint8List plain, Uint8List key, Uint8List iv) {
  final encrypted = aes.encryptChunk(plain, key, iv);
  final plainHash = Uint8List.fromList(sha256.convert(plain).bytes);
  final out = Uint8List(iv.length + plainHash.length + encrypted.length)
    ..setRange(0, iv.length, iv)
    ..setRange(iv.length, iv.length + plainHash.length, plainHash)
    ..setRange(iv.length + plainHash.length, iv.length + plainHash.length + encrypted.length, encrypted);
  return out;
}

Uint8List _decryptCbcAndVerifySync(
  AesService aes,
  Uint8List cipher,
  Uint8List key,
  Uint8List iv,
  Uint8List expectedHash,
) {
  final plain = aes.decryptChunk(cipher, key, iv);
  final actualHash = Uint8List.fromList(sha256.convert(plain).bytes);
  if (actualHash.length != expectedHash.length) {
    throw const GcmAuthenticationException('Chunk hash length mismatch');
  }
  for (var i = 0; i < actualHash.length; i++) {
    if (actualHash[i] != expectedHash[i]) {
      throw const GcmAuthenticationException('Chunk hash mismatch');
    }
  }
  return plain;
}
