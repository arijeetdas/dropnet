import 'package:flutter/material.dart';

import '../core/networking/tcp_transfer_service.dart';

class DeviceIdentityCard extends StatelessWidget {
  const DeviceIdentityCard({
    super.key,
    required this.deviceName,
    required this.localIp,
    this.ftpPort,
    this.webPort,
  });

  final String deviceName;
  final String localIp;
  final int? ftpPort;
  final int? webPort;

  @override
  Widget build(BuildContext context) {
    final ip = localIp.isEmpty ? 'Unavailable' : localIp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          runSpacing: 10,
          spacing: 14,
          children: [
            _InfoChip(label: 'Device', value: deviceName.isEmpty ? 'Generating…' : deviceName),
            _InfoChip(label: 'IP', value: ip),
            _InfoChip(label: 'Transfer', value: '${TcpTransferService.defaultPort}'),
            _InfoChip(label: 'FTP', value: '${ftpPort ?? 2121}'),
            _InfoChip(label: 'Web', value: '${webPort ?? 8080}'),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
