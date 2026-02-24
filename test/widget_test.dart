import 'package:dropnet/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('DropNet app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropNetApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Receive'), findsWidgets);
  });
}
