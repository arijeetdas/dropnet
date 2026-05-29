import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../models/favorite_peer_model.dart';

class FavoriteDevicesScreen extends ConsumerWidget {
  const FavoriteDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Favorite Devices'),
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton.filledTonal(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          if (state.favoritePeers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No favorite devices yet. Tap the Love button in Send to add devices.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.separated(
                itemCount: state.favoritePeers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final peer = state.favoritePeers[index];
                  final onlineDevice = state.devices
                      .where(
                        (device) =>
                            device.deviceId.trim().toLowerCase() ==
                            peer.deviceId.trim().toLowerCase(),
                      )
                      .firstOrNull;
                  final isOnline = onlineDevice?.isOnline ?? false;
                  return _FavoritePeerTile(
                    peer: peer,
                    isOnline: isOnline,
                    onRemove: () async {
                      await ref
                          .read(appControllerProvider.notifier)
                          .removeFavoritePeerByDeviceId(peer.deviceId);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Removed from favorites.'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoritePeerTile extends StatelessWidget {
  const _FavoritePeerTile({
    required this.peer,
    required this.isOnline,
    required this.onRemove,
  });

  final FavoritePeer peer;
  final bool isOnline;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleLines = <String>[
      if (peer.platform.trim().isNotEmpty || peer.manufacturer.trim().isNotEmpty)
        [peer.platform.trim(), peer.manufacturer.trim()]
            .where((part) => part.isNotEmpty)
            .join(' • '),
      if (peer.lastKnownIp.trim().isNotEmpty) 'Last IP: ${peer.lastKnownIp}',
      'Device ID: ${peer.deviceId}',
      'Saved: ${_formatDate(peer.addedAt)}',
      'Last seen: ${_formatDate(peer.lastSeenAt)}',
    ];

    return Card(
      child: ListTile(
        leading: Icon(
          isOnline ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isOnline ? Colors.red : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          peer.deviceName.trim().isEmpty ? peer.deviceId : peer.deviceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitleLines.join('\n')),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Remove favorite',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}
