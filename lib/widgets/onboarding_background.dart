import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// A full-screen animated blob background inspired by the Google Pixel setup
/// experience.  All colors are sourced from the ambient [ColorScheme] so they
/// automatically adapt to Material You / Monet themes.
///
/// Drop this widget as the bottommost layer of any onboarding [Stack].
class OnboardingBackground extends StatefulWidget {
  const OnboardingBackground({super.key});

  @override
  State<OnboardingBackground> createState() => _OnboardingBackgroundState();
}

class _OnboardingBackgroundState extends State<OnboardingBackground>
    with TickerProviderStateMixin {
  // Each blob gets its own controller for independent timing.
  late final List<AnimationController> _controllers;

  // Blob definitions – positions and sizes are expressed as fractions of the
  // screen, animations merely offset these values.
  static const List<_BlobDef> _blobs = [
    // Top-left accent
    _BlobDef(
      baseX: -0.15,
      baseY: -0.10,
      baseW: 0.72,
      baseH: 0.55,
      dxRange: 0.08,
      dyRange: 0.06,
      scaleRange: 0.08,
      durationMs: 14000,
      opacityBase: 0.38,
      opacityRange: 0.10,
      colorIndex: 0, // primaryContainer
    ),
    // Bottom-right accent
    _BlobDef(
      baseX: 0.42,
      baseY: 0.55,
      baseW: 0.75,
      baseH: 0.60,
      dxRange: 0.07,
      dyRange: 0.08,
      scaleRange: 0.07,
      durationMs: 17000,
      opacityBase: 0.32,
      opacityRange: 0.10,
      colorIndex: 1, // secondaryContainer
    ),
    // Centre-top subtle blob
    _BlobDef(
      baseX: 0.18,
      baseY: -0.20,
      baseW: 0.55,
      baseH: 0.45,
      dxRange: 0.06,
      dyRange: 0.07,
      scaleRange: 0.06,
      durationMs: 19000,
      opacityBase: 0.22,
      opacityRange: 0.08,
      colorIndex: 2, // tertiaryContainer
    ),
    // Bottom-left micro blob
    _BlobDef(
      baseX: -0.10,
      baseY: 0.62,
      baseW: 0.50,
      baseH: 0.42,
      dxRange: 0.05,
      dyRange: 0.06,
      scaleRange: 0.05,
      durationMs: 22000,
      opacityBase: 0.20,
      opacityRange: 0.07,
      colorIndex: 0, // primaryContainer again for cohesion
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_blobs.length, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _blobs[i].durationMs),
      );
      // Stagger the start phase so blobs never move in lockstep.
      ctrl.forward(from: (i * 0.25) % 1.0);
      ctrl.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          ctrl.reverse();
        } else if (status == AnimationStatus.dismissed) {
          ctrl.forward();
        }
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = [
      cs.primaryContainer,
      cs.secondaryContainer,
      cs.tertiaryContainer,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return AnimatedBuilder(
          animation: Listenable.merge(_controllers),
          builder: (context, _) {
            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                for (int i = 0; i < _blobs.length; i++)
                  _buildBlob(context, i, w, h, colors),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 110.0, sigmaY: 110.0),
                    child: const SizedBox.shrink(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBlob(
    BuildContext context,
    int i,
    double w,
    double h,
    List<Color> colors,
  ) {
    final def = _blobs[i];
    final ctrl = _controllers[i];
    // Use a smooth eased value for all tweens.
    final t = CurvedAnimation(parent: ctrl, curve: Curves.easeInOut).value;

    final dx = _lerp(-def.dxRange, def.dxRange, t);
    final dy = _lerp(-def.dyRange, def.dyRange, t);
    final scale = 1.0 + _lerp(-def.scaleRange, def.scaleRange, t);
    final opacity =
        def.opacityBase + _lerp(-def.opacityRange, def.opacityRange, t);

    final bw = def.baseW * w * scale;
    final bh = def.baseH * h * scale;
    final bx = (def.baseX + dx) * w;
    final by = (def.baseY + dy) * h;

    final color = colors[def.colorIndex % colors.length];

    // Use an irregular squircle-ish border radius for organic feel.
    final r1 = bw * (0.38 + 0.12 * math.sin(t * math.pi));
    final r2 = bw * (0.28 + 0.10 * math.cos(t * math.pi));

    return Positioned(
      left: bx,
      top: by,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: bw,
          height: bh,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(r1),
              topRight: Radius.circular(r2),
              bottomLeft: Radius.circular(r2),
              bottomRight: Radius.circular(r1),
            ),
          ),
        ),
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// ---------------------------------------------------------------------------
// Internal blob descriptor
// ---------------------------------------------------------------------------

class _BlobDef {
  const _BlobDef({
    required this.baseX,
    required this.baseY,
    required this.baseW,
    required this.baseH,
    required this.dxRange,
    required this.dyRange,
    required this.scaleRange,
    required this.durationMs,
    required this.opacityBase,
    required this.opacityRange,
    required this.colorIndex,
  });

  /// Fraction of screen width/height for the blob's resting position / size.
  final double baseX, baseY, baseW, baseH;

  /// Maximum drift as a fraction of screen width/height.
  final double dxRange, dyRange;

  /// Maximum scale oscillation (added to 1.0).
  final double scaleRange;

  final int durationMs;
  final double opacityBase, opacityRange;

  /// Index into the color list (primaryContainer=0, secondaryContainer=1, …).
  final int colorIndex;
}
