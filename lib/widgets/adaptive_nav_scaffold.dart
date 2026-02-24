import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/networking/tcp_transfer_service.dart';
import '../core/state/app_state.dart';

class AdaptiveNavScaffold extends ConsumerWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.currentIndex,
    this.title = '',
    required this.child,
    this.actions = const [],
  });

  final int currentIndex;
  final String title;
  final Widget child;
  final List<Widget> actions;

  bool get _hasTitle => title.trim().isNotEmpty;

  static const _items = <({IconData icon, String label, String route})>[
    (icon: Icons.wifi_tethering_rounded, label: 'Receive', route: '/receive'),
    (icon: Icons.send_rounded, label: 'Send', route: '/send'),
    (icon: Icons.language_rounded, label: 'Web', route: '/web'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: 260,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('DropNet', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            selected: i == currentIndex,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                            leading: Icon(_items[i].icon),
                            title: Text(_items[i].label),
                            onTap: () => context.go(_items[i].route),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          if (_hasTitle) Text(title, style: Theme.of(context).textTheme.headlineSmall),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Info',
                            onPressed: () => _showInfoDialog(context, state),
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                          IconButton(
                            tooltip: 'History',
                            onPressed: () => context.push('/history'),
                            icon: const Icon(Icons.history_rounded),
                          ),
                          IconButton(
                            tooltip: 'FTP',
                            onPressed: () => context.push('/ftp'),
                            icon: const Icon(Icons.storage_rounded),
                          ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () => context.push('/settings'),
                            icon: const Icon(Icons.settings_rounded),
                          ),
                          ...actions,
                        ],
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _hasTitle ? Text(title) : null,
        actions: [
          IconButton(
            tooltip: 'Info',
            onPressed: () => _showInfoDialog(context, state),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: 'History',
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'FTP',
            onPressed: () => context.push('/ftp'),
            icon: const Icon(Icons.storage_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
          ...actions,
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (index) => context.go(_items[index].route),
        destinations: [
          for (final item in _items) NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }

  Future<void> _showInfoDialog(BuildContext context, AppState state) {
    final taggedName = state.localDeviceManufacturer.trim().isEmpty
        ? (state.localDeviceName.isEmpty ? 'DropNet Device' : state.localDeviceName)
        : '${state.localDeviceName} • ${state.localDeviceManufacturer.trim()}';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: $taggedName'),
            const SizedBox(height: 6),
            Text('Platform: ${state.localDevicePlatform.isEmpty ? 'Unknown' : state.localDevicePlatform}'),
            const SizedBox(height: 6),
            Text('IP: ${state.localIp.isEmpty ? 'Unavailable' : state.localIp}'),
            const SizedBox(height: 6),
            Text('Port: ${TcpTransferService.defaultPort}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
