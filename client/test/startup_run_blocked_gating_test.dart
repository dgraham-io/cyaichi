import 'package:client/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('run blocked banner is gated until run is attempted', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    expect(find.text('Run blocked'), findsNothing);

    final runButton = find.widgetWithText(FilledButton, 'Run');
    await tester.ensureVisible(runButton);
    await tester.tap(runButton);
    await tester.pumpAndSettle();

    expect(find.text('Run blocked'), findsOneWidget);
    expect(
      find.textContaining('Add at least one node before running.'),
      findsOneWidget,
    );
  });
}
