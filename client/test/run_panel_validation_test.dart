import 'package:client/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.workspace_ids': <String>['11111111-1111-1111-1111-111111111111'],
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
  });

  testWidgets('run panel shows validation error when output_file missing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-file.write')));
    await tester.pumpAndSettle();

    final inputField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'input_file',
    );
    expect(inputField, findsOneWidget);
    await tester.enterText(inputField, 'input.txt');
    await tester.pumpAndSettle();

    expect(find.textContaining('output_file is required'), findsOneWidget);
  });
}
