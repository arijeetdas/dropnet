import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/android_installed_apps_service.dart';
import '../../core/platform/media_store_service.dart';
import '../../core/networking/temporary_link_share_service.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/dialog_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../models/device_model.dart';
import '../../widgets/macos_smiling_logo.dart';
import '../../widgets/adaptive_nav_scaffold.dart';
import '../../widgets/pairing_code_dialog.dart';
import '../../widgets/tab_shell_scope.dart';
import '../../widgets/expressive_loader.dart';

enum _MediaPickKind { media, audio }

class SendFilesScreen extends ConsumerStatefulWidget {
  const SendFilesScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  ConsumerState<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends ConsumerState<SendFilesScreen> {


  final List<_SelectedFile> _files = [];
  final Set<String> _selectedTargets = <String>{};
  final AndroidInstalledAppsService _androidInstalledAppsService =
      AndroidInstalledAppsService();
  bool _sending = false;
  bool _refreshingNearby = false;
  bool _extractingApk = false;
  bool _importingSharedFiles = false;
  Timer? _tempShareCopyResetTimer;

  @override
  void dispose() {
    _tempShareCopyResetTimer?.cancel();
    super.dispose();
  }

  bool _isShellBranchActive(BuildContext context) {
    final scope = TabShellScope.maybeOf(context);
    return widget.isActive && (scope == null || scope.currentIndex == 1);
  }

  @override
  Widget build(BuildContext context) {
    final isActiveBranch = !widget.embedded || _isShellBranchActive(context);
    if (widget.embedded && !isActiveBranch) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(appControllerProvider);
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final supportsDragDrop =
        kIsWeb ||
        (!kIsWeb &&
            (Platform.isAndroid ||
                Platform.isWindows ||
                Platform.isLinux ||
                Platform.isMacOS));
    final enableScreenDrop =
        supportsDragDrop && isActiveBranch && !widget.embedded;
    final tempShare = state.tempLinkShare;
    final isDark = theme.brightness == Brightness.dark;
    final isRootRouteVisible = !(Navigator.of(
      context,
      rootNavigator: true,
    ).canPop());
    final canImportPending = isActiveBranch && isRootRouteVisible;

    final hasPendingImports =
        state.pendingSharedFilePaths.isNotEmpty ||
        state.pendingSharedTexts.isNotEmpty;
    if (canImportPending && hasPendingImports && !_importingSharedFiles) {
      _importingSharedFiles = true;
      Future<void>(() async {
        try {
          final controller = ref.read(appControllerProvider.notifier);
          final pendingFiles = controller.consumePendingSharedFiles();
          final pendingTexts = controller.consumePendingSharedTexts();
          final textFiles = await _createTempFilesFromSharedTexts(pendingTexts);
          final pending = <String>[...pendingFiles, ...textFiles];
          if (pending.isNotEmpty) {
            await _addPaths(pending);
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text('${pending.length} shared file(s) added.'),
              ),
            );
          }
        } finally {
          _importingSharedFiles = false;
        }
      });
    }

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom + 120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _files.isNotEmpty
                          ? colorScheme.primary.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: _files.isNotEmpty ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_files.isNotEmpty)
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: _files.isNotEmpty
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Select Content',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _actionButton(
                              icon: Icons.insert_drive_file_rounded,
                              label: 'File',
                              onTap: _pickFile,
                              accentColor: Colors.blue.shade500,
                            ),
                            _actionButton(
                              icon: Icons.photo_library_rounded,
                              label: 'Media',
                              onTap: _pickMedia,
                              accentColor: Colors.purple.shade400,
                            ),
                            _actionButton(
                              icon: Icons.notes_rounded,
                              label: 'Text',
                              onTap: _addText,
                              accentColor: Colors.deepOrange.shade400,
                            ),
                            _actionButton(
                              icon: Icons.folder_rounded,
                              label: 'Folder',
                              onTap: _pickFolder,
                              accentColor: Colors.amber.shade600,
                            ),
                            if (isAndroid) ...[
                              _actionButton(
                                icon: Icons.android_rounded,
                                label: 'App',
                                onTap: _extractingApk ? () async {} : _pickApk,
                                accentColor: Colors.teal.shade500,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _selectedTargets.isNotEmpty
                          ? colorScheme.primary.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: _selectedTargets.isNotEmpty ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_selectedTargets.isNotEmpty)
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wifi_tethering_rounded,
                            size: 20,
                            color: _refreshingNearby
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Nearby Devices',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            iconSize: 20,
                            tooltip: 'Select all',
                            onPressed: _sending
                                ? null
                                : () => _selectAllTargets(state),
                            icon: const Icon(Icons.select_all_rounded),
                          ),
                          IconButton(
                            iconSize: 20,
                            tooltip: 'Clear selection',
                            onPressed: _sending || _selectedTargets.isEmpty
                                ? null
                                : _clearTargets,
                            icon: const Icon(Icons.clear_all_rounded),
                          ),
                          IconButton(
                            iconSize: 20,
                            tooltip: 'Refresh',
                            onPressed: _sending || _refreshingNearby
                                ? null
                                : _refreshNearbyDevices,
                            icon: _refreshingNearby
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: ExpressiveLoader(),
                                  )
                                : const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child:
                      (state.devices.isEmpty && state.connectedWebPeers.isEmpty)
                      ? (_refreshingNearby
                            ? const Column(
                                key: ValueKey('skeleton-peers'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _DeviceSkeletonTile(),
                                  SizedBox(height: 6),
                                  _DeviceSkeletonTile(),
                                ],
                              )
                            : Container(
                                key: const ValueKey('empty-peers'),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 36,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.devices_other_rounded,
                                      size: 36,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'No nearby devices or connected web peers.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ))
                      : Column(
                          key: const ValueKey('peer-list'),
                          children: [
                            ...state.devices.map(
                              (device) => _deviceTile(state, device),
                            ),
                            ...state.connectedWebPeers.map(
                              (peer) =>
                                  _webPeerTile(peer.name, peer.ip, peer.id),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _canSend
                          ? colorScheme.primary.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: _canSend ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_canSend)
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Row(
                          children: [
                            Icon(
                              Icons.description_rounded,
                              size: 20,
                              color: _canSend
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Selected: ${_files.length} file(s) • ${FileUtils.formatBytes(_totalBytes.toDouble())}',
                              key: ValueKey('${_files.length}-$_totalBytes'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _files.isEmpty
                            ? Padding(
                                key: const ValueKey('empty-files'),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 28,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.file_copy_outlined,
                                        size: 32,
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No files selected.',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                key: const ValueKey('files-list'),
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _files.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final file = _files[index];
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: colorScheme.surfaceContainerHigh
                                          .withValues(alpha: 0.45),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _previewWidget(file),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                file.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                FileUtils.formatBytes(
                                                  file.size.toDouble(),
                                                ),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Deselect',
                                          iconSize: 20,
                                          onPressed: () => setState(
                                            () => _files.removeAt(index),
                                          ),
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),
                      Divider(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTemporaryShareSection(tempShare, isDark),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: _canSend
                                ? [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: FilledButton.icon(
                            onPressed: _canSend ? _send : null,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              elevation: 0,
                            ),
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 20),
                            label: Text(
                              _sending ? 'Sending...' : 'Send Files',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final dropAwareContent = enableScreenDrop
        ? DropTarget(
            onDragDone: (detail) => _handleScreenDrop(context, detail),
            child: content,
          )
        : content;

    if (widget.embedded) {
      return dropAwareContent;
    }
    return AdaptiveNavScaffold(currentIndex: 1, child: dropAwareContent);
  }

  Future<void> _handleScreenDrop(
    BuildContext context,
    DropDoneDetails detail,
  ) async {
    if (!mounted || !_isShellBranchActive(context)) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final dropped = detail.files
        .map((file) => file.path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (dropped.isEmpty) {
      return;
    }

    await _addPaths(dropped);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${dropped.length} item(s) added from drag and drop.'),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 76,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _sending ? null : () => onTap(),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: Icon(icon, size: 20, color: accentColor),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemporaryShareSection(
    TemporaryLinkShareState tempShare,
    bool isDark,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        Row(
          children: [
            Text('Share via link', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (tempShare.running)
              OutlinedButton.icon(
                onPressed: _sending ? null : _stopTemporaryShare,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              )
            else
              OutlinedButton.icon(
                onPressed: _sending || _files.isEmpty ? null : _shareViaLink,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Start'),
              ),
          ],
        ),

        // ── Idle description ─────────────────────────────────────────────────
        if (!tempShare.running)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Create a temporary link and QR code for selected files.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // ── Running state ────────────────────────────────────────────────────
        if (tempShare.running) ...[
          const SizedBox(height: 12),

          // One row per adapter URL
          for (final url
              in (tempShare.urls.isNotEmpty ? tempShare.urls : [tempShare.url]))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.28,
                  ),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          url,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SmallLinkButton(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copy link',
                      onPressed: () => _copyTemporaryShareLink(url),
                    ),
                    _SmallLinkButton(
                      icon: Icons.qr_code_rounded,
                      tooltip: 'Show QR Code scanner',
                      onPressed: () => _showTempShareQrDialog(url),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 4),

          // Status chips (PIN + countdown)
          if (tempShare.pin.isNotEmpty || tempShare.expiresAt != null)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (tempShare.pin.isNotEmpty)
                  Tooltip(
                    message: 'PIN required to access the link',
                    child: Chip(
                      avatar: const Icon(Icons.lock_rounded, size: 14),
                      label: Text(
                        tempShare.pin,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                          fontSize: 12,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (tempShare.expiresAt != null)
                  _CountdownChip(expiresAt: tempShare.expiresAt!),
              ],
            ),

          // Connected clients
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.devices_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                tempShare.connectedClients.isEmpty
                    ? 'No devices connected yet'
                    : 'Connected (${tempShare.connectedClients.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (tempShare.connectedClients.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tempShare.connectedClients
                  .map(
                    (client) => Chip(
                      avatar: const Icon(Icons.computer_rounded, size: 14),
                      label: Text(
                        client.ip,
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _deviceTile(AppState appState, DeviceModel device) {
    final key = 'device:${device.deviceId}';
    final selected = _selectedTargets.contains(key);
    final trusted = _isTrustedDevice(appState, device);
    final favorite = _isFavoriteDevice(appState, device);
    final pairingRequired = appState.requirePairingCodeForDirectTransfers;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.28)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _sending
            ? null
            : () {
                if (pairingRequired && !trusted) {
                  _toggleDevicePairing(device, trusted: false);
                  return;
                }
                setState(() {
                  if (selected) {
                    _selectedTargets.remove(key);
                  } else {
                    _selectedTargets.add(key);
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar with Online Badge Overlay placed properly
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: selected
                            ? [
                                colorScheme.primaryContainer,
                                colorScheme.primaryContainer.withValues(alpha: 0.6),
                              ]
                            : [
                                colorScheme.surfaceContainerHigh,
                                colorScheme.surfaceContainerLow,
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: selected
                            ? colorScheme.primary.withValues(alpha: 0.3)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: device.deviceType == DeviceType.macos
                        ? MacOSSmilingLogo(
                            size: 24,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          )
                        : Icon(
                            _iconForDeviceType(device.deviceType),
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            size: 24,
                          ),
                  ),
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primaryContainer
                            : colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: device.isOnline
                              ? Colors.green.shade400
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Name & Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.taggedName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pairingRequired && trusted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Colors.green.shade400,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.platform.isEmpty ? 'Unknown' : device.platform} • ${device.ipAddress}${(pairingRequired && !trusted) ? ' • Not paired' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: favorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    onPressed: _sending
                        ? null
                        : () =>
                              _toggleFavoriteDevice(device, favorite: favorite),
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: favorite
                          ? Colors.red.shade400
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),

                  if (pairingRequired)
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: trusted
                          ? 'Unpair device'
                          : 'Pair and verify device',
                      onPressed: _sending
                          ? null
                          : () =>
                                _toggleDevicePairing(device, trusted: trusted),
                      icon: Icon(
                        trusted
                            ? Icons.verified_user_rounded
                            : Icons.verified_user_outlined,
                        color: trusted
                            ? Colors.green.shade400
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 4),
                  // Custom Checkmark Checkbox
                  GestureDetector(
                    onTap: _sending || (pairingRequired && !trusted)
                        ? null
                        : () => setState(() {
                            if (selected) {
                              _selectedTargets.remove(key);
                            } else {
                              _selectedTargets.add(key);
                            }
                          }),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? colorScheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webPeerTile(String name, String ip, String id) {
    final key = 'web:$id';
    final selected = _selectedTargets.contains(key);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.28)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _sending
            ? null
            : () => setState(() {
                if (selected) {
                  _selectedTargets.remove(key);
                } else {
                  _selectedTargets.add(key);
                }
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: selected
                        ? [
                            colorScheme.primaryContainer,
                            colorScheme.primaryContainer.withValues(alpha: 0.6),
                          ]
                        : [
                            colorScheme.surfaceContainerHigh,
                            colorScheme.surfaceContainerLow,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.language_rounded,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Web Browser • $ip',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending
                    ? null
                    : () => setState(() {
                        if (selected) {
                          _selectedTargets.remove(key);
                        } else {
                          _selectedTargets.add(key);
                        }
                      }),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colorScheme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isFavoriteDevice(AppState state, DeviceModel device) {
    final id = device.deviceId.trim().toLowerCase();
    if (id.isEmpty) {
      return false;
    }
    return state.favoritePeers.any(
      (peer) => peer.deviceId.trim().toLowerCase() == id,
    );
  }

  bool _isTrustedDevice(AppState state, DeviceModel device) {
    return isDeviceTrusted(trustedPeers: state.trustedPeers, device: device);
  }

  Future<void> _toggleDevicePairing(
    DeviceModel device, {
    required bool trusted,
  }) async {
    if (trusted) {
      try {
        await ref.read(appControllerProvider.notifier).unpairDevice(device);
        _showMessage('Device successfully unpaired.');
      } catch (e) {
        _showMessage('Failed to unpair device: $e');
      }
    } else {
      // Generate a secure random 6-digit code
      final randomCode = List.generate(6, (_) => math.Random().nextInt(10).toString()).join();

      bool pairingCompleted = false;
      BuildContext? localDialogContext;
      bool initiatorCancelledSelf = false;

      // Show the pairing code dialog in display mode on Device A (the initiator)
      final dialogFuture = showInstantDialog<void>(
        context: context,
        builder: (context) {
          localDialogContext = context;
          return PairingCodeDialog(
            deviceName: device.taggedName,
            fileName: 'Pairing Connection',
            displayCode: randomCode,
          );
        },
      );

      unawaited(dialogFuture.then((_) {
        if (!pairingCompleted) {
          initiatorCancelledSelf = true;
          ref.read(appControllerProvider.notifier).cancelPairing(device.deviceId);
        }
      }));

      _showMessage('Sending pairing request to ${device.taggedName}...');

      try {
        await ref
            .read(appControllerProvider.notifier)
            .pairDeviceWithVerification(device, pairingCode: randomCode);
        pairingCompleted = true;
        if (mounted) {
          if (localDialogContext != null && localDialogContext!.mounted) {
            Navigator.of(localDialogContext!).pop(); // Automatically dismiss the display dialog
          }
          _showMessage('Successfully paired with ${device.taggedName}.');
        }
      } catch (e) {
        pairingCompleted = true;
        if (mounted) {
          if (localDialogContext != null && localDialogContext!.mounted) {
            Navigator.of(localDialogContext!).pop(); // Automatically dismiss the display dialog
          }

          if (initiatorCancelledSelf) {
            return;
          }

          final isCancel = e.toString().contains('rejected') ||
              e.toString().contains('canceled') ||
              e.toString().contains('timeout') ||
              e.toString().contains('SocketException') ||
              e.toString().contains('closed') ||
              e.toString().contains('Connection closed') ||
              e.toString().contains('refused');

          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          showDropNetDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
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
                'Pairing Cancelled',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              content: Card(
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
                    isCancel
                        ? 'The pairing session was cancelled or disconnected by the other device.\n\nFor security, direct file transfers have been aborted. Please ensure both devices are open on the same local network and attempt to pair again.'
                        : 'The pairing connection attempt failed due to a connection error:\n\n$e\n\nPlease ensure both devices are open on the same Wi-Fi network and try again.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleFavoriteDevice(
    DeviceModel device, {
    required bool favorite,
  }) async {
    await ref.read(appControllerProvider.notifier).toggleFavoriteDevice(device);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          favorite
              ? 'Removed from favorite devices.'
              : 'Added to favorite devices.',
        ),
      ),
    );
  }

  IconData _iconForDeviceType(DeviceType type) {
    switch (type) {
      case DeviceType.phone:
        return Icons.smartphone_rounded;
      case DeviceType.tablet:
        return Icons.tablet_mac_rounded;
      case DeviceType.desktop:
        return Icons.desktop_windows_rounded;
      case DeviceType.web:
        return Icons.language_rounded;
      case DeviceType.other:
        return Icons.devices_other_rounded;
      case DeviceType.laptop:
        return Icons.laptop_rounded;
      case DeviceType.android:
        return Icons.android_rounded;
      case DeviceType.apple:
        return Icons.apple;
      case DeviceType.macos:
        return CupertinoIcons.smiley;
      case DeviceType.windows:
        return Icons.window_rounded;
      case DeviceType.linux:
        return Icons.terminal_rounded;
    }
  }

  Widget _previewWidget(_SelectedFile file) {
    if (file.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(file.path),
          width: 34,
          height: 34,
          fit: BoxFit.cover,
        ),
      );
    }
    return const Icon(Icons.insert_drive_file_rounded, size: 28);
  }

  int get _totalBytes => _files.fold(0, (sum, file) => sum + file.size);

  bool get _canSend =>
      !_sending && _files.isNotEmpty && _selectedTargets.isNotEmpty;

  List<String> _allTargetKeys(AppState state) {
    final pairingRequired = state.requirePairingCodeForDirectTransfers;
    final deviceKeys = state.devices
        .where((device) => !pairingRequired || _isTrustedDevice(state, device))
        .map((device) => 'device:${device.deviceId}');
    final webKeys = state.connectedWebPeers.map((peer) => 'web:${peer.id}');
    return [...deviceKeys, ...webKeys];
  }

  void _selectAllTargets(AppState state) {
    final allTargets = _allTargetKeys(state);
    setState(() {
      _selectedTargets
        ..clear()
        ..addAll(allTargets);
    });
  }

  void _clearTargets() {
    setState(_selectedTargets.clear);
  }

  Future<void> _refreshNearbyDevices() async {
    setState(() => _refreshingNearby = true);
    final startedAt = DateTime.now();
    try {
      await ref.read(appControllerProvider.notifier).refreshNearbyDevices();
    } finally {
      final elapsed = DateTime.now().difference(startedAt);
      // Keep the spinner visible for a brief moment for responsive UX feedback
      const minVisible = Duration(seconds: 1);
      if (elapsed < minVisible) {
        await Future<void>.delayed(minVisible - elapsed);
      }
      if (mounted) {
        setState(() => _refreshingNearby = false);
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) {
      return;
    }
    await _addPaths(result.paths.whereType<String>());
  }

  Future<void> _pickMedia() async {
    final mediaKind = await _askMediaType();
    if (!mounted || mediaKind == null) {
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      final List<String>? paths;
      if (mediaKind == _MediaPickKind.media) {
        paths = await const MediaStoreService().pickMedia();
      } else {
        paths = await const MediaStoreService().pickAudio();
      }
      if (paths != null && paths.isNotEmpty) {
        await _addPaths(paths);
      }
      return;
    }

    final pickerConfig = _pickerConfigForMediaKind(mediaKind);

    final result = await FilePicker.platform.pickFiles(
      type: pickerConfig.type,
      allowMultiple: true,
      withData: false,
      allowedExtensions: pickerConfig.allowedExtensions,
    );
    if (result == null) {
      return;
    }

    final picked = result.paths.whereType<String>().toList(growable: false);
    if (picked.isNotEmpty) {
      await _addPaths(picked);
    }
  }

  Future<_MediaPickKind?> _askMediaType() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showGeneralDialog<_MediaPickKind>(
      context: Navigator.of(context, rootNavigator: true).context,
      barrierDismissible: true,
      barrierLabel: 'Select Media Type',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final slideCurve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        final blurCurve = CurvedAnimation(parent: anim1, curve: Curves.easeInOut);

        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurCurve.value * 8,
            sigmaY: blurCurve.value * 8,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(slideCurve),
            child: FadeTransition(
              opacity: anim1,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.transparent,
                  child: SafeArea(
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 600),
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.perm_media_rounded,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Select Content Type',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.onSurface,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      Text(
                                        'Choose the type of media to share',
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
                            _MediaOptionCard(
                              icon: Icons.photo_library_rounded,
                              title: 'Photos & Videos',
                              subtitle: 'Select images and videos from your gallery',
                              gradient: LinearGradient(
                                colors: [Colors.purple.shade400, Colors.deepPurple.shade600],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              onTap: () => Navigator.of(context).pop(_MediaPickKind.media),
                            ),
                            _MediaOptionCard(
                              icon: Icons.audiotrack_rounded,
                              title: 'Audio',
                              subtitle: 'Select audio tracks or music files',
                              gradient: LinearGradient(
                                colors: [Colors.blue.shade400, Colors.indigo.shade600],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              onTap: () => Navigator.of(context).pop(_MediaPickKind.audio),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  ({FileType type, List<String>? allowedExtensions}) _pickerConfigForMediaKind(
    _MediaPickKind kind,
  ) {
    switch (kind) {
      case _MediaPickKind.media:
        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
          return (
            type: FileType.custom,
            allowedExtensions: const [
              'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
              'tiff', 'tif', 'svg', 'ico', 'avif', 'mp4', 'mov', 'avi',
              'mkv', 'wmv', 'flv', 'webm', 'm4v', '3gp', '3g2', 'ts',
              'mts', 'm2ts', 'vob', 'ogv',
            ],
          );
        }
        return (type: FileType.media, allowedExtensions: null);
      case _MediaPickKind.audio:
        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
          return (
            type: FileType.custom,
            allowedExtensions: const [
              'mp3', 'wav', 'm4a', 'flac', 'aac', 'ogg', 'wma', 'opus',
              'caf', 'aiff', 'alac', 'mid', 'midi',
            ],
          );
        }
        return (type: FileType.audio, allowedExtensions: null);
    }
  }

  Future<void> _pickApk() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    final selectedApps = await showDialog<List<AndroidInstalledApp>>(
      context: context,
      builder: (context) =>
          _InstalledAppsPickerDialog(service: _androidInstalledAppsService),
    );

    if (selectedApps == null || selectedApps.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _extractingApk = true);
    BuildContext? extractionDialogContext;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (context) {
          extractionDialogContext = context;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 6,
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExpressiveLoader(),
                SizedBox(height: 16),
                Text('Extracting APK...'),
              ],
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    void closeExtractionDialog() {
      final dialogContext = extractionDialogContext;
      if (dialogContext == null || !dialogContext.mounted) {
        return;
      }
      final navigator = Navigator.of(dialogContext, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }

    try {
      final apkPaths = <String>[];
      for (final app in selectedApps) {
        final path = await _copyApkToTemp(app);
        if (path != null) {
          apkPaths.add(path);
        }
      }

      if (apkPaths.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not extract APK from selected apps.'),
          ),
        );
        return;
      }

      await _addPaths(apkPaths);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${apkPaths.length} APK file(s) added from installed apps.',
          ),
        ),
      );
    } finally {
      closeExtractionDialog();
      if (mounted) {
        setState(() => _extractingApk = false);
      }
    }
  }

  Future<String?> _copyApkToTemp(AndroidInstalledApp app) async {
    try {
      final source = File(app.apkPath);
      if (!await source.exists()) {
        return null;
      }
      final tempDir = await getTemporaryDirectory();
      final cleanName = app.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final targetName =
          '${cleanName.isEmpty ? app.packageName : cleanName}_${DateTime.now().millisecondsSinceEpoch}.apk';
      final target = File(p.join(tempDir.path, targetName));
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) {
      return;
    }
    final files = await Directory(path)
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .map((file) => file.path)
        .toList();
    await _addPaths(files);
  }

  Future<void> _addText() async {
    try {
      final text = await showDropNetDialog<String>(
        context: context,
        builder: (dialogContext) => const _AddTextDialog(),
      );

      if (text == null || text.trim().isEmpty) {
        return;
      }

      final path = await _writeTextToTempFile(text, prefix: 'dropnet_text');
      if (path == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      await _addPaths([path]);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding text: $e')));
    }
  }

  Future<List<String>> _createTempFilesFromSharedTexts(
    List<String> texts,
  ) async {
    if (texts.isEmpty) {
      return const <String>[];
    }
    final created = <String>[];
    for (final text in texts) {
      final path = await _writeTextToTempFile(
        text,
        prefix: 'dropnet_shared_text',
      );
      if (path != null) {
        created.add(path);
      }
    }
    return created;
  }

  Future<String?> _writeTextToTempFile(
    String text, {
    required String prefix,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }

    Directory tempDirectory;
    try {
      tempDirectory = await getTemporaryDirectory();
    } catch (_) {
      tempDirectory = Directory.systemTemp;
    }

    final fileName =
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${normalized.length}.txt';
    final file = File(p.join(tempDirectory.path, fileName));
    try {
      await file.writeAsString(normalized);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _addPaths(Iterable<String> paths) async {
    final existing = _files.map((file) => file.path).toSet();
    final fresh = <_SelectedFile>[];
    for (final path in paths) {
      if (existing.contains(path)) {
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final size = await file.length();
      final ext = p.extension(path).toLowerCase();
      final isImage = const {
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.webp',
        '.bmp',
      }.contains(ext);
      fresh.add(
        _SelectedFile(
          path: path,
          name: p.basename(path),
          size: size,
          isImage: isImage,
        ),
      );
    }
    if (fresh.isEmpty) {
      return;
    }
    setState(() {
      _files.addAll(fresh);
    });
  }

  Future<void> _send() async {
    final targets = _selectedTargets.toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      final files = _files.map((file) => file.path).toList();
      var sentToDevices = 0;
      final webPeerIds = <String>[];
      final failedTargets = <String>[];
      final appState = ref.read(appControllerProvider);
      final controller = ref.read(appControllerProvider.notifier);

      for (final target in targets) {
        if (target.startsWith('device:')) {
          final deviceId = target.substring('device:'.length);
          final device = appState.devices
              .where((item) => item.deviceId == deviceId)
              .firstOrNull;
          if (device == null) {
            continue;
          }
          try {
            await controller.sendFiles(device, files);
            sentToDevices++;
          } catch (error) {
            failedTargets.add('${device.taggedName}: $error');
          }
          continue;
        }

        if (target.startsWith('web:')) {
          webPeerIds.add(target.substring('web:'.length));
        }
      }

      if (webPeerIds.isNotEmpty) {
        final copied = await controller.stageFilesForWebPeers(
          filePaths: files,
          peerIds: webPeerIds,
        );
        if (mounted && copied > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$copied file(s) shared for ${webPeerIds.length} connected web peer(s).',
              ),
            ),
          );
        }
      }

      if (mounted) {
        if (failedTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Transfer prepared for $sentToDevices device(s)${webPeerIds.isNotEmpty ? ' and ${webPeerIds.length} web peer(s)' : ''}.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failedTargets.join('\n')),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _shareViaLink() async {
    final filePaths = _files.map((file) => file.path).toList(growable: false);
    if (filePaths.isEmpty) {
      return;
    }

    final options = await _askShareLinkOptions();
    if (options.cancelled) {
      return;
    }
    if (!mounted) {
      return;
    }

    final appState = ref.read(appControllerProvider);
    var replaceWebServer = false;
    if (appState.webState.running) {
      final decision = await _showWebServiceConflictDialog(
        currentService: 'Web server',
        nextService: 'Temporary share link server',
      );
      if (!mounted || decision == null) {
        return;
      }
      replaceWebServer = decision;
    }

    try {
      await ref
          .read(appControllerProvider.notifier)
          .startTemporaryLinkShare(
            filePaths: filePaths,
            ttl: options.ttl,
            pin: options.pin,
            stopWebShareIfRunning: replaceWebServer,
          );
      if (!mounted) {
        return;
      }
      final url = ref.read(appControllerProvider).tempLinkShare.url;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Temporary share started: $url')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start temporary share: $error')),
      );
    }
  }

  Future<bool?> _showWebServiceConflictDialog({
    required String currentService,
    required String nextService,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showDropNetDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
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
            'Only One Web Service Allowed',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          content: Card(
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
                '$currentService is already running. For security reasons, $nextService cannot run at the same time.\n\nStop the current service and continue?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Keep Current',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Stop & Continue',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _stopTemporaryShare() async {
    await ref.read(appControllerProvider.notifier).stopTemporaryLinkShare();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Temporary share stopped.')));
  }

  Future<void> _copyTemporaryShareLink(String url) async {
    if (url.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _tempShareCopyResetTimer?.cancel();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard.')));
  }

  void _showTempShareQrDialog(String url) {
    if (url.trim().isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDropNetDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
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
              colors: [
                colorScheme.primaryContainer,
                colorScheme.primaryContainer.withValues(alpha: 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.qr_code_2_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          'QR Code',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 260,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                        data: url,
                        size: 184,
                        eyeStyle: QrEyeStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    url,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<({bool cancelled, Duration? ttl, String pin})>
  _askShareLinkOptions() async {
    final timerController = TextEditingController(text: '30');
    final pinController = TextEditingController(
      text: TemporaryLinkShareService.generatePin(),
    );
    var useNoTimer = false;
    var usePinProtection = false;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final result = await showDropNetDialog<({bool cancelled, Duration? ttl, String pin})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
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
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.link_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
              title: Text(
                'Share link options',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 520,
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customize how your link behaves before starting.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                              const Divider(height: 28, thickness: 0.5),
                              
                              // Section: Timer
                              Row(
                                children: [
                                  Icon(Icons.timer_outlined, size: 18, color: colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Link timer',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Theme(
                                data: theme.copyWith(
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                child: CheckboxListTile(
                                  value: useNoTimer,
                                  onChanged: (value) => setLocalState(
                                    () => useNoTimer = value ?? false,
                                  ),
                                  title: const Text('Keep link active until stopped manually'),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (!useNoTimer) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: timerController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Auto-stop after (minutes)',
                                    hintText: 'e.g. 30',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ],
                              
                              const Divider(height: 36, thickness: 0.5),
                              
                              // Section: PIN
                              Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 18, color: colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PIN protection',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Theme(
                                data: theme.copyWith(
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                child: CheckboxListTile(
                                  value: usePinProtection,
                                  onChanged: (value) => setLocalState(
                                    () => usePinProtection = value ?? false,
                                  ),
                                  title: const Text('Require PIN before opening the link'),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (usePinProtection) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: pinController,
                                  decoration: InputDecoration(
                                    labelText: 'PIN',
                                    hintText: 'Auto-generated',
                                    suffixIcon: IconButton(
                                      tooltip: 'Generate new PIN',
                                      icon: const Icon(Icons.refresh_rounded),
                                      onPressed: () => setLocalState(() {
                                        pinController.text =
                                            TemporaryLinkShareService.generatePin();
                                      }),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Receivers must enter this PIN in the browser before accessing files.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop((cancelled: true, ttl: null, pin: '')),
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
                        onPressed: () {
                          Duration? ttl;
                          if (!useNoTimer) {
                            final minutes = int.tryParse(timerController.text.trim());
                            if (minutes == null || minutes <= 0) {
                              return;
                            }
                            ttl = Duration(minutes: minutes);
                          }
                          final pin = usePinProtection
                              ? pinController.text.trim()
                              : '';
                          Navigator.of(context).pop((cancelled: false, ttl: ttl, pin: pin));
                        },
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Start sharing',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return (cancelled: true, ttl: null, pin: '');
    }
    return result;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SelectedFile {
  const _SelectedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.isImage,
  });

  final String path;
  final String name;
  final int size;
  final bool isImage;
}

/// Live countdown chip shown when a temporary share has an expiry.
class _CountdownChip extends StatefulWidget {
  const _CountdownChip({required this.expiresAt});
  final DateTime expiresAt;
  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  late Timer _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 86400);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final secs = widget.expiresAt
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 86400);
      setState(() => _remainingSeconds = secs);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    final label = '$m:${s.toString().padLeft(2, '0')}';
    return Chip(
      avatar: const Icon(Icons.timer_rounded, size: 14),
      label: Text(label, style: const TextStyle(fontFamily: 'monospace')),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: _remainingSeconds < 60
            ? Theme.of(context).colorScheme.error.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _AddTextDialog extends StatefulWidget {
  const _AddTextDialog();

  @override
  State<_AddTextDialog> createState() => _AddTextDialogState();
}

class _AddTextDialogState extends State<_AddTextDialog> {
  static const double _minInputHeight = 120;
  static const double _lineHeight = 22;

  late final TextEditingController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_handleChanged);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int _estimateInputLines(String text) {
    if (text.isEmpty) {
      return 3;
    }
    final hardBreaks = '\n'.allMatches(text).length;
    final softWraps = (text.length / 48).ceil();
    final estimated = hardBreaks + softWraps;
    return estimated.clamp(3, 18);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxInputHeight = (screenHeight * 0.42).clamp(180.0, 320.0);
    final estimatedLines = _estimateInputLines(_controller.text);
    final desiredHeight = (estimatedLines * _lineHeight + 28).clamp(
      _minInputHeight,
      maxInputHeight,
    );
    final isCapped = desiredHeight >= maxInputHeight;
    final trimmedText = _controller.text.trim();

    return PopScope(
      canPop: false,
      child: AlertDialog(
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
              colors: [
                colorScheme.primaryContainer,
                colorScheme.primaryContainer.withValues(alpha: 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.notes_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Add text',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        constraints: BoxConstraints(
                          minHeight: _minInputHeight,
                          maxHeight: maxInputHeight,
                        ),
                        height: desiredHeight,
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: isCapped,
                          child: TextField(
                            controller: _controller,
                            scrollController: _scrollController,
                            autofocus: true,
                            minLines: 3,
                            maxLines: 999,
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: trimmedText.isEmpty
                                  ? 'Type text to share...'
                                  : null,
                              prefix: trimmedText.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.notes_rounded, size: 20),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              filled: true,
                              fillColor: colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${trimmedText.length} characters${isCapped ? ' - Scroll for more' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                  onPressed: () => Navigator.of(context).pop(),
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
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppInfoChip extends StatelessWidget {
  const _AppInfoChip({
    required this.label,
    required this.icon,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = isPrimary
        ? colorScheme.primaryContainer
        : colorScheme.secondaryContainer;
    final fg = isPrimary
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _InstalledAppsPickerDialog extends StatefulWidget {
  const _InstalledAppsPickerDialog({required this.service});

  final AndroidInstalledAppsService service;

  @override
  State<_InstalledAppsPickerDialog> createState() =>
      _InstalledAppsPickerDialogState();
}

class _InstalledAppsPickerDialogState
    extends State<_InstalledAppsPickerDialog> {
  static const String _menuIncludeSystemApps = 'include_system_apps';

  bool _includeSystemApps = false;
  bool _loading = true;
  String? _error;
  List<AndroidInstalledApp> _apps = const [];
  final Set<String> _selectedPackages = <String>{};
  final TextEditingController _searchController = TextEditingController();
  int _loadGeneration = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AndroidInstalledApp> get _filteredApps {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _apps;
    }
    return _apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadApps();
    });
  }

  Future<void> _loadApps() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    try {
      final apps = await widget.service.listInstalledApps(
        includeSystemApps: _includeSystemApps,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _apps = apps;
        _loading = false;
        _selectedPackages.removeWhere(
          (pkg) => !_apps.any((app) => app.packageName == pkg),
        );
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Select installed apps',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value != _menuIncludeSystemApps) {
                        return;
                      }
                      setState(() => _includeSystemApps = !_includeSystemApps);
                      _loadApps();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: _menuIncludeSystemApps,
                        child: Row(
                          children: [
                            Checkbox(
                              value: _includeSystemApps,
                              onChanged: null,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Include system apps')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by app name or package name',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_filteredApps.length} app(s) shown',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_selectedPackages.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Theme.of(context).colorScheme.primaryContainer,
                      ),
                      child: Text(
                        '${_selectedPackages.length} selected',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Failed to load apps: $_error'),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: ExpressiveLoader())
                    : _filteredApps.isEmpty
                    ? const Center(child: Text('No installed apps available.'))
                    : ListView.separated(
                        itemCount: _filteredApps.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final selected = _selectedPackages.contains(
                            app.packageName,
                          );
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.35)
                                  : Colors.transparent,
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                backgroundImage: app.iconBytes != null
                                    ? MemoryImage(app.iconBytes!)
                                    : null,
                                child: app.iconBytes == null
                                    ? const Icon(
                                        Icons.android_rounded,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              title: Text(
                                app.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.packageName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (app.versionName.isNotEmpty)
                                          _AppInfoChip(
                                            label: app.versionName,
                                            icon: Icons.tag_rounded,
                                          ),
                                        if (app.apkSize > 0)
                                          _AppInfoChip(
                                            label: FileUtils.formatBytes(
                                              app.apkSize.toDouble(),
                                            ),
                                            icon: Icons.storage_rounded,
                                            isPrimary: true,
                                          ),
                                        if (app.isSystemApp)
                                          _AppInfoChip(
                                            label: 'System',
                                            icon: Icons
                                                .admin_panel_settings_rounded,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Checkbox(
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selectedPackages.remove(app.packageName);
                                  } else {
                                    _selectedPackages.add(app.packageName);
                                  }
                                }),
                              ),
                              onTap: () => setState(() {
                                if (selected) {
                                  _selectedPackages.remove(app.packageName);
                                } else {
                                  _selectedPackages.add(app.packageName);
                                }
                              }),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedPackages.isEmpty
                        ? null
                        : () {
                            final selected = _apps
                                .where(
                                  (app) => _selectedPackages.contains(
                                    app.packageName,
                                  ),
                                )
                                .toList(growable: false);
                            Navigator.of(context).pop(selected);
                          },
                    child: Text('Add APKs (${_selectedPackages.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceSkeletonTile extends StatefulWidget {
  const _DeviceSkeletonTile();

  @override
  State<_DeviceSkeletonTile> createState() => _DeviceSkeletonTileState();
}

class _DeviceSkeletonTileState extends State<_DeviceSkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(
      begin: 0.35,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.16);

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: colorScheme.surfaceContainerLow,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 16,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 220,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: baseColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: baseColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SmallLinkButton extends StatelessWidget {
  const _SmallLinkButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.surfaceContainerHigh,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaOptionCard extends StatelessWidget {
  const _MediaOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
