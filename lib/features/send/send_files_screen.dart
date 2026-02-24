import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/android_installed_apps_service.dart';
import '../../core/networking/temporary_link_share_service.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';
import '../../models/device_model.dart';
import '../../widgets/adaptive_nav_scaffold.dart';

class SendFilesScreen extends ConsumerStatefulWidget {
  const SendFilesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends ConsumerState<SendFilesScreen> {
  final List<_SelectedFile> _files = [];
  final Set<String> _selectedTargets = <String>{};
  final AndroidInstalledAppsService _androidInstalledAppsService = AndroidInstalledAppsService();
  bool _sending = false;
  bool _refreshingNearby = false;
  bool _extractingApk = false;
  bool _importingSharedFiles = false;
  bool _tempShareLinkCopied = false;
  Timer? _tempShareCopyResetTimer;

  @override
  void dispose() {
    _tempShareCopyResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(appControllerProvider);
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final tempShare = state.tempLinkShare;
    final isDark = theme.brightness == Brightness.dark;

    if (state.pendingSharedFilePaths.isNotEmpty && !_importingSharedFiles) {
      _importingSharedFiles = true;
      Future<void>(() async {
        final pending = ref.read(appControllerProvider.notifier).consumePendingSharedFiles();
        if (pending.isNotEmpty) {
          await _addPaths(pending);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('${pending.length} shared file(s) added from another app.')),
          );
        }
        _importingSharedFiles = false;
      });
    }

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: 4,
                          color: _files.isNotEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Selection', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _actionButton(icon: Icons.insert_drive_file_rounded, label: 'File', onTap: _pickFile),
                              const SizedBox(width: 8),
                              _actionButton(icon: Icons.photo_library_rounded, label: 'Media', onTap: _pickMedia),
                              const SizedBox(width: 8),
                              _actionButton(icon: Icons.notes_rounded, label: 'Text', onTap: _addText),
                              const SizedBox(width: 8),
                              _actionButton(icon: Icons.folder_rounded, label: 'Folder', onTap: _pickFolder),
                              if (isAndroid) ...[
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: _sending || _extractingApk ? null : _pickApk,
                                  icon: const Icon(Icons.android_rounded),
                                  label: const Text('App'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: 4,
                          color: _selectedTargets.isNotEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('Nearby Devices', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Select all',
                          onPressed: _sending ? null : () => _selectAllTargets(state),
                          icon: const Icon(Icons.select_all_rounded),
                        ),
                        IconButton(
                          tooltip: 'Clear selection',
                          onPressed: _sending || _selectedTargets.isEmpty ? null : _clearTargets,
                          icon: const Icon(Icons.clear_all_rounded),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _sending || _refreshingNearby ? null : _refreshNearbyDevices,
                          icon: _refreshingNearby
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: (state.devices.isEmpty && state.connectedWebPeers.isEmpty)
                          ? Padding(
                              key: const ValueKey('empty-peers'),
                              padding: const EdgeInsets.symmetric(vertical: 36),
                              child: Center(
                                child: Text(
                                  'No nearby devices or connected web peers.',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          : ListView(
                              key: const ValueKey('peer-list'),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                ...state.devices.map((device) => _deviceTile(device)),
                                ...state.connectedWebPeers.map((peer) => _webPeerTile(peer.name, peer.ip, peer.id)),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: 4,
                          color: _canSend ? colorScheme.primary : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            'Selected: ${_files.length} file(s) • ${FileUtils.formatBytes(_totalBytes.toDouble())}',
                            key: ValueKey('${_files.length}-$_totalBytes'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _files.isEmpty
                              ? Padding(
                                  key: const ValueKey('empty-files'),
                                  padding: const EdgeInsets.symmetric(vertical: 28),
                                  child: Center(
                                    child: Text(
                                      'No files selected.',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  key: const ValueKey('files-list'),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _files.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final file = _files[index];
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      curve: Curves.easeOut,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
                                      ),
                                      child: Row(
                                        children: [
                                          _previewWidget(file),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(FileUtils.formatBytes(file.size.toDouble()), style: theme.textTheme.bodySmall),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Deselect',
                                            onPressed: () => setState(() => _files.removeAt(index)),
                                            icon: const Icon(Icons.close_rounded),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),
                        Divider(color: colorScheme.outlineVariant),
                        const SizedBox(height: 8),
                        _buildTemporaryShareSection(tempShare, isDark),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _canSend ? _send : null,
                            icon: _sending
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_rounded),
                            label: Text(_sending ? 'Sending...' : 'Send'),
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
    if (widget.embedded) {
      return content;
    }
    return AdaptiveNavScaffold(currentIndex: 1, child: content);
  }

  Widget _actionButton({required IconData icon, required String label, required Future<void> Function() onTap}) {
    return FilledButton.tonalIcon(onPressed: _sending ? null : () => onTap(), icon: Icon(icon), label: Text(label));
  }

  Widget _buildTemporaryShareSection(TemporaryLinkShareState tempShare, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (!tempShare.running)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Create a temporary link and QR for selected files.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        if (tempShare.running) ...[
          const SizedBox(height: 8),
          Text(tempShare.deviceName, style: theme.textTheme.bodyMedium),
          Text(
            '${tempShare.platformLabel.isEmpty ? 'Unknown' : tempShare.platformLabel} ${tempShare.idSuffix}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  ),
                  child: SelectableText(tempShare.url),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _tempShareLinkCopied ? 'Copied' : 'Copy link',
                onPressed: () => _copyTemporaryShareLink(tempShare.url),
                icon: Icon(_tempShareLinkCopied ? Icons.check_rounded : Icons.copy_rounded),
              ),
            ],
          ),
          if (tempShare.expiresAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Expires at ${tempShare.expiresAt!.toLocal()}',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: QrImageView(
                data: tempShare.url,
                size: 200,
                backgroundColor: isDark ? Colors.black : Colors.white,
                eyeStyle: QrEyeStyle(color: isDark ? Colors.white : Colors.black),
                dataModuleStyle: QrDataModuleStyle(color: isDark ? Colors.white : Colors.black),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _deviceTile(DeviceModel device) {
    final key = 'device:${device.deviceId}';
    final selected = _selectedTargets.contains(key);
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? colorScheme.primary.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
        leading: Icon(_iconForDeviceType(device.deviceType)),
        title: Text(device.taggedName),
        subtitle: Text('${device.platform.isEmpty ? 'Unknown' : device.platform} • ${device.ipAddress}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(device.isOnline ? Icons.circle : Icons.circle_outlined, size: 11, color: device.isOnline ? Colors.green : Colors.grey),
            const SizedBox(width: 6),
            Checkbox(
              value: selected,
              onChanged: _sending
                  ? null
                  : (_) => setState(() {
                        if (selected) {
                          _selectedTargets.remove(key);
                        } else {
                          _selectedTargets.add(key);
                        }
                      }),
            ),
          ],
        ),
        onTap: _sending
            ? null
            : () => setState(() {
                  if (selected) {
                    _selectedTargets.remove(key);
                  } else {
                    _selectedTargets.add(key);
                  }
                }),
      ),
    );
  }

  Widget _webPeerTile(String name, String ip, String id) {
    final key = 'web:$id';
    final selected = _selectedTargets.contains(key);
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? colorScheme.primary.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
        leading: const Icon(Icons.language_rounded),
        title: Text(name),
        subtitle: Text('Web Peer • $ip'),
        trailing: Checkbox(
          value: selected,
          onChanged: _sending
              ? null
              : (_) => setState(() {
                    if (selected) {
                      _selectedTargets.remove(key);
                    } else {
                      _selectedTargets.add(key);
                    }
                  }),
        ),
        onTap: _sending
            ? null
            : () => setState(() {
                  if (selected) {
                    _selectedTargets.remove(key);
                  } else {
                    _selectedTargets.add(key);
                  }
                }),
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
    }
  }

  Widget _previewWidget(_SelectedFile file) {
    if (file.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(file.path), width: 34, height: 34, fit: BoxFit.cover),
      );
    }
    return const Icon(Icons.insert_drive_file_rounded, size: 28);
  }

  int get _totalBytes => _files.fold(0, (sum, file) => sum + file.size);

  bool get _canSend => !_sending && _files.isNotEmpty && _selectedTargets.isNotEmpty;

  List<String> _allTargetKeys(AppState state) {
    final deviceKeys = state.devices.map((device) => 'device:${device.deviceId}');
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
      const minVisible = Duration(milliseconds: 450);
      if (elapsed < minVisible) {
        await Future<void>.delayed(minVisible - elapsed);
      }
      if (mounted) {
        setState(() => _refreshingNearby = false);
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) {
      return;
    }
    await _addPaths(result.paths.whereType<String>());
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true, withData: false);
    if (result == null) {
      return;
    }
    await _addPaths(result.paths.whereType<String>());
  }

  Future<void> _pickApk() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    final selectedApps = await showDialog<List<AndroidInstalledApp>>(
      context: context,
      builder: (context) => _InstalledAppsPickerDialog(service: _androidInstalledAppsService),
    );

    if (selectedApps == null || selectedApps.isEmpty) {
      return;
    }

    setState(() => _extractingApk = true);
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
          const SnackBar(content: Text('Could not extract APK from selected apps.')),
        );
        return;
      }

      await _addPaths(apkPaths);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${apkPaths.length} APK file(s) added from installed apps.')),
      );
    } finally {
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
      final targetName = '${cleanName.isEmpty ? app.packageName : cleanName}_${DateTime.now().millisecondsSinceEpoch}.apk';
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
    final controller = TextEditingController();
    final textScrollController = ScrollController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final maxInputHeight = (screenHeight * 0.42).clamp(180.0, 320.0);
        const minInputHeight = 120.0;
        const lineHeight = 22.0;
        return AlertDialog(
          title: const Text('Add text'),
          content: SizedBox(
            width: 520,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final estimatedLines = _estimateInputLines(value.text);
                final desiredHeight = (estimatedLines * lineHeight + 28).clamp(minInputHeight, maxInputHeight);
                final isCapped = desiredHeight >= maxInputHeight;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      constraints: BoxConstraints(
                        minHeight: minInputHeight,
                        maxHeight: maxInputHeight,
                      ),
                      height: desiredHeight,
                      child: Scrollbar(
                        controller: textScrollController,
                        thumbVisibility: isCapped,
                        child: TextField(
                          controller: controller,
                          scrollController: textScrollController,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 999,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: value.text.trim().isEmpty ? 'Type text to share...' : null,
                            prefix: value.text.trim().isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(Icons.notes_rounded, size: 20),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${value.text.trim().length} characters${isCapped ? ' • Scroll for more' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Add')),
          ],
        );
      },
    );
    textScrollController.dispose();
    controller.dispose();
    if (text == null || text.trim().isEmpty) {
      return;
    }
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}dropnet_text_${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(text.trim());
    await _addPaths([file.path]);
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
      final isImage = const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext);
      fresh.add(_SelectedFile(path: path, name: p.basename(path), size: size, isImage: isImage));
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
      final appState = ref.read(appControllerProvider);
      final controller = ref.read(appControllerProvider.notifier);

      for (final target in targets) {
        if (target.startsWith('device:')) {
          final deviceId = target.substring('device:'.length);
          final device = appState.devices.where((item) => item.deviceId == deviceId).firstOrNull;
          if (device == null) {
            continue;
          }
          await controller.sendFiles(device, files);
          sentToDevices++;
          continue;
        }

        if (target.startsWith('web:')) {
          webPeerIds.add(target.substring('web:'.length));
        }
      }

      if (webPeerIds.isNotEmpty) {
        final copied = await controller.stageFilesForWebPeers(filePaths: files, peerIds: webPeerIds);
        if (mounted && copied > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$copied file(s) shared for ${webPeerIds.length} connected web peer(s).')));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer prepared for $sentToDevices device(s)${webPeerIds.isNotEmpty ? ' and ${webPeerIds.length} web peer(s)' : ''}.')),
        );
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

    final durationChoice = await _askTemporaryShareDuration();
    if (durationChoice.cancelled) {
      return;
    }
    if (!mounted) {
      return;
    }

    try {
      await ref.read(appControllerProvider.notifier).startTemporaryLinkShare(
            filePaths: filePaths,
            ttl: durationChoice.ttl,
          );
      if (!mounted) {
        return;
      }
      final url = ref.read(appControllerProvider).tempLinkShare.url;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Temporary share started: $url')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start temporary share: $error')),
      );
    }
  }

  Future<void> _stopTemporaryShare() async {
    await ref.read(appControllerProvider.notifier).stopTemporaryLinkShare();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Temporary share stopped.')),
    );
  }

  Future<void> _copyTemporaryShareLink(String url) async {
    if (url.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _tempShareCopyResetTimer?.cancel();
    if (mounted) {
      setState(() => _tempShareLinkCopied = true);
    }
    _tempShareCopyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _tempShareLinkCopied = false);
      }
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard.')),
    );
  }

  Future<({bool cancelled, Duration? ttl})> _askTemporaryShareDuration() async {
    final controller = TextEditingController(text: '30');
    var useNoTimer = false;

    final result = await showDialog<({bool cancelled, Duration? ttl})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Share link timer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: useNoTimer,
                    onChanged: (value) => setLocalState(() => useNoTimer = value ?? false),
                    title: const Text('No auto-stop timer'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    enabled: !useNoTimer,
                    decoration: const InputDecoration(
                      labelText: 'Stop sharing after (minutes)',
                      hintText: 'e.g. 30',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop((cancelled: true, ttl: null)),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (useNoTimer) {
                      Navigator.of(context).pop((cancelled: false, ttl: null));
                      return;
                    }
                    final minutes = int.tryParse(controller.text.trim());
                    if (minutes == null || minutes <= 0) {
                      return;
                    }
                    Navigator.of(context).pop((cancelled: false, ttl: Duration(minutes: minutes)));
                  },
                  child: const Text('Start sharing'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return (cancelled: true, ttl: null);
    }
    return result;
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

class _InstalledAppsPickerDialog extends StatefulWidget {
  const _InstalledAppsPickerDialog({required this.service});

  final AndroidInstalledAppsService service;

  @override
  State<_InstalledAppsPickerDialog> createState() => _InstalledAppsPickerDialogState();
}

class _InstalledAppsPickerDialogState extends State<_InstalledAppsPickerDialog> {
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
          (app) => app.name.toLowerCase().contains(query) || app.packageName.toLowerCase().contains(query),
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
      final apps = await widget.service.listInstalledApps(includeSystemApps: _includeSystemApps);
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _apps = apps;
        _loading = false;
        _selectedPackages.removeWhere((pkg) => !_apps.any((app) => app.packageName == pkg));
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
                  Text('Select installed apps', style: Theme.of(context).textTheme.titleLarge),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredApps.isEmpty
                        ? const Center(child: Text('No installed apps available.'))
                        : ListView.separated(
                            itemCount: _filteredApps.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final app = _filteredApps[index];
                              final selected = _selectedPackages.contains(app.packageName);
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: selected
                                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                                      : Colors.transparent,
                                ),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    backgroundImage: app.iconBytes != null ? MemoryImage(app.iconBytes!) : null,
                                    child: app.iconBytes == null ? const Icon(Icons.android_rounded, size: 18) : null,
                                  ),
                                  title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          app.packageName,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        if (app.isSystemApp)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                              color: Theme.of(context).colorScheme.secondaryContainer,
                                            ),
                                            child: Text(
                                              'System',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
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
                            final selected = _apps.where((app) => _selectedPackages.contains(app.packageName)).toList(growable: false);
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
