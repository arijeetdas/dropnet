import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// Thrown by [AesService.decryptChunk] (via the chunk-verification helpers in
/// `transfer_crypto_isolate.dart`) when a chunk fails to authenticate — i.e.
/// it was corrupted or tampered with.
///
/// NOTE: AES-GCM was evaluated for chunk encryption (single-pass authenticated
/// encryption, would remove the separate per-chunk SHA-256 below) and
/// rejected: `package:encrypt`'s pure-Dart PointyCastle GCM implementation
/// measured ~24x slower than CBC for chunk-sized data (~291ms vs ~12ms per
/// 512KB block, confirmed by direct benchmark) — its GHASH step has no
/// hardware acceleration in this library. CBC + a separate plaintext SHA-256
/// remains the chunk cipher; the isolate offload below is what actually
/// removes it from the main isolate's critical path.
class GcmAuthenticationException implements Exception {
  const GcmAuthenticationException(this.message);
  final String message;

  @override
  String toString() => 'GcmAuthenticationException: $message';
}

class AesService {
  static const _bootstrapSecret = 'dropnet-bootstrap-key-v1';
  final _random = Random.secure();

  Uint8List generateSessionKey() {
    return Uint8List.fromList(List<int>.generate(32, (_) => _random.nextInt(256)));
  }

  Uint8List generateIvBytes() {
    return Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));
  }

  Uint8List encryptChunk(Uint8List plain, Uint8List sessionKey, Uint8List ivBytes) {
    final encrypter = Encrypter(AES(Key(sessionKey), mode: AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plain, iv: IV(ivBytes));
    return Uint8List.fromList(encrypted.bytes);
  }

  Uint8List decryptChunk(Uint8List cipher, Uint8List sessionKey, Uint8List ivBytes) {
    final encrypter = Encrypter(AES(Key(sessionKey), mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(cipher), iv: IV(ivBytes));
    return Uint8List.fromList(decrypted);
  }

  Map<String, String> wrapSessionKey(Uint8List sessionKey) {
    final iv = generateIvBytes();
    final keyBytes = Uint8List.fromList(sha256.convert(utf8.encode(_bootstrapSecret)).bytes);
    final wrapped = encryptChunk(sessionKey, keyBytes, iv);
    return {
      'wrappedKey': base64Encode(wrapped),
      'wrappedIv': base64Encode(iv),
    };
  }

  Uint8List unwrapSessionKey({required String wrappedKey, required String wrappedIv}) {
    final keyBytes = Uint8List.fromList(sha256.convert(utf8.encode(_bootstrapSecret)).bytes);
    return decryptChunk(base64Decode(wrappedKey), keyBytes, base64Decode(wrappedIv));
  }
}
