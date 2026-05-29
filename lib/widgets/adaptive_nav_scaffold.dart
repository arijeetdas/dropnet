import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  Future<void> _showInfoDialog(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = state.localDeviceName.trim().isEmpty ? 'DropNet Device' : state.localDeviceName;
    final manufacturer = state.localDeviceManufacturer.trim();

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
                  titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  icon: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.primaryContainer.withValues(alpha: 0.5),
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
                    child: Icon(
                      Icons.devices_other_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 32,
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
