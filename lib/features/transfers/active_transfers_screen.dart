import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../widgets/transfer_progress_card.dart';

class ActiveTransfersScreen extends ConsumerWidget {
  const ActiveTransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Active Transfers')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: state.activeTransfers.isEmpty
            ? const Center(child: Text('No active transfers.'))
            : ListView.builder(
                itemCount: state.activeTransfers.length,
                itemBuilder: (context, index) {
                  final transfer = state.activeTransfers[index];
                  return TransferProgressCard(
                    transfer: transfer,
                    onCancel: () => ref.read(appControllerProvider.notifier).cancelTransfer(transfer.id),
                  );
                },
              ),
      ),
    );
  }
}
