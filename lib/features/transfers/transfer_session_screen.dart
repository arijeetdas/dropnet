import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../models/transfer_model.dart';

class TransferSessionScreen extends ConsumerWidget {
  const TransferSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final items = state.transferSessionItems;

    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.size);
    final doneBytes = items.fold<double>(0, (sum, item) {
      if (item.status == TransferStatus.completed) {
        return sum + item.size;
      }
      if (_isTerminal(item.status)) {
        return sum + (item.size * item.progress.clamp(0, 1));
      }
      return sum + (item.size * item.progress.clamp(0, 1));
    });
    final overallProgress = totalBytes == 0 ? 0.0 : (doneBytes / totalBytes).clamp(0.0, 1.0);

    final allDone = items.isNotEmpty && items.every((item) => _isTerminal(item.status));
    final hasErrors = items.any((item) => item.status == TransferStatus.failed || item.status == TransferStatus.canceled);

    return PopScope(
      canPop: allDone,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Transferring files'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (items.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasErrors ? 'Transfer finished with some errors' : (allDone ? 'Transfer successful' : 'Transfer in progress'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: overallProgress, minHeight: 8),
                        const SizedBox(height: 8),
                        Text(
                          'Overall ${(overallProgress * 100).toStringAsFixed(1)}% • ${FileUtils.formatBytes(doneBytes)} / ${FileUtils.formatBytes(totalBytes.toDouble())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Waiting for transfer...'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _statusChip(item.status),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${item.direction == TransferDirection.sent ? 'Sending to' : 'Receiving from'} ${item.deviceName}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: item.progress.clamp(0, 1), minHeight: 7),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(item.progress.clamp(0, 1) * 100).toStringAsFixed(1)}% • ${FileUtils.formatBytes(item.size.toDouble())}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (item.errorMessage != null && item.errorMessage!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Theme(
                                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                      child: ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        childrenPadding: const EdgeInsets.only(bottom: 8),
                                        title: Text(
                                          item.status == TransferStatus.failed ? 'Error details' : 'Details',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(10),
                                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                            ),
                                            child: Text(
                                              item.errorMessage!,
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: allDone
                      ? () {
                          ref.read(appControllerProvider.notifier).closeTransferSession();
                          Navigator.of(context).maybePop();
                        }
                      : null,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isTerminal(TransferStatus status) {
    return status == TransferStatus.completed || status == TransferStatus.failed || status == TransferStatus.canceled;
  }

  Widget _statusChip(TransferStatus status) {
    final (label, icon) = switch (status) {
      TransferStatus.completed => ('Success', Icons.check_circle_rounded),
      TransferStatus.failed => ('Error', Icons.error_rounded),
      TransferStatus.canceled => ('Canceled', Icons.cancel_rounded),
      TransferStatus.transferring => ('Transferring', Icons.sync_rounded),
      TransferStatus.connecting => ('Connecting', Icons.wifi_tethering_rounded),
      TransferStatus.pending => ('Pending', Icons.schedule_rounded),
      TransferStatus.paused => ('Paused', Icons.pause_circle_rounded),
    };

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
