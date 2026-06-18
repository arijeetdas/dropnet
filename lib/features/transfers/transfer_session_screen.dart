import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/dialog_utils.dart';
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

    final groupedItems = <String, List<TransferModel>>{};
    for (final item in items) {
      final key = item.deviceName.trim().isEmpty ? 'Unknown Device' : item.deviceName.trim();
      groupedItems.putIfAbsent(key, () => []).add(item);
    }

    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.size);
    final sessionTotalBytes = items.isNotEmpty
        ? (items.map((item) => item.sessionTotalBytes).firstWhere((b) => b != null, orElse: () => 0) ?? 0)
        : 0;
    final effectiveTotalBytes = sessionTotalBytes > 0 ? sessionTotalBytes : totalBytes;

    final doneBytes = items.fold<double>(0, (sum, item) {
      if (item.status == TransferStatus.completed) {
        return sum + item.size;
      }
      return sum + (item.size * item.progress.clamp(0, 1));
    });
    final overallProgress = effectiveTotalBytes == 0 ? 0.0 : (doneBytes / effectiveTotalBytes).clamp(0.0, 1.0);

    final expectedCount = items.isEmpty
        ? 0
        : (items.map((item) => item.sessionFileCount).firstWhere((c) => c != null, orElse: () => 1) ?? 1);

    final isCancelled = items.any((item) => item.status == TransferStatus.canceled);
    final hasErrors = items.any((item) => item.status == TransferStatus.failed || item.status == TransferStatus.canceled);
    final completedCount = items.where((item) => item.status == TransferStatus.completed).length;

    // A session is completed only when all expected items are terminal, or we have terminal failures
    final allDone = items.isNotEmpty && (
      hasErrors ||
      (items.length >= expectedCount && items.every((item) => _isTerminal(item.status)))
    );

    final currentSpeed = items.fold<double>(0, (sum, item) {
      if (item.status == TransferStatus.transferring) {
        return sum + item.speed;
      }
      return sum;
    });

    final boxBorderColor = allDone
        ? Colors.transparent
        : colorScheme.outlineVariant.withValues(alpha: 0.4);
    final textThemeColor = allDone ? Colors.white : colorScheme.onSurface;
    final subTextThemeColor = allDone ? Colors.white.withValues(alpha: 0.8) : colorScheme.onSurfaceVariant;

    return PopScope(
      canPop: allDone,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 90,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: allDone
                    ? (hasErrors
                        ? [colorScheme.errorContainer.withValues(alpha: 0.95), colorScheme.errorContainer.withValues(alpha: 0.8)]
                        : [Colors.green.shade100, Colors.green.shade50])
                    : [colorScheme.primaryContainer.withValues(alpha: 0.95), colorScheme.surfaceContainerHigh.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: allDone
                    ? (hasErrors ? colorScheme.error.withValues(alpha: 0.3) : Colors.green.shade300)
                    : colorScheme.primary.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!allDone) ...[
                  WavyCircularProgressIndicator(
                    value: overallProgress,
                    size: 20.0,
                    color: colorScheme.primary,
                    strokeWidth: 3.0,
                    waveAmplitude: 0.8,
                  ),
                  const SizedBox(width: 14),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      allDone ? 'Transfer Summary' : 'Transfer Session',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: allDone
                            ? (isCancelled
                                ? colorScheme.onSurfaceVariant
                                : (hasErrors ? colorScheme.onErrorContainer : Colors.green.shade900))
                            : colorScheme.onPrimaryContainer,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      allDone
                          ? (isCancelled
                              ? 'TRANSFER CANCELLED'
                              : (hasErrors ? 'FINISHED WITH ISSUES' : 'COMPLETED SUCCESSFULLY'))
                          : 'SYNCING ${(overallProgress * 100).toStringAsFixed(0)}% • SECURE EXPRESS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: allDone
                            ? (isCancelled
                                ? colorScheme.onSurfaceVariant
                                : (hasErrors ? colorScheme.error : Colors.green.shade700))
                            : colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          centerTitle: true,
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
                // Scrollable File list at the top, aligned to bottom of this container and reversing order
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
                      : (state.parallelSendingEnabled
                          ? ListView.separated(
                              itemCount: groupedItems.length,
                              padding: const EdgeInsets.fromLTRB(0, 135, 0, 8),
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final key = groupedItems.keys.elementAt(index);
                                final deviceItems = groupedItems[key]!;
                                return _DeviceProgressCard(
                                  deviceName: key,
                                  items: deviceItems,
                                  colorScheme: colorScheme,
                                  theme: theme,
                                );
                              },
                            )
                          : ListView.separated(
                              reverse: true, // stacks from the bottom upwards
                              itemCount: items.length,
                              padding: const EdgeInsets.fromLTRB(0, 135, 0, 8),
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final accent = TransferVisuals.accentColor(context, item.fileName);
                                final isSuccess = item.status == TransferStatus.completed;
                                final isFailure = item.status == TransferStatus.failed || item.status == TransferStatus.canceled;

                                return _AnimatedFileItemTile(
                                  key: ValueKey(item.id),
                                  item: item,
                                  accent: accent,
                                  isSuccess: isSuccess,
                                  isFailure: isFailure,
                                  colorScheme: colorScheme,
                                  theme: theme,
                                );
                              },
                            )),
                ),
                const SizedBox(height: 16),

                // Premium Animated overall progress box above the done button
                if (items.isNotEmpty)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeInOut,
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: allDone ? null : colorScheme.surfaceContainerLow,
                      gradient: allDone
                          ? LinearGradient(
                              colors: isCancelled
                                  ? [const Color(0xFF78909C), const Color(0xFF455A64)]
                                  : (hasErrors
                                      ? [const Color(0xFFE53935), const Color(0xFFB71C1C)]
                                      : [const Color(0xFF43A047), const Color(0xFF1B5E20)]),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: allDone
                              ? (isCancelled
                                  ? const Color(0xFF78909C).withValues(alpha: 0.25)
                                  : (hasErrors
                                      ? const Color(0xFFE53935).withValues(alpha: 0.25)
                                      : const Color(0xFF43A047).withValues(alpha: 0.25)))
                              : Colors.black.withValues(alpha: 0.03),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(
                        color: boxBorderColor,
                        width: allDone ? 0.0 : 1.0,
                      ),
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.fastOutSlowIn,
                      child: Column(
                        crossAxisAlignment: allDone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                        children: [
                          if (allDone) ...[
                            // Stunning Hero completed state
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isCancelled
                                        ? Icons.cancel_rounded
                                        : (hasErrors ? Icons.close_rounded : Icons.check_rounded),
                                    size: 44,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isCancelled
                                      ? 'Transfer Cancelled'
                                      : (hasErrors ? 'Session Finished with Issues' : 'All Files Transferred!'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontSize: 20,
                                    letterSpacing: -0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isCancelled
                                      ? 'The transfer session was cancelled.'
                                      : (hasErrors
                                          ? 'Some files failed or were canceled.'
                                          : 'All $expectedCount files were successfully shared.'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ] else ...[
                            // Detailed transferring state
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.sync_rounded,
                                    size: 22,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Transfer Session in Progress',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: textThemeColor,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$completedCount of $expectedCount files completed',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: subTextThemeColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _SummaryChip(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: '$completedCount / $expectedCount files',
                                ),
                                _SummaryChip(
                                  icon: Icons.folder_copy_outlined,
                                  label: FileUtils.formatBytes(effectiveTotalBytes.toDouble()),
                                ),
                                if (currentSpeed > 0)
                                  _SummaryChip(
                                    icon: Icons.speed_rounded,
                                    label: FileUtils.formatSpeed(currentSpeed),
                                  )
                                else
                                  _SummaryChip(
                                    icon: Icons.tune_rounded,
                                    label: '${(overallProgress * 100).toStringAsFixed(1)}%',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            WavyLinearProgressIndicator(
                              value: overallProgress,
                              strokeWidth: 10.0,
                              waveHeight: 5.0,
                              isTerminal: false,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${FileUtils.formatBytes(doneBytes)} of ${FileUtils.formatBytes(effectiveTotalBytes.toDouble())}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: subTextThemeColor,
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
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Premium Action Buttons Row (with smooth width extension)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: allDone
                                ? [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: FilledButton(
                            onPressed: allDone
                                ? () {
                                    ref.read(appControllerProvider.notifier).closeTransferSession();
                                    Navigator.of(context).maybePop();
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)),
                              backgroundColor: allDone ? colorScheme.primary : colorScheme.surfaceContainerHigh,
                              foregroundColor: allDone ? colorScheme.onPrimary : colorScheme.onSurface.withValues(alpha: 0.38),
                              padding: EdgeInsets.zero,
                              elevation: 0,
                            ),
                            child: allDone
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'Finish Session',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      WavyCircularProgressIndicator(
                                        value: overallProgress,
                                        size: 22.0,
                                        color: colorScheme.onSurface.withValues(alpha: 0.38),
                                        strokeWidth: 3.5,
                                        waveAmplitude: 1.0,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Transferring (${(overallProgress * 100).toStringAsFixed(0)}%)',
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
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: allDone ? 0 : 12,
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      width: allDone ? 0 : 150,
                      height: 58,
                      child: ClipRect(
                        child: OverflowBox(
                          minWidth: 150,
                          maxWidth: 150,
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirm = await showDropNetDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  backgroundColor: colorScheme.surface,
                                  elevation: 6,
                                  titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                                  actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                                  icon: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          colorScheme.errorContainer,
                                          colorScheme.errorContainer.withValues(alpha: 0.5),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.error.withValues(alpha: 0.15),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: colorScheme.onErrorContainer,
                                      size: 32,
                                    ),
                                  ),
                                  title: Text(
                                    'Cancel Transfer?',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  content: SizedBox(
                                    width: 320,
                                    child: Card(
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
                                        child: Text(
                                          'Are you sure you want to cancel the transfer session? Partially received files will be deleted.',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
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
                                              'No',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: () => Navigator.of(context).pop(true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: colorScheme.error,
                                              foregroundColor: colorScheme.onError,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                            ),
                                            child: const Text(
                                              'Yes, Cancel',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final sessionId = items.firstOrNull?.sessionId;
                                if (sessionId != null) {
                                  await ref.read(appControllerProvider.notifier).cancelTransferSession(sessionId);
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
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
      ),
    );
  }

  static bool _isTerminal(TransferStatus status) {
    return status == TransferStatus.completed || status == TransferStatus.failed || status == TransferStatus.canceled;
  }
}

class _DeviceProgressCard extends StatefulWidget {
  const _DeviceProgressCard({
    required this.deviceName,
    required this.items,
    required this.colorScheme,
    required this.theme,
  });

  final String deviceName;
  final List<TransferModel> items;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  State<_DeviceProgressCard> createState() => _DeviceProgressCardState();
}

class _DeviceProgressCardState extends State<_DeviceProgressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final colorScheme = widget.colorScheme;
    final items = widget.items;

    final totalSize = items.fold<int>(0, (sum, i) => sum + i.size);
    final doneBytes = items.fold<double>(0.0, (sum, i) {
      if (i.status == TransferStatus.completed) return sum + i.size;
      return sum + (i.size * i.progress.clamp(0.0, 1.0));
    });
    final progress = totalSize == 0 ? 0.0 : (doneBytes / totalSize).clamp(0.0, 1.0);
    final speed = items.fold<double>(0.0, (sum, i) => i.status == TransferStatus.transferring ? sum + i.speed : sum);

    final completedCount = items.where((i) => i.status == TransferStatus.completed).length;
    final totalCount = items.length;

    var status = TransferStatus.connecting;
    if (items.any((i) => i.status == TransferStatus.failed)) {
      status = TransferStatus.failed;
    } else if (items.any((i) => i.status == TransferStatus.canceled)) {
      status = TransferStatus.canceled;
    } else if (items.any((i) => i.status == TransferStatus.transferring)) {
      status = TransferStatus.transferring;
    } else if (items.every((i) => i.status == TransferStatus.completed)) {
      status = TransferStatus.completed;
    }

    final isSuccess = status == TransferStatus.completed;
    final isFailure = status == TransferStatus.failed || status == TransferStatus.canceled;

    final statusColor = isSuccess
        ? Colors.green
        : isFailure
            ? colorScheme.error
            : colorScheme.primary;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSuccess
              ? Colors.green.withValues(alpha: 0.25)
              : isFailure
                  ? colorScheme.error.withValues(alpha: 0.25)
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == TransferStatus.completed
                          ? Icons.devices_rounded
                          : status == TransferStatus.transferring
                              ? Icons.sync_rounded
                              : status == TransferStatus.connecting
                                  ? Icons.hourglass_empty_rounded
                                  : Icons.error_outline_rounded,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.deviceName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$completedCount / $totalCount files completed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (speed > 0) ...[
                              Text(
                                '•',
                                style: TextStyle(color: colorScheme.outline),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                FileUtils.formatSpeed(speed),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        WavyLinearProgressIndicator(
                          value: progress,
                          strokeWidth: 6.0,
                          waveHeight: 3.0,
                          isTerminal: isSuccess || isFailure,
                          color: statusColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final accent = TransferVisuals.accentColor(context, item.fileName);
                  final isItemSuccess = item.status == TransferStatus.completed;
                  final isItemFailure = item.status == TransferStatus.failed || item.status == TransferStatus.canceled;

                  return _AnimatedFileItemTile(
                    key: ValueKey(item.id),
                    item: item,
                    accent: accent,
                    isSuccess: isItemSuccess,
                    isFailure: isItemFailure,
                    colorScheme: colorScheme,
                    theme: theme,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
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

class _AnimatedFileItemTile extends StatefulWidget {
  const _AnimatedFileItemTile({
    required Key key,
    required this.item,
    required this.accent,
    required this.isSuccess,
    required this.isFailure,
    required this.colorScheme,
    required this.theme,
  }) : super(key: key);

  final TransferModel item;
  final Color accent;
  final bool isSuccess;
  final bool isFailure;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  State<_AnimatedFileItemTile> createState() => _AnimatedFileItemTileState();
}

class _AnimatedFileItemTileState extends State<_AnimatedFileItemTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _opacityAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = widget.colorScheme;
    final theme = widget.theme;

    return FadeTransition(
      opacity: _opacityAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: widget.accent.withValues(alpha: 0.16),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              // File Type Icon Container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  TransferVisuals.iconForName(item.fileName),
                  color: widget.accent,
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
                            color: widget.isFailure
                                ? colorScheme.error
                                : widget.isSuccess
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
                isCompleted: widget.isSuccess,
                isFailed: widget.isFailure,
                size: 32.0,
                color: widget.accent,
              ),
            ],
          ),
        ),
      ),
    );
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
