import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropnet/app.dart';
import 'package:dropnet/core/state/app_state.dart';
import 'package:dropnet/core/networking/discovery_service.dart';
import 'package:dropnet/core/networking/tcp_transfer_service.dart';
import 'package:dropnet/models/device_model.dart';
import 'package:dropnet/models/transfer_model.dart';

class MockDiscoveryService extends DiscoveryService {
  @override
  Future<void> start() async {}
  @override
  Future<void> updatePairingModeEnabled(bool enabled) async {}
  @override
  Future<void> updateCustomDeviceType(dynamic type) async {}
  @override
  Stream<List<DeviceModel>> get devicesStream => const Stream.empty();
  @override
  String get deviceName => 'MockDevice';
  @override
  String get manufacturerTag => '';
  @override
  String get platformTag => 'iOS';
  @override
  String get deviceId => 'mock-id';
  @override
  String get localTlsCertificateSha256 => 'mock-fingerprint';
  @override
  Future<String> getLocalIp({String? preferredPeerIp}) async => '127.0.0.1';
  @override
  Future<List<String>> getAllLocalIps() async => ['127.0.0.1'];
}

class MockTcpTransferService extends TcpTransferService {
  @override
  Future<void> startReceiver({required String saveDirectory, int port = 45455}) async {}
  @override
  Future<void> stopReceiver() async {}
  @override
  Stream<List<TransferModel>> get activeTransfersStream => const Stream.empty();
  @override
  Stream<TransferModel> get completedTransfersStream => const Stream.empty();
  @override
  Stream<List<IncomingTransferRequest>> get incomingRequestsStream => const Stream.empty();
  @override
  Stream<List<IncomingPairingRequest>> get incomingPairingRequestsStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Set up mock method channel for path_provider
  const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
  
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory') {
        return '/tmp';
      }
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/documents';
      }
      if (methodCall.method == 'getDownloadsDirectory') {
        return '/tmp/downloads';
      }
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('iOS/macOS flow - open text dialog, enter text, and add', (WidgetTester tester) async {
    await tester.runAsync(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferences.setMockInitialValues({
        'onboarding.completed': true,
        'settings.downloadDirectory': '',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryServiceProvider.overrideWithValue(MockDiscoveryService()),
            tcpTransferServiceProvider.overrideWithValue(MockTcpTransferService()),
          ],
          child: const DropNetApp(),
        ),
      );

      // Robustly poll for boot/loading to complete
      bool booted = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('Receive').evaluate().isNotEmpty) {
          booted = true;
          break;
        }
      }

      expect(booted, isTrue, reason: 'App did not finish booting');

      // Tap on the Send icon in the navigation scaffold (Go to /send)
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      // Verify we are on the Send screen
      expect(find.text('Text'), findsOneWidget);

      // Tap "Text" action button
      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // open animation for dialog

      // Verify Add text dialog is open
      expect(find.text('Add text'), findsOneWidget);

      // Type text in TextField
      await tester.enterText(find.byType(TextField), 'Testing shared text contents');
      await tester.pump();

      // Tap the "Add" button
      await tester.tap(find.text('Add'));
      
      // Pump to close dialog animation, and let filesytem writing resolve
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // close animation
      
      // Let real filesystem operations process
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      // Verify dialog is dismissed
      expect(find.text('Add text'), findsNothing);

      // Verify the text is added
      expect(find.textContaining('dropnet_text'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
