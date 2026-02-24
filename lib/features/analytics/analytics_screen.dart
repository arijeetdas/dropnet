import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/file_utils.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.read(appControllerProvider.notifier).analytics();
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 3 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _MetricCard(label: 'Total Files', value: '${analytics['totalFiles']}'),
            _MetricCard(label: 'Completed', value: '${analytics['totalSentOrReceived']}'),
            _MetricCard(label: 'Total Data', value: FileUtils.formatBytes((analytics['totalBytes'] as int).toDouble())),
            _MetricCard(label: 'Average Speed', value: FileUtils.formatSpeed(analytics['avgSpeed'] as double)),
            _MetricCard(label: 'Most Active Device', value: '${analytics['mostActive']}'),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
