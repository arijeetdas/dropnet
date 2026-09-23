import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Which certificate a TLS server should present.
///
/// - [transferIdentity]: the device's long-lived identity. Its SHA-256
///   fingerprint is advertised through discovery (UDP presence + mDNS TXT),
///   pinned by senders during the TLS handshake, and stored by paired peers.
///   It must therefore never change while the app is installed, no matter
///   which network the device joins.
/// - [webServer]: the certificate used by the browser-facing HTTPS servers
///   (Web Mode and temporary share links). Browsers want the current LAN IP
///   in the certificate's subjectAlternativeNames, so this one is regenerated
///   whenever the IP changes — which is exactly why it must be kept separate
///   from the transfer identity.
enum TlsCertificatePurpose { transferIdentity, webServer }

class LocalTlsCertificateService {
  static const _securityDirectoryName = 'security';

  // Transfer identity (file names kept for backwards compatibility, so an
  // existing install keeps its fingerprint and all of its pairings).
  static const _certificateFileName = 'dropnet_local_cert.pem';
  static const _privateKeyFileName = 'dropnet_local_key.pem';
  static const _metaFileName = 'dropnet_local_cert_meta.json';

  // Browser-facing HTTPS servers.
  static const _webCertificateFileName = 'dropnet_web_cert.pem';
  static const _webPrivateKeyFileName = 'dropnet_web_key.pem';
  static const _webMetaFileName = 'dropnet_web_cert_meta.json';

  static const _identityCommonName = 'DropNet Local';
  static const _identitySans = <String>['localhost', '127.0.0.1'];

  /// Process-wide (per isolate) identity material. Every service instance
  /// (discovery, TCP receiver, pairing, presence signing) shares this single
  /// in-memory copy, so the fingerprint that gets advertised is always the
  /// fingerprint of the exact certificate the TCP server presents.
  ///
  /// Previously each service had its own instance and read/generated the
  /// files independently: two services racing on first launch could each
  /// generate a different key pair (leaving a cert from one run and a key
  /// from the other), and the "self-heal" path regenerated the certificate
  /// behind discovery's back. Either way peers pinned a fingerprint the
  /// server no longer presented, and every transfer failed with
  /// "Secure channel verification failed".
  static Future<_PemMaterial>? _identityFuture;

  /// Serializes web-certificate (re)generation so concurrent starts of the
  /// web server and the temporary link server can't interleave writes.
  static Future<void> _webLock = Future<void>.value();

  Future<SecurityContext> createServerContext({
    required String commonName,
    required List<String> subjectAlternativeNames,
    TlsCertificatePurpose purpose = TlsCertificatePurpose.transferIdentity,
  }) async {
    final material = purpose == TlsCertificatePurpose.transferIdentity
        ? await _identityMaterial()
        : await _webMaterial(
            commonName: commonName,
            subjectAlternativeNames: subjectAlternativeNames,
          );
    return _buildContext(material);
  }

  Future<String> readCertificateSha256Fingerprint({
    String commonName = _identityCommonName,
    List<String> subjectAlternativeNames = _identitySans,
  }) async {
    final material = await _identityMaterial();
    return _sha256FingerprintFromPem(material.certificatePem);
  }

  Future<String> readCertificatePem({
    String commonName = _identityCommonName,
    List<String> subjectAlternativeNames = _identitySans,
  }) async {
    final material = await _identityMaterial();
    return material.certificatePem;
  }

