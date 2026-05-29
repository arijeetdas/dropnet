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
import 'core/utils/file_utils.dart';
import 'core/networking/web_server_service.dart';
import 'models/transfer_model.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/receive/receive_screen.dart';
import 'features/receive/received_file_screen.dart';
import 'features/receive/shared_text_screen.dart';
import 'features/receive/incoming_requests_screen.dart';
import 'features/send/send_files_screen.dart';
import 'features/settings/favorite_devices_screen.dart';
import 'features/settings/settings_screen.dart';
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
  final Set<String> _peerDialogShownFor = {};
  final Set<String> _webUploadDialogShownFor = {};
  bool _transferSessionOpen = false;
  bool _sharedTextOpening = false;
  bool _receivedFilePreviewOpening = false;
  bool _globalDragActive = false;
  bool _startupRouteReady = false;
  Timer? _permissionPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    Future<void>(() async {
      await _routeForStartup();
      if (mounted) {
        setState(() => _startupRouteReady = true);
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
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _permissionPollTimer?.cancel();
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
      _pairingDialogShownFor.removeWhere(
        (id) => !next.pendingPairingRequests.any((request) => request.id == id),
      );
      _peerDialogShownFor.removeWhere(
        (id) => !next.pendingWebPeerRequests.any((request) => request.id == id),
      );
      _webUploadDialogShownFor.removeWhere(
        (id) =>
            !next.pendingWebIncomingUploads.any((request) => request.id == id),
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

      final hasPendingSendImports =
          next.pendingSharedFilePaths.isNotEmpty ||
          next.pendingSharedTexts.isNotEmpty;
      if (hasPendingSendImports) {
        if (!_isSendRouteVisible()) {
          _router.go('/send');
        }
      }

      if (next.transferSessionActive && !_transferSessionOpen) {
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

      for (final request in next.pendingIncomingRequests) {
        if (!_dialogShownFor.contains(request.id)) {
          _dialogShownFor.add(request.id);
          _showIncomingDialog(request);
          break;
        }
      }

      for (final request in next.pendingPairingRequests) {
        if (!_pairingDialogShownFor.contains(request.id)) {
          _pairingDialogShownFor.add(request.id);
          _showIncomingPairingDialog(request);
          break;
        }
      }

      for (final peerRequest in next.pendingWebPeerRequests) {
        if (!_peerDialogShownFor.contains(peerRequest.id)) {
          _peerDialogShownFor.add(peerRequest.id);
          _showWebPeerDialog(peerRequest);
          break;
        }
      }

      for (final uploadRequest in next.pendingWebIncomingUploads) {
        if (!_webUploadDialogShownFor.contains(uploadRequest.id)) {
          _webUploadDialogShownFor.add(uploadRequest.id);
          _showWebIncomingUploadDialog(uploadRequest);
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
      return;
    }

    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => PairingCodeDialog(
        deviceName: request.fromDeviceName,
        fileName: 'Pairing Request',
        expectedCode: request.pairingCode,
      ),
    );

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

  Future<void> _showIncomingDialog(IncomingTransferRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
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
    final initialApproved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => PopScope(
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
      ),
    );

    if (!mounted || initialApproved != true) {
      if (!mounted) {
        return;
      }
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
      final codeApproved = await showDialog<bool>(
        context: verificationContext,
        barrierDismissible: false,
        builder: (context) => PairingCodeDialog(
          deviceName: request.fromDeviceName,
          fileName: request.fileName,
          expectedCode: request.pairingCode,
        ),
      );

      if (!mounted) {
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
    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
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
    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: _DecisionScreen(
          eyebrow: 'Web upload request',
          title: 'Accept this file from the web?',
          subtitle:
              'The file will be saved into your current DropNet download location.',
          highlightTitle: request.fileName,
          highlightSubtitle: TransferVisuals.kindLabel(request.fileName),
          icon: TransferVisuals.iconForName(request.fileName),
          accent: TransferVisuals.accentColor(context, request.fileName),
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
              label: 'File size',
              value: FileUtils.formatBytes(request.size.toDouble()),
            ),
          ],
          secondaryLabel: 'Reject',
          primaryLabel: 'Accept',
          onSecondary: () => Navigator.of(context).pop(false),
          onPrimary: () => Navigator.of(context).pop(true),
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
  _DropNetLifecycleObserver({required this.onDetached});

  final Future<void> Function() onDetached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      onDetached();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Dialog.fullscreen(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: 0.09), colorScheme.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Center(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withValues(
                                  alpha: 0.82,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(eyebrow),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(22),
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
                                        style: theme.textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        subtitle,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
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
                                    child: Icon(icon, color: accent),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          highlightTitle,
                                          style: theme.textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          highlightSubtitle,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: details
                                  .map(
                                    (detail) => SizedBox(
                                      width: 260,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant
                                                .withValues(alpha: 0.65),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(detail.icon, color: accent),
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
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(detail.value),
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
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSecondary,
                          child: Text(secondaryLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: onPrimary,
                          child: Text(primaryLabel),
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
