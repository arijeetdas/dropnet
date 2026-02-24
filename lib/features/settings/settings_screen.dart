import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Timer? _nameDebounce;
  Timer? _manufacturerDebounce;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _manufacturerController = TextEditingController();
    _loadAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final canEditManufacturer = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (_nameController.text.isEmpty && state.localDeviceBaseName.isNotEmpty) {
      _nameController.text = state.localDeviceBaseName;
    }
    if (_manufacturerController.text.isEmpty && state.localDeviceManufacturer.isNotEmpty) {
      _manufacturerController.text = state.localDeviceManufacturer;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Device', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Device identity updates automatically as you type.', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(appControllerProvider.notifier).randomizeDeviceName();
                          _nameController.text = ref.read(appControllerProvider).localDeviceBaseName;
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name randomized.')));
                        },
                        icon: const Icon(Icons.casino_rounded),
                        label: const Text('Randomize'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manufacturerController,
                      enabled: canEditManufacturer,
                      onChanged: canEditManufacturer ? _scheduleManufacturerUpdate : null,
                      decoration: _fieldDecoration(
                        context,
                        labelText: 'Manufacturer tag',
                        hintText: 'Samsung Galaxy S23 / iPhone 15 / Nothing',
                        prefixIcon: Icons.precision_manufacturing_rounded,
                      ),
                    ),
                    if (!canEditManufacturer)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Auto-detected for this platform (read-only).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text('Platform: ${state.localDevicePlatform.isEmpty ? 'Unknown' : state.localDevicePlatform}', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (canEditManufacturer)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await ref.read(appControllerProvider.notifier).resetDeviceManufacturerToAuto();
                                _manufacturerController.text = ref.read(appControllerProvider).localDeviceManufacturer;
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manufacturer reset to auto.')));
                              },
                              icon: const Icon(Icons.autorenew_rounded),
                              label: const Text('Reset Auto'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Theme', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    if (compact) {
                      return RadioGroup<ThemeMode>(
                        groupValue: state.themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(appControllerProvider.notifier).setThemeMode(value);
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<ThemeMode>(
                              contentPadding: EdgeInsets.zero,
                              value: ThemeMode.system,
                              secondary: const Icon(Icons.settings_suggest_rounded),
                              title: const Text('System Default'),
                            ),
                            RadioListTile<ThemeMode>(
                              contentPadding: EdgeInsets.zero,
                              value: ThemeMode.light,
                              secondary: const Icon(Icons.light_mode),
                              title: const Text('Light'),
                            ),
                            RadioListTile<ThemeMode>(
                              contentPadding: EdgeInsets.zero,
                              value: ThemeMode.dark,
                              secondary: const Icon(Icons.dark_mode),
                              title: const Text('Dark'),
                            ),
                          ],
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_rounded), label: Text('System Default')),
                          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                        ],
                        selected: {state.themeMode},
                        onSelectionChanged: (selection) {
                          ref.read(appControllerProvider.notifier).setThemeMode(selection.first);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Monet Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System uses wallpaper color on Android 12+ and Indigo on unsupported devices.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, icon: Icon(Icons.auto_awesome_rounded), label: Text('System')),
                        ButtonSegment(value: false, icon: Icon(Icons.palette_rounded), label: Text('Other')),
                      ],
                      selected: {state.useSystemAccent},
                      onSelectionChanged: (selection) {
                        ref.read(appControllerProvider.notifier).setUseSystemAccent(selection.first);
                      },
                    ),
                    if (!state.useSystemAccent) ...[
                      const SizedBox(height: 10),
                      Text('Other colors', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                    ],
                    if (!state.useSystemAccent)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._accentOptions.map(
                          (option) => ChoiceChip(
                            label: Text(option.label),
                            avatar: CircleAvatar(radius: 7, backgroundColor: option.color),
                            selected: state.themeSeed.toARGB32() == option.color.toARGB32(),
                            onSelected: (_) => ref.read(appControllerProvider.notifier).setThemeSeed(option.color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Receive', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save location'),
                      subtitle: Text(state.downloadDirectory),
                      trailing: FilledButton.tonal(
                        onPressed: _pickSaveLocation,
                        child: const Text('Choose'),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save photos/videos to gallery'),
                      subtitle: const Text('When enabled, received photos and videos are added to gallery apps.'),
                      value: state.saveMediaToGallery,
                      onChanged: (value) => ref.read(appControllerProvider.notifier).setSaveMediaToGallery(value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('FTP', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-randomize FTP credentials per session'),
                  subtitle: const Text(
                    'When off (default), your custom FTP username and password are retained. Randomize remains available manually in FTP screen.',
                  ),
                  value: state.ftpAutoRandomizeCredentials,
                  onChanged: (value) => ref.read(appControllerProvider.notifier).setFtpAutoRandomizeCredentials(value),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_appVersion.isNotEmpty)
              Column(
                children: [
                  Text(
                    'Version $_appVersion',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Developed by Arijeet Das',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSaveLocation() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) {
      return;
    }
    await ref.read(appControllerProvider.notifier).setDownloadDirectory(path);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save location updated.')));
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _manufacturerDebounce?.cancel();
    _nameController.dispose();
    _manufacturerController.dispose();
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {}
  }
}
