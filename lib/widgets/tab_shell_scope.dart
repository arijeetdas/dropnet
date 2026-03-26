import 'package:flutter/widgets.dart';

class TabShellScope extends InheritedWidget {
  const TabShellScope({
    super.key,
    required this.currentIndex,
    required super.child,
  });

  final int currentIndex;

  static TabShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TabShellScope>();
  }

  @override
  bool updateShouldNotify(TabShellScope oldWidget) {
    return currentIndex != oldWidget.currentIndex;
  }
}