import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/platform/device_environment.dart';

/// Full-color logo of the OS this app is installed on, from
/// `assets/platforms/<name>_info.svg`. Falls back to a globe icon on web.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, this.size = 16});

  /// Height of the logo. Wide logos (Android) keep their aspect ratio.
  final double size;

  static String? currentAssetPath() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      return DeviceEnvironment.isChromeOS
          ? 'assets/platforms/chromeOS_info.svg'
          : 'assets/platforms/android_info.svg';
    }
    if (Platform.isIOS) return 'assets/platforms/iOS_info.svg';
    if (Platform.isMacOS) return 'assets/platforms/macOS_info.svg';
    if (Platform.isWindows) return 'assets/platforms/windows_info.svg';
    if (Platform.isLinux) return 'assets/platforms/linux_info.svg';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = currentAssetPath();
    if (assetPath == null) {
      return Icon(
        Icons.language_rounded,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    // The Apple logo is a single black shape: tint it so it reads dark on a
    // light theme and white on a dark theme. Every other logo is full color.
    ColorFilter? colorFilter;
    if (!kIsWeb && Platform.isIOS) {
      final theme = Theme.of(context);
      final tint = theme.brightness == Brightness.dark
          ? Colors.white
          : theme.colorScheme.onSurface;
      colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
    }

    return SvgPicture.asset(
      assetPath,
      height: size,
      fit: BoxFit.contain,
      colorFilter: colorFilter,
      semanticsLabel: DeviceEnvironment.platformDisplayName,
    );
  }
}
