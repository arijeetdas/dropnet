import 'package:flutter/material.dart';

import '../core/utils/file_utils.dart';
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
    final progressLabel = '${(transfer.progress * 100).toStringAsFixed(1)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(transfer.fileName, style: Theme.of(context).textTheme.titleMedium)),
                if (transfer.verified)
                  const Chip(
                    label: Text('Verified'),
                    avatar: Icon(Icons.verified, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('To/From: ${transfer.deviceName}'),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              tween: Tween(begin: 0, end: transfer.progress.clamp(0, 1)),
              builder: (context, value, child) => LinearProgressIndicator(value: value, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(progressLabel),
                Text(FileUtils.formatBytes(transfer.size)),
              ],
            ),
            const SizedBox(height: 8),
            SpeedIndicator(
              currentSpeed: transfer.speed,
              eta: transfer.eta,
            ),
            if (transfer.status == TransferStatus.transferring && onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
