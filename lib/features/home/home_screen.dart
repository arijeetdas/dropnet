import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';
import '../../widgets/device_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DropNet - Nearby Devices'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Badge.count(
              count: state.pendingIncomingRequests.length,
              isLabelVisible: state.pendingIncomingRequests.isNotEmpty,
              child: IconButton(
                tooltip: 'Incoming requests',
                onPressed: () => context.push('/receive'),
                icon: const Icon(Icons.notifications_active_outlined),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(onPressed: () => context.push('/send'), icon: const Icon(Icons.send), label: const Text('Send Files')),
                      OutlinedButton.icon(onPressed: () => context.push('/receive'), icon: const Icon(Icons.download), label: const Text('Receive')),
                      OutlinedButton.icon(onPressed: () => context.push('/transfers'), icon: const Icon(Icons.swap_horiz), label: const Text('Transfers')),
                      OutlinedButton.icon(onPressed: () => context.push('/ftp'), icon: const Icon(Icons.storage), label: const Text('FTP Mode')),
                      OutlinedButton.icon(onPressed: () => context.push('/web'), icon: const Icon(Icons.language), label: const Text('Web Mode')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: state.devices.isEmpty
                          ? const Center(child: Text('No devices discovered yet. Refresh every 3s.'))
                          : ListView.builder(
                              key: ValueKey(state.devices.length),
                              itemCount: state.devices.length,
                              itemBuilder: (context, index) {
                                final device = state.devices[index];
                                return DeviceCard(
                                  device: device,
                                  onTap: () => context.push('/send'),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (MediaQuery.of(context).size.width > 1000)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick Stats', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text('Devices Online: ${state.devices.length}'),
                        Text('Active Transfers: ${state.activeTransfers.length}'),
                        Text('History Entries: ${state.history.length}'),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: () => context.push('/analytics'),
                          icon: const Icon(Icons.analytics_outlined),
                          label: const Text('View Analytics'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => context.push('/settings'),
                          icon: const Icon(Icons.settings),
                          label: const Text('Settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
