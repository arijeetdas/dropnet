import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/dialog_utils.dart';
import '../../core/networking/web_server_service.dart';
import '../../core/state/app_state.dart';
import '../../widgets/adaptive_nav_scaffold.dart';
import '../../widgets/tab_shell_scope.dart';

class WebModeScreen extends ConsumerStatefulWidget {
  const WebModeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WebModeScreen> createState() => _WebModeScreenState();
}

class _WebModeScreenState extends ConsumerState<WebModeScreen> {
  bool _isShellBranchActive(BuildContext context) {
    final scope = TabShellScope.maybeOf(context);
    return scope == null || scope.currentIndex == 2;
  }

  void _showQrDialog(BuildContext context, String url, bool isDark) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDropNetDialog<void>(
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
            Icons.qr_code_2_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        title: Text(
          'QR Code',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 260,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                        data: url,
                        size: 184,
                        eyeStyle: QrEyeStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    url,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
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
                child: FilledButton.tonal(
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
          ),
        ],
      ),
    );
  }

  Future<void> _startWebServer() async {
    final appState = ref.read(appControllerProvider);
    var replaceTemporaryShare = false;
    if (appState.tempLinkShare.running) {
      final decision = await _showWebServiceConflictDialog(
        currentService: 'Temporary share link server',
        nextService: 'Web server',
      );
      if (!mounted || decision == null) {
        return;
      }
      replaceTemporaryShare = decision;
    }

    final options = await _askWebServerOptions();
    if (options == null || !mounted) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .startWebShare(
            pin: options.pin,
            stopTemporaryShareIfRunning: replaceTemporaryShare,
          );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start web server: $error')),
      );
    }
  }

  Future<bool?> _showWebServiceConflictDialog({
    required String currentService,
    required String nextService,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showDropNetDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
              size: 32,
            ),
          ),
          title: Text(
            'Only One Web Service Allowed',
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
                '$currentService is already running. For security reasons, $nextService cannot run at the same time.\n\nStop the current service and continue?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Keep Current',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Stop & Continue',
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
  }

  Future<({String pin})?> _askWebServerOptions() async {
    final pinController = TextEditingController(
      text: WebServerService.generatePin(),
    );
    var usePinProtection = false;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showDropNetDialog<({String pin})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
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
                  Icons.lan_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
              title: Text(
                'Start Web Server',
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
                            Text(
                              'Web peers will be able to send and receive files through the browser.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const Divider(height: 32, thickness: 0.5),
                            Row(
                              children: [
                                Icon(Icons.security_rounded, size: 18, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'PIN Protection',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Theme(
                              data: theme.copyWith(
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: CheckboxListTile(
                                value: usePinProtection,
                                onChanged: (v) =>
                                    setState(() => usePinProtection = v ?? false),
                                title: const Text('Require PIN to access'),
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            if (usePinProtection) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: pinController,
                                decoration: InputDecoration(
                                  labelText: 'PIN',
                                  hintText: 'Auto-generated',
                                  suffixIcon: IconButton(
                                    tooltip: 'Generate new PIN',
                                    icon: const Icon(Icons.refresh_rounded),
                                    onPressed: () => setState(() {
                                      pinController.text =
                                          WebServerService.generatePin();
                                    }),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Visitors must enter this PIN before accessing the web interface.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
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
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final pin = usePinProtection
                              ? pinController.text.trim()
                              : '';
                          Navigator.of(context).pop((pin: pin));
                        },
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Start',
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

  @override
  Widget build(BuildContext context) {
    final isActiveBranch = !widget.embedded || _isShellBranchActive(context);
    if (widget.embedded && !isActiveBranch) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final state = ref.watch(
      appControllerProvider.select(
        (state) => (
          webState: state.webState,
          connectedWebPeers: state.connectedWebPeers,
        ),
      ),
    );
    final web = state.webState;
    final isDark = theme.brightness == Brightness.dark;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: web.running
                ? _buildRunningState(context, web, state.connectedWebPeers, isDark)
                : _buildStoppedState(context),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }
    return AdaptiveNavScaffold(currentIndex: 2, child: content);
  }

  Widget _buildStoppedState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      key: const ValueKey('web-stopped-state'),
      children: [
        const SizedBox(height: 12),
        // Premium central Stopped illustration panel
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.08),
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing gradient badge icon
              _PulsingServerNode(
                isRunning: false,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Web Portal Sharing',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share files instantly with any browser-equipped phone, tablet, or laptop on the same local network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 220,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _startWebServer,
                  icon: const Icon(Icons.play_arrow_rounded),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  label: const Text(
                    'Start Web Server',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'How Browser Sharing Works',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        // Visitor Feature guides
        GridPaper(
          color: Colors.transparent,
          child: Column(
            children: [
              _buildFeatureTile(
                context,
                icon: Icons.phonelink_rounded,
                title: 'No Application Required',
                subtitle: 'Your friends can simply scan a QR code or type your local IP address in Chrome, Safari, or Firefox to start exchanging files.',
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                context,
                icon: Icons.security_rounded,
                title: 'Secure Access Control',
                subtitle: 'Enable custom PIN protection to ensure only authorized visitors can explore or access your shared web network.',
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                context,
                icon: Icons.wifi_rounded,
                title: 'Blazing Fast & Local',
                subtitle: 'Files are sent directly over local Wi-Fi. It is completely offline, utilizes zero cellular data, and guarantees maximum speed.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildRunningState(
    BuildContext context,
    WebShareState web,
    List<WebPeer> connectedPeers,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      key: const ValueKey('web-running-state'),
      children: [
        const SizedBox(height: 12),
        // Active server pulsing node card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PulsingServerNode(
                    isRunning: true,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Web Server is Running',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Listening on local ports',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Secure PIN Chip
                  if (web.pin.isNotEmpty) ...[
                    Tooltip(
                      message: 'Secure PIN Required',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              web.pin,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Stop button
                  IconButton.filledTonal(
                    onPressed: () => ref.read(appControllerProvider.notifier).stopWebShare(),
                    icon: const Icon(Icons.stop_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.7),
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Connection Links Section
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Browser Access Portals',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter one of these addresses in any device\'s browser while connected to the same network. Skip certificate warnings if prompted.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                // One row per adapter URL
                for (final url in (web.urls.isNotEmpty ? web.urls : [web.url]))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SelectableText(
                                url,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _SmallLinkButton(
                            icon: Icons.copy_rounded,
                            tooltip: 'Copy portal link',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: url));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Portal link copied.')),
                              );
                            },
                          ),
                          _SmallLinkButton(
                            icon: Icons.qr_code_rounded,
                            tooltip: 'Show QR Code scanner',
                            onPressed: () => _showQrDialog(context, url, isDark),
                          ),
                          _SmallLinkButton(
                            icon: Icons.open_in_new_rounded,
                            tooltip: 'Open locally',
                            onPressed: () => launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
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
        const SizedBox(height: 16),
        // Connected Clients Grid
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.devices_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Connected Devices',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${connectedPeers.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (connectedPeers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_tethering_off_rounded, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text(
                            'No browsers connected yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: connectedPeers.map((peer) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getBrowserIcon(peer.name),
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${peer.name} (${peer.ip})',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  IconData _getBrowserIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('chrome')) return Icons.language_rounded;
    if (lower.contains('safari')) return Icons.explore_rounded;
    if (lower.contains('firefox')) return Icons.language_rounded;
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('iphone') || lower.contains('ios')) return Icons.phone_iphone_rounded;
    return Icons.computer_rounded;
  }

  Widget _buildFeatureTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
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

class _SmallLinkButton extends StatelessWidget {
  const _SmallLinkButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: IconButton(
          icon: Icon(icon, size: 16),
          color: colorScheme.primary,
          onPressed: onPressed,
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _PulsingServerNode extends StatefulWidget {
  const _PulsingServerNode({
    required this.isRunning,
    required this.child,
  });

  final bool isRunning;
  final Widget child;

  @override
  State<_PulsingServerNode> createState() => _PulsingServerNodeState();
}

class _PulsingServerNodeState extends State<_PulsingServerNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isRunning) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.repeat(reverse: true); // soft pulse Stopped gradient too
    }
  }

  @override
  void didUpdateWidget(covariant _PulsingServerNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // keep pulsing
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + _pulseController.value * (widget.isRunning ? 0.28 : 0.12);
        final opacity = 0.8 - _pulseController.value * 0.6;
        
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outward pulsing ring shadow
            Transform.scale(
              scale: scale,
              child: Container(
                width: widget.isRunning ? 24 : 105,
                height: widget.isRunning ? 24 : 105,
                decoration: BoxDecoration(
                  color: (widget.isRunning ? Colors.green : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}
