import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/apk_inspector_service.dart';
import '../../core/utils/dialog_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../models/apk_info.dart';
import '../../models/transfer_model.dart';

/// Android-only preview shown after receiving a single `.apk` file (never
/// for a file that arrived as part of a multi-file batch): app icon/name,
/// a package-details table, and Close/Delete/Install actions.
class ApkPreviewScreen extends ConsumerStatefulWidget {
  const ApkPreviewScreen({super.key, required this.transfer});

  final TransferModel transfer;

  @override
  ConsumerState<ApkPreviewScreen> createState() => _ApkPreviewScreenState();
}

class _ApkPreviewScreenState extends ConsumerState<ApkPreviewScreen> {
  final ApkInspectorService _inspector = ApkInspectorService();
  ApkInfo? _info;
  bool _loading = true;
  bool _working = false;
  String? _loadError;

  String get _localPath => widget.transfer.localPath?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_localPath.isEmpty || !await File(_localPath).exists()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'The received file is no longer available.';
        });
      }
      return;
    }
    final info = await _inspector.inspect(_localPath);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
      if (info == null) {
        _loadError = 'Could not read this APK file.';
      }
    });
  }

  Future<void> _install() async {
    if (_info == null || _working) return;
    setState(() => _working = true);
    try {
      final started = await _inspector.install(_localPath);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the installer for this file.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _delete() async {
    if (_localPath.isEmpty || _working) return;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDropNetDialog<bool>(
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
            Icons.delete_sweep_rounded,
            color: colorScheme.onErrorContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Delete this app file?',
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
              'Are you sure you want to permanently delete ${widget.transfer.fileName} from this device?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      final file = File(_localPath);
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete file: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Received App'),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(theme, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    final info = _info;
    if (info == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _loadError ?? 'Could not read this file.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Close'),
          ),
        ],
      );
    }

    final eligibility = info.installEligibility;

    final rows = <_InfoRowData>[
      _InfoRowData('Package Name', info.packageName),
      _InfoRowData('Version', info.versionName.isEmpty ? '—' : info.versionName),
      _InfoRowData('APK Size', FileUtils.formatBytes(info.apkSize.toDouble())),
      if (info.isOwnPackage) ...[
        _InfoRowData('Status', info.buildStatus),
        _InfoRowData('Build Number', info.versionCode.toString()),
      ],
      if (info.isInstalled)
        _InfoRowData(
          'Currently Installed',
          (info.installedVersionName?.trim().isNotEmpty ?? false)
              ? info.installedVersionName!.trim()
              : 'Unknown version',
        ),
    ];

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: colorScheme.surfaceContainerHighest,
            ),
            child: info.iconBytes != null
                ? Image.memory(info.iconBytes!, fit: BoxFit.cover)
                : Icon(Icons.android_rounded, size: 56, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            info.appName.isEmpty ? widget.transfer.fileName : info.appName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    _InfoRow(data: rows[i]),
                  ],
                ],
              ),
            ),
          ),
          if (!eligibility.canInstall && eligibility.reason != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      eligibility.reason!,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close'),
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
              if (eligibility.canInstall)
                FilledButton.icon(
                  onPressed: _working ? null : _install,
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: const Text('Install'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.label, this.value);
  final String label;
  final String value;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.data});

  final _InfoRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              data.label,
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
