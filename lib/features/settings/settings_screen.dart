import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/trusted_peer_model.dart';
import '../../core/state/app_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _accentOptions = <({String label, Color color})>[
    (label: 'Blue', color: Colors.blue),
    (label: 'Teal', color: Colors.teal),
    (label: 'Green', color: Colors.green),
    (label: 'Orange', color: Colors.orange),
    (label: 'Pink', color: Colors.pink),
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _manufacturerController;
  late final TextEditingController _maxIncomingRequestsController;
  late final TextEditingController _incomingRequestTimeoutController;
  late final FocusNode _maxIncomingRequestsFocusNode;
  late final FocusNode _incomingRequestTimeoutFocusNode;
  Timer? _nameDebounce;
  Timer? _manufacturerDebounce;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _manufacturerController = TextEditingController();
    _maxIncomingRequestsController = TextEditingController();
    _incomingRequestTimeoutController = TextEditingController();
    _maxIncomingRequestsFocusNode = FocusNode();
    _incomingRequestTimeoutFocusNode = FocusNode();
    _loadAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canEditManufacturer = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (_nameController.text.isEmpty && state.localDeviceBaseName.isNotEmpty) {
      _nameController.text = state.localDeviceBaseName;
    }
    if (_manufacturerController.text.isEmpty && state.localDeviceManufacturer.isNotEmpty) {
      _manufacturerController.text = state.localDeviceManufacturer;
    }
    if (!_maxIncomingRequestsFocusNode.hasFocus) {
      final valueText = state.maxIncomingRequests.toString();
      if (_maxIncomingRequestsController.text != valueText) {
        _maxIncomingRequestsController.value = TextEditingValue(
          text: valueText,
          selection: TextSelection.collapsed(offset: valueText.length),
        );
      }
    }
    if (!_incomingRequestTimeoutFocusNode.hasFocus) {
      final valueText = state.incomingRequestTimeoutSeconds.toString();
      if (_incomingRequestTimeoutController.text != valueText) {
        _incomingRequestTimeoutController.value = TextEditingValue(
          text: valueText,
          selection: TextSelection.collapsed(offset: valueText.length),
        );
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Medium Flexible AppBar
          SliverAppBar.medium(
            title: const Text('Settings'),
            pinned: true,
            backgroundColor: colorScheme.surface,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ───── Section: Device Identity ─────
                _SectionHeader(
                  icon: Icons.badge_rounded,
                  label: 'Device Identity',
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your device name is visible to nearby DropNet peers.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _nameController,
                        onChanged: _scheduleBaseNameUpdate,
                        decoration: _fieldDecoration(
                          context,
                          labelText: 'Device base name',
                          hintText: 'Fine Grape',
                          prefixIcon: Icons.badge_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await ref.read(appControllerProvider.notifier).randomizeDeviceName();
                          _nameController.text = ref.read(appControllerProvider).localDeviceBaseName;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name randomized.')));
                        },
                        icon: const Icon(Icons.casino_rounded, size: 18),
                        label: const Text('Randomize'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _manufacturerController,
                        enabled: canEditManufacturer,
                        onChanged: canEditManufacturer ? _scheduleManufacturerUpdate : null,
                        decoration: _fieldDecoration(
                          context,
                          labelText: 'Manufacturer tag',
                          hintText: 'Samsung Galaxy / iPhone / Nothing',
                          prefixIcon: Icons.precision_manufacturing_rounded,
                        ),
                      ),
                      if (!canEditManufacturer)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Auto-detected for this platform (read-only).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.devices_rounded,
                        label: 'Platform',
                        value: state.localDevicePlatform.isEmpty ? 'Unknown' : state.localDevicePlatform,
                        colorScheme: colorScheme,
                        theme: theme,
                      ),
                      if (canEditManufacturer) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ref.read(appControllerProvider.notifier).resetDeviceManufacturerToAuto();
                            _manufacturerController.text = ref.read(appControllerProvider).localDeviceManufacturer;
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manufacturer reset to auto.')));
                          },
                          icon: const Icon(Icons.autorenew_rounded, size: 18),
                          label: const Text('Reset Auto'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ───── Section: Security ─────
                _SectionHeader(
                  icon: Icons.security_rounded,
                  label: 'Security',
                  color: Colors.deepOrange,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PremiumSwitchTile(
                        icon: Icons.verified_user_rounded,
                        title: 'Require Pairing Code',
                        subtitle: state.requirePairingCodeForDirectTransfers
                            ? 'Only paired devices can transfer files.'
                            : 'Direct transfers are open to discovered devices.',
                        value: state.requirePairingCodeForDirectTransfers,
                        onChanged: (v) => ref.read(appControllerProvider.notifier).setRequirePairingCodeForDirectTransfers(v),
                        accentColor: Colors.deepOrange,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Enable this for safer direct transfers using device pairing.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _SettingsDivider(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.link_rounded, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Paired Devices',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Only paired devices can send files to this device.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (state.trustedPeers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.device_unknown_rounded, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No paired devices yet. Pair devices from the Send screen.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: state.trustedPeers.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final peer = state.trustedPeers[index];
                            final pairingEnabled = state.requirePairingCodeForDirectTransfers;
                            final title = peer.deviceName.trim().isEmpty ? peer.deviceId : peer.deviceName;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.verified_user_rounded, size: 18, color: colorScheme.onPrimaryContainer),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Paired ${_formatPairedAt(peer.pairedAt)}',
                                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: pairingEnabled ? () => _unpairTrustedPeer(peer) : null,
                                    child: const Text('Unpair'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      _SettingsDivider(),
                      const SizedBox(height: 12),
                      _PremiumSwitchTile(
                        icon: Icons.inbox_rounded,
                        title: 'Show incoming request list',
                        subtitle: state.showIncomingRequestList
                            ? 'Requests will be queued before approval.'
                            : 'Requests show approval dialog immediately.',
                        value: state.showIncomingRequestList,
                        onChanged: (v) => ref.read(appControllerProvider.notifier).setShowIncomingRequestList(v),
                        accentColor: colorScheme.primary,
                      ),
                      if (state.showIncomingRequestList) ...[
                        const SizedBox(height: 16),
                        _NumberInputRow(
                          label: 'Maximum incoming requests',
                          icon: Icons.stacked_line_chart_rounded,
                          controller: _maxIncomingRequestsController,
                          focusNode: _maxIncomingRequestsFocusNode,
                          onChanged: (v) {
                            final p = int.tryParse(v);
                            if (p != null) ref.read(appControllerProvider.notifier).setMaxIncomingRequests(p);
                          },
                        ),
                        const SizedBox(height: 12),
                        _NumberInputRow(
                          label: 'Request timeout (seconds)',
                          icon: Icons.timer_rounded,
                          controller: _incomingRequestTimeoutController,
                          focusNode: _incomingRequestTimeoutFocusNode,
                          onChanged: (v) {
                            final p = int.tryParse(v);
                            if (p != null) ref.read(appControllerProvider.notifier).setIncomingRequestTimeoutSeconds(p);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ───── Section: Favorites ─────
                _SectionHeader(
                  icon: Icons.favorite_rounded,
                  label: 'Favorites',
                  color: Colors.pink,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/settings/favorites'),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.pink.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.favorite_outline_rounded, color: Colors.pink, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Favorite devices', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  Text(
                                    state.favoritePeers.isEmpty ? 'No favorites yet' : '${state.favoritePeers.length} device(s) saved',
                                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ───── Section: Theme ─────
                _SectionHeader(
                  icon: Icons.palette_rounded,
                  label: 'Appearance',
                  color: Colors.purple,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme Mode',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(builder: (context, constraints) {
                        final compact = constraints.maxWidth < 430;
                        if (compact) {
                          return Column(
                            children: ThemeMode.values.map((mode) {
                              final icons = {
                                ThemeMode.system: Icons.settings_suggest_rounded,
                                ThemeMode.light: Icons.light_mode_rounded,
                                ThemeMode.dark: Icons.dark_mode_rounded,
                              };
                              final labels = {
                                ThemeMode.system: 'System',
                                ThemeMode.light: 'Light',
                                ThemeMode.dark: 'Dark',
                              };
                              final selected = state.themeMode == mode;
                              return _ThemeOptionTile(
                                icon: icons[mode]!,
                                label: labels[mode]!,
                                selected: selected,
                                onTap: () => ref.read(appControllerProvider.notifier).setThemeMode(mode),
                              );
                            }).toList(),
                          );
                        }
                        return SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_rounded), label: Text('System')),
                            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                          ],
                          selected: {state.themeMode},
                          onSelectionChanged: (s) => ref.read(appControllerProvider.notifier).setThemeMode(s.first),
                        );
                      }),
                      const SizedBox(height: 20),
                      _SettingsDivider(),
                      const SizedBox(height: 16),
                      Text(
                        'Accent Color',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'System uses wallpaper color on Android 12+; Indigo on others.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, icon: Icon(Icons.auto_awesome_rounded), label: Text('System')),
                          ButtonSegment(value: false, icon: Icon(Icons.color_lens_rounded), label: Text('Custom')),
                        ],
                        selected: {state.useSystemAccent},
                        onSelectionChanged: (s) => ref.read(appControllerProvider.notifier).setUseSystemAccent(s.first),
                      ),
                      if (!state.useSystemAccent) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _accentOptions.map((option) {
                            final isSelected = state.themeSeed.toARGB32() == option.color.toARGB32();
                            return GestureDetector(
                              onTap: () => ref.read(appControllerProvider.notifier).setThemeSeed(option.color),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: option.color.withValues(alpha: isSelected ? 1.0 : 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? option.color : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                    width: isSelected ? 3 : 1.5,
                                  ),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: option.color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(Icons.check_rounded, color: isSelected ? Colors.white : option.color, size: 22)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ───── Section: Receive ─────
                _SectionHeader(
                  icon: Icons.download_rounded,
                  label: 'Receive',
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Save location
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.folder_open_rounded, color: Colors.teal, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Save location', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                Text(
                                  state.downloadDirectory,
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _pickSaveLocation,
                            child: const Text('Choose'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SettingsDivider(),
                      const SizedBox(height: 12),
                      _PremiumSwitchTile(
                        icon: Icons.photo_library_rounded,
                        title: 'Save photos/videos to gallery',
                        subtitle: 'Received photos and videos are added to gallery apps.',
                        value: state.saveMediaToGallery,
                        onChanged: (v) => ref.read(appControllerProvider.notifier).setSaveMediaToGallery(v),
                        accentColor: Colors.teal,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ───── Footer ─────
                if (_appVersion.isNotEmpty)
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 15, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                'DropNet v$_appVersion',
                                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                          () {
                            final abis = state.localDeviceCpuArchitecture
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                            if (abis.isNotEmpty) {
                              final bestAbi = abis.first;
                              final installedType = state.installedApkType.isNotEmpty ? state.installedApkType : 'universal';
                              return Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Best supported ABI: $bestAbi',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Installed type: $installedType',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }(),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Developed by Arijeet Das',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSaveLocation() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;
    await ref.read(appControllerProvider.notifier).setDownloadDirectory(path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save location updated.')));
  }

  Future<void> _unpairTrustedPeer(TrustedPeer peer) async {
    try {
      await ref.read(appControllerProvider.notifier).unpairTrustedPeer(peer);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trusted device removed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String _formatPairedAt(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _manufacturerDebounce?.cancel();
    _nameController.dispose();
    _manufacturerController.dispose();
    _maxIncomingRequestsController.dispose();
    _incomingRequestTimeoutController.dispose();
    _maxIncomingRequestsFocusNode.dispose();
    _incomingRequestTimeoutFocusNode.dispose();
    super.dispose();
  }

  void _scheduleBaseNameUpdate(String value) {
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(appControllerProvider.notifier).setDeviceName(value);
    });
  }

  void _scheduleManufacturerUpdate(String value) {
    _manufacturerDebounce?.cancel();
    _manufacturerDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(appControllerProvider.notifier).setDeviceManufacturer(value);
    });
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(prefixIcon),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }
}

// ───────────────────────────────────────────────────────
// Helper Widgets
// ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _PremiumSwitchTile extends StatelessWidget {
  const _PremiumSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: value ? accentColor.withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: value ? accentColor : colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: accentColor,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _NumberInputRow extends StatelessWidget {
  const _NumberInputRow({
    required this.label,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            keyboardType: TextInputType.number,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            const Spacer(),
            if (selected) Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
