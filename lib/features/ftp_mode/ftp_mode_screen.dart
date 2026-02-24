import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/android_saf_service.dart';
import '../../core/platform/android_storage_service.dart';
import '../../core/networking/ftp_service.dart';
import '../../core/state/app_state.dart';

class FtpModeScreen extends ConsumerStatefulWidget {
  const FtpModeScreen({super.key});

  @override
  ConsumerState<FtpModeScreen> createState() => _FtpModeScreenState();
}

class _FtpModeScreenState extends ConsumerState<FtpModeScreen> {
  static const int _defaultPort = 2121;

  final _port = TextEditingController(text: '2121');
  final _rootDirectoryInput = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final AndroidStorageService _androidStorageService = AndroidStorageService();
  final AndroidSafService _androidSafService = AndroidSafService();
  final List<String> _sharedRoots = <String>[];
  List<AndroidStorageRoot> _detectedStorageRoots = const <AndroidStorageRoot>[];
  List<AndroidSafTree> _persistedSafTrees = const <AndroidSafTree>[];

  bool _anonymous = false;
  bool _readOnly = false;
  bool _busy = false;
  bool _showLogs = true;
  bool _showPassword = false;
  bool _rootInitialized = false;
  bool _credentialsInitialized = false;
  bool _loadingDetectedRoots = false;
  bool _loadingSafTrees = false;

