import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

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
