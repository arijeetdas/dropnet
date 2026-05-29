import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/dialog_utils.dart';

import '../../core/platform/media_store_service.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/transfer_visuals.dart';
import '../../models/transfer_model.dart';

class ReceivedFileScreen extends StatefulWidget {
  const ReceivedFileScreen({
    super.key,
    required this.transfer,
  });

  final TransferModel transfer;

  @override
  State<ReceivedFileScreen> createState() => _ReceivedFileScreenState();
}

class _ReceivedFileScreenState extends State<ReceivedFileScreen> {
  bool _working = false;
  final MediaStoreService _mediaStoreService = const MediaStoreService();

  String get _localPath => widget.transfer.localPath?.trim() ?? '';

  Future<void> _openFile() async {
    if (_localPath.isEmpty || _working) {
      return;
    }

    setState(() => _working = true);
    try {
      final file = File(_localPath);
      if (!await file.exists()) {
        _showMessage('The received file is no longer available.');
        return;
      }

      if (!kIsWeb) {
        if (Platform.isAndroid) {
          final openedByPlatform = await _mediaStoreService.openFileExternally(
            file.path,
          );
          if (openedByPlatform) {
            return;
          }
        }

        final openResult = await OpenFilex.open(file.path);
        if (openResult.type == ResultType.done) {
          return;
        }
      }

      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showMessage('Unable to open this file on the current device.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Failed to open file: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _deleteFile() async {
    if (_localPath.isEmpty || _working) {
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDropNetDialog<bool>(
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
            Icons.delete_sweep_rounded,
            color: colorScheme.onErrorContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Delete received file?',
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
                    'Delete',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _working = true);
    try {
      final file = File(_localPath);
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        _showMessage('Failed to delete file: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Widget _buildRichPreview({
    required BuildContext context,
    required TransferModel transfer,
    required String localPath,
    required Color accent,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final kind = TransferVisuals.kindForName(transfer.fileName);

    if (kind == TransferFileKind.image && localPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(
          File(localPath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _GenericPreview(fileName: transfer.fileName, accent: accent);
          },
        ),
      );
    }

    if (kind == TransferFileKind.video) {
      return _VideoPreview(fileName: transfer.fileName, accent: accent);
    }

    if (kind == TransferFileKind.audio) {
      return _AudioPreview(fileName: transfer.fileName, accent: accent);
    }

    if (kind == TransferFileKind.pdf) {
      return _PdfPreview(fileName: transfer.fileName, accent: accent);
    }

    if (kind == TransferFileKind.document) {
      return _DocPreview(fileName: transfer.fileName, accent: accent);
    }

    return _GenericPreview(fileName: transfer.fileName, accent: accent);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final transfer = widget.transfer;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = TransferVisuals.accentColor(context, transfer.fileName);
    final kindLabel = TransferVisuals.kindLabel(transfer.fileName);


    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Received File'),
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
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.18),
                          colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$kindLabel received successfully',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          transfer.fileName,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _MetaChip(
                              icon: Icons.person_outline_rounded,
                              label: 'From ${transfer.deviceName}',
                            ),
                            _MetaChip(
                              icon: Icons.data_object_rounded,
                              label: FileUtils.formatBytes(transfer.size.toDouble()),
                            ),
                            _MetaChip(
                              icon: Icons.check_circle_rounded,
                              label: transfer.verified ? 'Integrity verified' : 'Saved to device',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: _buildRichPreview(
                        context: context,
                        transfer: transfer,
                        localPath: _localPath,
                        accent: accent,
                        colorScheme: colorScheme,
                        theme: theme,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                        onPressed: _working ? null : _deleteFile,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                      ),
                      FilledButton.icon(
                        onPressed: _working ? null : _openFile,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _GenericPreview extends StatelessWidget {
  const _GenericPreview({
    required this.fileName,
    required this.accent,
  });

  final String fileName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.16),
            colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.04),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: accent.withValues(alpha: 0.05),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: CircleAvatar(
              radius: 80,
              backgroundColor: accent.withValues(alpha: 0.03),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                      width: 2.0,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      TransferVisuals.iconForName(fileName),
                      size: 52,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  TransferVisuals.kindLabel(fileName),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.launch_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        'Preview in Default Application',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.fileName,
    required this.accent,
  });

  final String fileName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.black.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Elegant dark cinema mesh background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  radius: 1.0,
                ),
              ),
            ),
          ),

          // Central Cinematic Play Dashboard
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Cinema Player Ready',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '1080p Ultra-HD Preview',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // High-end video playback deck overlay at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mock glowing video seek scrubber
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: 0.0,
                            minHeight: 5,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        '0:00 / --:--',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 18),
                      const SizedBox(width: 16),
                      const Icon(Icons.hd_rounded, color: Colors.white70, size: 18),
                      const SizedBox(width: 16),
                      const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 22),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioPreview extends StatelessWidget {
  const _AudioPreview({
    required this.fileName,
    required this.accent,
  });

  final String fileName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating Neon Disc Deck Mockup
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ],
                border: Border.all(color: Colors.grey.shade900, width: 6),
              ),
              child: Center(
                // Stylized vinyl grooves & central artwork
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 3),
                  ),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Music Station ready',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            // Premium Glowing Audio wave lines mockup
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _waveBar(16, true),
                _waveBar(28, false),
                _waveBar(42, true),
                _waveBar(24, false),
                _waveBar(38, true),
                _waveBar(52, true),
                _waveBar(34, false),
                _waveBar(20, true),
                _waveBar(32, false),
                _waveBar(12, true),
              ],
            ),
            const SizedBox(height: 24),
            // Audio Media playback scrubber
            Row(
              children: [
                Text(
                  '0:00',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.0,
                      minHeight: 5,
                      backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '--:--',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _waveBar(double height, bool highlight) {
    return Container(
      width: 5,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: highlight
              ? [accent, accent.withValues(alpha: 0.5)]
              : [accent.withValues(alpha: 0.5), accent.withValues(alpha: 0.2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(3),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.2),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({
    required this.fileName,
    required this.accent,
  });

  final String fileName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.picture_as_pdf_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'PDF Reader Hub',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '1 / -- pages',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mockLine(widthFraction: 0.45, height: 12, context: context),
                  const SizedBox(height: 16),
                  _mockLine(widthFraction: 0.95, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.88, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.72, height: 8, context: context),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.01),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(Icons.image_outlined, size: 54, color: colorScheme.outline.withValues(alpha: 0.6)),
                          ),
                          // Premium Floating Zoom dock
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.zoom_in_rounded, size: 14, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'FIT WIDTH',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mockLine({required double widthFraction, required double height, required BuildContext context}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * 0.4 * widthFraction,
      decoration: BoxDecoration(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _DocPreview extends StatelessWidget {
  const _DocPreview({
    required this.fileName,
    required this.accent,
  });

  final String fileName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.article_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Document Sheet Inspector',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Formatting mock toolbar
                  Row(
                    children: [
                      _toolbarIcon(Icons.format_bold_rounded, colorScheme),
                      _toolbarIcon(Icons.format_italic_rounded, colorScheme),
                      _toolbarIcon(Icons.format_underlined_rounded, colorScheme),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 16, color: colorScheme.outlineVariant),
                      const SizedBox(width: 8),
                      _toolbarIcon(Icons.format_align_left_rounded, colorScheme),
                      _toolbarIcon(Icons.format_align_center_rounded, colorScheme),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _mockLine(widthFraction: 0.5, height: 14, context: context),
                  const SizedBox(height: 20),
                  _mockLine(widthFraction: 0.95, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.9, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.92, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.4, height: 8, context: context),
                  const SizedBox(height: 24),
                  _mockLine(widthFraction: 0.6, height: 14, context: context),
                  const SizedBox(height: 16),
                  _mockLine(widthFraction: 0.95, height: 8, context: context),
                  const SizedBox(height: 8),
                  _mockLine(widthFraction: 0.8, height: 8, context: context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarIcon(IconData icon, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _mockLine({required double widthFraction, required double height, required BuildContext context}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * 0.4 * widthFraction,
      decoration: BoxDecoration(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}