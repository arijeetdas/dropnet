import 'dart:ui';
import 'package:flutter/material.dart';

/// Shows an ultra-premium Material 3 Expressive dialog featuring:
/// - Smooth scale-and-fade scale transition
/// - Custom animated whole-screen background blur (BackdropFilter)
/// - Strict close control: non-dismissible outside and PopScope locked.
Future<T?> showDropNetDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  String barrierLabel = 'Dialog',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (context, anim1, anim2, child) {
      final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: anim1.value * 6,
          sigmaY: anim1.value * 6,
        ),
        child: ScaleTransition(
          scale: curve,
          child: FadeTransition(
            opacity: anim1,
            child: PopScope(
              canPop: false,
              child: builder(context),
            ),
          ),
        ),
      );
    },
  );
}
