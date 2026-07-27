import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

import '../core/networking/discovery_service.dart';
import '../core/networking/tcp_transfer_service.dart';
import '../core/state/app_state.dart';

class AdaptiveNavScaffold extends ConsumerWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.currentIndex,
    this.title = '',
    required this.child,
    this.actions = const [],
    this.onDestinationSelected,
  });

  final int currentIndex;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final ValueChanged<int>? onDestinationSelected;

  bool get _hasTitle => title.trim().isNotEmpty;

  static const _items = <({IconData icon, String label, String route})>[
    (icon: Icons.wifi_tethering_rounded, label: 'Receive', route: '/receive'),
    (icon: Icons.send_rounded, label: 'Send', route: '/send'),
    (icon: Icons.language_rounded, label: 'Web', route: '/web'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22),
                    Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'DropNet',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            selected: i == currentIndex,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.45),
                            leading: Icon(_items[i].icon),
                            title: Text(_items[i].label),
                            onTap: () => _handleDestinationSelected(context, i),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (_hasTitle)
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          const Spacer(),
                          Builder(
                            builder: (ctx) {
                              final health = ref
                                  .watch(appControllerProvider)
                                  .discoveryHealth;
                              if (health == DiscoveryHealthStatus.healthy) {
                                return const SizedBox.shrink();
                              }
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton.filled(
                                    tooltip: health == DiscoveryHealthStatus.noNetwork
                                        ? 'No network connection'
                                        : 'Discovery issue detected',
                                    style: IconButton.styleFrom(
                                      backgroundColor: Theme.of(ctx).colorScheme.error,
                                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                                    ),
                                    onPressed: () => _showNetworkWarningDialog(
                                      ctx,
                                      health,
                                    ),
                                    icon: const Icon(Icons.warning_amber_rounded),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                              );
                            },
                          ),
                          IconButton.filled(
                            tooltip: 'Info',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                            onPressed: () => _showInfoDialog(
                              context,
                              ref.read(appControllerProvider),
                            ),
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            tooltip: 'History',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                            onPressed: () => context.push('/history'),
                            icon: const Icon(Icons.history_rounded),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            tooltip: 'Settings',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
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

    final mobileScaffold = Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: _hasTitle ? Text(title) : null,
        actions: [
          // Network-health warning button (Fix #2) — visible only when
          // discovery is degraded.  Placed to the left of the Info button.
          Builder(
            builder: (ctx) {
              final health = ref
                  .watch(appControllerProvider)
                  .discoveryHealth;
              if (health == DiscoveryHealthStatus.healthy) {
                return const SizedBox.shrink();
              }
              return IconButton.filled(
                tooltip: health == DiscoveryHealthStatus.noNetwork
                    ? 'No network connection'
                    : 'Discovery issue detected',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => _showNetworkWarningDialog(ctx, health),
                icon: const Icon(Icons.warning_amber_rounded),
              );
            },
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: 'Info',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            onPressed: () => _showInfoDialog(
              context,
              ref.read(appControllerProvider),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
                          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: 'History',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.history_rounded),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: 'Settings',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: 8),
          ...actions,
        ],
      ),
      body: child,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Container(
            // Outer container for shadow only (prevents shadow from being clipped by ClipRRect)
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Builder(
                          builder: (context) {
                            final item = _items[i];
                            final isSelected = i == (currentIndex < 0 ? 0 : currentIndex);
                            final theme = Theme.of(context);
                            final inactiveColor = theme.colorScheme.onSurfaceVariant;
                            
                            return Expanded(
                              flex: isSelected ? 4 : 3,
                              child: GestureDetector(
                                onTap: () => _handleDestinationSelected(context, i),
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  height: double.infinity,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.fastOutSlowIn,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isSelected ? 16 : 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        color: isSelected
                                            ? theme.colorScheme.primaryContainer
                                            : Colors.transparent,
                                      ),
                                      child: AnimatedSize(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.fastOutSlowIn,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              item.icon,
                                              color: isSelected
                                                  ? theme.colorScheme.onPrimaryContainer
                                                  : inactiveColor,
                                              size: 24,
                                            ),
                                            ClipRect(
                                              child: AnimatedOpacity(
                                                duration: const Duration(milliseconds: 200),
                                                opacity: isSelected ? 1.0 : 0.0,
                                                child: isSelected
                                                    ? Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            item.label,
                                                            style: theme.textTheme.labelLarge?.copyWith(
                                                              color: theme.colorScheme.onPrimaryContainer,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                            maxLines: 1,
                                                          ),
                                                        ],
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return BackButtonListener(
      onBackButtonPressed: () async {
        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator.canPop()) {
          // Let top routes like History/Settings handle back first.
          return false;
        }

        if (currentIndex == 0) {
          if (!kIsWeb && Platform.isAndroid) {
            await SystemNavigator.pop();
            return true;
          }
          return Navigator.of(context).maybePop();
        }

        _handleDestinationSelected(context, 0);
        return true;
      },
      child: mobileScaffold,
    );
  }

  void _handleDestinationSelected(BuildContext context, int index) {
    final callback = onDestinationSelected;
    if (callback != null) {
      callback(index);
      return;
    }
    context.go(_items[index].route);
  }

  /// Shows the network-health warning dialog.  The content adapts based on
  /// whether the issue is a missing network or a router-level broadcast block.
  Future<void> _showNetworkWarningDialog(
    BuildContext context,
    DiscoveryHealthStatus health,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isNoNetwork = health == DiscoveryHealthStatus.noNetwork;

    final title = isNoNetwork ? 'No Network Connection' : 'Discovery Issue Detected';

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: anim1.value * 6,
            sigmaY: anim1.value * 6,
          ),
          child: ScaleTransition(
            scale: curve,
            child: FadeTransition(
              opacity: anim1,
              child: PopScope(
                canPop: false,
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  backgroundColor: colorScheme.surface,
                  elevation: 6,
                  titlePadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  icon: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.error,
                          colorScheme.error.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.error.withValues(alpha: 0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: colorScheme.onError,
                      size: 34,
                    ),
                  ),
                  title: Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Primary explanation card.
                        Card(
                          elevation: 0,
                          color: colorScheme.errorContainer.withValues(alpha: 0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: colorScheme.error.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isNoNetwork
                                          ? Icons.signal_wifi_off_rounded
                                          : Icons.router_rounded,
                                      size: 20,
                                      color: colorScheme.error,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isNoNetwork
                                            ? 'Not connected to a network'
                                            : 'Router is blocking device broadcasts',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  isNoNetwork
                                      ? 'DropNet requires a local network (Wi-Fi or Ethernet) to discover nearby devices and perform transfers. Please connect this device to the same network as your peers.'
                                      : 'DropNet is connected to a network and is actively sending discovery signals, but no devices have responded. Your router may have AP Isolation or multicast suppression enabled, which prevents wireless clients from communicating directly with each other.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onErrorContainer
                                        .withValues(alpha: 0.85),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!isNoNetwork) ...[
                          const SizedBox(height: 14),
                          // Tips card for broadcast-blocked scenario.
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.tips_and_updates_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'How to fix this',
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _buildTipRow(
                                    context,
                                    index: '1',
                                    text:
                                        'Open your router\'s admin panel (usually 192.168.1.1 or 192.168.0.1) in a browser.',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildTipRow(
                                    context,
                                    index: '2',
                                    text:
                                        'Look for \'AP Isolation\', \'Client Isolation\', or \'Wireless Isolation\' settings and disable them.',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildTipRow(
                                    context,
                                    index: '3',
                                    text:
                                        'Ensure all devices are on the same Wi-Fi band (2.4 GHz or 5 GHz) and the same SSID.',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildTipRow(
                                    context,
                                    index: '4',
                                    text:
                                        'Note: DropNet continues to probe previously-seen devices via unicast. If you have ever discovered a device before, it may still appear shortly.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Got it',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds a numbered tip row used inside the warning dialog.
  Widget _buildTipRow(
    BuildContext context, {
    required String index,
    required String text,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              index,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showInfoDialog(BuildContext context, AppState state) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = state.localDeviceName.trim().isEmpty ? 'DropNet Device' : state.localDeviceName;
    final manufacturer = state.localDeviceManufacturer.trim();

    String activeIconAsset = 'assets/icon/app_icon.png';
    if (!kIsWeb && Platform.isAndroid) {
      String? currentAlias;
      try {
        currentAlias = await FlutterDynamicIconPlus.alternateIconName.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => null,
        );
      } catch (_) {}
      currentAlias ??= 'com.dropnet.MainActivityIcon1';

      const iconsData = [
        (asset: 'assets/icon/app_icons/foreground_1.png', alias: 'com.dropnet.MainActivityIcon1'),
        (asset: 'assets/icon/app_icons/foreground_2.png', alias: 'com.dropnet.MainActivityIcon2'),
        (asset: 'assets/icon/app_icons/foreground_3.png', alias: 'com.dropnet.MainActivityIcon3'),
        (asset: 'assets/icon/app_icons/foreground_4.png', alias: 'com.dropnet.MainActivityIcon4'),
      ];

      int activeIndex = iconsData.indexWhere((e) => e.alias == currentAlias);
      if (activeIndex == -1) activeIndex = 0;
      activeIconAsset = iconsData[activeIndex].asset;
    }

    if (!context.mounted) return;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Device Information',
      barrierColor: Colors.black.withValues(alpha: 0.54),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: anim1.value * 6,
            sigmaY: anim1.value * 6,
          ),
          child: ScaleTransition(
            scale: curve,
            child: FadeTransition(
              opacity: anim1,
              child: PopScope(
                canPop: false,
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  backgroundColor: colorScheme.surface,
                  elevation: 6,
                  titlePadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  icon: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          activeIconAsset,
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    'Device Information',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildInfoRow(
                                  context,
                                  icon: Icons.badge_rounded,
                                  label: 'Device Name',
                                  value: name,
                                ),
                                if (manufacturer.isNotEmpty) ...[
                                  const Divider(height: 24, thickness: 0.5),
                                  _buildInfoRow(
                                    context,
                                    icon: Icons.precision_manufacturing_rounded,
                                    label: 'Manufacturer',
                                    value: manufacturer,
                                  ),
                                ],
                                const Divider(height: 24, thickness: 0.5),
                                _buildInfoRow(
                                  context,
                                  icon: Icons.language_rounded,
                                  label: 'Platform',
                                  value: state.localDevicePlatform.isEmpty
                                      ? 'Unknown'
                                      : state.localDevicePlatform,
                                ),
                                const Divider(height: 24, thickness: 0.5),
                                _buildInfoRow(
                                  context,
                                  icon: Icons.lan_rounded,
                                  label: 'Service Port',
                                  value: TcpTransferService.defaultPort.toString(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (state.localIps.isNotEmpty)
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.wifi_tethering_rounded,
                                        size: 20,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'IP Addresses',
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  for (final ip in state.localIps)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.subdirectory_arrow_right_rounded,
                                            size: 16,
                                            color: colorScheme.primary.withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SelectableText(
                                              ip,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        else
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: _buildInfoRow(
                                context,
                                icon: Icons.wifi_tethering_off_rounded,
                                label: 'IP Address',
                                value: state.localIp.isEmpty ? 'Unavailable' : state.localIp,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
