import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';
import '../../widgets/adaptive_nav_scaffold.dart';
import '../../widgets/tab_shell_scope.dart';

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> with SingleTickerProviderStateMixin {
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

    final state = ref.watch(
      appControllerProvider.select(
        (state) => (
          localDeviceBaseName: state.localDeviceBaseName,
          localDeviceNumber: state.localDeviceNumber,
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: _opacityAnimation.value),
                              ),
                            ),
                          );
                        },
                      ),
                      Icon(
                        Icons.adjust_rounded,
                        size: 120,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  state.localDeviceBaseName.isEmpty
                      ? 'DropNet Device'
                      : state.localDeviceBaseName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  '#${state.localDeviceNumber}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Quick Save',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (quickSaveLocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Quick Save is disabled while pairing mode is enabled.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: SegmentedButton<QuickSaveMode>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      segments: const [
                        ButtonSegment<QuickSaveMode>(
                          value: QuickSaveMode.on,
                          label: Text('On'),
                        ),
                        ButtonSegment<QuickSaveMode>(
                          value: QuickSaveMode.favorites,
                          label: Text('Favorites'),
                        ),
                        ButtonSegment<QuickSaveMode>(
                          value: QuickSaveMode.off,
                          label: Text('Off'),
                        ),
                      ],
                      selected: {state.quickSaveMode},
                      onSelectionChanged: quickSaveLocked
                          ? null
                          : (selection) => _onQuickSaveModeTapped(
                                selection.first,
                                dismissedModes:
                                    state.quickSaveDismissedModes,
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (state.showIncomingRequestList)
            Align(
              alignment: Alignment.topRight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/receive/incoming-requests'),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Incoming Request'),
                  ),
                  if (state.pendingRequestsCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: FadeTransition(
                        opacity: _pulseController.drive(
                          Tween<double>(begin: 0.28, end: 1),
                        ),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return AdaptiveNavScaffold(
      currentIndex: 0,
      child: content,
    );
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

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (value) => setLocalState(
                      () => dontShowAgain = value ?? false,
                    ),
                    title: const Text('Do not show again'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
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
