import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/transfer_visuals.dart';
import '../../models/transfer_model.dart';

class IncomingRequestsScreen extends ConsumerStatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  ConsumerState<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends ConsumerState<IncomingRequestsScreen> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Refresh UI every second to update timeouts
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final timeoutSeconds = state.incomingRequestTimeoutSeconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming Requests'),
      ),
      body: state.pendingIncomingRequests.isEmpty
          ? Center(
              child: Text(
                'No incoming requests',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.pendingIncomingRequests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final request = state.pendingIncomingRequests[index];
                final elapsed = DateTime.now().difference(request.requestedAt);
                final remaining = Duration(seconds: timeoutSeconds) - elapsed;
                final isExpired = remaining.isNegative;
                final secondsRemaining = remaining.inSeconds.clamp(0, timeoutSeconds);

                if (isExpired) {
                  // Auto-reject expired request
                  Future.microtask(() {
                    if (mounted) {
                      controller.rejectIncomingRequest(request.id);
                    }
                  });
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Device info
                        Row(
                          children: [
                            Icon(
                              Icons.devices_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.fromDeviceName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    request.fromAddress,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // File info
                        Row(
                          children: [
                            Icon(
                              Icons.file_present_rounded,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.fileName,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatBytes(request.size),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Timeout progress
                        if (!isExpired)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Expires in',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    '$secondsRemaining s',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: secondsRemaining <= 10
                                              ? Theme.of(context).colorScheme.error
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (secondsRemaining / timeoutSeconds).clamp(0, 1),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Request expired',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isExpired
                                    ? null
                                    : () => _showApprovalDialog(context, request, ref),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Approve'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isExpired
                                    ? null
                                    : () {
                                        ref.read(appControllerProvider.notifier)
                                            .rejectIncomingRequest(request.id);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Request rejected'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.errorContainer,
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Reject'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  Future<void> _showApprovalDialog(
    BuildContext context,
    IncomingTransferRequest request,
    WidgetRef ref,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Approve this transfer?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.fileName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: TransferVisuals.accentColor(context, request.fileName),
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text(
                'From: ${request.fromDeviceName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Size: ${FileUtils.formatBytes(request.size)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if ((request.batchFileCount ?? 0) > 1) ...[
                const SizedBox(height: 4),
                Text(
                  'File ${(request.batchIndex ?? 0) + 1} of ${request.batchFileCount}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (mounted && approved == true) {
      ref.read(appControllerProvider.notifier).approveIncomingRequest(request.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request approved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
