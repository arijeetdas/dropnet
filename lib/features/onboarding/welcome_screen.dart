import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

import '../../widgets/onboarding_background.dart';

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Animated blob background ──────────────────────────────────────
          const OnboardingBackground(),
          // ── Foreground content ────────────────────────────────────────────
          Center(
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
                      children: [
                        OnboardingActionButton(
                          label: 'Get Started',
                          onPressed: _onContinue,
                          loadingDuration: const Duration(seconds: 8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding Action Button with Custom Morphing M3 Expressive Loading Animation
// ─────────────────────────────────────────────────────────────────────────────

/// Reusable action button for onboarding screens. It smoothly morphs from a 
/// regular Material 3 FilledButton to a contained M3 expressive loader pill 
/// upon click.
class OnboardingActionButton extends StatefulWidget {
  const OnboardingActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.loadingDuration,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final Duration loadingDuration;
  final bool enabled;

  @override
  State<OnboardingActionButton> createState() => _OnboardingActionButtonState();
}

class _OnboardingActionButtonState extends State<OnboardingActionButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  Timer? _timer;

  // Visual tap scale animation
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OnboardingActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _loading) {
      _timer?.cancel();
      setState(() => _loading = false);
    }
  }

  Future<void> _handleTap() async {
    if (_loading || !widget.enabled) return;

    // Quick scale bounce feedback
    await _scaleCtrl.animateTo(0.95, curve: Curves.easeIn);
    await _scaleCtrl.animateTo(1.0, curve: Curves.easeOut);

    if (!mounted) return;
    setState(() => _loading = true);

    _timer = Timer(widget.loadingDuration, () {
      if (mounted) {
        setState(() => _loading = false);
        widget.onPressed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isButtonEnabled = widget.enabled && !_loading;

    // Monet-aware colors matching standard Material 3 FilledButton specs
    final Color backgroundColor = _loading
        ? cs.primary
        : (isButtonEnabled ? cs.primary : cs.onSurface.withValues(alpha: 0.12));

    final Color foregroundColor = isButtonEnabled 
        ? cs.onPrimary 
        : cs.onSurface.withValues(alpha: 0.38);

    // Precise widths based on label to give a perfectly sized starting pill
    final double defaultWidth = widget.label == 'Get Started' ? 190.0 : 130.0;
    // Shrink / morph to exactly 52.0 width (equal to height) when loading to become a perfect circle container
    final double currentWidth = _loading ? 52.0 : defaultWidth;

    return ScaleTransition(
      scale: _scaleCtrl,
      child: GestureDetector(
        onTap: isButtonEnabled ? _handleTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
          width: currentWidth,
          height: 52,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(26),
            boxShadow: isButtonEnabled
                ? [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Button contents: Label & Arrow (fades out completely when loading)
                AnimatedOpacity(
                  opacity: _loading ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: foregroundColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                // Material 3 Expressive shape morphing loading indicator inside the perfect circular button container
                AnimatedOpacity(
                  opacity: _loading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _loading
                      ? Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: LoadingIndicatorM3E(
                              color: cs.onPrimary,
                              variant: LoadingIndicatorM3EVariant.defaultStyle,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

