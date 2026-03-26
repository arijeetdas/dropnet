import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../models/transfer_model.dart';

class _HistoryStats {
  const _HistoryStats({
    required this.count,
    required this.totalBytes,
    required this.successCount,
  });

  final int count;
  final int totalBytes;
  final int successCount;
}

class _HistoryNavDestination {
  const _HistoryNavDestination({
    required this.label,
    required this.icon,
    required this.direction,
  });

  final String label;
  final IconData icon;
  final TransferDirection direction;
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryMenuAction { information, deleteFromHistory }

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const _desktopBreakpoint = 900.0;
  static const _destinations = <_HistoryNavDestination>[
    _HistoryNavDestination(
      label: 'Sent',
      icon: Icons.upload_rounded,
      direction: TransferDirection.sent,
    ),
    _HistoryNavDestination(
      label: 'Received',
      icon: Icons.download_rounded,
      direction: TransferDirection.received,
    ),
  ];

  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final isDesktop = MediaQuery.of(context).size.width >= _desktopBreakpoint;

    final sentEntries = state.history
        .where((entry) => entry.direction == TransferDirection.sent)
        .toList(growable: false);
    final receivedEntries = state.history
        .where((entry) => entry.direction == TransferDirection.received)
        .toList(growable: false);

    final sentStats = _computeStats(sentEntries);
    final receivedStats = _computeStats(receivedEntries);

