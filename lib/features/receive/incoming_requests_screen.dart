import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dialog_utils.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/transfer_visuals.dart';
import '../../models/transfer_model.dart';

class IncomingRequestsScreen extends ConsumerStatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  ConsumerState<IncomingRequestsScreen> createState() =>
      _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState
    extends ConsumerState<IncomingRequestsScreen> {
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.05),
              colorScheme.secondary.withValues(alpha: 0.02),
              colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: const Text('Incoming Requests'),
              pinned: true,
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            if (state.pendingIncomingRequests.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No incoming requests',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.separated(
                  itemCount: state.pendingIncomingRequests.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final request = state.pendingIncomingRequests[index];
                    final elapsed = DateTime.now().difference(
                      request.requestedAt,
                    );
                    final remaining =
                        Duration(seconds: timeoutSeconds) - elapsed;
                    final isExpired = remaining.isNegative;
                    final secondsRemaining = remaining.inSeconds.clamp(
                      0,
                      timeoutSeconds,
                    );

                    if (isExpired) {
                      // Auto-reject expired request
                      Future.microtask(() {
                        if (mounted) {
                          controller.rejectIncomingRequest(request.id);
                        }
                      });
                    }

                    final accent = TransferVisuals.accentColor(
                      context,
                      request.fileName,
                    );
                    final isDangerZone = secondsRemaining <= 10;
                    final theme = Theme.of(context);
                    final colorScheme = theme.colorScheme;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.surface,
                            colorScheme.surfaceContainerLow.withValues(
                              alpha: 0.8,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDangerZone
                              ? colorScheme.error.withValues(alpha: 0.4)
                              : colorScheme.primary.withValues(alpha: 0.15),
                          width: isDangerZone ? 2.0 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDangerZone
                                ? colorScheme.error.withValues(alpha: 0.12)
                                : colorScheme.primary.withValues(alpha: 0.04),
                            blurRadius: isDangerZone ? 24 : 16,
                            spreadRadius: isDangerZone ? 2 : 0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Eyebrow badge showing remaining time or expired status
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isExpired
                                            ? [
                                                colorScheme.errorContainer,
                                                colorScheme.errorContainer
                                                    .withValues(alpha: 0.8),
                                              ]
                                            : (isDangerZone
                                                  ? [
                                                      colorScheme
                                                          .errorContainer,
                                                      colorScheme.errorContainer
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                    ]
                                                  : [
                                                      colorScheme
                                                          .primaryContainer
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                      colorScheme
                                                          .primaryContainer
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                    ]),
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              (isDangerZone
                                                      ? colorScheme.error
                                                      : colorScheme.primary)
                                                  .withValues(alpha: 0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isExpired
                                              ? Icons.error_outline_rounded
                                              : Icons.hourglass_top_rounded,
                                          size: 14,
                                          color: isExpired || isDangerZone
                                              ? colorScheme.error
                                              : colorScheme.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isExpired
                                              ? 'Expired'
                                              : '$secondsRemaining s remaining',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: isExpired || isDangerZone
                                                    ? colorScheme.error
                                                    : colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (request.batchFileCount != null &&
                                      request.batchFileCount! > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondaryContainer
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: colorScheme.secondary
                                              .withValues(alpha: 0.2),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Text(
                                        '📦 Batch (${request.batchFileCount} files)',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onSecondaryContainer,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    )
                                  else
                                    Text(
                                      'Incoming Request',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // Device & Sender block
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.08,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.phone_android_rounded,
                                      color: colorScheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request.fromDeviceName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.2,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Sender IP: ${request.fromAddress}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // File Name & Details with accent background
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.12),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            accent.withValues(alpha: 0.2),
                                            accent.withValues(alpha: 0.05),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        TransferVisuals.iconForName(
                                          request.fileName,
                                        ),
                                        color: accent,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            request.fileName,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.onSurface,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatBytes(request.size),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Thicker countdown progress indicator
                              if (!isExpired) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: (secondsRemaining / timeoutSeconds)
                                        .clamp(0, 1),
                                    minHeight: 8,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHigh,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDangerZone
                                          ? colorScheme.error
                                          : colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              // Approve / Reject Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: isExpired
                                          ? null
                                          : () => _showApprovalDialog(
                                              context,
                                              request,
                                              ref,
                                            ),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        foregroundColor: Colors.white,
                                        elevation: 3,
                                        shadowColor: Colors.green.shade600
                                            .withValues(alpha: 0.4),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                      label: const Text(
                                        'Approve',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: isExpired
                                          ? null
                                          : () {
                                              ref
                                                  .read(
                                                    appControllerProvider
                                                        .notifier,
                                                  )
                                                  .rejectIncomingRequest(
                                                    request.id,
                                                  );
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Request rejected',
                                                    ),
                                                    duration: Duration(
                                                      seconds: 2,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: colorScheme
                                            .errorContainer
                                            .withValues(alpha: 0.9),
                                        foregroundColor: colorScheme.error,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                      ),
                                      label: const Text(
                                        'Reject',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileIcon = TransferVisuals.iconForName(request.fileName);
    final accent = TransferVisuals.accentColor(context, request.fileName);

    final approved = await showDropNetDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: colorScheme.surface,
        elevation: 6,
        titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        icon: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            fileIcon,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Approve this transfer?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _infoLine(context, 'File Name', request.fileName),
                      const Divider(height: 24, thickness: 0.5),
                      _infoLine(context, 'Sender', request.fromDeviceName),
                      const Divider(height: 24, thickness: 0.5),
                      _infoLine(
                        context,
                        'Size',
                        FileUtils.formatBytes(request.size),
                      ),
                      if ((request.batchFileCount ?? 0) > 1) ...[
                        const Divider(height: 24, thickness: 0.5),
                        _infoLine(
                          context,
                          'Batch info',
                          'File ${(request.batchIndex ?? 0) + 1} of ${request.batchFileCount}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Approve',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (context.mounted && approved == true) {
      ref
          .read(appControllerProvider.notifier)
          .approveIncomingRequest(request.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request approved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
