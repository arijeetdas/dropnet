import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/file_utils.dart';
import '../../core/state/app_state.dart';
import '../../models/transfer_model.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            tooltip: 'Clear all history',
            onPressed: state.history.isEmpty
                ? null
                : () async {
                    final clear = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear all history?'),
                        content: const Text('This will remove all transfer history entries.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (clear != true) {
                      return;
                    }
                    await ref.read(appControllerProvider.notifier).clearAllHistory();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared.')));
                  },
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: state.history.isEmpty
            ? const Center(child: Text('No transfer history yet.'))
            : ListView.separated(
                itemCount: state.history.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = state.history[index];
                  return Card(
                    child: ListTile(
                      title: Text(entry.fileName),
                      subtitle: Text('${entry.deviceName} • ${entry.date}'),
                      leading: Chip(
                        label: Text(entry.direction == TransferDirection.received ? 'Received' : 'Sent'),
                        avatar: Icon(
                          entry.direction == TransferDirection.received ? Icons.download_rounded : Icons.upload_rounded,
                          size: 16,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(FileUtils.formatBytes(entry.size)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _statusIcon(entry.status),
                                    size: 14,
                                    color: _statusColor(context, entry.status),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(_statusLabel(entry.status)),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Remove entry',
                            onPressed: () async {
                              final remove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Remove entry?'),
                                  content: Text('Remove ${entry.fileName} from history?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
                                  ],
                                ),
                              );
                              if (remove != true) {
                                return;
                              }
                              await ref.read(appControllerProvider.notifier).removeHistoryEntry(entry);
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History entry removed.')));
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      onLongPress: () async {
                        final remove = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Remove entry?'),
                            content: Text('Remove ${entry.fileName} from history?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (remove != true) {
                          return;
                        }
                        await ref.read(appControllerProvider.notifier).removeHistoryEntry(entry);
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History entry removed.')));
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _statusLabel(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => 'Success',
      TransferStatus.failed => 'Failed',
      TransferStatus.canceled => 'Canceled',
      _ => status.name,
    };
  }

  IconData _statusIcon(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => Icons.check_circle_rounded,
      TransferStatus.failed => Icons.error_rounded,
      TransferStatus.canceled => Icons.cancel_rounded,
      _ => Icons.timelapse_rounded,
    };
  }

  Color _statusColor(BuildContext context, TransferStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      TransferStatus.completed => colorScheme.primary,
      TransferStatus.failed => colorScheme.error,
      TransferStatus.canceled => colorScheme.onSurfaceVariant,
      _ => colorScheme.onSurfaceVariant,
    };
  }
}
