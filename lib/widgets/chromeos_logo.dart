import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Monochrome ChromeOS mark used as a device icon. Tinted like a regular
/// [Icon] so it follows the surrounding icon color in light and dark themes.
class ChromeOSLogo extends StatelessWidget {
  const ChromeOSLogo({
    super.key,
    this.size,
    this.color,
  });

  static const assetPath = 'assets/platforms/ChromeOS.svg';

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveSize = size ?? iconTheme.size ?? 24.0;
    final effectiveColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;

    // The mark fills its whole viewBox, so shrink it slightly to match the
    // visual weight of Material icons, which keep an inner margin.
    final scaledSize = effectiveSize * 0.84;

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: Center(
        child: SvgPicture.asset(
          assetPath,
          width: scaledSize,
          height: scaledSize,
          colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}
