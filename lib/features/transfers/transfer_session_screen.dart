import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/transfer_visuals.dart';
import '../../models/transfer_model.dart';
import '../../widgets/wavy_progress_indicators.dart';

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
          title: Text(
            allDone ? 'Transfer Summary' : 'Transfer Session',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.04),
                colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                if (items.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: colorScheme.surfaceContainerLow,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (hasErrors
                                    ? colorScheme.errorContainer
                                    : allDone
                                        ? colorScheme.primaryContainer
                                        : colorScheme.secondaryContainer),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                hasErrors
                                    ? Icons.warning_amber_rounded
                                    : allDone
                                        ? Icons.check_rounded
                                        : Icons.sync_rounded,
                                size: 20,
                                color: (hasErrors
                                    ? colorScheme.onErrorContainer
                                    : allDone
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSecondaryContainer),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hasErrors
                                        ? 'Session completed with issues'
                                        : allDone
                                            ? 'Transfer session completed'
                                            : 'Files are moving right now',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${items.length} file${items.length == 1 ? '' : 's'} in this session',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
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
                        const SizedBox(height: 24),
                        // Premium Bold/Thick Linear Wavy Progress Indicator
                        WavyLinearProgressIndicator(
                          value: overallProgress,
                          strokeWidth: 10.0,
                          waveHeight: 5.0,
                          isTerminal: allDone,
                          terminalColor: hasErrors ? colorScheme.error : Colors.green,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${FileUtils.formatBytes(doneBytes)} of ${FileUtils.formatBytes(totalBytes.toDouble())}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(overallProgress * 100).toStringAsFixed(0)}%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Waiting for transfer...',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final accent = TransferVisuals.accentColor(context, item.fileName);
                            final isSuccess = item.status == TransferStatus.completed;
                            final isFailure = item.status == TransferStatus.failed || item.status == TransferStatus.canceled;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // File Type Icon Container
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      TransferVisuals.iconForName(item.fileName),
                                      color: accent,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // File information
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${item.direction == TransferDirection.sent ? 'To' : 'From'} ${item.deviceName} • ${FileUtils.formatBytes(item.size.toDouble())}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _statusDescription(item),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: isFailure
                                                    ? colorScheme.error
                                                    : isSuccess
                                                        ? Colors.green
                                                        : colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.errorMessage != null && item.errorMessage!.trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(10),
                                              color: colorScheme.errorContainer.withValues(alpha: 0.3),
                                            ),
                                            child: Text(
                                              item.errorMessage!,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onErrorContainer,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Circular Wavy Progress Indicator (Check/Cross on success/fail)
                                  WavyCircularProgressIndicator(
                                    value: item.progress,
                                    isCompleted: isSuccess,
                                    isFailed: isFailure,
                                    size: 32.0,
                                    color: accent,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                // Premium Wavy Done Button Block
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: allDone
                        ? () {
                            ref.read(appControllerProvider.notifier).closeTransferSession();
                            Navigator.of(context).maybePop();
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: EdgeInsets.zero, // padding handles internally
                    ),
                    child: allDone
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Done',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Circular wavy progress on disabled button
                              WavyCircularProgressIndicator(
                                value: overallProgress,
                                size: 20.0,
                                color: colorScheme.onSurface.withValues(alpha: 0.38),
                                strokeWidth: 3.0,
                                waveAmplitude: 1.0,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Waiting for completion (${(overallProgress * 100).toStringAsFixed(0)}%)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colorScheme.onSurface.withValues(alpha: 0.38),
                                ),
                              ),
                            ],
                          ),
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

  String _statusDescription(TransferModel item) {
    if (item.status == TransferStatus.completed) {
      return 'Completed';
    }
    if (item.status == TransferStatus.failed) {
      return 'Failed';
    }
    if (item.status == TransferStatus.canceled) {
      return 'Canceled';
    }
    if (item.status == TransferStatus.connecting) {
      return 'Connecting';
    }
    if (item.status == TransferStatus.pending) {
      return 'Pending';
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
