import 'package:dropnet/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('DropNet app boots', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({'onboarding.completed': true});
    
    await tester.pumpWidget(const ProviderScope(child: DropNetApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Receive'), findsWidgets);
    
    debugDefaultTargetPlatformOverride = null;
  });
}
