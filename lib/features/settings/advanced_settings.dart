import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/dialog_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../models/private_network_profile.dart';

class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  ConsumerState<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends ConsumerState<AdvancedSettingsScreen> {
  late final TextEditingController _customPortController;

  late final FocusNode _customPortFocusNode;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appControllerProvider);
    _customPortController = TextEditingController(text: state.customListeningPort.toString());

    _customPortFocusNode = FocusNode();

    _customPortFocusNode.addListener(_onFocusChange);

    _customPortController.addListener(_onTextChanged);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _customPortController.dispose();

    _customPortFocusNode.removeListener(_onFocusChange);

    _customPortController.removeListener(_onTextChanged);

    _customPortFocusNode.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pairingActive = state.requirePairingCodeForDirectTransfers;

    // Sync input values if not focused
    if (!_customPortFocusNode.hasFocus) {
      final textVal = state.customListeningPort.toString();
      if (_customPortController.text != textVal) {
        _customPortController.text = textVal;
      }
    }

    final bool isCustomPortChanged = _customPortController.text.trim() != state.customListeningPort.toString();
    final bool isCustomPortDefault = state.customListeningPort == 45455 && _customPortController.text.trim() == '45455';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Advanced Settings'),
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
                if (pairingActive) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Require Pairing Code is active. Network connection toggles and ports are restricted to safe defaults.',
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ───── Section: General Settings ─────
                const _SectionHeader(
                  icon: Icons.tune_rounded,
                  label: 'General Settings',
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PremiumSwitchTile(
                        icon: Icons.dynamic_feed_rounded,
                        title: 'Parallel Sending',
                        subtitle: 'Send files to multiple devices concurrently rather than queuing them.',
                        value: state.parallelSendingEnabled,
                        onChanged: (v) => ref.read(appControllerProvider.notifier).setParallelSendingEnabled(v),
                        accentColor: Colors.indigo,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'This combines the send progress charts by device rather than displaying individual file progress tiles.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ───── Section: Network Connection ─────
                _SectionHeader(
                  icon: Icons.lan_rounded,
                  label: 'Network Connection',
                  color: pairingActive ? Colors.grey : Colors.amber.shade800,
                ),
                const SizedBox(height: 12),
                _buildConflictWrapper(
                  disabled: pairingActive,
                  child: _SettingsCard(
                    child: Column(
                      children: [
                        _buildConflictWrapper(
                          disabled: state.fullPrivateModeEnabled,
                          child: _PremiumSwitchTile(
                            icon: Icons.qr_code_scanner_rounded,
                            title: 'Manual Connect via IP',
                            subtitle: 'Connect directly using a QR code or manual IP entry.',
                            value: state.manualConnectEnabled,
                            onChanged: (v) => ref.read(appControllerProvider.notifier).setManualConnectEnabled(v),
                            accentColor: Colors.amber.shade800,
                            enabled: !state.fullPrivateModeEnabled,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _SettingsDivider(),
                        const SizedBox(height: 14),
                        _buildConflictWrapper(
                          disabled: state.fullPrivateModeEnabled,
                          child: _PremiumSwitchTile(
                            icon: Icons.visibility_off_rounded,
                            title: 'Semi-Private Mode',
                            subtitle: 'Disable presence broadcasting (UDP and mDNS) entirely.',
                            value: state.semiPrivateModeEnabled,
                            onChanged: (v) => ref.read(appControllerProvider.notifier).setSemiPrivateModeEnabled(v),
                            accentColor: Colors.amber.shade800,
                            enabled: !state.fullPrivateModeEnabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ───── Section: Ports & Servers ─────
                _SectionHeader(
                  icon: Icons.router_rounded,
                  label: 'Ports & Servers',
                  color: Colors.blueGrey,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildConflictWrapper(
                        disabled: pairingActive || state.fullPrivateModeEnabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _NumberInputRow(
                              label: 'Custom Listening Port',
                              icon: Icons.settings_ethernet_rounded,
                              controller: _customPortController,
                              focusNode: _customPortFocusNode,
                              enabled: !(pairingActive || state.fullPrivateModeEnabled),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: (isCustomPortDefault || pairingActive || state.fullPrivateModeEnabled) ? null : () {
                                    const defaultPort = 45455;
                                    ref.read(appControllerProvider.notifier).setCustomListeningPort(defaultPort);
                                    _customPortController.text = defaultPort.toString();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Custom listening port reset to default (45455)')),
                                    );
                                  },
                                  icon: const Icon(Icons.undo_rounded, size: 16),
                                  label: const Text('Default', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: (!isCustomPortChanged || pairingActive || state.fullPrivateModeEnabled) ? null : () {
                                    final val = _customPortController.text.trim();
                                    final parsed = int.tryParse(val);
                                    if (parsed != null && parsed >= 1024 && parsed <= 65535) {
                                      ref.read(appControllerProvider.notifier).setCustomListeningPort(parsed);
                                      _customPortFocusNode.unfocus();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Custom listening port applied: $parsed')),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Invalid port. Must be between 1024 and 65535.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check_rounded, size: 16),
                                  label: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Standard listening port is 45455. Modifying this changes the listening port used for incoming transfers when full private mode is off.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _SettingsDivider(),
                      const SizedBox(height: 16),
                      _buildConflictWrapper(
                        disabled: pairingActive,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PremiumSwitchTile(
                              icon: Icons.lock_person_rounded,
                              title: 'Full Private Mode',
                              subtitle: 'Create isolated networks using private discovery/listening ports.',
                              value: state.fullPrivateModeEnabled,
                              onChanged: (v) => ref.read(appControllerProvider.notifier).setFullPrivateModeEnabled(v),
                              accentColor: Colors.blueGrey,
                            ),
                            if (state.fullPrivateModeEnabled) ...[
                              const SizedBox(height: 16),
                              // ── Manage Private Networks button ──
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => context.push('/settings/private-networks'),
                                  icon: const Icon(Icons.lan_rounded, size: 18),
                                  label: const Text(
                                    'Manage Private Networks',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              () {
                                PrivateNetworkProfile? activeProfile;
                                for (final p in state.privateNetworkProfiles) {
                                  if (p.id == state.activePrivateProfileId) {
                                    activeProfile = p;
                                    break;
                                  }
                                }
                                if (activeProfile == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.lock_rounded,
                                              size: 16,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Active Private Network',
                                                style: theme.textTheme.labelMedium?.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          activeProfile.name,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (activeProfile.description.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            activeProfile.description,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Discovery Port',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${activeProfile.discoveryPort}',
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Listening Port',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${activeProfile.listeningPort}',
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }(),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Full private mode allows creating hidden networks by utilizing non-default ports for both discovery and listening. Manage your private network profiles to configure port sets.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ───── Section: Troubleshooting ─────
                const _SectionHeader(
                  icon: Icons.bug_report_rounded,
                  label: 'Troubleshooting',
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Column(
                    children: [
                      _PremiumActionTile(
                        icon: Icons.delete_sweep_rounded,
                        title: 'Clear DropNet Folder',
                        subtitle: FileUtils.isDropNetFolder(state.downloadDirectory)
                            ? 'Delete all received files from the DropNet folder and its category subfolders.'
                            : 'Only available when your save location is a folder named "DropNet".',
                        accentColor: Colors.teal,
                        onTap: FileUtils.isDropNetFolder(state.downloadDirectory)
                            ? () => _showClearDropNetFolderDialog(context)
                            : null,
                      ),
                      const SizedBox(height: 14),
                      const _SettingsDivider(),
                      const SizedBox(height: 14),
                      _PremiumActionTile(
                        icon: Icons.cleaning_services_rounded,
                        title: 'Clear App Cache',
                        subtitle: 'Remove temporary files DropNet no longer needs. Never touches your received files.',
                        accentColor: Colors.teal,
                        onTap: () => _showClearAppCacheDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ───── Reset All Settings Button ─────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () async {
                      final theme = Theme.of(context);
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
                              Icons.restart_alt_rounded,
                              color: colorScheme.onErrorContainer,
                              size: 32,
                            ),
                          ),
                          title: Text(
                            'Reset Advanced Settings',
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
                                  'This will completely revert all settings in the Advanced screen to their default values, restart networking, and return to settings.',
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
                                      'Cancel',
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
                                      'Reset',
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
                        await ref.read(appControllerProvider.notifier).resetAdvancedSettings();
                        if (!context.mounted) return;
                        Navigator.of(context).pop(); // Back to Settings Screen
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Reset Advanced Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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

  Future<void> _showClearDropNetFolderDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            Icons.delete_sweep_rounded,
            color: colorScheme.onErrorContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Clear DropNet Folder?',
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
                'This permanently deletes every file in your DropNet folder and in its category subfolders (Documents, Image, Audio, Video, Programs, Code, Text, Compressed, Others). '
                'Those subfolders are kept, but any other folder inside DropNet that the app did not create will be removed entirely. This cannot be undone.',
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
                    'Cancel',
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
                    'Proceed',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    final downloadDirectory = ref.read(appControllerProvider).downloadDirectory;
    await FileUtils.clearDropNetFolder(downloadDirectory);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('DropNet folder cleared.')),
    );
  }

  Future<void> _showClearAppCacheDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            Icons.cleaning_services_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Clear App Cache?',
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
                'This removes temporary files DropNet created for sharing and web transfers that it no longer needs — '
                'never anything in your DropNet folder or your received files. DropNet already clears these automatically from time to time; this does it right now.',
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
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
                    'Proceed',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    await ref.read(appControllerProvider.notifier).clearAppCacheNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App cache cleared.')),
    );
  }

  Widget _buildConflictWrapper({required bool disabled, required Widget child}) {
    if (!disabled) return child;
    return Opacity(
      opacity: 0.45,
      child: IgnorePointer(
        ignoring: true,
        child: child,
      ),
    );
  }
}

// ───────────────────────────────────────────────────────
// Helper Widgets (Mirroring Settings Screen Style)
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
  const _SettingsDivider();
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
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color accentColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool active = enabled && onChanged != null;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: (value && active) ? accentColor.withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: (value && active) ? accentColor : colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: active ? null : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: active ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: active ? onChanged : null,
          activeThumbColor: active ? accentColor : null,
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
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.38)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled ? null : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textAlign: TextAlign.center,
            enabled: enabled,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }
}

class _PremiumActionTile extends StatelessWidget {
  const _PremiumActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool active = onTap != null;
    return InkWell(
      onTap: active ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: active ? accentColor.withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: active ? accentColor : colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: active ? null : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: active ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: active ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
          ],
        ),
      ),
    );
  }
}