    final isReceivedTab = _selectedTabIndex == 1;
    final activeDirection = isReceivedTab
        ? TransferDirection.received
        : TransferDirection.sent;
    final activeEntries = isReceivedTab ? receivedEntries : sentEntries;
    final activeStats = isReceivedTab ? receivedStats : sentStats;

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey(_selectedTabIndex),
        child: _buildHistoryTab(
          context,
          entries: activeEntries,
          stats: activeStats,
          isReceivedTab: isReceivedTab,
        ),
      ),
    );

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopNavPanel(context),
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const Spacer(),
                          _buildDeleteAllButton(
                            context,
                            direction: activeDirection,
                            enabled: activeEntries.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: _buildDeleteAllButton(
              context,
              direction: activeDirection,
              enabled: activeEntries.isNotEmpty,
            ),
          ),
        ],
      ),
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: _setSelectedTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.upload_rounded),
            label: 'Sent',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_rounded),
            label: 'Received',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopNavPanel(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 260,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            theme.colorScheme.surface.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Back',
                      onPressed: () => _handleBackNavigation(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'History',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < _destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    selected: index == _selectedTabIndex,
                    selectedTileColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.45),
                    leading: Icon(_destinations[index].icon),
                    title: Text(_destinations[index].label),
                    onTap: () => _setSelectedTab(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteAllButton(
    BuildContext context, {
    required TransferDirection direction,
    required bool enabled,
  }) {
    return FilledButton.tonalIcon(
      onPressed: enabled
          ? () => _confirmClearHistory(context, direction: direction)
          : null,
      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
      label: const Text('Delete all'),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  void _setSelectedTab(int index) {
    if (_selectedTabIndex == index) {
      return;
    }
    setState(() => _selectedTabIndex = index);
  }

  void _handleBackNavigation(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/receive');
  }

  Future<void> _confirmClearHistory(
    BuildContext context, {
    required TransferDirection direction,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final tabLabel = direction == TransferDirection.sent ? 'sent' : 'received';

    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_rounded),
        title: Text('Delete all $tabLabel history?'),
        content: Text(
          'This will remove all $tabLabel transfer history entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (clear != true) {
      return;
    }

    await ref
        .read(appControllerProvider.notifier)
        .clearHistoryByDirection(direction);

    if (!mounted) {
      return;
    }

    messenger?.showSnackBar(
      SnackBar(content: Text('All $tabLabel history deleted.')),
    );
  }

  _HistoryStats _computeStats(List<TransferHistoryEntry> entries) {
    var totalBytes = 0;
    var successCount = 0;
    for (final entry in entries) {
      totalBytes += entry.size;
      if (entry.status == TransferStatus.completed) {
        successCount += 1;
      }
    }
    return _HistoryStats(
      count: entries.length,
      totalBytes: totalBytes,
      successCount: successCount,
    );
  }

  Widget _buildHistoryTab(
    BuildContext context, {
    required List<TransferHistoryEntry> entries,
    required _HistoryStats stats,
    required bool isReceivedTab,
  }) {
    if (entries.isEmpty) {
      return _buildEmptyState(context, isReceivedTab: isReceivedTab);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: entries.length + 1,
      separatorBuilder: (context, index) =>
          SizedBox(height: index == 0 ? 12 : 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryCard(
            context,
            stats: stats,
            isReceivedTab: isReceivedTab,
          );
        }

        final entry = entries[index - 1];
        return _buildHistoryCard(
          context,
          entry: entry,
          isReceivedTab: isReceivedTab,
        );
      },
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required _HistoryStats stats,
    required bool isReceivedTab,
  }) {
    final icon = isReceivedTab ? Icons.download_rounded : Icons.upload_rounded;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _summaryMetric(
                context,
                icon: icon,
                label: isReceivedTab ? 'Received' : 'Sent',
                value: '${stats.count}',
              ),
            ),
            _summaryDivider(context),
            Expanded(
              child: _summaryMetric(
                context,
                icon: Icons.data_usage_rounded,
                label: 'Total size',
                value: FileUtils.formatBytes(stats.totalBytes),
              ),
            ),
            _summaryDivider(context),
            Expanded(
              child: _summaryMetric(
                context,
                icon: Icons.check_circle_rounded,
                label: 'Successful',
                value: '${stats.successCount}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: textTheme.titleMedium),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      ],
    );
  }

  Widget _summaryDivider(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: color,
    );
  }

  Widget _buildHistoryCard(
    BuildContext context, {
    required TransferHistoryEntry entry,
    required bool isReceivedTab,
  }) {
    final details =
        '${_formatDateTime(entry.date)} • ${FileUtils.formatBytes(entry.size)}';
    final statusColor = _statusColor(context, entry.status);

    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showInfoDialog(context, entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: statusColor.withValues(alpha: 0.14),
                ),
                child: Icon(
                  _iconForFileType(entry.fileName),
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.fileName,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildStatusPill(context, entry.status),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.deviceName,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_HistoryMenuAction>(
                tooltip: 'Actions',
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (action) =>
                    _handleMenuAction(context, action, entry),
                itemBuilder: (context) => [
                  _menuItem(
                    _HistoryMenuAction.information,
                    Icons.info_outline_rounded,
                    'Information',
                  ),
                  _menuItem(
                    _HistoryMenuAction.deleteFromHistory,
                    Icons.delete_outline_rounded,
                    'Delete from history',
                  ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context, TransferStatus status) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _statusLabel(status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isReceivedTab}) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = isReceivedTab
        ? 'No received transfers yet'
        : 'No sent transfers yet';
    final subtitle = isReceivedTab
        ? 'Files you receive will show up here with details and quick actions.'
        : 'Files you send will show up here with details and delivery status.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReceivedTab
                  ? Icons.download_for_offline_outlined
                  : Icons.upload_file_outlined,
              size: 46,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_HistoryMenuAction> _menuItem(
    _HistoryMenuAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_HistoryMenuAction>(
      value: action,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    _HistoryMenuAction action,
    TransferHistoryEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (action) {
      case _HistoryMenuAction.information:
        await _showInfoDialog(context, entry);
        break;
      case _HistoryMenuAction.deleteFromHistory:
        await ref
            .read(appControllerProvider.notifier)
            .removeHistoryEntry(entry);
        if (!mounted) {
          return;
        }
        messenger?.showSnackBar(
          const SnackBar(content: Text('History entry deleted.')),
        );
        break;
    }
  }

  Future<void> _showInfoDialog(
    BuildContext context,
    TransferHistoryEntry entry,
  ) async {
    final visiblePath = await _resolveVisibleHistoryPath(entry);
    final deviceLabel = entry.direction == TransferDirection.sent
        ? 'Receiver'
        : 'Sender';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('Transfer Information'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoLine(context, 'File name', entry.fileName),
              if (visiblePath != null) ...[
                const SizedBox(height: 10),
                _infoLine(context, 'Path', visiblePath),
              ],
              const SizedBox(height: 10),
              _infoLine(context, 'Size', FileUtils.formatBytes(entry.size)),
              const SizedBox(height: 10),
              _infoLine(context, deviceLabel, entry.deviceName),
              const SizedBox(height: 10),
              _infoLine(
                context,
                'Time',
                _formatDateTime(entry.date, withSeconds: true),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    );
  }

  Future<String?> _resolveVisibleHistoryPath(TransferHistoryEntry entry) async {
    final rawPath = (entry.localPath ?? '').trim();
    final configuredDownloadDirectory = ref
        .read(appControllerProvider)
        .downloadDirectory
        .trim();

    if (rawPath.isEmpty || configuredDownloadDirectory.isEmpty) {
      return null;
    }

    final storedFile = File(rawPath);
    if (!await storedFile.exists()) {
      return null;
    }

    if (_isWithinDirectory(storedFile.path, configuredDownloadDirectory)) {
      return storedFile.path;
    }

    return null;
  }

  bool _isWithinDirectory(String filePath, String directoryPath) {
    final normalizedFilePath = _normalizePathForCompare(filePath);
    final normalizedDirectory = _normalizePathForCompare(directoryPath);
    if (normalizedFilePath.isEmpty || normalizedDirectory.isEmpty) {
      return false;
    }

    return normalizedFilePath == normalizedDirectory ||
        normalizedFilePath.startsWith('$normalizedDirectory/');
  }

  String _normalizePathForCompare(String value) {
    return value
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp('/+'), '/')
        .toLowerCase();
  }

  String _statusLabel(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => 'Success',
      TransferStatus.failed => 'Failed',
      TransferStatus.canceled => 'Canceled',
      TransferStatus.transferring => 'In progress',
      TransferStatus.pending => 'Pending',
      TransferStatus.paused => 'Paused',
      TransferStatus.connecting => 'Connecting',
    };
  }

  IconData _statusIcon(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => Icons.check_circle_rounded,
      TransferStatus.failed => Icons.error_rounded,
      TransferStatus.canceled => Icons.cancel_rounded,
      TransferStatus.transferring => Icons.sync_rounded,
      TransferStatus.pending => Icons.schedule_rounded,
      TransferStatus.paused => Icons.pause_circle_rounded,
      TransferStatus.connecting => Icons.lan_rounded,
    };
  }

  Color _statusColor(BuildContext context, TransferStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      TransferStatus.completed => colorScheme.primary,
      TransferStatus.failed => colorScheme.error,
      TransferStatus.canceled => colorScheme.onSurfaceVariant,
      TransferStatus.transferring => colorScheme.secondary,
      TransferStatus.pending => colorScheme.tertiary,
      TransferStatus.paused => colorScheme.secondary,
      TransferStatus.connecting => colorScheme.tertiary,
    };
  }

  IconData _iconForFileType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    const image = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic'};
    const video = {'.mp4', '.mkv', '.mov', '.avi', '.webm'};
    const audio = {'.mp3', '.wav', '.aac', '.flac', '.ogg', '.m4a'};
    const archive = {'.zip', '.rar', '.7z', '.tar', '.gz'};
    const code = {
      '.dart',
      '.js',
      '.ts',
      '.kt',
      '.swift',
      '.java',
      '.cpp',
      '.c',
      '.py',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
    };
    if (image.contains(ext)) {
      return Icons.image_rounded;
    }
    if (video.contains(ext)) {
      return Icons.movie_rounded;
    }
    if (audio.contains(ext)) {
      return Icons.music_note_rounded;
    }
    if (archive.contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    if (ext == '.pdf') {
      return Icons.picture_as_pdf_rounded;
    }
    if (ext == '.txt') {
      return Icons.description_rounded;
    }
    if (code.contains(ext)) {
      return Icons.code_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _formatDateTime(DateTime date, {bool withSeconds = false}) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (!withSeconds) {
      return '$day/$month/${local.year} $hour:$minute';
    }
    final second = local.second.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute:$second';
  }
}
