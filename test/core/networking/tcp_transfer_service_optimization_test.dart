import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dropnet/core/networking/tcp_transfer_service.dart';
import 'package:dropnet/models/device_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TcpTransferService optimization smoke tests', () {
    test('single-device transfer remains reliable and verified', () async {
      final sender = TcpTransferService();
      final receiver = TcpTransferService();
      final tempRoot = await Directory.systemTemp.createTemp('dropnet_single_');
      final sourceDir = Directory('${tempRoot.path}${Platform.pathSeparator}src')..createSync(recursive: true);
      final receiverDir = Directory('${tempRoot.path}${Platform.pathSeparator}dst')..createSync(recursive: true);

      final sourceFile = await _createRandomFile(
        sourceDir,
        'single.bin',
        768 * 1024,
      );

      final incomingSub = receiver.incomingRequestsStream.listen((requests) {
        for (final request in requests) {
          receiver.approveIncomingRequest(request.id);
        }
      });

      await receiver.startReceiver(saveDirectory: receiverDir.path, port: 45501);

      final target = _device('127.0.0.1', 'receiver-single');
      await sender.sendFiles(
        target: target,
        filePaths: [sourceFile.path],
        senderDeviceName: 'sender-single',
        port: 45501,
      );

      final receivedFile = File('${receiverDir.path}${Platform.pathSeparator}${sourceFile.uri.pathSegments.last}');
      expect(await receivedFile.exists(), isTrue);
      expect(await receivedFile.length(), await sourceFile.length());
      expect(await _sha(receivedFile), await _sha(sourceFile));

      await incomingSub.cancel();
      await sender.dispose();
      await receiver.dispose();
      await tempRoot.delete(recursive: true);
    });

    test('multi-file session asks approval once and transfers all files', () async {
      final sender = TcpTransferService();
      final receiver = TcpTransferService();
      final tempRoot = await Directory.systemTemp.createTemp('dropnet_batch_');
      final sourceDir = Directory('${tempRoot.path}${Platform.pathSeparator}src')..createSync(recursive: true);
      final receiverDir = Directory('${tempRoot.path}${Platform.pathSeparator}dst')..createSync(recursive: true);

      final sourceFiles = <File>[];
      for (var index = 0; index < 8; index++) {
        sourceFiles.add(await _createRandomFile(sourceDir, 'batch_$index.dat', 200 * 1024 + (index * 4096)));
      }

      var approvalPrompts = 0;
      final seenRequestIds = <String>{};
      final incomingSub = receiver.incomingRequestsStream.listen((requests) {
        for (final request in requests) {
          if (seenRequestIds.add(request.id)) {
            approvalPrompts++;
          }
          receiver.approveIncomingRequest(request.id);
        }
      });

      await receiver.startReceiver(saveDirectory: receiverDir.path, port: 45502);

      final target = _device('127.0.0.1', 'receiver-batch');
      await sender.sendFiles(
        target: target,
        filePaths: sourceFiles.map((file) => file.path).toList(growable: false),
        senderDeviceName: 'sender-batch',
        port: 45502,
      );

      expect(approvalPrompts, 1, reason: 'Batch transfer should require only one approval prompt per session.');

      for (final file in sourceFiles) {
        final name = file.uri.pathSegments.last;
        final received = File('${receiverDir.path}${Platform.pathSeparator}$name');
        expect(await received.exists(), isTrue, reason: 'Missing received file: $name');
        expect(await _sha(received), await _sha(file), reason: 'Checksum mismatch for $name');
      }

      await incomingSub.cancel();
      await sender.dispose();
      await receiver.dispose();
      await tempRoot.delete(recursive: true);
    });

    test('parallel multi-target transfers remain stable with strong throughput', () async {
      final sender = TcpTransferService();
      final receiverA = TcpTransferService();
      final receiverB = TcpTransferService();

      final tempRoot = await Directory.systemTemp.createTemp('dropnet_multi_target_');
      final sourceDir = Directory('${tempRoot.path}${Platform.pathSeparator}src')..createSync(recursive: true);
      final dstA = Directory('${tempRoot.path}${Platform.pathSeparator}dstA')..createSync(recursive: true);
      final dstB = Directory('${tempRoot.path}${Platform.pathSeparator}dstB')..createSync(recursive: true);

      final files = <File>[
        await _createRandomFile(sourceDir, 'stress_1.bin', 2 * 1024 * 1024),
        await _createRandomFile(sourceDir, 'stress_2.bin', 2 * 1024 * 1024),
        await _createRandomFile(sourceDir, 'stress_3.bin', 2 * 1024 * 1024),
      ];

      final subA = receiverA.incomingRequestsStream.listen((requests) {
        for (final request in requests) {
          receiverA.approveIncomingRequest(request.id);
        }
      });
      final subB = receiverB.incomingRequestsStream.listen((requests) {
        for (final request in requests) {
          receiverB.approveIncomingRequest(request.id);
        }
      });

      await receiverA.startReceiver(saveDirectory: dstA.path, port: 45503);
      await receiverB.startReceiver(saveDirectory: dstB.path, port: 45504);

      final paths = files.map((file) => file.path).toList(growable: false);
      final totalBytes = files.fold<int>(0, (sum, file) => sum + file.lengthSync()) * 2;
      final stopwatch = Stopwatch()..start();

      await Future.wait([
        sender.sendFiles(
          target: _device('127.0.0.1', 'receiver-A'),
          filePaths: paths,
          senderDeviceName: 'sender-multi',
          port: 45503,
        ),
        sender.sendFiles(
          target: _device('127.0.0.1', 'receiver-B'),
          filePaths: paths,
          senderDeviceName: 'sender-multi',
          port: 45504,
        ),
      ]);

      stopwatch.stop();
      final seconds = max(1, stopwatch.elapsedMilliseconds) / 1000;
      final throughputMbPerSec = (totalBytes / (1024 * 1024)) / seconds;

      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final outA = File('${dstA.path}${Platform.pathSeparator}$name');
        final outB = File('${dstB.path}${Platform.pathSeparator}$name');
        expect(await outA.exists(), isTrue, reason: 'receiver A missing $name');
        expect(await outB.exists(), isTrue, reason: 'receiver B missing $name');
        final sourceSha = await _sha(file);
        expect(await _sha(outA), sourceSha, reason: 'receiver A checksum mismatch for $name');
        expect(await _sha(outB), sourceSha, reason: 'receiver B checksum mismatch for $name');
      }

      expect(throughputMbPerSec, greaterThan(1.5), reason: 'Throughput unexpectedly low on localhost benchmark.');

      await subA.cancel();
      await subB.cancel();
      await sender.dispose();
      await receiverA.dispose();
      await receiverB.dispose();
      await tempRoot.delete(recursive: true);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

DeviceModel _device(String ip, String id) {
  return DeviceModel(
    deviceId: id,
    deviceName: id,
    manufacturer: 'test',
    platform: 'TestOS',
    ipAddress: ip,
    deviceType: DeviceType.desktop,
    isOnline: true,
    lastSeen: DateTime.now(),
  );
}

Future<File> _createRandomFile(Directory dir, String name, int bytes) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  final random = Random(42 + bytes + name.length);
  final data = List<int>.generate(bytes, (_) => random.nextInt(256), growable: false);
  await file.writeAsBytes(data, flush: true);
  return file;
}

Future<String> _sha(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
