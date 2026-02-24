import 'package:flutter/material.dart';

import '../core/utils/file_utils.dart';

class SpeedIndicator extends StatelessWidget {
  const SpeedIndicator({
    super.key,
    required this.currentSpeed,
    this.eta,
  });

  final double currentSpeed;
  final Duration? eta;

  @override
  Widget build(BuildContext context) {
    final etaLabel = eta == null ? '--' : '${eta!.inMinutes}:${(eta!.inSeconds % 60).toString().padLeft(2, '0')}';
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          tween: Tween(begin: 0, end: currentSpeed),
          builder: (context, value, child) => Text('Speed: ${FileUtils.formatSpeed(value)}'),
        ),
        const Spacer(),
        Text('ETA: $etaLabel'),
      ],
    );
  }
}