  Future<String> signPayloadSha256Base64Url({
    required String payload,
    String commonName = _identityCommonName,
    List<String> subjectAlternativeNames = _identitySans,
  }) async {
    final material = await _identityMaterial();
    final privateKey = CryptoUtils.rsaPrivateKeyFromPem(
      material.privateKeyPem,
    );
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

  // ── Transfer identity ─────────────────────────────────────────────────────

  Future<_PemMaterial> _identityMaterial() {
    final existing = _identityFuture;
    if (existing != null) {
      return existing;
    }
    final future = _loadOrCreateIdentity();
    _identityFuture = future;
    // Don't cache a failure (e.g. a transient I/O error) forever.
    future.catchError((Object _) {
      if (identical(_identityFuture, future)) {
        _identityFuture = null;
      }
      return const _PemMaterial(certificatePem: '', privateKeyPem: '');
    });
    return future;
  }

  Future<_PemMaterial> _loadOrCreateIdentity() async {
    final directory = await _certificateDirectory();
    final certificate = File(p.join(directory.path, _certificateFileName));
    final privateKey = File(p.join(directory.path, _privateKeyFileName));
    final meta = File(p.join(directory.path, _metaFileName));

    // The identity is reused whenever it is present and valid — deliberately
    // regardless of which subjectAlternativeNames it was generated with.
    // Peers pin its fingerprint, so replacing it is only acceptable when the
    // material is genuinely missing or unusable.
    for (var attempt = 0; attempt < 2; attempt++) {
      final existing = await _readValidMaterial(certificate, privateKey);
      if (existing != null) {
        return existing;
      }
      if (!await certificate.exists() && !await privateKey.exists()) {
        break;
      }
      // Files exist but don't form a valid pair. Another isolate (e.g. a
      // second Flutter engine in the same process) may be mid-write, so give
      // it a moment before concluding the material is corrupt.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final generated = await _generateMaterial(
      commonName: _identityCommonName,
      subjectAlternativeNames: _normalizeSubjectAlternativeNames(
        _identitySans,
      ),
    );
    await _writeMaterial(
      material: generated,
      certificate: certificate,
      privateKey: privateKey,
      meta: meta,
      subjectAlternativeNames: _normalizeSubjectAlternativeNames(
        _identitySans,
      ),
    );
    return generated;
  }

  // ── Web server certificate ────────────────────────────────────────────────

  Future<_PemMaterial> _webMaterial({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) {
    final completer = Completer<_PemMaterial>();
    final previous = _webLock;
    final done = Completer<void>();
    _webLock = done.future;
    () async {
      try {
        await previous;
      } catch (_) {}
      try {
        completer.complete(
          await _loadOrCreateWeb(
            commonName: commonName,
            subjectAlternativeNames: subjectAlternativeNames,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        done.complete();
      }
    }();
    return completer.future;
  }

  Future<_PemMaterial> _loadOrCreateWeb({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    final directory = await _certificateDirectory();
    final certificate = File(p.join(directory.path, _webCertificateFileName));
    final privateKey = File(p.join(directory.path, _webPrivateKeyFileName));
    final meta = File(p.join(directory.path, _webMetaFileName));
    final normalizedNames = _normalizeSubjectAlternativeNames(
      subjectAlternativeNames,
    );

    final existingNames = await _readExistingNames(meta);
    if (_covers(existingNames, normalizedNames)) {
      final existing = await _readValidMaterial(certificate, privateKey);
      if (existing != null) {
        return existing;
      }
    }

    // Keep previously covered names too, so alternating between two networks
    // doesn't regenerate the certificate every single time.
    final mergedNames = <String>{...existingNames, ...normalizedNames}.toList()
      ..sort();
    final generated = await _generateMaterial(
      commonName: commonName,
      subjectAlternativeNames: mergedNames,
    );
    await _writeMaterial(
      material: generated,
      certificate: certificate,
      privateKey: privateKey,
      meta: meta,
      subjectAlternativeNames: mergedNames,
    );
    return generated;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  SecurityContext _buildContext(_PemMaterial material) {
    final context = SecurityContext();
    context.useCertificateChainBytes(utf8.encode(material.certificatePem));
    context.usePrivateKeyBytes(utf8.encode(material.privateKeyPem));
    return context;
  }

  /// Returns the material only if both files exist and the key actually
  /// belongs to the certificate (BoringSSL rejects a mismatched pair with
  /// KEY_VALUES_MISMATCH when the key is loaded into a context).
  Future<_PemMaterial?> _readValidMaterial(
    File certificate,
    File privateKey,
  ) async {
    try {
      if (!await certificate.exists() || !await privateKey.exists()) {
        return null;
      }
      final material = _PemMaterial(
        certificatePem: await certificate.readAsString(),
        privateKeyPem: await privateKey.readAsString(),
      );
      if (material.certificatePem.trim().isEmpty ||
          material.privateKeyPem.trim().isEmpty) {
        return null;
      }
      _buildContext(material);
      return material;
    } catch (_) {
      return null;
    }
  }

  Future<_PemMaterial> _generateMaterial({
    required String commonName,
    required List<String> subjectAlternativeNames,
  }) async {
    // Offload ALL synchronous CPU-intensive crypto work to a background isolate:
    // key-pair generation, CSR building, self-signed cert creation, and PEM
    // encoding.  Each of these is pure-Dart CPU work that blocks the main
    // isolate for several seconds on a physical iPhone, causing UI freezes and
    // triggering iOS's watchdog process killer on cold launch.
    final serialNumber = DateTime.now().millisecondsSinceEpoch.toString();
    final notBefore = DateTime.now().subtract(const Duration(minutes: 5));
    final subject = <String, String>{
      'CN': commonName.trim().isEmpty ? _identityCommonName : commonName.trim(),
      'O': 'DropNet',
      'OU': 'Local Transfer',
    };
    final names = List<String>.from(subjectAlternativeNames);

    final generated = await Isolate.run(() {
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privateKeyObject = keyPair.privateKey as RSAPrivateKey;
      final publicKeyObject = keyPair.publicKey as RSAPublicKey;

      final csr = X509Utils.generateRsaCsrPem(
        subject,
        privateKeyObject,
        publicKeyObject,
        san: names,
      );

      final certificatePem = X509Utils.generateSelfSignedCertificate(
        privateKeyObject,
        csr,
        3650,
        sans: names,
        serialNumber: serialNumber,
        notBefore: notBefore,
      );

      final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
        privateKeyObject,
      );

      return (certificatePem: certificatePem, privateKeyPem: privateKeyPem);
    });

    return _PemMaterial(
      certificatePem: generated.certificatePem,
      privateKeyPem: generated.privateKeyPem,
    );
  }

  /// Writes each file to a temporary sibling first and renames it into place,
  /// so a concurrent reader never observes a half-written PEM.
  Future<void> _writeMaterial({
    required _PemMaterial material,
    required File certificate,
    required File privateKey,
    required File meta,
    required List<String> subjectAlternativeNames,
  }) async {
    Future<void> writeAtomically(File target, String contents) async {
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(target.path);
    }

    await writeAtomically(privateKey, material.privateKeyPem);
    await writeAtomically(certificate, material.certificatePem);
    await writeAtomically(
      meta,
      jsonEncode({
        'subjectAlternativeNames': subjectAlternativeNames,
        'generatedAt': DateTime.now().toIso8601String(),
      }),
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

class _PemMaterial {
  const _PemMaterial({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;
}
