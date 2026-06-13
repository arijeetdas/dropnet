import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import '../models/device_model.dart';
import 'macos_smiling_logo.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
    this.selected = false,
  });

  final DeviceModel device;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: device.deviceType == DeviceType.macos
                      ? const MacOSSmilingLogo(size: 24)
                      : Icon(_iconForDeviceType(device.deviceType)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.taggedName, style: Theme.of(context).textTheme.titleMedium),
                      Text(device.ipAddress, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: device.isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForDeviceType(DeviceType type) {
    switch (type) {
      case DeviceType.phone:
        return Icons.smartphone;
      case DeviceType.tablet:
        return Icons.tablet_mac;
      case DeviceType.desktop:
        return Icons.desktop_windows;
      case DeviceType.web:
        return Icons.language;
      case DeviceType.other:
        return Icons.devices_other;
      case DeviceType.laptop:
        return Icons.laptop;
      case DeviceType.android:
        return Icons.android;
      case DeviceType.apple:
        return Icons.apple;
      case DeviceType.macos:
        return CupertinoIcons.smiley;
      case DeviceType.windows:
        return Icons.window;
      case DeviceType.linux:
        return Icons.terminal;
    }
  }
}
