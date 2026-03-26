import 'package:flutter/material.dart';

import '../core/utils/file_utils.dart';
import '../core/utils/transfer_visuals.dart';
import '../models/transfer_model.dart';
import 'speed_indicator.dart';

class TransferProgressCard extends StatelessWidget {
  const TransferProgressCard({
    super.key,
    required this.transfer,
    this.onCancel,
  });

  final TransferModel transfer;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = transfer.progress.clamp(0.0, 1.0).toDouble();
    final progressLabel = '${(progress * 100).toStringAsFixed(1)}%';
    final accent = TransferVisuals.accentColor(context, transfer.fileName);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.08),
              colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      TransferVisuals.iconForName(transfer.fileName),
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transfer.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${transfer.direction == TransferDirection.sent ? 'Sending to' : 'Receiving from'} ${transfer.deviceName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (transfer.verified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Verified'),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TransferMetaPill(label: TransferVisuals.kindLabel(transfer.fileName)),
                  _TransferMetaPill(label: FileUtils.formatBytes(transfer.size.toDouble())),
                  _TransferMetaPill(label: _statusLabel(transfer.status)),
                ],
              ),
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 280),
                tween: Tween(begin: 0, end: progress),
                builder: (context, value, child) => ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(progressLabel, style: theme.textTheme.titleSmall),
                  Text(
                    FileUtils.formatSpeed(transfer.speed),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SpeedIndicator(
                currentSpeed: transfer.speed,
                eta: transfer.eta,
              ),
              if (transfer.status == TransferStatus.transferring && onCancel != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(TransferStatus status) {
    return switch (status) {
      TransferStatus.pending => 'Pending',
      TransferStatus.connecting => 'Connecting',
      TransferStatus.transferring => 'Transferring',
      TransferStatus.paused => 'Paused',
      TransferStatus.completed => 'Completed',
      TransferStatus.canceled => 'Canceled',
      TransferStatus.failed => 'Failed',
    };
  }
}

class _TransferMetaPill extends StatelessWidget {
  const _TransferMetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
