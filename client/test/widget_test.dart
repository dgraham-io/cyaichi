import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app.dart';

void main() {
  testWidgets('renders canvas and adds file.read node', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    expect(find.text('cyaichi node canvas spike'), findsOneWidget);
    expect(find.byKey(const Key('add-file.read')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-file.read')));
    await tester.pumpAndSettle();

    expect(find.textContaining('file.read'), findsWidgets);
  });
}
