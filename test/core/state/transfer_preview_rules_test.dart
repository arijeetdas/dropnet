import 'package:dropnet/core/state/app_state.dart';
import 'package:dropnet/models/transfer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transfer preview eligibility rules', () {
    test('eligible for single received text file', () {
      final transfer = _transfer(
        fileName: 'note.txt',
        localPath: '/tmp/note.txt',
        sessionFileCount: 1,
      );

      expect(isTransferPreviewEligible(transfer), isTrue);
    });

    test('eligible for single received link file', () {
      final transfer = _transfer(
        fileName: 'shortcut.url',
        localPath: '/tmp/shortcut.url',
        sessionFileCount: 1,
      );

      expect(isTransferPreviewEligible(transfer), isTrue);
    });

    test('not eligible when multiple files are in one session', () {
      final transfer = _transfer(
        fileName: 'note.txt',
        localPath: '/tmp/note.txt',
        sessionFileCount: 2,
      );

      expect(isTransferPreviewEligible(transfer), isFalse);
    });

    test('not eligible for non-received direction', () {
      final transfer = _transfer(
        fileName: 'note.txt',
        localPath: '/tmp/note.txt',
        sessionFileCount: 1,
        direction: TransferDirection.sent,
      );

      expect(isTransferPreviewEligible(transfer), isFalse);
    });

    test('not eligible for non-completed status', () {
      final transfer = _transfer(
        fileName: 'note.txt',
        localPath: '/tmp/note.txt',
        sessionFileCount: 1,
        status: TransferStatus.transferring,
      );

      expect(isTransferPreviewEligible(transfer), isFalse);
    });

    test('not eligible for unsupported extension', () {
      final transfer = _transfer(
        fileName: 'archive.zip',
        localPath: '/tmp/archive.zip',
        sessionFileCount: 1,
      );

      expect(isTransferPreviewEligible(transfer), isFalse);
    });

    test('not eligible when local path is missing', () {
      final transfer = _transfer(
        fileName: 'note.txt',
        localPath: null,
        sessionFileCount: 1,
      );

      expect(isTransferPreviewEligible(transfer), isFalse);
    });
  });
}

TransferModel _transfer({
  required String fileName,
  required String? localPath,
  required int? sessionFileCount,
  TransferDirection direction = TransferDirection.received,
  TransferStatus status = TransferStatus.completed,
}) {
  return TransferModel(
    id: 'id-1',
    fileName: fileName,
    size: 100,
    progress: 1,
    speed: 0,
    status: status,
    deviceName: 'peer',
    startedAt: DateTime(2026),
    direction: direction,
    localPath: localPath,
    sessionFileCount: sessionFileCount,
  );
}
