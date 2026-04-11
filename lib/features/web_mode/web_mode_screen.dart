import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('QR Code'),
        content: SizedBox(
          width: 220,
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
              const SizedBox(height: 8),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Only One Web Service Allowed'),
          content: Text(
            '$currentService is already running. For security reasons, $nextService cannot run at the same time.\n\nStop the current service and continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Keep Current'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop Current & Continue'),
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

    return showDialog<({String pin})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Start Web Server'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web peers will be able to send and receive files through the browser.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'PIN Protection',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    CheckboxListTile(
                      value: usePinProtection,
                      onChanged: (v) =>
                          setState(() => usePinProtection = v ?? false),
                      title: const Text('Require PIN to access'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (usePinProtection) ...[
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Visitors must enter this PIN before accessing the web interface.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final pin = usePinProtection
                        ? pinController.text.trim()
                        : '';
                    Navigator.of(context).pop((pin: pin));
                  },
                  child: const Text('Start'),
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
    final colorScheme = theme.colorScheme;
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
                        color: web.running
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            web.running
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: web.running
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              web.running
                                  ? 'Web server is running'
                                  : 'Web server is stopped',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (web.running && web.pin.isNotEmpty) ...[
                            Tooltip(
                              message: 'PIN: ${web.pin}',
                              child: Chip(
                                avatar: const Icon(
                                  Icons.lock_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  web.pin,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.5,
                                    fontSize: 12,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Chip(
                            avatar: const Icon(Icons.devices_rounded, size: 16),
                            label: Text(
                              '${state.connectedWebPeers.length} connected',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        web.running
                            ? 'Web peers connect over HTTPS and can request transfers for this active session.'
                            : 'Start the server to accept web device connections.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (web.running) ...[
                        const SizedBox(height: 6),
                        Text(
                          'First-time browser access may show a local certificate warning before continuing.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: web.running ? null : _startWebServer,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Web Server'),
                          ),
                          OutlinedButton.icon(
                            onPressed: web.running
                                ? () => ref
                                      .read(appControllerProvider.notifier)
                                      .stopWebShare()
                                : null,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Stop'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: web.running
                    ? Column(
                        key: const ValueKey('running-sections'),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connection links',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'First-time browser access may show a local certificate warning before continuing.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // One row per adapter URL
                                  for (final url in (web.urls.isNotEmpty ? web.urls : [web.url]))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(18),
                                                color: colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.35),
                                              ),
                                              child: SelectableText(
                                                url,
                                                style: theme.textTheme.bodySmall,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            tooltip: 'Copy link',
                                            icon: const Icon(Icons.copy_rounded),
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                ClipboardData(text: url),
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Link copied.')),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'Show QR code',
                                            icon: const Icon(Icons.qr_code_rounded),
                                            onPressed: () => _showQrDialog(context, url, isDark),
                                          ),
                                          IconButton(
                                            tooltip: 'Open in browser',
                                            icon: const Icon(Icons.open_in_browser_rounded),
                                            onPressed: () => launchUrl(
                                              Uri.parse(url),
                                              mode: LaunchMode.externalApplication,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connected devices',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 10),
                                  if (state.connectedWebPeers.isEmpty)
                                    Text(
                                      'No devices connected yet.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: state.connectedWebPeers
                                          .map(
                                            (peer) => Chip(
                                              avatar: const Icon(
                                                Icons.phone_android_rounded,
                                                size: 16,
                                              ),
                                              label: Text(
                                                '${peer.name} (${peer.ip})',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('stopped-sections')),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return AdaptiveNavScaffold(currentIndex: 2, child: content);
  }
}
