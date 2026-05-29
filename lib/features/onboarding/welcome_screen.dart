import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Future<void> _onContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding.completed', true);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final manage = await Permission.manageExternalStorage.status;
      final storage = await Permission.storage.status;
      if (!mounted) return;
      context.go(
        manage.isGranted || storage.isGranted ? '/receive' : '/permission',
      );
    } else {
      context.go('/receive');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Welcome to DropNet',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    height: 260,
                    child: SvgPicture.asset(
                      'assets/onboarding/preview.svg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Fast & Private Nearby File Sharing',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Send and receive files directly over your local network. No cloud, no tracking - everything stays on your devices.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_AnimatedContinueButton(onPressed: _onContinue)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedContinueButton extends StatefulWidget {
  const _AnimatedContinueButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<_AnimatedContinueButton> createState() =>
      _AnimatedContinueButtonState();
}

class _AnimatedContinueButtonState extends State<_AnimatedContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    return ScaleTransition(
      scale: scale,
      child: FilledButton(
        onPressed: _onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        child: const Text(
          'Continue',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
