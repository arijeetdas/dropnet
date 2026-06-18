import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/dialog_utils.dart';
import '../../models/private_network_profile.dart';

class PrivateNetworksScreen extends ConsumerStatefulWidget {
  const PrivateNetworksScreen({super.key});

  @override
  ConsumerState<PrivateNetworksScreen> createState() =>
      _PrivateNetworksScreenState();
}

class _PrivateNetworksScreenState
    extends ConsumerState<PrivateNetworksScreen> {
  String? _activatingId;
  String? _deletingId;
  String? _exportingId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final profiles = state.privateNetworkProfiles;
    final activeId = state.activePrivateProfileId;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Private Networks'),
            pinned: true,
            backgroundColor: colorScheme.surface,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.upload_file_rounded),
                  tooltip: 'Import profile from file',
                  onPressed: _importFromFile,
                ),
              ),
            ],
          ),

          // ── Header description ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Each profile defines an isolated private network with its own discovery and listening ports. '
                        'Activate a profile to use those ports when Full Private Mode is enabled.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Profile list ───────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: profiles.isEmpty
                ? SliverToBoxAdapter(
                    child: _buildEmptyState(theme, colorScheme),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final profile = profiles[index];
                        final isActive = profile.id == activeId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ProfileCard(
                            profile: profile,
                            isActive: isActive,
                            isActivating: _activatingId == profile.id,
                            isDeleting: _deletingId == profile.id,
                            isExporting: _exportingId == profile.id,
                            onActivate: () => _activateProfile(profile),
                            onEdit: () => _editProfile(profile),
                            onDuplicate: () => _duplicateProfile(profile),
                            onExport: () => _exportProfile(profile),
                            onShare: () => _shareProfile(profile),
                            onDelete: () => _deleteProfile(profile),
                            canDelete: profiles.length > 1,
                          ),
                        );
                      },
                      childCount: profiles.length,
                    ),
                  ),
          ),

          // ── Add Network button ─────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addProfile,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Add Private Network',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_rounded, size: 56, color: colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'No Private Networks',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a private network profile to get started.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _addProfile() async {
    await _showProfileDialog();
  }

  Future<void> _editProfile(PrivateNetworkProfile profile) async {
    await _showProfileDialog(existing: profile);
  }

  Future<void> _activateProfile(PrivateNetworkProfile profile) async {
    if (_activatingId != null) return;
    setState(() => _activatingId = profile.id);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .activatePrivateProfile(profile.id);
      if (!mounted) return;
      _showSnackBar('Switched to "${profile.name}"');
    } finally {
      if (mounted) setState(() => _activatingId = null);
    }
  }

  Future<void> _duplicateProfile(PrivateNetworkProfile profile) async {
    final copy = await ref
        .read(appControllerProvider.notifier)
        .duplicatePrivateProfile(profile.id);
    if (!mounted) return;
    if (copy != null) {
      _showSnackBar('"${copy.name}" created.');
    }
  }

  Future<void> _exportProfile(PrivateNetworkProfile profile) async {
    if (_exportingId != null) return;
    setState(() => _exportingId = profile.id);
    try {
      final path = await ref
          .read(appControllerProvider.notifier)
          .exportPrivateProfile(profile.id);
      if (!mounted) return;
      // Offer to share on mobile; just show path on desktop.
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            subject: '${profile.name}.dnetprofile',
          ),
        );
      } else {
        _showSnackBar('Exported to: $path');
      }
    } catch (e) {
      if (mounted) _showSnackBar('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  Future<void> _shareProfile(PrivateNetworkProfile profile) async {
    if (_exportingId != null) return;
    setState(() => _exportingId = profile.id);
    try {
      final path = await ref
          .read(appControllerProvider.notifier)
          .exportPrivateProfile(profile.id);
      if (!mounted) return;
      ref.read(appControllerProvider.notifier).addPendingSharedFiles([path]);
      _showSnackBar('"${profile.name}.dnetprofile" added to selected files.');
    } catch (e) {
      if (mounted) _showSnackBar('Failed to share: $e');
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  Future<void> _deleteProfile(PrivateNetworkProfile profile) async {
    final confirmed = await _showDeleteConfirmation(profile);
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = profile.id);
    try {
      final error = await ref
          .read(appControllerProvider.notifier)
          .deletePrivateProfile(profile.id);
      if (!mounted) return;
      if (error != null) {
        _showSnackBar(error);
      } else {
        _showSnackBar('"${profile.name}" deleted.');
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      if (!mounted) return;

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      // Read the data first
      final readRes = await ref
          .read(appControllerProvider.notifier)
          .readProfileDataFromFile(path);
      if (readRes.error != null || readRes.data == null) {
        _showSnackBar(readRes.error ?? 'Failed to read profile file.');
        return;
      }

      final data = readRes.data!;
      final name = data['name']?.toString() ?? 'Unnamed';
      final desc = data['description']?.toString() ?? '';
      final discoveryPort = data['discoveryPort'] as int? ?? 0;
      final listeningPort = data['listeningPort'] as int? ?? 0;
      final webPortalPort = data['webPortalPort'] as int?;

      bool activateImmediately = true;

      if (!mounted) return;

      final shouldImport = await showDropNetDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
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
                Icons.download_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 32,
              ),
            ),
            title: Text(
              'Import Private Network',
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.label_rounded, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(
                                desc,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          const Divider(height: 24, thickness: 0.5),
                          Row(
                            children: [
                              Icon(Icons.network_ping_rounded, size: 18, color: colorScheme.secondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Discovery Port: $discoveryPort',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.electrical_services_rounded, size: 18, color: colorScheme.secondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Listening Port: $listeningPort',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          if (webPortalPort != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.language_rounded, size: 18, color: colorScheme.secondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Web Portal Port: $webPortalPort',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Activate immediately'),
                    value: activateImmediately,
                    onChanged: (v) {
                      setLocalState(() {
                        activateImmediately = v ?? true;
                      });
                    },
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
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      child: const Text('Import', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      if (shouldImport != true || !mounted) return;

      // Check duplicate
      final duplicate = ref.read(appControllerProvider.notifier).checkDuplicateProfile(data);
      if (duplicate != null) {
        if (!mounted) return;
        final conflictChoice = await showDropNetDialog<String>(
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
              'Profile Already Exists',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 520,
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
                    'A profile named "$name" or using ports ($discoveryPort, $listeningPort) already exists.\n\nWhat would you like to do?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop('copy'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Import As Copy', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop('replace'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Replace Existing', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop('cancel'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        );

        if (conflictChoice == null || conflictChoice == 'cancel' || !mounted) return;

        final importRes = await ref.read(appControllerProvider.notifier).importProfileWithDetails(
          profileData: data,
          mode: conflictChoice,
          replaceProfileId: duplicate.id,
          activate: activateImmediately,
        );

        if (!mounted) return;
        if (importRes.error != null) {
          _showSnackBar(importRes.error!);
        } else {
          _showSnackBar('Profile "${importRes.profile?.name}" imported successfully.');
        }
      } else {
        // Normal import
        final importRes = await ref.read(appControllerProvider.notifier).importProfileWithDetails(
          profileData: data,
          mode: 'normal',
          activate: activateImmediately,
        );

        if (!mounted) return;
        if (importRes.error != null) {
          _showSnackBar(importRes.error!);
        } else {
          _showSnackBar('Profile "${importRes.profile?.name}" imported successfully.');
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Import failed: $e');
    }
  }

  Future<bool?> _showDeleteConfirmation(
      PrivateNetworkProfile profile) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return showDropNetDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
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
          child: Icon(Icons.delete_outline_rounded,
              color: colorScheme.onErrorContainer, size: 32),
        ),
        title: Text(
          'Delete Profile?',
          style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800, color: colorScheme.onSurface, letterSpacing: -0.5),
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
              'Are you sure you want to delete "${profile.name}"? This action cannot be undone.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
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
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Delete',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showProfileDialog({PrivateNetworkProfile? existing}) async {
    await showDropNetDialog<void>(
      context: context,
      builder: (context) => _ProfileFormDialog(
        existing: existing,
        onSubmit: existing == null ? _handleCreate : _handleUpdate,
      ),
    );
  }

  Future<void> _handleCreate(
      String name, String desc, int disc, int listen, int? web) async {
    final result = await ref
        .read(appControllerProvider.notifier)
        .createPrivateProfile(
          name: name,
          description: desc,
          discoveryPort: disc,
          listeningPort: listen,
          webPortalPort: web,
        );
    if (!mounted) return;
    if (result.error != null) {
      _showSnackBar(result.error!);
    } else {
      _showSnackBar('"${result.profile?.name}" added.');
    }
  }

  Future<void> _handleUpdate(
      String name, String desc, int disc, int listen, int? web) async {
    _showSnackBar('Updated successfully.');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── Profile Card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.isActivating,
    required this.isDeleting,
    required this.isExporting,
    required this.onActivate,
    required this.onEdit,
    required this.onDuplicate,
    required this.onExport,
    required this.onShare,
    required this.onDelete,
    required this.canDelete,
  });

  final PrivateNetworkProfile profile;
  final bool isActive;
  final bool isActivating;
  final bool isDeleting;
  final bool isExporting;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onExport;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.05)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.7)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                // Network lock/status icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isActive ? Icons.vpn_lock_rounded : Icons.lan_outlined,
                    color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (profile.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          profile.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Ports Info ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PortInfoColumn(
                      icon: Icons.network_ping_rounded,
                      label: 'Discovery',
                      port: profile.discoveryPort,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                  ),
                  _divider(colorScheme),
                  Expanded(
                    child: _PortInfoColumn(
                      icon: Icons.electrical_services_rounded,
                      label: 'Listening',
                      port: profile.listeningPort,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                  ),
                  if (profile.webPortalPort != null) ...[
                    _divider(colorScheme),
                    Expanded(
                      child: _PortInfoColumn(
                        icon: Icons.language_rounded,
                        label: 'Web Portal',
                        port: profile.webPortalPort!,
                        colorScheme: colorScheme,
                        theme: theme,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            Divider(
              height: 1,
              thickness: 0.5,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),

            // ── Actions Row ──────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isActive) ...[
                  FilledButton.icon(
                    onPressed: isActivating ? null : onActivate,
                    icon: isActivating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('Activate', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      minimumSize: const Size(0, 40),
                      elevation: 0,
                    ),
                  ),
                ],
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minimumSize: const Size(0, 40),
                    elevation: 0,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  position: PopupMenuPosition.under,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onSelected: (value) {
                    if (value == 'duplicate') onDuplicate();
                    if (value == 'export') onExport();
                    if (value == 'share') onShare();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(Icons.copy_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Duplicate'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(isExporting ? Icons.hourglass_bottom_rounded : Icons.ios_share_rounded, size: 18),
                          const SizedBox(width: 12),
                          Text(isExporting ? 'Exporting...' : 'Export'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Share'),
                        ],
                      ),
                    ),
                    if (canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
                            const SizedBox(width: 12),
                            Text(
                              isDeleting ? 'Deleting...' : 'Delete',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.more_vert_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

// ── Port Info Column ─────────────────────────────────────────────────────────

class _PortInfoColumn extends StatelessWidget {
  const _PortInfoColumn({
    required this.icon,
    required this.label,
    required this.port,
    required this.colorScheme,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final int port;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$port',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ── Profile Form Dialog ──────────────────────────────────────────────────────

typedef _ProfileFormCallback = Future<void> Function(
    String name, String description, int discoveryPort, int listeningPort, int? webPortalPort);

class _ProfileFormDialog extends StatefulWidget {
  const _ProfileFormDialog({
    this.existing,
    required this.onSubmit,
  });

  final PrivateNetworkProfile? existing;
  final _ProfileFormCallback onSubmit;

  @override
  State<_ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends State<_ProfileFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _discPortCtrl;
  late final TextEditingController _listenPortCtrl;
  late final TextEditingController _webPortCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _discPortCtrl =
        TextEditingController(text: e?.discoveryPort.toString() ?? '');
    _listenPortCtrl =
        TextEditingController(text: e?.listeningPort.toString() ?? '');
    _webPortCtrl = TextEditingController(
        text: e?.webPortalPort?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _discPortCtrl.dispose();
    _listenPortCtrl.dispose();
    _webPortCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            widget.existing == null ? Icons.add_moderator_rounded : Icons.edit_note_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          widget.existing == null ? 'New Private Network' : 'Edit Profile',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormField(
                    controller: _nameCtrl,
                    label: 'Network Name',
                    hint: 'e.g. Home, Office, Friends',
                    icon: Icons.label_rounded,
                    colorScheme: colorScheme,
                    theme: theme,
                    validator: (v) =>
                        (v?.trim() ?? '').isEmpty ? 'Name is required.' : null,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _descCtrl,
                    label: 'Description (optional)',
                    hint: 'Short note about this network',
                    icon: Icons.notes_rounded,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FormField(
                          controller: _discPortCtrl,
                          label: 'Discovery Port',
                          hint: '45454',
                          icon: Icons.network_ping_rounded,
                          colorScheme: colorScheme,
                          theme: theme,
                          keyboardType: TextInputType.number,
                          validator: _validatePort,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FormField(
                          controller: _listenPortCtrl,
                          label: 'Listen Port',
                          hint: '45455',
                          icon: Icons.electrical_services_rounded,
                          colorScheme: colorScheme,
                          theme: theme,
                          keyboardType: TextInputType.number,
                          validator: _validatePort,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _webPortCtrl,
                    label: 'Web Portal Port (optional)',
                    hint: 'e.g. 8081',
                    icon: Icons.language_rounded,
                    colorScheme: colorScheme,
                    theme: theme,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final trimmed = v?.trim() ?? '';
                      if (trimmed.isEmpty) return null;
                      return _validatePort(trimmed);
                    },
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
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.existing == null ? 'Add Network' : 'Save',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _validatePort(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Required.';
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 1024 || parsed > 65535) {
      return '1024–65535';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final disc = int.parse(_discPortCtrl.text.trim());
      final listen = int.parse(_listenPortCtrl.text.trim());
      final webRaw = _webPortCtrl.text.trim();
      final web = webRaw.isEmpty ? null : int.tryParse(webRaw);

      if (disc == listen) {
        _showError('Discovery and listening ports must be different.');
        return;
      }

      if (widget.existing != null) {
        final controller = _ProfileFormDialogRef._controllerOf(context);
        if (controller != null) {
          final error = await controller.updatePrivateProfile(
            widget.existing!.copyWith(
              name: _nameCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              discoveryPort: disc,
              listeningPort: listen,
              webPortalPort: web,
              updatedAt: DateTime.now(),
            ),
          );
          if (!mounted) return;
          if (error != null) {
            _showError(error);
            return;
          }
        }
      } else {
        await widget.onSubmit(
          _nameCtrl.text.trim(),
          _descCtrl.text.trim(),
          disc,
          listen,
          web,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ProfileFormDialogRef {
  static AppController? _controllerOf(BuildContext context) {
    try {
      return ProviderScope.containerOf(context).read(appControllerProvider.notifier);
    } catch (_) {
      return null;
    }
  }
}

// ── Form Field Helper ─────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.colorScheme,
    required this.theme,
    this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