  @override
  void initState() {
    super.initState();
    _loadDetectedStorageRoots();
    _loadPersistedSafTrees();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(appControllerProvider);
    final server = state.ftpState;
    final ftpLink = _ftpLink(server);
    final ftpAuthLink = _ftpAuthLink(server);
    final isDark = theme.brightness == Brightness.dark;

    if (!_rootInitialized) {
      _rootInitialized = true;
      _sharedRoots
        ..clear()
        ..addAll(
          _defaultSharedRoots(
            state.downloadDirectory,
            preferredRoot: state.ftpPreferredStorageRoot,
            detectedRoots: _detectedStorageRoots.map((root) => root.path).toList(growable: false),
          ),
        );
    }

    if (!_credentialsInitialized) {
      _credentialsInitialized = true;
      _username.text = state.ftpSavedUsername;
      _password.text = state.ftpSavedPassword;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('FTP Server')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: 4,
                          color: server.running ? colorScheme.primary : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              server.running ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: server.running ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                server.running ? 'FTP server is running' : 'FTP server is stopped',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Chip(
                              avatar: const Icon(Icons.link_rounded, size: 16),
                              label: Text('${server.activeConnections} active'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (server.running)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            ),
                            child: SelectableText(
                              ftpLink,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        if (server.running && !server.anonymous) const SizedBox(height: 6),
                        if (server.running && !server.anonymous)
                          Text(
                            'Tip: on Windows Explorer, use the plain FTP link and enter username/password when prompted.',
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        if (server.running) const SizedBox(height: 8),
                        if (server.running)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: const Icon(Icons.folder_open_rounded, size: 16),
                                label: Text('${server.sharedRoots.length} shared root'),
                              ),
                              Chip(
                                avatar: const Icon(Icons.network_check_rounded, size: 16),
                                label: Text('Port ${server.port}'),
                              ),
                            ],
                          ),
                        if (server.running) const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: server.running || _busy ? null : () => _startServer(state),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start FTP Server'),
                            ),
                            OutlinedButton.icon(
                              onPressed: !server.running || _busy ? null : _stopServer,
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('Stop'),
                            ),
                            if (server.running)
                              FilledButton.tonalIcon(
                                onPressed: () => _copyLink(ftpLink),
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('Copy Link'),
                              ),
                            if (server.running && !server.anonymous)
                              FilledButton.tonalIcon(
                                onPressed: () => _copyLink(ftpAuthLink),
                                icon: const Icon(Icons.key_rounded),
                                label: const Text('Copy Auth Link'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Configuration', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          value: _anonymous,
                          onChanged: server.running
                              ? null
                              : (value) {
                                  setState(() {
                                    _anonymous = value;
                                  });
                                  if (!value && _username.text.trim().isEmpty && _password.text.trim().isEmpty) {
                                    _username.text = state.ftpSavedUsername;
                                    _password.text = state.ftpSavedPassword;
                                  }
                                },
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Anonymous mode'),
                          subtitle: const Text(
                            'Allow clients to connect without username and password.',
                          ),
                        ),
                        SwitchListTile.adaptive(
                          value: _readOnly,
                          onChanged: server.running ? null : (value) => setState(() => _readOnly = value),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Read-only mode'),
                          subtitle: const Text('Block delete and write operations for connected clients.'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _port,
                          enabled: !server.running,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'Port',
                            helperText: 'FTP port, range: 1-65535',
                            prefixIcon: const Icon(Icons.numbers_rounded),
                            filled: true,
                            suffixIcon: IconButton(
                              tooltip: 'Reset default port',
                              onPressed: server.running
                                  ? null
                                  : () {
                                      _port.text = '$_defaultPort';
                                    },
                              icon: const Icon(Icons.restart_alt_rounded),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _rootDirectoryInput,
                          enabled: !server.running,
                          decoration: InputDecoration(
                            labelText: 'Add shared directory path',
                            helperText: 'Add one or more folders. Multiple roots allow cross-folder operations in FTP.',
                            prefixIcon: const Icon(Icons.folder_rounded),
                            filled: true,
                            suffixIcon: IconButton(
                              tooltip: 'Add shared directory',
                              onPressed: server.running ? null : _addRootFromInput,
                              icon: const Icon(Icons.add_rounded),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: server.running ? null : _pickRootDirectory,
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('Pick folder'),
                            ),
                            OutlinedButton.icon(
                              onPressed: server.running
                                  ? null
                                  : () {
                                      _addSharedRoot(state.downloadDirectory, notify: true);
                                    },
                              icon: const Icon(Icons.shield_rounded),
                              label: Text(
                                Platform.isAndroid ? 'Add App Folder (private)' : 'Add App Folder',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (!server.running)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _suggestedRootDirectories(
                                  state.downloadDirectory,
                                  preferredRoot: state.ftpPreferredStorageRoot,
                                )
                                .map(
                                  (dir) => ActionChip(
                                    avatar: state.ftpPreferredStorageRoot.trim() == dir.trim()
                                        ? const Icon(Icons.star_rounded, size: 16)
                                        : null,
                                    label: Text(_compactDirLabel(dir)),
                                    onPressed: () => _addSharedRoot(dir, notify: true),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        if (!server.running && Platform.isAndroid) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('SAF folders (protected storage)', style: theme.textTheme.titleSmall),
                              if (_loadingSafTrees)
                                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                IconButton(
                                  tooltip: 'Refresh SAF folders',
                                  onPressed: _loadPersistedSafTrees,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              OutlinedButton.icon(
                                onPressed: _pickSafTree,
                                icon: const Icon(Icons.add_link_rounded),
                                label: const Text('Add SAF folder'),
                              ),
                            ],
                          ),
                          if (_persistedSafTrees.isEmpty)
                            Text(
                              'No SAF folder selected yet. Use "Add SAF folder" for protected locations.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            )
                          else
                            ..._persistedSafTrees.map(
                              (tree) {
                                final safRoot = 'saf://${tree.uri}';
                                final selected = _sharedRoots.contains(safRoot);
                                final preferred = state.ftpPreferredStorageRoot.trim() == safRoot;
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.folder_special_rounded),
                                  title: Text(tree.name.isEmpty ? tree.uri : tree.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(tree.uri, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        tooltip: preferred ? 'Preferred SAF root' : 'Set preferred SAF root',
                                        onPressed: () {
                                          ref.read(appControllerProvider.notifier).setFtpPreferredStorageRoot(safRoot);
                                          _showMessage('Preferred FTP root set to SAF folder.');
                                        },
                                        icon: Icon(preferred ? Icons.star_rounded : Icons.star_outline_rounded),
                                      ),
                                      IconButton(
                                        tooltip: selected ? 'Remove from shared roots' : 'Add to shared roots',
                                        onPressed: () {
                                          setState(() {
                                            if (selected) {
                                              _sharedRoots.remove(safRoot);
                                            } else {
                                              _sharedRoots.add(safRoot);
                                            }
                                          });
                                        },
                                        icon: Icon(selected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove SAF permission',
                                        onPressed: () => _releaseSafTree(tree.uri),
                                        icon: const Icon(Icons.link_off_rounded),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                        if (!server.running && _detectedStorageRoots.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('Detected storage', style: theme.textTheme.titleSmall),
                              const Spacer(),
                              if (_loadingDetectedRoots)
                                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                IconButton(
                                  tooltip: 'Refresh storage roots',
                                  onPressed: _loadDetectedStorageRoots,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                            ],
                          ),
                          ..._detectedStorageRoots.map(
                            (root) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                root.isRemovable ? Icons.usb_rounded : Icons.sd_storage_rounded,
                              ),
                              title: Text(root.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${root.label.isEmpty ? 'Storage' : root.label}${root.isRemovable ? ' • Removable' : ''}${root.isPrimary ? ' • Primary' : ''}',
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Set preferred root',
                                    onPressed: () {
                                      ref.read(appControllerProvider.notifier).setFtpPreferredStorageRoot(root.path);
                                      _showMessage('Preferred storage root set.');
                                    },
                                    icon: Icon(
                                      state.ftpPreferredStorageRoot.trim() == root.path.trim()
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Add root',
                                    onPressed: () => _addSharedRoot(root.path, notify: true),
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (!server.running)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Shared directories (${_sharedRoots.length})', style: theme.textTheme.titleSmall),
                              const SizedBox(height: 6),
                              if (_sharedRoots.isEmpty)
                                Text(
                                  'No shared folder added yet.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                )
                              else
                                ..._sharedRoots.map(
                                  (root) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.folder_open_rounded),
                                    title: Text(root, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () => setState(() => _sharedRoots.remove(root)),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _username,
                          enabled: !_anonymous && !server.running,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person_rounded),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !_anonymous && !server.running,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? 'Hide password' : 'Show password',
                              onPressed: (!_anonymous && !server.running)
                                  ? () => setState(() => _showPassword = !_showPassword)
                                  : null,
                              icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            ),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          obscureText: !_showPassword,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: server.running || _anonymous
                                ? null
                                : () {
                                    setState(_applyRandomCredentials);
                                  },
                            icon: const Icon(Icons.casino_rounded),
                            label: const Text('Randomize credentials'),
                          ),
                        ),
                        if (_anonymous)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Anonymous mode is enabled: username/password are ignored.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (server.running) ...[
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.qr_code_rounded, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Scan to connect', style: theme.textTheme.titleMedium),
                            ],
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
                                data: ftpLink,
                                size: 210,
                                backgroundColor: isDark ? Colors.black : Colors.white,
                                eyeStyle: QrEyeStyle(color: isDark ? Colors.white : Colors.black),
                                dataModuleStyle: QrDataModuleStyle(color: isDark ? Colors.white : Colors.black),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (server.running) ...[
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open_rounded, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Shared directory', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (server.sharedRoots.isEmpty)
                            Text(
                              'No shared directory detected.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: server.sharedRoots.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final root = server.sharedRoots[index];
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.26),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.storage_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(root)),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (server.running && server.sharedMounts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.route_rounded, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Mounted FTP roots', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...server.sharedMounts.map(
                            (mount) => Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                              ),
                              child: Text(
                                mount,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Server logs', style: theme.textTheme.titleMedium),
                            const Spacer(),
                            IconButton(
                              tooltip: _showLogs ? 'Collapse logs' : 'Expand logs',
                              onPressed: () => setState(() => _showLogs = !_showLogs),
                              icon: Icon(_showLogs ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                            ),
                          ],
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 180),
                          crossFadeState: _showLogs ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          firstChild: SizedBox(
                            height: 250,
                            child: server.logs.isEmpty
                                ? Center(
                                    child: Text(
                                      'No server logs yet.',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: server.logs.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                                    itemBuilder: (context, index) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                      ),
                                      child: Text(
                                        server.logs[index],
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                          ),
                          secondChild: const SizedBox.shrink(),
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

  @override
  void dispose() {
    _port.dispose();
    _rootDirectoryInput.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  List<String> _defaultSharedRoots(
    String fallback, {
    String preferredRoot = '',
    List<String> detectedRoots = const <String>[],
  }) {
    final preferred = preferredRoot.trim();
    final out = <String>[];

    if (preferred.isNotEmpty) {
      out.add(preferred);
    }

    if (Platform.isAndroid) {
      final roots = <String>{...detectedRoots, '/storage/emulated/0'};
      if (preferred.startsWith('saf://')) {
        roots.clear();
      }
      roots.addAll(_discoverAndroidVolumeRoots());
      out.addAll(roots);
      return out.toSet().toList(growable: false);
    }
    if (Platform.isWindows) {
      final roots = _discoverWindowsDriveRoots();
      if (roots.isNotEmpty) {
        out.addAll(roots);
        return out.toSet().toList(growable: false);
      }
      out.add('C:\\');
      return out.toSet().toList(growable: false);
    }
    if (Platform.isLinux) {
      out.add('/');
      return out.toSet().toList(growable: false);
    }
    if (Platform.isMacOS) {
      out.add('/');
      return out.toSet().toList(growable: false);
    }
    out.add(fallback);
    return out.toSet().toList(growable: false);
  }

  List<String> _discoverWindowsDriveRoots() {
    final drives = <String>[];
    for (var code = 65; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      final root = '$letter:\\';
      try {
        if (Directory(root).existsSync()) {
          drives.add(root);
        }
      } catch (_) {}
    }
    return drives;
  }

  List<String> _discoverAndroidVolumeRoots() {
    final volumes = <String>{};
    try {
      final storageRoot = Directory('/storage');
      if (!storageRoot.existsSync()) {
        return const <String>[];
      }
      for (final entity in storageRoot.listSync(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final path = entity.path;
        final normalized = path.replaceAll('\\', '/').toLowerCase();
        if (normalized == '/storage/emulated' || normalized == '/storage/self') {
          continue;
        }
        volumes.add(path);
      }
    } catch (_) {}
    return volumes.toList(growable: false);
  }

  Future<void> _pickRootDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (!mounted || selected == null || selected.trim().isEmpty) {
      return;
    }
    _addSharedRoot(selected, notify: true);
  }

  void _addRootFromInput() {
    final path = _rootDirectoryInput.text.trim();
    if (path.isEmpty) {
      return;
    }
    _addSharedRoot(path, notify: true);
    _rootDirectoryInput.clear();
  }

  void _addSharedRoot(String path, {bool notify = false}) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_sharedRoots.contains(normalized)) {
      if (notify) {
        _showMessage('Folder already added.');
      }
      return;
    }
    setState(() {
      _sharedRoots.add(normalized);
    });
    if (notify) {
      _showMessage('Added shared folder.');
    }
  }

  List<String> _suggestedRootDirectories(String appDir, {String preferredRoot = ''}) {
    final out = <String>{
      ..._defaultSharedRoots(
        appDir,
        preferredRoot: preferredRoot,
        detectedRoots: _detectedStorageRoots.map((root) => root.path).toList(growable: false),
      ),
      appDir,
    };
    if (Platform.isAndroid) {
      out.add('/storage/emulated/0');
      out.add('/storage/emulated/0/Download');
      out.add('/storage/emulated/0/Documents');
      out.add('/storage/emulated/0/DCIM');
      out.add('/storage/emulated/0/Pictures');
      out.add('/storage/emulated/0/Movies');
      out.addAll(_discoverAndroidVolumeRoots());
    }
    if (Platform.isWindows) {
      out.addAll(_discoverWindowsDriveRoots());
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME']?.trim() ?? '';
      if (home.isNotEmpty) {
        out.add('$home/Downloads');
        out.add('$home/Documents');
        out.add('$home/Pictures');
        out.add('$home/Desktop');
      }
    }
    return out.toList(growable: false);
  }

  Future<void> _loadDetectedStorageRoots() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (mounted) {
      setState(() => _loadingDetectedRoots = true);
    }
    final roots = await _androidStorageService.listStorageRoots();
    if (!mounted) {
      return;
    }
    setState(() {
      _detectedStorageRoots = roots;
      _loadingDetectedRoots = false;
      if (!_rootInitialized) {
        return;
      }
      for (final root in roots) {
        if (!_sharedRoots.contains(root.path)) {
          _sharedRoots.add(root.path);
        }
      }
    });
  }

  Future<void> _loadPersistedSafTrees() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (mounted) {
      setState(() => _loadingSafTrees = true);
    }
    final trees = await _androidSafService.listPersistedTrees();
    if (!mounted) {
      return;
    }
    setState(() {
      _persistedSafTrees = trees;
      _loadingSafTrees = false;
      for (final tree in trees) {
        final safRoot = 'saf://${tree.uri}';
        if (!_sharedRoots.contains(safRoot) &&
            ref.read(appControllerProvider).ftpSafTreeUris.contains(tree.uri)) {
          _sharedRoots.add(safRoot);
        }
      }
    });
  }

  Future<void> _pickSafTree() async {
    final selected = await _androidSafService.pickDirectoryTree();
    if (selected == null || !mounted) {
      return;
    }
    final safRoot = 'saf://${selected.uri}';
    setState(() {
      if (!_sharedRoots.contains(safRoot)) {
        _sharedRoots.add(safRoot);
      }
    });
    await _loadPersistedSafTrees();
    _showMessage('SAF folder added for FTP.');
  }

  Future<void> _releaseSafTree(String uri) async {
    final ok = await _androidSafService.releasePersistedTree(uri);
    if (!ok) {
      _showMessage('Could not remove SAF permission.');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sharedRoots.remove('saf://$uri');
      _persistedSafTrees = _persistedSafTrees.where((tree) => tree.uri != uri).toList(growable: false);
    });
    _showMessage('Removed SAF permission.');
  }

  String _compactDirLabel(String dir) {
    final normalized = dir.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) {
      return dir;
    }
    return parts.last;
  }

  String _ftpLink(FtpServerState server) {
    final host = server.host.trim();
    final resolvedHost = host.isEmpty ? '127.0.0.1' : host;
    return 'ftp://$resolvedHost:${server.port}/';
  }

  String _ftpAuthLink(FtpServerState server) {
    final host = server.host.trim().isEmpty ? '127.0.0.1' : server.host.trim();
    final user = Uri.encodeComponent(server.username);
    final pass = Uri.encodeComponent(server.password);
    return 'ftp://$user:$pass@$host:${server.port}/';
  }

  Future<void> _startServer(AppState state) async {
    var username = _username.text.trim();
    var password = _password.text.trim();
    final roots = _sharedRoots.where((path) => path.trim().isNotEmpty).toList(growable: false);
    if (roots.isEmpty) {
      _showMessage('Add at least one shared directory.');
      return;
    }
    final parsedPort = int.tryParse(_port.text.trim());
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      _showMessage('Port must be between 1 and 65535.');
      return;
    }
    final physicalRoots = roots.where((root) => !root.startsWith('saf://')).toList(growable: false);
    final safRoots = roots.where((root) => root.startsWith('saf://')).toList(growable: false);

    for (final rootDirectory in physicalRoots) {
      final hasStoragePermission = await ref.read(appControllerProvider.notifier).ensureStoragePermission(
            openSettingsIfDenied: true,
            targetPath: rootDirectory,
          );
      if (!hasStoragePermission) {
        _showMessage('Storage permission is required for: $rootDirectory');
        return;
      }

      final hasRootAccess = await _canAccessRootDirectory(rootDirectory);
      if (!hasRootAccess) {
        _showMessage('Cannot access: $rootDirectory');
        return;
      }
    }

    final aliases = <String, int>{};
    for (final root in physicalRoots) {
      final parts = root.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).toList(growable: false);
      final alias = (parts.isEmpty ? root : parts.last).toLowerCase();
      aliases[alias] = (aliases[alias] ?? 0) + 1;
    }
    if (aliases.values.any((count) => count > 1) && physicalRoots.length > 1) {
      _showMessage('Shared folders must have unique last folder names when using multiple roots.');
      return;
    }

    ref.read(appControllerProvider.notifier).setFtpSafTreeUris(
          safRoots.map((item) => item.substring('saf://'.length)).toList(growable: false),
        );
    if (!_anonymous && username.isEmpty) {
      _showMessage('Username is required when anonymous mode is off.');
      return;
    }
    if (!_anonymous && password.isEmpty) {
      _showMessage('Password is required when anonymous mode is off.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (!_anonymous && state.ftpAutoRandomizeCredentials) {
        final generated = ref.read(appControllerProvider.notifier).generateRandomFtpCredentials();
        username = generated.username;
        password = generated.password;
        _username.text = username;
        _password.text = password;
      }

      if (!_anonymous && !state.ftpAutoRandomizeCredentials) {
        ref.read(appControllerProvider.notifier).setFtpSavedCredentials(
              username: username,
              password: password,
            );
      }

      await ref.read(appControllerProvider.notifier).startFtp(
        sharedRoots: roots,
            anonymous: _anonymous,
            readOnly: _readOnly,
            username: username,
            password: password,
            port: parsedPort,
          );
      _showMessage('FTP server started.');
    } catch (_) {
      _showMessage('Failed to start FTP server.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopServer() async {
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).stopFtp();
      _showMessage('FTP server stopped.');
    } catch (_) {
      _showMessage('Failed to stop FTP server.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    _showMessage('FTP link copied.');
  }

  void _applyRandomCredentials() {
    final generated = ref.read(appControllerProvider.notifier).generateRandomFtpCredentials();
    _username.text = generated.username;
    _password.text = generated.password;
    ref.read(appControllerProvider.notifier).setFtpSavedCredentials(
          username: generated.username,
          password: generated.password,
        );
  }

  Future<bool> _canAccessRootDirectory(String rootDirectory) async {
    try {
      final directory = Directory(rootDirectory);
      if (!await directory.exists()) {
        return false;
      }
      await directory.list(followLinks: false).take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
