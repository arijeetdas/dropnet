import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/dialog_utils.dart';
import '../../widgets/adaptive_nav_scaffold.dart';
import '../../widgets/tab_shell_scope.dart';

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.36, end: 0.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool _isShellBranchActive(BuildContext context) {
    final scope = TabShellScope.maybeOf(context);
    return scope == null || scope.currentIndex == 0;
  }

  @override
  Widget build(BuildContext context) {
    final isBranchActive = !widget.embedded || _isShellBranchActive(context);
    if (isBranchActive) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      return const SizedBox.shrink();
    } else {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(
      appControllerProvider.select(
        (state) => (
          localDeviceBaseName: state.localDeviceBaseName,
          localDeviceNumber: state.localDeviceNumber,
          localDevicePlatform: state.localDevicePlatform,
          localDeviceManufacturer: state.localDeviceManufacturer,
          localIp: state.localIp,
          quickSaveMode: state.quickSaveMode,
          quickSaveDismissedModes: state.quickSaveInfoDismissedModes,
          pairingRequired: state.requirePairingCodeForDirectTransfers,
          showIncomingRequestList: state.showIncomingRequestList,
          pendingRequestsCount: state.pendingIncomingRequests.length,
        ),
      ),
    );
    final quickSaveLocked = state.pairingRequired;
    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = MediaQuery.sizeOf(context);
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : viewport.width;
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : viewport.height;
          final isCompactHeight = availableHeight < 680;
          final isNarrow = availableWidth < 380;
          final horizontalPadding = isNarrow ? 12.0 : 16.0;
          final topPadding = isCompactHeight ? 12.0 : 18.0;
          final systemBottom = MediaQuery.paddingOf(context).bottom;
          final bottomPadding = widget.embedded ? (106.0 + systemBottom) : (24.0 + systemBottom);
          final radarSize = (availableWidth * (isNarrow ? 0.58 : 0.52))
              .clamp(
                isCompactHeight ? 164.0 : 184.0,
                isCompactHeight ? 212.0 : 240.0,
              )
              .toDouble();
          final orbSize = radarSize * 0.46;
          final glowSize = radarSize * 0.58;
          final platformIconSize = radarSize * 0.2;
          final sectionGap = isCompactHeight ? 18.0 : 28.0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (availableHeight - topPadding - bottomPadding)
                    .clamp(0.0, double.infinity)
                    .toDouble(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Floating pending requests banner or chip
                      if (state.showIncomingRequestList && state.pendingRequestsCount > 0) ...[
                        GestureDetector(
                          onTap: () => context.push('/receive/incoming-requests'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.errorContainer,
                                  colorScheme.errorContainer.withValues(alpha: 0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: colorScheme.error.withValues(alpha: 0.28),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.error.withValues(alpha: 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.error.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.mark_email_unread_rounded,
                                    color: colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pending Transfer Requests',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          color: colorScheme.onErrorContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'You have ${state.pendingRequestsCount} incoming file request(s) waiting for approval.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onErrorContainer.withValues(alpha: 0.85),
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: colorScheme.error.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (state.showIncomingRequestList) ...[
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _IncomingRequestsChip(
                              count: 0,
                              onTap: () => context.push('/receive/incoming-requests'),
                            ),
                          ),
                        ),
                      ],

                      // central Radar Pulsing block
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: radarSize,
                            height: radarSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: Size.square(radarSize),
                                  painter: _RadarPulsePainter(
                                    _pulseController,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _scaleAnimation.value,
                                      child: Container(
                                        width: glowSize,
                                        height: glowSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colorScheme.primary.withValues(
                                            alpha: _opacityAnimation.value * 0.4,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Container(
                                  width: orbSize,
                                  height: orbSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primaryContainer,
                                        colorScheme.primaryContainer.withValues(
                                          alpha: 0.4,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.25,
                                        ),
                                        blurRadius: 24,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    _getPlatformIcon(state.localDevicePlatform),
                                    size: platformIconSize,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _PulsingDot(color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Ready to Receive',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: sectionGap),

                      // Premium Device Identity Card
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.surfaceContainerLow,
                                colorScheme.surfaceContainer.withValues(alpha: 0.5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: colorScheme.primary.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getPlatformIcon(state.localDevicePlatform),
                                          size: 14,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          state.localDevicePlatform.toUpperCase(),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: colorScheme.secondary.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Text(
                                      '#${state.localDeviceNumber}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.secondary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Text(
                                state.localDeviceBaseName.isEmpty
                                    ? 'DropNet Device'
                                    : state.localDeviceBaseName,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              if (state.localDeviceManufacturer.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  state.localDeviceManufacturer,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              const Divider(height: 32, thickness: 0.5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.wifi_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text(
                                    state.localIp.isNotEmpty ? 'IP: ${state.localIp}' : 'Offline / Checking IP...',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),

                      // Quick Save Settings
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Quick Save Mode',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (quickSaveLocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Quick Save is disabled while pairing mode is enabled.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: _SlidingQuickSaveSelector(
                              selectedMode: state.quickSaveMode,
                              disabled: quickSaveLocked,
                              onChanged: (mode) => _onQuickSaveModeTapped(
                                mode,
                                dismissedModes: state.quickSaveDismissedModes,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
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
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (state.quickSaveMode == QuickSaveMode.off
                                              ? colorScheme.primary
                                              : state.quickSaveMode == QuickSaveMode.favorites
                                                  ? Colors.amber
                                                  : Colors.orange)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      state.quickSaveMode == QuickSaveMode.off
                                          ? Icons.verified_user_rounded
                                          : state.quickSaveMode == QuickSaveMode.favorites
                                              ? Icons.star_rounded
                                              : Icons.gpp_maybe_rounded,
                                      size: 18,
                                      color: state.quickSaveMode == QuickSaveMode.off
                                          ? colorScheme.primary
                                          : state.quickSaveMode == QuickSaveMode.favorites
                                              ? Colors.amber
                                              : Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          state.quickSaveMode == QuickSaveMode.off
                                              ? 'High Security Active'
                                              : state.quickSaveMode == QuickSaveMode.favorites
                                                  ? 'Trusted Auto-Save'
                                                  : 'Open Auto-Save',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          state.quickSaveMode == QuickSaveMode.off
                                              ? 'Manual approval required for all file transfers.'
                                              : state.quickSaveMode == QuickSaveMode.favorites
                                                  ? 'Only favorited devices are auto-saved. Others require approval.'
                                                  : 'All incoming files are auto-saved without confirmation.',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return AdaptiveNavScaffold(currentIndex: 0, child: content);
  }

  IconData _getPlatformIcon(String platform) {
    final lower = platform.toLowerCase().trim();
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('ios') ||
        lower.contains('iphone') ||
        lower.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (lower.contains('windows')) return Icons.laptop_windows_rounded;
    if (lower.contains('macos') || lower.contains('mac')) {
      return Icons.laptop_mac_rounded;
    }
    if (lower.contains('linux')) return Icons.settings_suggest_rounded;
    return Icons.devices_rounded;
  }

  Future<void> _onQuickSaveModeTapped(
    QuickSaveMode mode, {
    required Set<QuickSaveMode> dismissedModes,
  }) async {
    ref.read(appControllerProvider.notifier).setQuickSaveMode(mode);

    if (dismissedModes.contains(mode)) {
      return;
    }

    await _showQuickSaveConsequencesDialog(mode);
  }

  Future<void> _showQuickSaveConsequencesDialog(QuickSaveMode mode) async {
    var dontShowAgain = false;
    final title = switch (mode) {
      QuickSaveMode.on => 'Quick Save: On',
      QuickSaveMode.favorites => 'Quick Save: Favorites',
      QuickSaveMode.off => 'Quick Save: Off',
    };
    final message = switch (mode) {
      QuickSaveMode.on =>
        'All incoming transfer requests will be auto-approved from every device on your network. Use this only on trusted networks.',
      QuickSaveMode.favorites =>
        'Only favorite devices will be auto-approved. Requests from other devices still require manual approval.',
      QuickSaveMode.off =>
        'All incoming transfers require manual approval, which is the safest default behavior.',
    };

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDanger = mode == QuickSaveMode.on;

    await showDropNetDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
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
                      isDanger
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      isDanger
                          ? colorScheme.errorContainer.withValues(alpha: 0.5)
                          : colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isDanger ? colorScheme.error : colorScheme.primary)
                              .withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isDanger ? Icons.gpp_maybe_rounded : Icons.shield_rounded,
                  color: isDanger
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                  size: 32,
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
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Theme(
                      data: theme.copyWith(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                      ),
                      child: CheckboxListTile(
                        value: dontShowAgain,
                        onChanged: (value) =>
                            setLocalState(() => dontShowAgain = value ?? false),
                        title: Text(
                          'Do not show again',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
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
            );
          },
        );
      },
    );

    if (!mounted || !dontShowAgain) {
      return;
    }
    ref
        .read(appControllerProvider.notifier)
        .setQuickSaveInfoDismissed(mode: mode, dismissed: true);
  }
}

class _RadarPulsePainter extends CustomPainter {
  _RadarPulsePainter(this.animation, {required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw sonar sweep background
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, sweepPaint);

    // Static concentric background circles
    final dottedPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    for (int r = 1; r <= 3; r++) {
      canvas.drawCircle(center, maxRadius * (r / 3.0), dottedPaint);
    }

    // Dynamic expanding pulse waves
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < 4; i++) {
      final t = (animation.value + i / 4.0) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1.0 - t) * 0.42;
      pulsePaint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter oldDelegate) => true;
}

class _SlidingQuickSaveSelector extends StatelessWidget {
  const _SlidingQuickSaveSelector({
    required this.selectedMode,
    required this.onChanged,
    this.disabled = false,
  });

  final QuickSaveMode selectedMode;
  final ValueChanged<QuickSaveMode> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final modes = [
      QuickSaveMode.on,
      QuickSaveMode.favorites,
      QuickSaveMode.off,
    ];
    final activeIndex = modes.indexOf(selectedMode);

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final pillWidth = totalWidth / 3;

            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: activeIndex * pillWidth,
                  top: 0,
                  bottom: 0,
                  width: pillWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: List.generate(modes.length, (index) {
                    final mode = modes[index];
                    final isSelected = index == activeIndex;
                    final label = switch (mode) {
                      QuickSaveMode.on => 'On',
                      QuickSaveMode.favorites => 'Favorites',
                      QuickSaveMode.off => 'Off',
                    };
                    final icon = switch (mode) {
                      QuickSaveMode.on => Icons.flash_on_rounded,
                      QuickSaveMode.favorites => Icons.star_rounded,
                      QuickSaveMode.off => Icons.lock_outline_rounded,
                    };
                    final foregroundColor = isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant;

                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: disabled ? null : () => onChanged(mode),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Icon(
                                      icon,
                                      key: ValueKey('${mode.name}-$isSelected'),
                                      size: 17,
                                      color: foregroundColor,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: theme.textTheme.labelMedium!
                                        .copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: foregroundColor,
                                        ),
                                    child: Text(label),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IncomingRequestsChip extends StatelessWidget {
  const _IncomingRequestsChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPending = count > 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: Material(
        key: ValueKey(count),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasPending
                    ? colorScheme.error.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: hasPending ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: (hasPending ? colorScheme.error : colorScheme.primary)
                      .withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasPending
                      ? Icons.mark_email_unread_rounded
                      : Icons.mail_outline_rounded,
                  size: 18,
                  color: hasPending ? colorScheme.error : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  hasPending ? 'Incoming ($count)' : 'Incoming Requests',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: hasPending
                        ? colorScheme.error
                        : colorScheme.onSurface,
                  ),
                ),
                if (hasPending) ...[
                  const SizedBox(width: 6),
                  _PulsingDot(color: colorScheme.error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween<double>(begin: 0.3, end: 1.0)),
      child: ScaleTransition(
        scale: _controller.drive(Tween<double>(begin: 0.8, end: 1.2)),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
