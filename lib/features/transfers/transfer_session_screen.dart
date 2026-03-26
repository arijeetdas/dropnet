import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/transfer_visuals.dart';
import '../../models/transfer_model.dart';

class TransferSessionScreen extends ConsumerWidget {
  const TransferSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final items = state.transferSessionItems;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
    final completedCount = items.where((item) => item.status == TransferStatus.completed).length;

    return PopScope(
      canPop: allDone,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(allDone ? 'Transfer summary' : 'Transfer session'),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.06),
                colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (items.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: colorScheme.surfaceContainerLow,
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasErrors
                              ? 'Session completed with issues'
                              : allDone
                                  ? 'Transfer session completed'
                                  : 'Files are moving right now',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${items.length} file${items.length == 1 ? '' : 's'} in this session',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _SummaryChip(
                              icon: Icons.check_circle_outline_rounded,
                              label: '$completedCount complete',
                            ),
                            _SummaryChip(
                              icon: Icons.folder_copy_outlined,
                              label: FileUtils.formatBytes(totalBytes.toDouble()),
                            ),
                            _SummaryChip(
                              icon: Icons.tune_rounded,
                              label: '${(overallProgress * 100).toStringAsFixed(1)}% overall',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: overallProgress,
                            minHeight: 10,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${FileUtils.formatBytes(doneBytes)} of ${FileUtils.formatBytes(totalBytes.toDouble())}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Waiting for transfer...',
                            style: theme.textTheme.titleMedium,
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final accent = TransferVisuals.accentColor(context, item.fileName);
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          TransferVisuals.iconForName(item.fileName),
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.fileName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${item.direction == TransferDirection.sent ? 'Sending to' : 'Receiving from'} ${item.deviceName}',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _statusChip(context, item.status),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _SummaryChip(
                                        icon: Icons.category_outlined,
                                        label: TransferVisuals.kindLabel(item.fileName),
                                      ),
                                      _SummaryChip(
                                        icon: Icons.data_object_rounded,
                                        label: FileUtils.formatBytes(item.size.toDouble()),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: item.progress.clamp(0, 1),
                                      minHeight: 8,
                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${(item.progress.clamp(0, 1) * 100).toStringAsFixed(1)}%',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Text(
                                        _statusDescription(item),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.errorMessage != null && item.errorMessage!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: colorScheme.errorContainer.withValues(alpha: 0.42),
                                      ),
                                      child: Text(
                                        item.errorMessage!,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ],
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
                    child: Text(allDone ? 'Done' : 'Waiting for completion'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isTerminal(TransferStatus status) {
    return status == TransferStatus.completed || status == TransferStatus.failed || status == TransferStatus.canceled;
  }

  Widget _statusChip(BuildContext context, TransferStatus status) {
    final (label, icon) = switch (status) {
      TransferStatus.completed => ('Success', Icons.check_circle_rounded),
      TransferStatus.failed => ('Error', Icons.error_rounded),
      TransferStatus.canceled => ('Canceled', Icons.cancel_rounded),
      TransferStatus.transferring => ('Transferring', Icons.sync_rounded),
      TransferStatus.connecting => ('Connecting', Icons.wifi_tethering_rounded),
      TransferStatus.pending => ('Pending', Icons.schedule_rounded),
      TransferStatus.paused => ('Paused', Icons.pause_circle_rounded),
    };

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  String _statusDescription(TransferModel item) {
    if (item.status == TransferStatus.completed) {
      return 'Completed';
    }
    if (item.status == TransferStatus.failed) {
      return 'Needs attention';
    }
    if (item.status == TransferStatus.canceled) {
      return 'Canceled';
    }
    if (item.speed > 0) {
      return FileUtils.formatSpeed(item.speed);
    }
    return 'Preparing';
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
