import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'core/state/app_state.dart';
import 'core/utils/file_utils.dart';
import 'core/networking/web_server_service.dart';
import 'models/transfer_model.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/ftp_mode/ftp_mode_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/receive/receive_screen.dart';
import 'features/send/send_files_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/transfers/active_transfers_screen.dart';
import 'features/transfers/transfer_session_screen.dart';
import 'features/web_mode/web_mode_screen.dart';
import 'widgets/adaptive_nav_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/receive',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    ShellRoute(
      builder: (context, state, child) => _TabShellScaffold(state: state, child: child),
      routes: [
        GoRoute(
          path: '/receive',
          pageBuilder: (context, state) => const NoTransitionPage(child: ReceiveScreen(embedded: true)),
        ),
        GoRoute(
          path: '/send',
          pageBuilder: (context, state) => const NoTransitionPage(child: SendFilesScreen(embedded: true)),
        ),
        GoRoute(
          path: '/web',
          pageBuilder: (context, state) => const NoTransitionPage(child: WebModeScreen(embedded: true)),
        ),
      ],
    ),
    GoRoute(path: '/transfers', builder: (context, state) => const ActiveTransfersScreen()),
    GoRoute(path: '/transfer-session', builder: (context, state) => const TransferSessionScreen()),
    GoRoute(path: '/ftp', builder: (context, state) => const FtpModeScreen()),
    GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
    GoRoute(path: '/analytics', builder: (context, state) => const AnalyticsScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);

class _TabShellScaffold extends StatelessWidget {
  const _TabShellScaffold({required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  static const _tabs = <({String route, int index})>[
    (route: '/receive', index: 0),
    (route: '/send', index: 1),
    (route: '/web', index: 2),
  ];

  @override
  Widget build(BuildContext context) {
    final currentPath = state.uri.path;
    ({String route, int index})? matched;
    for (final tab in _tabs) {
      if (currentPath.startsWith(tab.route)) {
        matched = tab;
        break;
      }
    }
    final index = matched?.index ?? 0;
    return AdaptiveNavScaffold(
      currentIndex: index,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return FadeTransition(opacity: fade, child: SlideTransition(position: slide, child: child));
        },
        child: KeyedSubtree(
          key: ValueKey(currentPath),
          child: child,
        ),
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
  final Set<String> _peerDialogShownFor = {};
  final Set<String> _webUploadDialogShownFor = {};
  bool _transferSessionOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    Future<void>(() async {
      await ref.read(appControllerProvider.notifier).bootstrap();
    });
  }

  late final WidgetsBindingObserver _lifecycleObserver = _DropNetLifecycleObserver(
    onDetached: () async {
      await ref.read(appControllerProvider.notifier).shutdownNetworkServices();
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider);
    ref.listen<AppState>(appControllerProvider, (previous, next) {
      _dialogShownFor.removeWhere((id) => !next.pendingIncomingRequests.any((request) => request.id == id));
      _peerDialogShownFor.removeWhere((id) => !next.pendingWebPeerRequests.any((request) => request.id == id));
      _webUploadDialogShownFor.removeWhere((id) => !next.pendingWebIncomingUploads.any((request) => request.id == id));

      if (next.pendingSharedFilePaths.isNotEmpty) {
        final currentPath = _router.routeInformationProvider.value.uri.path;
        if (currentPath != '/send') {
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

      for (final request in next.pendingIncomingRequests) {
        if (!_dialogShownFor.contains(request.id)) {
          _dialogShownFor.add(request.id);
          _showIncomingDialog(request);
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
    return DynamicColorBuilder(
      builder: (dynamicLight, dynamicDark) {
        final dynamicSeed = dynamicLight?.primary ?? dynamicDark?.primary;
        final effectiveSeed = appState.useSystemAccent ? (dynamicSeed ?? Colors.indigo) : appState.themeSeed;
        return MaterialApp.router(
          title: 'DropNet',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          themeMode: appState.themeMode,
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showIncomingDialog(IncomingTransferRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      return;
    }
    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Incoming Transfer Request', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Text(request.fileName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('From: ${request.fromDeviceName} (${request.fromAddress})'),
                Text('Size: ${FileUtils.formatBytes(request.size)}'),
                if ((request.batchFileCount ?? 0) > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Batch transfer: file ${(request.batchIndex ?? 0) + 1} of ${request.batchFileCount}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if ((request.batchTotalBytes ?? 0) > 0)
                    Text('Batch total: ${FileUtils.formatBytes(request.batchTotalBytes!)}'),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Accept'),
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
    if (!mounted) {
      return;
    }
    if (approved == true) {
      ref.read(appControllerProvider.notifier).approveIncomingRequest(request.id);
    } else {
      ref.read(appControllerProvider.notifier).rejectIncomingRequest(request.id);
    }
  }

  Future<void> _showWebPeerDialog(WebPeerConnectRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      return;
    }
    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Web Peer Connection Request', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Text(request.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('IP: ${request.ip}'),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Connect'),
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
    if (!mounted) {
      return;
    }
    if (approved == true) {
      ref.read(appControllerProvider.notifier).approveWebPeerRequest(request.id);
    } else {
      ref.read(appControllerProvider.notifier).rejectWebPeerRequest(request.id);
    }
  }

  Future<void> _showWebIncomingUploadDialog(WebIncomingUploadRequest request) async {
    final dialogContext = _rootNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) {
      return;
    }
    final approved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Incoming Web File Request', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Text(request.fileName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('From: ${request.peerName} (${request.ip})'),
                Text('Size: ${FileUtils.formatBytes(request.size.toDouble())}'),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Accept'),
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
    if (!mounted) {
      return;
    }
    if (approved == true) {
      ref.read(appControllerProvider.notifier).approveWebIncomingUpload(request.id);
    } else {
      ref.read(appControllerProvider.notifier).rejectWebIncomingUpload(request.id);
    }
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
