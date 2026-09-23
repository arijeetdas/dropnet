import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'core/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/platform/app_shortcut_service.dart';
import 'core/utils/file_utils.dart';
import 'core/utils/dialog_utils.dart';
import 'widgets/expressive_loader.dart';
import 'core/networking/web_server_service.dart';
import 'models/transfer_model.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/receive/receive_screen.dart';
import 'features/receive/apk_preview_screen.dart';
import 'features/receive/received_file_screen.dart';
import 'features/receive/shared_text_screen.dart';
import 'features/receive/incoming_requests_screen.dart';
import 'features/send/send_files_screen.dart';
import 'features/settings/favorite_devices_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/advanced_settings.dart';
import 'features/settings/private_networks_screen.dart';
import 'features/transfers/active_transfers_screen.dart';
import 'features/transfers/transfer_session_screen.dart';
import 'features/web_mode/web_mode_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/onboarding/permission_screen.dart';
import 'core/utils/transfer_visuals.dart';
import 'widgets/adaptive_nav_scaffold.dart';
import 'widgets/pairing_code_dialog.dart';
import 'widgets/tab_shell_scope.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/welcome',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/permission',
      builder: (context, state) => const PermissionScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _TabShellScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/receive',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ReceiveScreen(embedded: true)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/send',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SendFilesScreen(embedded: true),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/web',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: WebModeScreen(embedded: true)),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/transfers',
      builder: (context, state) => const ActiveTransfersScreen(),
    ),
    GoRoute(
      path: '/transfer-session',
      builder: (context, state) => const TransferSessionScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/analytics',
      builder: (context, state) => const AnalyticsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/favorites',
      builder: (context, state) => const FavoriteDevicesScreen(),
    ),
    GoRoute(
      path: '/settings/advanced',
      builder: (context, state) => const AdvancedSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/private-networks',
      builder: (context, state) => const PrivateNetworksScreen(),
    ),
    GoRoute(
      path: '/receive/incoming-requests',
      builder: (context, state) => const IncomingRequestsScreen(),
    ),
    GoRoute(
      path: '/shared-text',
      builder: (context, state) {
        final text = state.extra is String ? (state.extra as String) : '';
        return SharedTextScreen(text: text);
      },
    ),
    GoRoute(
      path: '/received-file',
      builder: (context, state) {
        final transfer = state.extra is TransferModel
            ? state.extra as TransferModel
            : null;
        if (transfer == null) {
          return const Scaffold(
            body: Center(child: Text('No received file to preview.')),
          );
        }
        return ReceivedFileScreen(transfer: transfer);
      },
    ),
    GoRoute(
      path: '/apk-preview',
      builder: (context, state) {
        final transfer = state.extra is TransferModel
            ? state.extra as TransferModel
            : null;
        if (transfer == null) {
          return const Scaffold(
            body: Center(child: Text('No received app to preview.')),
          );
        }
        return ApkPreviewScreen(transfer: transfer);
      },
    ),
  ],
);

class _TabShellScaffold extends StatelessWidget {
  const _TabShellScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return AdaptiveNavScaffold(
      currentIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) {
        if (index == navigationShell.currentIndex) {
          return;
        }
        navigationShell.goBranch(index);
      },
      child: TabShellScope(
        currentIndex: navigationShell.currentIndex,
        child: navigationShell,
      ),
    );
  }
}

class DropNetApp extends ConsumerStatefulWidget {
  const DropNetApp({super.key});

  @override
  ConsumerState<DropNetApp> createState() => _DropNetAppState();
}

class _DropNetAppState extends ConsumerState<DropNetApp> {
  final Set<String> _dialogShownFor = {};
  final Set<String> _pairingDialogShownFor = {};
  final Set<String> _manualConnectDialogShownFor = {};
  final Set<String> _peerDialogShownFor = {};
  final Set<String> _webUploadDialogShownFor = {};
  final Set<String> _cancellationNoticeShownFor = {};
  final Set<String> _manualDisconnectNoticeShownFor = {};
  final Map<String, _ActivePairingDialog> _activePairingDialogs = {};
  // Incoming-transfer approval dialogs currently on screen, by request id.
  final Map<String, ({BuildContext context, IncomingTransferRequest request})>
  _activeIncomingDialogs = {};
  // Context of the "Preparing shared files" popup while it is on screen.
  BuildContext? _sharedImportDialogContext;
  Timer? _sharedImportDialogDelay;
  bool _transferSessionOpen = false;
  bool _sharedTextOpening = false;
  bool _receivedFilePreviewOpening = false;
  bool _apkPreviewOpening = false;
  bool _globalDragActive = false;
  bool _startupRouteReady = false;
  Timer? _permissionPollTimer;
  final AppShortcutService _appShortcuts = AppShortcutService();
  StreamSubscription<AppShortcutAction>? _shortcutSub;

