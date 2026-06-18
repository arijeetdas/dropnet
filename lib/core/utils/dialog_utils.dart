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
  bool useBlur = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, anim1, anim2) => PopScope(
      canPop: false,
      child: builder(context),
    ),
    transitionBuilder: (context, anim1, anim2, child) {
      final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
      final transitionChild = ScaleTransition(
        scale: curve,
        child: FadeTransition(
          opacity: anim1,
          child: child,
        ),
      );
      if (!useBlur) {
        return transitionChild;
      }
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: anim1.value * 6,
                sigmaY: anim1.value * 6,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          transitionChild,
        ],
      );
    },
  );
}

/// Shows a dialog instantly without transition animation.
Future<T?> showInstantDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    pageBuilder: (BuildContext buildContext, Animation<double> animation, Animation<double> secondaryAnimation) {
      final Widget pageChild = Builder(builder: builder);
      return useSafeArea ? SafeArea(child: pageChild) : pageChild;
    },
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: Duration.zero,
  );
}
