import 'package:dropnet/core/security/local_tls_certificate_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalTlsCertificateService', () {
    test(
      'concurrent callers all see the same transfer identity',
      () async {
        final services = List.generate(4, (_) => LocalTlsCertificateService());
        final fingerprints = await Future.wait([
          for (final service in services)
            service.readCertificateSha256Fingerprint(),
          services.first
              .createServerContext(
                commonName: 'DropNet Local',
                subjectAlternativeNames: const ['localhost', '127.0.0.1'],
              )
              .then((_) => services.first.readCertificateSha256Fingerprint()),
        ]);
        expect(fingerprints.toSet(), hasLength(1));
        expect(fingerprints.first, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'web server certificates for new IPs never replace the transfer identity',
      () async {
        final service = LocalTlsCertificateService();
        final before = await service.readCertificateSha256Fingerprint();

        // Simulates starting Web Mode on two different networks.
        for (final ip in ['192.168.77.10', '10.20.30.40']) {
          await service.createServerContext(
            commonName: 'DropNet Web Server',
            subjectAlternativeNames: [ip, 'localhost', '127.0.0.1'],
            purpose: TlsCertificatePurpose.webServer,
          );
        }

        final after = await LocalTlsCertificateService()
            .readCertificateSha256Fingerprint();
        expect(after, before);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
