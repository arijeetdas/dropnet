import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';

class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  Timer? _poll;
  bool _checking = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndMaybeProceed();
    });
    _startPolling();
  }

  void _startPolling() {
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkAndMaybeProceed();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkAndMaybeProceed() async {
    if (kIsWeb || !Platform.isAndroid) {
      if (mounted) GoRouter.of(context).go('/receive');
      return;
    }
    final granted = await _hasRequiredAndroidStorageAccess();
    if (mounted) {
      setState(() => _granted = granted);
    }
  }

  Future<void> _requestPermission() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final controller = ref.read(appControllerProvider.notifier);
      await controller.ensureStoragePermission(
        openSettingsIfDenied: true,
        targetPath: '/storage/emulated/0/Download/DropNet',
      );
      await _checkAndMaybeProceed();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<bool> _hasRequiredAndroidStorageAccess() async {
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) {
      return true;
    }

    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  Future<void> _continueToApp() async {
    if (!_granted) {
      return;
    }
    try {
      await ref
          .read(appControllerProvider.notifier)
          .setDownloadDirectory('/storage/emulated/0/Download/DropNet');
    } catch (_) {}
    if (mounted) {
      GoRouter.of(context).go('/receive');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions required'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 160,
                    child: SvgPicture.asset(
                      'assets/onboarding/permission.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Storage Access Needed',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'DropNet needs access to your device storage to save received files and to share files from your device. The app works completely offline and does not collect or upload your data.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _checking ? null : _requestPermission,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Grant permission'),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _granted ? _continueToApp : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
