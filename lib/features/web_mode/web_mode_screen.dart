import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_state.dart';
import '../../widgets/adaptive_nav_scaffold.dart';

class WebModeScreen extends ConsumerStatefulWidget {
  const WebModeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WebModeScreen> createState() => _WebModeScreenState();
}

class _WebModeScreenState extends ConsumerState<WebModeScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(appControllerProvider);
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
                        color: web.running ? colorScheme.primary : colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            web.running ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: web.running ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              web.running ? 'Web server is running' : 'Web server is stopped',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Chip(
                            avatar: const Icon(Icons.devices_rounded, size: 16),
                            label: Text('${state.connectedWebPeers.length} connected'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        web.running
                            ? 'Web peers can connect with the shared link and request transfers for this active session.'
                            : 'Start the server to accept web device connections.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: web.running ? null : () => ref.read(appControllerProvider.notifier).startWebShare(),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Web Server'),
                          ),
                          OutlinedButton.icon(
                            onPressed: web.running ? () => ref.read(appControllerProvider.notifier).stopWebShare() : null,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Stop'),
                          ),
                          if (web.running)
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: web.url));
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Web link copied.')));
                              },
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Copy Link'),
                            ),
                          if (web.running)
                            OutlinedButton.icon(
                              onPressed: () => launchUrl(Uri.parse(web.url), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.open_in_browser_rounded),
                              label: const Text('Open'),
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
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 620;
                                  final qr = Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      ),
                                      child: QrImageView(
                                        data: web.url,
                                        size: 200,
                                        backgroundColor: isDark ? Colors.black : Colors.white,
                                        eyeStyle: QrEyeStyle(color: isDark ? Colors.white : Colors.black),
                                        dataModuleStyle: QrDataModuleStyle(color: isDark ? Colors.white : Colors.black),
                                      ),
                                    ),
                                  );

                                  final details = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Connection link', style: theme.textTheme.titleMedium),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                        ),
                                        child: SelectableText(web.url),
                                      ),
                                    ],
                                  );

                                  if (compact) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        details,
                                        const SizedBox(height: 14),
                                        qr,
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: details),
                                      const SizedBox(width: 14),
                                      qr,
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          if (state.connectedWebPeers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Connected devices', style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: state.connectedWebPeers
                                          .map(
                                            (peer) => Chip(
                                              avatar: const Icon(Icons.phone_android_rounded, size: 16),
                                              label: Text('${peer.name} (${peer.ip})'),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
