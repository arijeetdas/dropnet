import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalTlsCertificateService {
  static const _securityDirectoryName = 'security';
  static const _certificateFileName = 'dropnet_local_cert.pem';
  static const _privateKeyFileName = 'dropnet_local_key.pem';
  static const _metaFileName = 'dropnet_local_cert_meta.json';

  Future<void> _deleteExistingMaterial() async {
    try {
      final directory = await _certificateDirectory();
      final certificate = File(p.join(directory.path, _certificateFileName));
      final privateKey = File(p.join(directory.path, _privateKeyFileName));
      final meta = File(p.join(directory.path, _metaFileName));
      if (await certificate.exists()) {
        await certificate.delete();
      }
      if (await privateKey.exists()) {
        await privateKey.delete();
      }
      if (await meta.exists()) {
        await meta.delete();
      }
    } catch (_) {}
  }

  Future<SecurityContext> createServerContext({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    try {
      final material = await _loadOrCreateMaterial(
        commonName: commonName,
        subjectAlternativeNames: subjectAlternativeNames,
      );

      final context = SecurityContext();
      context.useCertificateChain(material.certificate.path);
      context.usePrivateKey(material.privateKey.path);
      return context;
    } catch (e) {
      // Catch KEY_VALUES_MISMATCH or other TlsExceptions and heal by regenerating
      await _deleteExistingMaterial();

      final material = await _loadOrCreateMaterial(
        commonName: commonName,
        subjectAlternativeNames: subjectAlternativeNames,
      );

      final context = SecurityContext();
      context.useCertificateChain(material.certificate.path);
      context.usePrivateKey(material.privateKey.path);
      return context;
    }
  }

  Future<String> readCertificateSha256Fingerprint({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    final material = await _loadOrCreateMaterial(
      commonName: commonName,
      subjectAlternativeNames: subjectAlternativeNames,
    );
    final pem = await material.certificate.readAsString();
    return _sha256FingerprintFromPem(pem);
  }

  Future<String> readCertificatePem({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    final material = await _loadOrCreateMaterial(
      commonName: commonName,
      subjectAlternativeNames: subjectAlternativeNames,
    );
    return material.certificate.readAsString();
  }

  Future<String> signPayloadSha256Base64Url({
    required String payload,
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    final material = await _loadOrCreateMaterial(
      commonName: commonName,
      subjectAlternativeNames: subjectAlternativeNames,
    );
    final privateKeyPem = await material.privateKey.readAsString();
    final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
    final signature = CryptoUtils.rsaSign(
      privateKey,
      Uint8List.fromList(utf8.encode(payload)),
      algorithmName: 'SHA-256/RSA',
    );
    return base64UrlEncode(signature);
  }

  bool verifyPayloadSha256SignatureFromCertificate({
    required String payload,
    required String signatureBase64Url,
    required String certificatePem,
  }) {
    final normalizedSignature = signatureBase64Url.trim();
    final normalizedCertificatePem = certificatePem.trim();
    if (normalizedSignature.isEmpty || normalizedCertificatePem.isEmpty) {
      return false;
    }

    try {
      final modulus = X509Utils.getModulusFromRSAX509Pem(
        normalizedCertificatePem,
      );
      final publicKey = RSAPublicKey(modulus, BigInt.from(65537));
      final signature = _decodeBase64Url(normalizedSignature);
      return CryptoUtils.rsaVerify(
        publicKey,
        Uint8List.fromList(utf8.encode(payload)),
        signature,
        algorithm: 'SHA-256/RSA',
      );
    } catch (_) {
      return false;
    }
  }

  String readCertificateSha256FingerprintFromPem(String pem) {
    return _sha256FingerprintFromPem(pem);
  }

  String _sha256FingerprintFromPem(String pem) {
    final normalizedPem = pem.replaceAll(RegExp(r'\s+'), '');
    return sha256.convert(utf8.encode(normalizedPem)).toString();
  }

  Future<_TlsCertificateMaterial> _loadOrCreateMaterial({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    final directory = await _certificateDirectory();
    final certificate = File(p.join(directory.path, _certificateFileName));
    final privateKey = File(p.join(directory.path, _privateKeyFileName));
    final meta = File(p.join(directory.path, _metaFileName));

    final normalizedNames = _normalizeSubjectAlternativeNames(
      subjectAlternativeNames,
    );

    final existingNames = await _readExistingNames(meta);
    final hasExistingMaterial =
        await certificate.exists() && await privateKey.exists();

    if (hasExistingMaterial && _covers(existingNames, normalizedNames)) {
      return _TlsCertificateMaterial(
        certificate: certificate,
        privateKey: privateKey,
      );
    }

    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKeyObject = keyPair.privateKey as RSAPrivateKey;
    final publicKeyObject = keyPair.publicKey as RSAPublicKey;

    final subject = <String, String>{
      'CN': commonName.trim().isEmpty ? 'DropNet Local' : commonName.trim(),
      'O': 'DropNet',
      'OU': 'Local Transfer',
    };

    final csr = X509Utils.generateRsaCsrPem(
      subject,
      privateKeyObject,
      publicKeyObject,
      san: normalizedNames,
    );

    final certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKeyObject,
      csr,
      3650,
      sans: normalizedNames,
      serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
      notBefore: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
      privateKeyObject,
    );

    await certificate.writeAsString(certificatePem, flush: true);
    await privateKey.writeAsString(privateKeyPem, flush: true);
    await meta.writeAsString(
      jsonEncode({
        'subjectAlternativeNames': normalizedNames,
        'generatedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );

    return _TlsCertificateMaterial(
      certificate: certificate,
      privateKey: privateKey,
    );
  }

  Future<Directory> _certificateDirectory() async {
    Directory root;
    try {
      root = await getApplicationSupportDirectory();
    } catch (_) {
      root = Directory.systemTemp;
    }

    final directory = Directory(p.join(root.path, _securityDirectoryName));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Set<String>> _readExistingNames(File metaFile) async {
    if (!await metaFile.exists()) {
      return <String>{};
    }

    try {
      final payload =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final rawList =
          (payload['subjectAlternativeNames'] as List<dynamic>? ?? const []);
      return rawList
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  List<String> _normalizeSubjectAlternativeNames(List<String> names) {
    final sanitized = names
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: true);

    if (!sanitized.contains('localhost')) {
      sanitized.add('localhost');
    }
    if (!sanitized.contains('127.0.0.1')) {
      sanitized.add('127.0.0.1');
    }

    sanitized.sort();
    return sanitized;
  }

  bool _covers(Set<String> existingNames, List<String> requiredNames) {
    for (final required in requiredNames) {
      if (!existingNames.contains(required.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  Uint8List _decodeBase64Url(String value) {
    final normalized = value.replaceAll('\n', '').replaceAll('\r', '').trim();
    final padding = (4 - normalized.length % 4) % 4;
    return base64Url.decode('$normalized${'=' * padding}');
  }
}

class _TlsCertificateMaterial {
  const _TlsCertificateMaterial({
    required this.certificate,
    required this.privateKey,
  });

  final File certificate;
  final File privateKey;
}
