import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

import '../../models/trusted_peer_model.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/dialog_utils.dart';

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
                      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                        const SizedBox(height: 16),
                        _SettingsDivider(),
                        const SizedBox(height: 16),
                        Text(
                          'App Icon',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Customize the app launcher icon. Applying changes will restart the application automatically.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showAppIconPickerDialog(context),
                            icon: const Icon(Icons.category_rounded),
                            label: const Text('Change App Icon'),
                          ),
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
                        () {
                          final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
                          final versionWidget = Container(
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
                          );

                          if (isAndroid) {
                            return InkWell(
                              onTap: () => _showBuildTypeDetailsDialog(context),
                              borderRadius: BorderRadius.circular(20),
                              child: versionWidget,
                            );
                          }
                          return versionWidget;
                        }(),
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

  Future<void> _showBuildTypeDetailsDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.read(appControllerProvider);

    // Fetch current app icon alias
    String? currentAlias;
    try {
      currentAlias = await FlutterDynamicIconPlus.alternateIconName.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
    } catch (_) {}
    currentAlias ??= 'com.dropnet.MainActivityIcon1';

    const iconsData = [
      (name: 'Default', asset: 'assets/icon/app_icons/foreground_1.png', alias: 'com.dropnet.MainActivityIcon1'),
      (name: 'Yellow', asset: 'assets/icon/app_icons/foreground_2.png', alias: 'com.dropnet.MainActivityIcon2'),
      (name: 'Glass G', asset: 'assets/icon/app_icons/foreground_3.png', alias: 'com.dropnet.MainActivityIcon3'),
      (name: 'Glass Y', asset: 'assets/icon/app_icons/foreground_4.png', alias: 'com.dropnet.MainActivityIcon4'),
    ];

    int activeIndex = iconsData.indexWhere((e) => e.alias == currentAlias);
    if (activeIndex == -1) activeIndex = 0;
    final activeIconAsset = iconsData[activeIndex].asset;

    final abis = state.localDeviceCpuArchitecture
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final bestAbi = abis.isNotEmpty ? abis.first : 'unknown';
    final rawInstalledType = state.installedApkType.isNotEmpty ? state.installedApkType : 'universal';

    // Normalize installedType typography
    String installedType = 'Universal';
    if (rawInstalledType == 'arm-v8a' || rawInstalledType == 'arm64-v8a') {
      installedType = 'arm64-v8a';
    } else if (rawInstalledType == 'arm-v7a' || rawInstalledType == 'armeabi-v7a') {
      installedType = 'armeabi-v7a';
    } else if (rawInstalledType == 'x86_64') {
      installedType = 'x86_64';
    } else if (rawInstalledType == 'x86') {
      installedType = 'x86';
    } else if (rawInstalledType == 'universal') {
      installedType = 'Universal';
    } else {
      installedType = rawInstalledType.isNotEmpty
          ? rawInstalledType[0].toUpperCase() + rawInstalledType.substring(1)
          : 'Universal';
    }

    // Map bestAbi to recommended type string
    String recommendedType = 'Universal';
    if (bestAbi == 'arm64-v8a') {
      recommendedType = 'arm64-v8a';
    } else if (bestAbi == 'armeabi-v7a') {
      recommendedType = 'armeabi-v7a';
    } else if (bestAbi == 'x86_64') {
      recommendedType = 'x86_64';
    } else if (bestAbi == 'x86') {
      recommendedType = 'x86';
    }

    final isUsingRecommended = installedType == recommendedType && installedType != 'Universal';

    if (!context.mounted) return;

    await showDropNetDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          backgroundColor: colorScheme.surface,
          elevation: 6,
          titlePadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          icon: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.5),
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
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  activeIconAsset,
                  width: 44,
                  height: 44,
                ),
              ),
            ),
          ),
          title: Text(
            'DropNet v$_appVersion',
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
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Installed Type',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              installedType,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isUsingRecommended
                              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isUsingRecommended
                                ? colorScheme.primary.withValues(alpha: 0.5)
                                : colorScheme.outlineVariant.withValues(alpha: 0.3),
                            width: isUsingRecommended ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Recommended',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: isUsingRecommended
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: isUsingRecommended ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              recommendedType,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isUsingRecommended
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isUsingRecommended
                        ? const Color(0xFF10B981).withValues(alpha: 0.08)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isUsingRecommended
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isUsingRecommended) ...[
                        const Icon(Icons.stars_rounded, color: Color(0xFF10B981), size: 28),
                        const SizedBox(height: 10),
                        Text(
                          'Congratulations! You are using the build optimized specifically for your device\'s architecture ($bestAbi). This ensures the smallest download size, minimal storage usage, and maximum performance.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ] else ...[
                        Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 28),
                        const SizedBox(height: 10),
                        Text(
                          'We recommend switching to the $recommendedType build because it is optimized for your device\'s $bestAbi architecture. The Universal build contains library support for multiple processor types, making it much larger in download and install size.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'Thank you for using DropNet!',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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
        );
      },
    );
  }

  Future<void> _showAppIconPickerDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String? currentAlias;
    try {
      currentAlias = await FlutterDynamicIconPlus.alternateIconName.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
    } catch (_) {}

    // Map null or any unknown alias to the default Icon 1
    currentAlias ??= 'com.dropnet.MainActivityIcon1';

    const iconsData = [
      (name: 'Default', asset: 'assets/icon/app_icons/foreground_1.png', alias: 'com.dropnet.MainActivityIcon1'),
      (name: 'Yellow', asset: 'assets/icon/app_icons/foreground_2.png', alias: 'com.dropnet.MainActivityIcon2'),
      (name: 'Glass G', asset: 'assets/icon/app_icons/foreground_3.png', alias: 'com.dropnet.MainActivityIcon3'),
      (name: 'Glass Y', asset: 'assets/icon/app_icons/foreground_4.png', alias: 'com.dropnet.MainActivityIcon4'),
    ];

    int initialIndex = iconsData.indexWhere((e) => e.alias == currentAlias);
    if (initialIndex == -1) initialIndex = 0;

    int selectedIndex = initialIndex;

    if (!context.mounted) return;

    await showDropNetDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isChanged = selectedIndex != initialIndex;
            final activeIcon = iconsData[initialIndex];

            return AlertDialog(
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
                      colorScheme.primary,
                      colorScheme.primary.withValues(alpha: 0.5),
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
                  Icons.category_rounded,
                  color: colorScheme.onPrimary,
                  size: 32,
                ),
              ),
              title: Text(
                'Change App Icon',
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
                    Text(
                      'Select a launcher icon below. Applying changes will restart the application automatically.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Current Icon badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Current: ${activeIcon.name}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate((iconsData.length / 3).ceil(), (rowIndex) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: rowIndex < (iconsData.length / 3).ceil() - 1 ? 12 : 0),
                          child: Row(
                            children: List.generate(3, (colIndex) {
                              final index = rowIndex * 3 + colIndex;
                              if (index >= iconsData.length) {
                                return const Expanded(child: SizedBox.shrink());
                              }
                              final item = iconsData[index];
                              final isSelected = selectedIndex == index;
                              final isCurrentlyActive = initialIndex == index;

                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: colIndex == 0 ? 0 : 6,
                                    right: colIndex == 2 ? 0 : 6,
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        selectedIndex = index;
                                      });
                                    },
                                    child: AspectRatio(
                                      aspectRatio: 0.8,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                                              : colorScheme.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                            width: isSelected ? 2.5 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: colorScheme.primary.withValues(alpha: 0.1),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.asset(
                                                item.asset,
                                                width: 48,
                                                height: 48,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                              child: Text(
                                                item.name,
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  fontWeight: isSelected || isCurrentlyActive
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : colorScheme.onSurface,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isChanged
                            ? () async {
                                final state = ref.read(appControllerProvider);
                                final manufacturer = state.localDeviceManufacturer.trim().isNotEmpty
                                    ? state.localDeviceManufacturer
                                    : 'unknown';
                                
                                try {
                                  await FlutterDynamicIconPlus.setAlternateIconName(
                                    iconName: iconsData[selectedIndex].alias,
                                    blacklistManufactures: [manufacturer],
                                    blacklistBrands: [manufacturer],
                                  );
                                } catch (_) {}
                                exit(0);
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
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
            );
          },
        );
      },
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
