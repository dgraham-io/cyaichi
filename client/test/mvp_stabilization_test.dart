import 'package:client/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Run button is disabled when no workspace selected', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    final runButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Run'),
    );
    expect(runButton.onPressed, isNull);
  });

  testWidgets('dirty-state indicator turns on after adding a node', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('•'), findsNothing);

    await tester.tap(find.byKey(const Key('add-file.read')));
    await tester.pumpAndSettle();

    expect(find.textContaining('•'), findsOneWidget);
  });
}
