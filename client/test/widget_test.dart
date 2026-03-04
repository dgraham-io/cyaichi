import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/src/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders canvas and adds file.read node', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    expect(find.text('cyaichi flow client'), findsOneWidget);
    expect(find.byKey(const Key('add-file.read')), findsOneWidget);
    expect(find.text('File Read 1'), findsNothing);

    await tester.tap(find.byKey(const Key('add-file.read')));
    await tester.pumpAndSettle();

    expect(find.text('File Read 1'), findsWidgets);
  });
}
