import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/apk_inspector_service.dart';
import '../../core/utils/dialog_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../models/apk_info.dart';
import '../../models/transfer_model.dart';
import '../../widgets/github_mark.dart';
import '../../widgets/onboarding_background.dart';

/// Android-only preview shown after receiving a single `.apk` file (never
/// for a file that arrived as part of a multi-file batch): app icon/name,
/// a package-details table, and Close/Delete/Install actions.
///
/// A received DropNet build itself ([ApkInfo.isOwnPackage]) gets a distinct,
/// more expressive presentation — the live animated background otherwise
/// reserved for onboarding, plus quick links to the project. The underlying
/// data/actions are identical either way.
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

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEasterEgg = _info?.isOwnPackage ?? false;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: isEasterEgg
            ? Text(
                'DropNet',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              )
            : null,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _GlassCircleButton(
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (isEasterEgg)
            const OnboardingBackground()
          else
            _AmbientBackground(colorScheme: colorScheme),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(theme, colorScheme, isEasterEgg),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme, bool isEasterEgg) {
    final info = _info;
    if (info == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _loadError ?? 'Could not read this file.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _GlassButton(
            icon: Icons.close_rounded,
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
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
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          _AppIconHalo(
            iconBytes: info.iconBytes,
            colorScheme: colorScheme,
            special: isEasterEgg,
          ),
          const SizedBox(height: 20),
          Text(
            info.appName.isEmpty ? widget.transfer.fileName : info.appName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (isEasterEgg) ...[
            const SizedBox(height: 8),
            _EasterEggBadge(colorScheme: colorScheme),
          ],
          const SizedBox(height: 24),
          _GlassPanel(
            colorScheme: colorScheme,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
                  _InfoRow(data: rows[i]),
                ],
              ],
            ),
          ),
          if (isEasterEgg) ...[
            const SizedBox(height: 20),
            _ProjectLinksRow(colorScheme: colorScheme, onOpenLink: _openLink),
          ],
          if (!eligibility.canInstall && eligibility.reason != null) ...[
            const SizedBox(height: 16),
            _GlassPanel(
              colorScheme: colorScheme,
              tint: colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              _GlassButton(
                icon: Icons.close_rounded,
                label: 'Close',
                onPressed: _working ? null : () => Navigator.of(context).pop(),
              ),
              _GlassButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onPressed: _working ? null : _delete,
              ),
              if (eligibility.canInstall)
                FilledButton.icon(
                  onPressed: _working ? null : _install,
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: const Text('Install'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

/// A calmer, static counterpart to [OnboardingBackground] for the ordinary
/// (non-DropNet) case: two soft blurred washes rather than a live animation.
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -120,
          left: -80,
          child: _blob(colorScheme.primaryContainer, 320),
        ),
        Positioned(
          bottom: -140,
          right: -100,
          child: _blob(colorScheme.tertiaryContainer, 340),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared glass building blocks
// ---------------------------------------------------------------------------

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.colorScheme,
    required this.child,
    this.tint,
    this.padding,
  });

  final ColorScheme colorScheme;
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? colorScheme.surfaceContainerHigh).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: IconButton(icon: Icon(icon), onPressed: onPressed),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, color: colorScheme.onSurface),
            label: Text(label, style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIconHalo extends StatelessWidget {
  const _AppIconHalo({required this.iconBytes, required this.colorScheme, required this.special});

  final Uint8List? iconBytes;
  final ColorScheme colorScheme;
  final bool special;

  @override
  Widget build(BuildContext context) {
    final haloColor = special ? colorScheme.tertiary : colorScheme.primary;
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  haloColor.withValues(alpha: special ? 0.45 : 0.28),
                  haloColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Container(
            width: 100,
            height: 100,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: (special ? colorScheme.tertiary : colorScheme.primary).withValues(alpha: 0.35),
                width: special ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: haloColor.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: iconBytes != null
                ? Image.memory(iconBytes!, fit: BoxFit.cover)
                : Icon(Icons.android_rounded, size: 56, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EasterEggBadge extends StatelessWidget {
  const _EasterEggBadge({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.tertiary, colorScheme.primary],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: colorScheme.onPrimary),
          const SizedBox(width: 6),
          Text(
            'Official Build',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectLinksRow extends StatelessWidget {
  const _ProjectLinksRow({required this.colorScheme, required this.onOpenLink});

  final ColorScheme colorScheme;
  final void Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LinkButton(
          tooltip: 'DropNet Website',
          colorScheme: colorScheme,
          onPressed: () => onOpenLink('https://dropnet.arijeet.in'),
          child: ClipOval(
            child: Image.asset('assets/icon/app_icon.png', width: 26, height: 26, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 16),
        _LinkButton(
          tooltip: 'GitHub Repository',
          colorScheme: colorScheme,
          onPressed: () => onOpenLink('https://git-dropnet.arijeet.in'),
          child: GitHubMark(size: 24, color: colorScheme.onPrimary),
        ),
        const SizedBox(width: 16),
        _LinkButton(
          tooltip: 'Developer',
          colorScheme: colorScheme,
          onPressed: () => onOpenLink('https://arijeetdas.in'),
          child: Icon(Icons.person_rounded, size: 24, color: colorScheme.onPrimary),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.tooltip,
    required this.colorScheme,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(child: child),
          ),
        ),
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
