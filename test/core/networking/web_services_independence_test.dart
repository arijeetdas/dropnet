import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dropnet/core/networking/discovery_service.dart';
import 'package:dropnet/core/networking/tcp_transfer_service.dart';
import 'package:dropnet/core/networking/temporary_link_share_service.dart';
import 'package:dropnet/core/networking/web_server_service.dart';
import 'package:dropnet/core/platform/media_store_service.dart';
import 'package:dropnet/core/platform/share_intent_service.dart';
import 'package:dropnet/core/state/app_state.dart';

class _FakeDiscoveryService extends DiscoveryService {
  _FakeDiscoveryService();

  @override
  Future<String> getLocalIp({String? preferredPeerIp}) async {
    return '127.0.0.1';
  }
}

void main() {
  group('Web services mutual exclusion', () {
    late Directory rootDir;
    late File sample;
    late AppController controller;

    setUp(() async {
      rootDir = await Directory.systemTemp.createTemp('dropnet-web-test-');
      sample = File('${rootDir.path}${Platform.pathSeparator}sample.txt');
      await sample.writeAsString('hello dropnet');

      controller = AppController(
        discovery: _FakeDiscoveryService(),
        transfer: TcpTransferService(),
        web: WebServerService(),
        tempShare: TemporaryLinkShareService(),
        shareIntent: ShareIntentService(),
        mediaStore: const MediaStoreService(),
      );
    });

    tearDown(() async {
      await controller.stopTemporaryLinkShare();
      await controller.stopWebShare();
      controller.dispose();
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test(
      'starting temporary share is blocked when web server is running',
      () async {
        await controller.startWebShare();
        expect(controller.state.webState.running, isTrue);

        await expectLater(
          () => controller.startTemporaryLinkShare(
            filePaths: <String>[sample.path],
          ),
          throwsA(isA<StateError>()),
        );

        expect(controller.state.webState.running, isTrue);
        expect(controller.state.tempLinkShare.running, isFalse);
      },
    );

    test(
      'starting web server is blocked when temporary share is running',
      () async {
        await controller.startTemporaryLinkShare(
          filePaths: <String>[sample.path],
        );
        expect(controller.state.tempLinkShare.running, isTrue);

        await expectLater(
          () => controller.startWebShare(),
          throwsA(isA<StateError>()),
        );

        expect(controller.state.tempLinkShare.running, isTrue);
        expect(controller.state.webState.running, isFalse);
      },
    );

    test(
      'startTemporaryLinkShare can replace running web server when requested',
      () async {
        await controller.startWebShare();
        expect(controller.state.webState.running, isTrue);

        await controller.startTemporaryLinkShare(
          filePaths: <String>[sample.path],
          stopWebShareIfRunning: true,
        );

        expect(controller.state.webState.running, isFalse);
        expect(controller.state.tempLinkShare.running, isTrue);
      },
    );

    test(
      'startWebShare can replace running temporary share when requested',
      () async {
        await controller.startTemporaryLinkShare(
          filePaths: <String>[sample.path],
        );
        expect(controller.state.tempLinkShare.running, isTrue);

        await controller.startWebShare(stopTemporaryShareIfRunning: true);

        expect(controller.state.tempLinkShare.running, isFalse);
        expect(controller.state.webState.running, isTrue);
      },
    );
  });
}
