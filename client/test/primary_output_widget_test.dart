import 'package:client/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('file.write primary badge appears after selection', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    final addWrite = find.byKey(const Key('add-file.write'));
    await tester.tap(addWrite);
    await tester.pumpAndSettle();
    await tester.tap(addWrite);
    await tester.pumpAndSettle();

    expect(find.text('Set as Primary Output'), findsOneWidget);
    await tester.tap(find.text('Set as Primary Output'));
    await tester.pumpAndSettle();

    expect(find.text('Primary'), findsWidgets);
  });
}
