import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A premium, Material 3 Expressive linear progress indicator that paints
/// a bold, continuous shifting sine wave for its active track.
/// When [isTerminal] is true (transfer done or failed), the wave morphs to
/// a flat straight line at the current progress point with thinner stroke.
class WavyLinearProgressIndicator extends StatefulWidget {
  const WavyLinearProgressIndicator({
    super.key,
    required this.value,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 10.0,
    this.waveHeight = 4.0,
    this.waveLength = 32.0,
    this.isTerminal = false,
    this.terminalColor,
  });

  /// The progress fraction, from 0.0 to 1.0.
  final double value;

  /// The active color of the wave progress.
  final Color? color;

  /// The inactive background track color.
  final Color? backgroundColor;

  /// The stroke thickness of the wave.
  final double strokeWidth;

  /// The vertical amplitude of the wave.
  final double waveHeight;

  /// The horizontal wavelength of each wave segment.
  final double waveLength;

  /// When true, the wave morphs to a straight flat line (transfer complete/failed).
  final bool isTerminal;

  /// Override color when in terminal state (e.g. green for success, red for failure).
  final Color? terminalColor;

  @override
  State<WavyLinearProgressIndicator> createState() => _WavyLinearProgressIndicatorState();
}

class _WavyLinearProgressIndicatorState extends State<WavyLinearProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _phaseController;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _phaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseActive = widget.color ?? theme.colorScheme.primary;
    final trackColor = widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: widget.isTerminal ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, flatFraction, child) {
        final effectiveWaveHeight = widget.waveHeight * (1.0 - flatFraction);
        final effectiveStroke = widget.strokeWidth * (1.0 - flatFraction * 0.55);
        final activeColor = (widget.isTerminal && widget.terminalColor != null)
            ? Color.lerp(baseActive, widget.terminalColor!, flatFraction)!
            : baseActive;

        return AnimatedBuilder(
          animation: _phaseController,
          builder: (context, _) {
            return CustomPaint(
              size: Size(double.infinity, widget.strokeWidth + widget.waveHeight * 2),
              painter: _WavyLinearProgressPainter(
                value: widget.value,
                activeColor: activeColor,
                trackColor: trackColor,
                strokeWidth: effectiveStroke,
                waveHeight: effectiveWaveHeight,
                waveLength: widget.waveLength,
                phase: _phaseController.value * 2 * math.pi,
              ),
            );
          },
        );
      },
    );
  }
}

class _WavyLinearProgressPainter extends CustomPainter {
  const _WavyLinearProgressPainter({
    required this.value,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.waveHeight,
    required this.waveLength,
    required this.phase,
  });

  final double value;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;
  final double waveHeight;
  final double waveLength;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final progress = value.clamp(0.0, 1.0);

    // 1. Paint inactive track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth * 0.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      trackPaint,
    );

    // 2. Paint active wavy track
    final activeWidth = progress * size.width;
    if (activeWidth <= 0) return;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(0, centerY);

    const step = 2.0;
    for (double x = 0; x <= activeWidth; x += step) {
      // Shifting sine wave equation: y = sin(kx - wt)
      final angle = (2 * math.pi * x / waveLength) - phase;
      final y = centerY + waveHeight * math.sin(angle);
      path.lineTo(x, y);
    }

    // Connect cleanly to the final progress point if sampling left a small gap
    if (activeWidth > 0) {
      final angle = (2 * math.pi * activeWidth / waveLength) - phase;
      final y = centerY + waveHeight * math.sin(angle);
      path.lineTo(activeWidth, y);
    }

    canvas.drawPath(path, activePaint);
  }

  @override
  bool shouldRepaint(covariant _WavyLinearProgressPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.phase != phase;
  }
}

/// An organic, Material 3 Expressive circular progress indicator that paints
/// a wavy wobbling arc. Successfully completed or failed indicators automatically
/// morph into premium filled check/cross status badges.
class WavyCircularProgressIndicator extends StatefulWidget {
  const WavyCircularProgressIndicator({
    super.key,
    required this.value,
    this.isCompleted = false,
    this.isFailed = false,
    this.size = 36.0,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 4.5,
    this.waveAmplitude = 1.8,
    this.waveFrequency = 6.0,
  });

  /// The progress fraction, from 0.0 to 1.0.
  final double value;

  /// Whether the transfer is completed successfully.
  final bool isCompleted;

  /// Whether the transfer failed.
  final bool isFailed;

  /// Diameter of the circular progress indicator.
  final double size;

  /// Active progress track color.
  final Color? color;

  /// Inactive progress track background color.
  final Color? backgroundColor;

  /// Thickness of the stroke.
  final double strokeWidth;

  /// Radiative amplitude of wave wobbling.
  final double waveAmplitude;

  /// Number of wave peaks around the full circle.
  final double waveFrequency;

  @override
  State<WavyCircularProgressIndicator> createState() => _WavyCircularProgressIndicatorState();
}

class _WavyCircularProgressIndicatorState extends State<WavyCircularProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Morph immediately to premium completed/failed states if flagged
    if (widget.isCompleted) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: widget.size * 0.6,
        ),
      );
    }

    if (widget.isFailed) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.close_rounded,
          color: Colors.white,
          size: widget.size * 0.6,
        ),
      );
    }

    final theme = Theme.of(context);
    final activeColor = widget.color ?? theme.colorScheme.primary;
    final trackColor = widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return AnimatedBuilder(
      animation: _rotateController,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _WavyCircularProgressPainter(
              value: widget.value,
              activeColor: activeColor,
              trackColor: trackColor,
              strokeWidth: widget.strokeWidth,
              waveAmplitude: widget.waveAmplitude,
              waveFrequency: widget.waveFrequency,
              phase: _rotateController.value * 2 * math.pi,
            ),
          ),
        );
      },
    );
  }
}

class _WavyCircularProgressPainter extends CustomPainter {
  const _WavyCircularProgressPainter({
    required this.value,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.waveAmplitude,
    required this.waveFrequency,
    required this.phase,
  });

  final double value;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;
  final double waveAmplitude;
  final double waveFrequency;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = (size.width - strokeWidth - waveAmplitude * 2) / 2;
    if (baseRadius <= 0) return;

    final progress = value.clamp(0.0, 1.0);

    // 1. Draw inactive background circle
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth * 0.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, baseRadius, trackPaint);

    // 2. Draw active progress wavy arc
    if (progress <= 0) return;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    // Start angle: -pi / 2 (top of the circle)
    const startAngle = -math.pi / 2;
    final sweepAngle = progress * 2 * math.pi;

    // Sample points along the active arc
    const angleStep = 0.04; // sample every ~2 degrees
    var isFirst = true;

    for (double a = 0; a <= sweepAngle; a += angleStep) {
      final angle = startAngle + a;
      // Oscillate radius: r = baseRadius + amplitude * sin(frequency * a - phase)
      final r = baseRadius + waveAmplitude * math.sin(waveFrequency * a - phase);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw final point to close gaps
    if (sweepAngle > 0) {
      final angle = startAngle + sweepAngle;
      final r = baseRadius + waveAmplitude * math.sin(waveFrequency * sweepAngle - phase);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (isFirst) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, activePaint);
  }

  @override
  bool shouldRepaint(covariant _WavyCircularProgressPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.phase != phase;
  }
}