  bool get _supportsAppShortcuts =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    if (_supportsAppShortcuts) {
      unawaited(_appShortcuts.initialize());
      _shortcutSub = _appShortcuts.shortcutStream.listen(_handleAppShortcut);
    }
    Future<void>(() async {
      await _routeForStartup();
      if (mounted) {
        setState(() => _startupRouteReady = true);
      }

      if (_supportsAppShortcuts) {
        final pending = await _appShortcuts.consumePendingShortcut();
        if (pending != null) {
          _handleAppShortcut(pending);
        }
      }

      await ref.read(appControllerProvider.notifier).bootstrap();

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _permissionPollTimer = Timer.periodic(const Duration(seconds: 2), (
          _,
        ) async {
          final prefs = await SharedPreferences.getInstance();
          final seen = prefs.getBool('onboarding.completed') ?? false;
          if (!seen) {
            return;
          }
          final currentPath = _router.routeInformationProvider.value.uri.path;
          if (currentPath == '/welcome') {
            return;
          }
          final granted = await _hasRequiredAndroidStorageAccess();
          if (!granted) {
            if (currentPath != '/permission') {
              _router.go('/permission');
            }
          }
        });
      }
    });
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _DropNetLifecycleObserver(
        onDetached: () async {
          await ref
              .read(appControllerProvider.notifier)
              .shutdownNetworkServices();
        },
        onResume: () {
          _checkAndroidPermissionAndRedirect();
          unawaited(
            ref.read(appControllerProvider.notifier).runAutomaticCacheCleanupIfDue(),
          );
        },
      );

  Future<void> _checkAndroidPermissionAndRedirect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding.completed') ?? false;
    if (!seen) return;

    final currentPath = _router.routeInformationProvider.value.uri.path;
    if (currentPath == '/welcome') return;

    final granted = await _hasRequiredAndroidStorageAccess();
    if (!granted) {
      if (currentPath != '/permission') {
        _router.go('/permission');
      }
    }
  }

  void _handleAppShortcut(AppShortcutAction action) {
    if (!mounted) return;
    switch (action) {
      case AppShortcutAction.settings:
        _router.push('/settings');
      case AppShortcutAction.history:
        _router.push('/history');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _permissionPollTimer?.cancel();
    _sharedImportDialogDelay?.cancel();
    unawaited(_shortcutSub?.cancel());
    unawaited(_appShortcuts.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(
      appControllerProvider.select(
        (state) => (
          themeMode: state.themeMode,
          themeSeed: state.themeSeed,
          useSystemAccent: state.useSystemAccent,
        ),
      ),
    );
    ref.listen<AppState>(appControllerProvider, (previous, next) {
      _dialogShownFor.removeWhere(
        (id) =>
            !next.pendingIncomingRequests.any((request) => request.id == id),
      );
      _closeExpiredIncomingDialogs(next);
      _pairingDialogShownFor.removeWhere(
        (id) => !next.pendingPairingRequests.any((request) => request.id == id),
      );
      _manualConnectDialogShownFor.removeWhere(
        (id) => !next.pendingManualConnectRequests.any((request) => request.id == id),
      );
      _peerDialogShownFor.removeWhere(
        (id) => !next.pendingWebPeerRequests.any((request) => request.id == id),
      );
      _webUploadDialogShownFor.removeWhere(
        (id) =>
            !next.pendingWebIncomingUploads.any((request) => request.id == id),
      );
      _cancellationNoticeShownFor.removeWhere(
        (id) => !next.pendingRecipientCancellationNotices.any((notice) => notice.sessionId == id),
      );
      _manualDisconnectNoticeShownFor.removeWhere(
        (id) => !next.pendingManualDisconnectNotices.any((notice) => notice.id == id),
      );

      if (!_sharedTextOpening && next.pendingTransferPreviewTexts.isNotEmpty) {
        _sharedTextOpening = true;
        Future<void>(() async {
          try {
            while (mounted) {
              final text = ref
                  .read(appControllerProvider.notifier)
                  .consumeNextPendingTransferPreviewText();
              if (text == null) {
                break;
              }
              await _router.push('/shared-text', extra: text);
            }
          } finally {
            _sharedTextOpening = false;
          }
        });
      }

      if (!_receivedFilePreviewOpening &&
          next.pendingTransferPreviewFiles.isNotEmpty) {
        _receivedFilePreviewOpening = true;
        Future<void>(() async {
          try {
            while (mounted) {
              final transfer = ref
                  .read(appControllerProvider.notifier)
                  .consumeNextPendingTransferPreviewFile();
              if (transfer == null) {
                break;
              }
              await _router.push('/received-file', extra: transfer);
            }
          } finally {
            _receivedFilePreviewOpening = false;
          }
        });
      }

      if (!_apkPreviewOpening && next.pendingApkPreviewFiles.isNotEmpty) {
        _apkPreviewOpening = true;
        Future<void>(() async {
          try {
            while (mounted) {
              final transfer = ref
                  .read(appControllerProvider.notifier)
                  .consumeNextPendingApkPreviewFile();
              if (transfer == null) {
                break;
              }
              await _router.push('/apk-preview', extra: transfer);
            }
          } finally {
            _apkPreviewOpening = false;
          }
        });
      }

      final hasPendingSendImports =
          next.pendingSharedFilePaths.isNotEmpty ||
          next.pendingSharedTexts.isNotEmpty ||
          // Open Send as soon as a share starts importing, instead of
          // leaving the user on the Receive tab while a large file copies.
          (next.sharedImportInProgress &&
              !(previous?.sharedImportInProgress ?? false));
      if (hasPendingSendImports) {
        if (!_isSendRouteVisible()) {
          _router.go('/send');
        }
      }

      final wasImporting = previous?.sharedImportInProgress ?? false;
      if (next.sharedImportInProgress && !wasImporting) {
        _showSharedImportDialog();
      } else if (!next.sharedImportInProgress && wasImporting) {
        _closeSharedImportDialog();
      }

      final sessionStarted = next.transferSessionActive && !(previous?.transferSessionActive ?? false);
      if (sessionStarted && !_transferSessionOpen) {
        _transferSessionOpen = true;
        Future<void>(() async {
          await _router.push('/transfer-session');
          _transferSessionOpen = false;
        });
      }

      final pendingMessage = ref
          .read(appControllerProvider.notifier)
          .consumeNextPendingSystemMessage();
      if (pendingMessage != null) {
        final activeContext = _rootNavigatorKey.currentContext ?? context;
        final messenger = ScaffoldMessenger.maybeOf(activeContext);
        messenger?.showSnackBar(SnackBar(content: Text(pendingMessage)));
      }

      // Auto-cancel active pairing dialog on Device B if Device A cancelled/disconnected
      final activeIds = _activePairingDialogs.keys.toList();
      for (final id in activeIds) {
        final stillExists = next.pendingPairingRequests.any((r) => r.id == id);
        if (!stillExists) {
          final dialogState = _activePairingDialogs[id];
          if (dialogState != null && !dialogState.isPopped) {
            dialogState.isPopped = true;
            Navigator.of(
              dialogState.context,
            ).pop(false); // Dismiss the input dialog on Device B
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final activeContext = _rootNavigatorKey.currentContext ?? context;
              final theme = Theme.of(activeContext);
              final colorScheme = theme.colorScheme;
              showDropNetDialog<void>(
                context: activeContext,
                builder: (context) => AlertDialog(
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
                          colorScheme.errorContainer,
                          colorScheme.errorContainer.withValues(alpha: 0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.error.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: colorScheme.onErrorContainer,
                      size: 32,
                    ),
                  ),
                  title: Text(
                    'Pairing Cancelled',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: Card(
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
                        'The pairing session was cancelled or disconnected by the other device.\n\nFor security, direct file transfers have been aborted. Please ensure both devices are open on the same local network and attempt to pair again.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
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
                ),
              );
            });
          }
        }
      }

      for (final request in next.pendingIncomingRequests) {
        if (!_dialogShownFor.contains(request.id)) {
          _dialogShownFor.add(request.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showIncomingDialog(request);
          });
          break;
        }
      }

      for (final request in next.pendingPairingRequests) {
        if (!_pairingDialogShownFor.contains(request.id)) {
          _pairingDialogShownFor.add(request.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showIncomingPairingDialog(request);
          });
          break;
        }
      }

      for (final request in next.pendingManualConnectRequests) {
        if (!_manualConnectDialogShownFor.contains(request.id)) {
          _manualConnectDialogShownFor.add(request.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showIncomingManualConnectDialog(request);
          });
          break;
        }
      }

      for (final peerRequest in next.pendingWebPeerRequests) {
        if (!_peerDialogShownFor.contains(peerRequest.id)) {
          _peerDialogShownFor.add(peerRequest.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showWebPeerDialog(peerRequest);
          });
          break;
        }
      }

      for (final uploadRequest in next.pendingWebIncomingUploads) {
        if (!_webUploadDialogShownFor.contains(uploadRequest.id)) {
          _webUploadDialogShownFor.add(uploadRequest.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showWebIncomingUploadDialog(uploadRequest);
          });
          break;
        }
      }

      for (final notice in next.pendingRecipientCancellationNotices) {
        if (!_cancellationNoticeShownFor.contains(notice.sessionId)) {
          _cancellationNoticeShownFor.add(notice.sessionId);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showCancellationDialog(notice);
          });
          break;
        }
      }

      for (final notice in next.pendingManualDisconnectNotices) {
        if (!_manualDisconnectNoticeShownFor.contains(notice.id)) {
          _manualDisconnectNoticeShownFor.add(notice.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showIncomingManualDisconnectDialog(notice);
          });
          break;
        }
      }
    });
    if (!_startupRouteReady) {
      return DynamicColorBuilder(
        builder: (dynamicLight, dynamicDark) {
          final dynamicSeed = dynamicLight?.primary ?? dynamicDark?.primary;
          final effectiveSeed = themeSettings.useSystemAccent
              ? (dynamicSeed ?? Colors.indigo)
              : themeSettings.themeSeed;
          return MaterialApp(
            title: 'DropNet',
            debugShowCheckedModeBanner: false,
            themeMode: themeSettings.themeMode,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorSchemeSeed: effectiveSeed,
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: effectiveSeed,
            ),
            home: const Scaffold(body: SizedBox.shrink()),
          );
        },
      );
    }
    return DynamicColorBuilder(
      builder: (dynamicLight, dynamicDark) {
        final dynamicSeed = dynamicLight?.primary ?? dynamicDark?.primary;
        final effectiveSeed = themeSettings.useSystemAccent
            ? (dynamicSeed ?? Colors.indigo)
            : themeSettings.themeSeed;
        return MaterialApp.router(
          title: 'DropNet',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          builder: (context, child) {
            final appChild = child ?? const SizedBox.shrink();
            if (!_supportsGlobalDrop) {
              return appChild;
            }
            return DropTarget(
              onDragEntered: (_) => _setGlobalDragActive(true),
              onDragExited: (_) => _setGlobalDragActive(false),
              onDragDone: _handleGlobalDrop,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  appChild,
                  if (_globalDragActive) _buildGlobalDropOverlay(context),
                ],
              ),
            );
          },
          themeMode: themeSettings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: effectiveSeed,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
              },
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: effectiveSeed,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
              },
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _supportsGlobalDrop {
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  Future<bool> _hasRequiredAndroidStorageAccess() async {
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) {
      return true;
    }

    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  Future<void> _routeForStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('onboarding.completed') ?? false;
      if (!seen) {
        _router.go('/welcome');
        return;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _hasRequiredAndroidStorageAccess();
        _router.go(ok ? '/receive' : '/permission');
        return;
      }

      _router.go('/receive');
    } catch (_) {
      _router.go('/welcome');
    }
  }

  void _setGlobalDragActive(bool value) {
    if (!mounted || _globalDragActive == value) {
      return;
    }
    setState(() => _globalDragActive = value);
  }

  void _handleGlobalDrop(DropDoneDetails detail) {
    _setGlobalDragActive(false);

    final dropped = detail.files
        .map((file) => file.path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (dropped.isEmpty) {
      return;
    }

    ref.read(appControllerProvider.notifier).addPendingSharedFiles(dropped);

    if (!_isSendRouteVisible()) {
      _router.go('/send');
    }
  }

  Future<void> _showIncomingPairingDialog(
    IncomingPairingRequest request,
  ) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _pairingDialogShownFor.remove(request.id);
      return;
    }

    final dialogState = _ActivePairingDialog(context: dialogContext);
    _activePairingDialogs[request.id] = dialogState;

    final approved = await showInstantDialog<bool>(
      context: dialogContext,
      builder: (context) {
        dialogState.context = context;
        return PairingCodeDialog(
          deviceName: request.fromDeviceName,
          fileName: 'Pairing Request',
          expectedCode: request.pairingCode,
        );
      },
    );

    dialogState.isPopped = true;
    _activePairingDialogs.remove(request.id);

    if (!mounted) {
      return;
    }

    await ref
        .read(appControllerProvider.notifier)
        .respondToIncomingPairingRequest(request, approved: approved == true);

    if (!mounted) {
      return;
    }

    final activeContext = _rootNavigatorKey.currentContext;
    if (activeContext == null || !activeContext.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(activeContext);
    if (approved == true) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${request.fromDeviceName} paired successfully.'),
        ),
      );
    } else {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Pairing verification failed or canceled.'),
        ),
      );
    }
  }

  Future<void> _showIncomingManualConnectDialog(
    IncomingManualConnectRequest request,
  ) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _manualConnectDialogShownFor.remove(request.id);
      return;
    }

    final theme = Theme.of(dialogContext);
    final colorScheme = theme.colorScheme;

    final approved = await showDropNetDialog<bool>(
      context: dialogContext,
      builder: (context) {
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
              Icons.lan_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 32,
            ),
          ),
          title: Text(
            'Connection Request',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: 320,
            child: Card(
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
                  '${request.fromDeviceName} (${request.fromDevicePlatform.toUpperCase()}) wants to connect manually with this device.\n\nDo you want to accept?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    await ref
        .read(appControllerProvider.notifier)
        .respondToIncomingManualConnectRequest(request, approved: approved == true);
  }

  bool _isSendRouteVisible() {
    final path = _router.routeInformationProvider.value.uri.path;
    final hasPushedRoute = _rootNavigatorKey.currentState?.canPop() ?? false;
    return path.startsWith('/send') && !hasPushedRoute;
  }

  Widget _buildGlobalDropOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return IgnorePointer(
      child: Container(
        color: colorScheme.primary.withValues(alpha: 0.08),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.file_upload_rounded),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Drop files anywhere to share with DropNet',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCancellationDialog(RecipientCancellationNotice notice) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _cancellationNoticeShownFor.remove(notice.sessionId);
      return;
    }
    
    final theme = Theme.of(dialogContext);
    final colorScheme = theme.colorScheme;
    
    await showDropNetDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
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
                colorScheme.errorContainer,
                colorScheme.errorContainer.withValues(alpha: 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.error.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.cancel_outlined,
            color: colorScheme.onErrorContainer,
            size: 32,
          ),
        ),
        title: Text(
          'Transfer Cancelled',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        content: Card(
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
              'The transfer session was cancelled by the Recipient (${notice.deviceName}).\n\nAny partially sent files have been rejected and cleaned up.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
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
      ),
    );
    
    if (mounted) {
      ref.read(appControllerProvider.notifier).dismissRecipientCancellationNotice(notice.sessionId);
    }
  }

  Future<void> _showIncomingManualDisconnectDialog(
    RemoteManualDisconnectNotice notice,
  ) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _manualDisconnectNoticeShownFor.remove(notice.id);
      return;
    }

    final theme = Theme.of(dialogContext);
    final colorScheme = theme.colorScheme;

    await showDropNetDialog<void>(
      context: dialogContext,
      builder: (context) {
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
                  colorScheme.errorContainer,
                  colorScheme.errorContainer.withValues(alpha: 0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.error.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.link_off_rounded,
              color: colorScheme.onErrorContainer,
              size: 32,
            ),
          ),
          title: Text(
            'Device disconnected',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          content: Card(
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
                '${notice.fromDeviceName} disconnected the manual connection.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
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

    if (mounted) {
      ref.read(appControllerProvider.notifier).dismissManualDisconnectNotice(notice.id);
    }
  }

  /// Shown while Android copies shared content into the app (large files
  /// from apps like WhatsApp). Closes itself once the import finishes.
  void _showSharedImportDialog() {
    // Only when preparing actually takes a moment: most shares (including
    // large files that can be read in place) finish almost instantly, and a
    // popup that flashes for a few milliseconds is just noise.
    if (_sharedImportDialogDelay?.isActive ?? false) {
      return;
    }
    _sharedImportDialogDelay = Timer(const Duration(milliseconds: 250), () {
      if (mounted && ref.read(appControllerProvider).sharedImportInProgress) {
        _presentSharedImportDialog();
        WidgetsBinding.instance.scheduleFrame();
      }
    });
  }

  void _presentSharedImportDialog() {
    // After the frame, so the switch to the Send tab triggered by the same
    // state change happens first and can't dismiss this popup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sharedImportDialogContext != null) {
        return;
      }
      if (!ref.read(appControllerProvider).sharedImportInProgress) {
        return;
      }
      final dialogContext = _rootNavigatorKey.currentContext;
      if (dialogContext == null) {
        // Navigator not built yet (app still starting): try next frame.
        _presentSharedImportDialog();
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      unawaited(
        showDropNetDialog<void>(
          context: dialogContext,
          barrierLabel: 'Preparing shared files',
          builder: (context) {
            _sharedImportDialogContext = context;
            // The import may have finished while the popup was opening.
            if (!ref.read(appControllerProvider).sharedImportInProgress) {
              _closeSharedImportDialog();
            }
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              backgroundColor: colorScheme.surface,
              elevation: 6,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExpressiveLoader(),
                  const SizedBox(height: 16),
                  Text(
                    'Preparing shared files…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          },
        ).whenComplete(() {
          _sharedImportDialogContext = null;
          // Removed while the import is still running — typically because
          // switching to the Send tab replaced a page (Settings, History…)
          // the popup was stacked on. Put it back so the user isn't left
          // without any sign that the file is still being prepared.
          if (mounted &&
              ref.read(appControllerProvider).sharedImportInProgress) {
            _presentSharedImportDialog();
          }
        }),
      );
    });
  }

  void _closeSharedImportDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dialogContext = _sharedImportDialogContext;
      _sharedImportDialogContext = null;
      if (dialogContext == null || !dialogContext.mounted) {
        return;
      }
      final route = ModalRoute.of(dialogContext);
      if (route != null && route.isActive) {
        Navigator.of(dialogContext).removeRoute(route);
      }
    });
  }

  bool _isIncomingRequestPending(String id) {
    return ref
        .read(appControllerProvider)
        .pendingIncomingRequests
        .any((pending) => pending.id == id);
  }

  void _reshowIncomingDialogIfStillPending(IncomingTransferRequest request) {
    if (!_isIncomingRequestPending(request.id)) {
      return;
    }
    _dialogShownFor.remove(request.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _dialogShownFor.contains(request.id) ||
          !_isIncomingRequestPending(request.id)) {
        return;
      }
      _dialogShownFor.add(request.id);
      _showIncomingDialog(request);
    });
  }

  /// Closes approval dialogs whose request is no longer pending (it expired
  /// on the receiver, or the sender gave up). Otherwise the stale dialog
  /// stays up and a later "Accept" tap silently does nothing while the
  /// sender already reports "Rejected by receiver".
  void _closeExpiredIncomingDialogs(AppState next) {
    if (_activeIncomingDialogs.isEmpty) {
      return;
    }
    final expired = _activeIncomingDialogs.entries
        .where(
          (entry) => !next.pendingIncomingRequests.any(
            (request) => request.id == entry.key,
          ),
        )
        .toList(growable: false);
    if (expired.isEmpty) {
      return;
    }
    for (final entry in expired) {
      _activeIncomingDialogs.remove(entry.key);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final entry in expired) {
        final dialogContext = entry.value.context;
        if (!dialogContext.mounted) {
          continue;
        }
        final route = ModalRoute.of(dialogContext);
        if (route == null || !route.isActive) {
          // Already answered and closed by the user.
          continue;
        }
        Navigator.of(dialogContext).removeRoute(route);
        final messengerContext = _rootNavigatorKey.currentContext;
        if (messengerContext != null) {
          ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
            SnackBar(
              content: Text(
                'Transfer request from ${entry.value.request.fromDeviceName} '
                'expired or was withdrawn.',
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _showIncomingDialog(IncomingTransferRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _dialogShownFor.remove(request.id);
      return;
    }

    final appState = ref.read(appControllerProvider);

    // Quick Save auto-approval policy (only active when pairing mode is off).
    if (!appState.requirePairingCodeForDirectTransfers) {
      final quickSaveMode = appState.quickSaveMode;
      if (quickSaveMode == QuickSaveMode.on) {
        ref
            .read(appControllerProvider.notifier)
            .approveIncomingRequest(request.id);
        return;
      }
      if (quickSaveMode == QuickSaveMode.favorites) {
        final incomingId = (request.fromDeviceId ?? '').trim().toLowerCase();
        final incomingAddress = request.fromAddress.trim();
        final isFavorite = appState.favoritePeers.any((peer) {
          final favoriteId = peer.deviceId.trim().toLowerCase();
          if (incomingId.isNotEmpty && favoriteId == incomingId) {
            return true;
          }
          return incomingId.isEmpty &&
              peer.lastKnownIp.trim().isNotEmpty &&
              peer.lastKnownIp.trim() == incomingAddress;
        });
        if (isFavorite) {
          ref
              .read(appControllerProvider.notifier)
              .approveIncomingRequest(request.id);
          return;
        }
      }
    }

    // If incoming request list is enabled, non-auto-approved requests are
    // handled from the incoming requests screen.
    if (appState.showIncomingRequestList) {
      return;
    }

    final requiresCodeVerification =
        appState.requirePairingCodeForDirectTransfers &&
        request.pairingCode != null;

    final details = <_DecisionDetail>[
      _DecisionDetail(
        icon: Icons.person_outline_rounded,
        label: 'From',
        value: request.fromDeviceName,
      ),
      _DecisionDetail(
        icon: Icons.wifi_rounded,
        label: 'Address',
        value: request.fromAddress,
      ),
      _DecisionDetail(
        icon: Icons.data_object_rounded,
        label: 'File size',
        value: FileUtils.formatBytes(request.size),
      ),
    ];
    if ((request.batchFileCount ?? 0) > 1) {
      details.add(
        _DecisionDetail(
          icon: Icons.layers_rounded,
          label: 'Batch',
          value:
              'File ${(request.batchIndex ?? 0) + 1} of ${request.batchFileCount}',
        ),
      );
      if ((request.batchTotalBytes ?? 0) > 0) {
        details.add(
          _DecisionDetail(
            icon: Icons.folder_copy_outlined,
            label: 'Batch total',
            value: FileUtils.formatBytes(request.batchTotalBytes!),
          ),
        );
      }
    }
    if (requiresCodeVerification) {
      details.add(
        const _DecisionDetail(
          icon: Icons.password_rounded,
          label: 'Verification',
          value: '6-digit code required before accepting',
        ),
      );
    }

    // Show initial transfer request
    final initialApproved = await showInstantDialog<bool>(
      context: dialogContext,
      builder: (context) {
        _activeIncomingDialogs[request.id] = (
          context: context,
          request: request,
        );
        return PopScope(
          canPop: false,
          child: _DecisionScreen(
            eyebrow: 'Incoming transfer',
            title: 'Accept this transfer request?',
            subtitle:
                'Approve to start receiving this file into your current download location.',
            highlightTitle: request.fileName,
            highlightSubtitle: TransferVisuals.kindLabel(request.fileName),
            icon: TransferVisuals.iconForName(request.fileName),
            accent: TransferVisuals.accentColor(context, request.fileName),
            details: details,
            secondaryLabel: 'Reject',
            primaryLabel: 'Accept',
            onSecondary: () => Navigator.of(context).pop(false),
            onPrimary: () => Navigator.of(context).pop(true),
          ),
        );
      },
    );
    _activeIncomingDialogs.remove(request.id);

    if (!mounted) {
      return;
    }
    // null means the dialog went away without the user answering: either a
    // navigation (share-intent redirect to Send, permission check, startup
    // routing) replaced the page beneath it, or the request expired and
    // _closeExpiredIncomingDialogs removed it. That used to be treated as a
    // rejection, so transfers were declined that nobody had declined.
    if (initialApproved == null) {
      _reshowIncomingDialogIfStillPending(request);
      return;
    }
    if (initialApproved != true) {
      ref
          .read(appControllerProvider.notifier)
          .rejectIncomingRequest(request.id);
      return;
    }

    // If code verification is required, show code input dialog
    if (requiresCodeVerification) {
      final verificationContext = _rootNavigatorKey.currentContext;
      if (!mounted ||
          verificationContext == null ||
          !verificationContext.mounted) {
        return;
      }
      final codeApproved = await showInstantDialog<bool>(
        context: verificationContext,
        builder: (context) => PairingCodeDialog(
          deviceName: request.fromDeviceName,
          fileName: request.fileName,
          expectedCode: request.pairingCode,
        ),
      );

      if (!mounted) {
        return;
      }

      if (codeApproved == null) {
        _reshowIncomingDialogIfStillPending(request);
        return;
      }
      if (codeApproved == true) {
        ref
            .read(appControllerProvider.notifier)
            .approveIncomingRequest(request.id);
      } else {
        ref
            .read(appControllerProvider.notifier)
            .rejectIncomingRequest(request.id);
      }
    } else {
      // No code verification needed, approve directly
      if (mounted) {
        ref
            .read(appControllerProvider.notifier)
            .approveIncomingRequest(request.id);
      }
    }
  }

  Future<void> _showWebPeerDialog(WebPeerConnectRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _scheduleWebPeerDialogRetry(request.id);
      return;
    }
    final approved = await showInstantDialog<bool>(
      context: dialogContext,
      builder: (context) => PopScope(
        canPop: false,
        child: _DecisionScreen(
          eyebrow: 'Web to app connection',
          title: 'Allow this browser to connect?',
          subtitle:
              'This grants the active web client access to this DropNet session.',
          highlightTitle: request.name,
          highlightSubtitle: request.ip,
          icon: Icons.language_rounded,
          accent: Theme.of(context).colorScheme.secondary,
          details: [
            _DecisionDetail(
              icon: Icons.computer_rounded,
              label: 'Web client',
              value: request.name,
            ),
            _DecisionDetail(
              icon: Icons.wifi_rounded,
              label: 'IP address',
              value: request.ip,
            ),
            const _DecisionDetail(
              icon: Icons.shield_outlined,
              label: 'Scope',
              value: 'This session only',
            ),
          ],
          secondaryLabel: 'Reject',
          primaryLabel: 'Connect',
          onSecondary: () => Navigator.of(context).pop(false),
          onPrimary: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (approved == null) {
      _scheduleWebPeerDialogRetry(request.id);
      return;
    }
    if (approved == true) {
      ref
          .read(appControllerProvider.notifier)
          .approveWebPeerRequest(request.id);
    } else {
      ref.read(appControllerProvider.notifier).rejectWebPeerRequest(request.id);
    }
  }

  void _scheduleWebPeerDialogRetry(String requestId) {
    _peerDialogShownFor.remove(requestId);

    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }

      WebPeerConnectRequest? pendingRequest;
      for (final item
          in ref.read(appControllerProvider).pendingWebPeerRequests) {
        if (item.id == requestId) {
          pendingRequest = item;
          break;
        }
      }

      if (pendingRequest == null || _peerDialogShownFor.contains(requestId)) {
        return;
      }

      _peerDialogShownFor.add(requestId);
      _showWebPeerDialog(pendingRequest);
    });
  }

  Future<void> _showWebIncomingUploadDialog(
    WebIncomingUploadRequest request,
  ) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      _scheduleWebIncomingUploadDialogRetry(request.id);
      return;
    }
    final isBatch =
        request.batchFileCount != null && request.batchFileCount! > 1;
    final displayTitle = isBatch
        ? 'Accept ${request.batchFileCount} files from the web?'
        : 'Accept this file from the web?';
    final displayHighlightTitle = isBatch
        ? 'Batch of ${request.batchFileCount} files'
        : request.fileName;
    final displayHighlightSubtitle = isBatch
        ? 'Web Share Portal Transfer'
        : TransferVisuals.kindLabel(request.fileName);
    final displayIcon = isBatch
        ? Icons.inventory_2_rounded
        : TransferVisuals.iconForName(request.fileName);
    final displayAccent = isBatch
        ? Theme.of(dialogContext).colorScheme.primary
        : TransferVisuals.accentColor(dialogContext, request.fileName);

    final fileSizeLabel = isBatch ? 'Total size' : 'File size';
    final fileSizeValue = isBatch
        ? FileUtils.formatBytes(
            (request.batchTotalBytes ?? request.size).toDouble(),
          )
        : FileUtils.formatBytes(request.size.toDouble());

    Widget? batchCard;
    if (isBatch) {
      final theme = Theme.of(dialogContext);
      final colorScheme = theme.colorScheme;
      batchCard = Card(
        elevation: 0,
        color: colorScheme.secondaryContainer.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.secondary.withValues(alpha: 0.15),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: colorScheme.secondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This transfer contains a batch of ${request.batchFileCount} files. Approving will automatically accept the entire batch.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final approved = await showInstantDialog<bool>(
      context: dialogContext,
      builder: (context) => PopScope(
        canPop: false,
        child: _DecisionScreen(
          eyebrow: 'Web upload request',
          title: displayTitle,
          subtitle:
              'The files will be saved into your current DropNet download location.',
          highlightTitle: displayHighlightTitle,
          highlightSubtitle: displayHighlightSubtitle,
          icon: displayIcon,
          accent: displayAccent,
          details: [
            _DecisionDetail(
              icon: Icons.person_outline_rounded,
              label: 'From',
              value: request.peerName,
            ),
            _DecisionDetail(
              icon: Icons.wifi_rounded,
              label: 'IP address',
              value: request.ip,
            ),
            _DecisionDetail(
              icon: Icons.data_object_rounded,
              label: fileSizeLabel,
              value: fileSizeValue,
            ),
          ],
          secondaryLabel: 'Reject',
          primaryLabel: 'Accept',
          onSecondary: () => Navigator.of(context).pop(false),
          onPrimary: () => Navigator.of(context).pop(true),
          batchInfoCard: batchCard,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (approved == null) {
      _scheduleWebIncomingUploadDialogRetry(request.id);
      return;
    }
    if (approved == true) {
      ref
          .read(appControllerProvider.notifier)
          .approveWebIncomingUpload(request.id);
    } else {
      ref
          .read(appControllerProvider.notifier)
          .rejectWebIncomingUpload(request.id);
    }
  }

  void _scheduleWebIncomingUploadDialogRetry(String requestId) {
    _webUploadDialogShownFor.remove(requestId);

    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }

      WebIncomingUploadRequest? pendingRequest;
      for (final item
          in ref.read(appControllerProvider).pendingWebIncomingUploads) {
        if (item.id == requestId) {
          pendingRequest = item;
          break;
        }
      }

      if (pendingRequest == null ||
          _webUploadDialogShownFor.contains(requestId)) {
        return;
      }

      _webUploadDialogShownFor.add(requestId);
      _showWebIncomingUploadDialog(pendingRequest);
    });
  }
}

class _DropNetLifecycleObserver extends WidgetsBindingObserver {
  _DropNetLifecycleObserver({required this.onDetached, required this.onResume});

  final Future<void> Function() onDetached;
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      onDetached();
    } else if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class _DecisionDetail {
  const _DecisionDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _DecisionScreen extends StatelessWidget {
  const _DecisionScreen({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.highlightTitle,
    required this.highlightSubtitle,
    required this.icon,
    required this.accent,
    required this.details,
    required this.secondaryLabel,
    required this.primaryLabel,
    required this.onSecondary,
    required this.onPrimary,
    this.batchInfoCard,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String highlightTitle;
  final String highlightSubtitle;
  final IconData icon;
  final Color accent;
  final List<_DecisionDetail> details;
  final String secondaryLabel;
  final String primaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback onPrimary;
  final Widget? batchInfoCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Dialog.fullscreen(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.08),
              colorScheme.primary.withValues(alpha: 0.03),
              colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                              child: Text(
                                eyebrow.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        accent.withValues(alpha: 0.2),
                                        accent.withValues(alpha: 0.05),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.1),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(icon, size: 36, color: accent),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        subtitle,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                              height: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.surfaceContainerLow,
                                    colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.25),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.04),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(icon, color: accent, size: 26),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          highlightTitle,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          highlightSubtitle,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (batchInfoCard != null) ...[
                              const SizedBox(height: 16),
                              batchInfoCard!,
                            ],
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: details
                                  .map(
                                    (detail) => SizedBox(
                                      width: 250,
                                      child: Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              colorScheme.surface,
                                              colorScheme.surfaceContainerLow
                                                  .withValues(alpha: 0.6),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant
                                                .withValues(alpha: 0.4),
                                            width: 1.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.01,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              detail.icon,
                                              color: accent,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    detail.label,
                                                    style: theme
                                                        .textTheme
                                                        .labelLarge
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    detail.value,
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSecondary,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.errorContainer
                                .withValues(alpha: 0.9),
                            foregroundColor: colorScheme.error,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          label: Text(
                            secondaryLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onPrimary,
                          icon: const Icon(Icons.check_rounded, size: 20),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor: Colors.green.shade600.withValues(
                              alpha: 0.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          label: Text(
                            primaryLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
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
        ),
      ),
    );
  }
}

class _ActivePairingDialog {
  _ActivePairingDialog({required this.context});
  BuildContext context;
  bool isPopped = false;
}
