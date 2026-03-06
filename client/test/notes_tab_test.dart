import 'package:client/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('notes sidebar tab shows workspace empty state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    final tabBarElement = tester.element(find.byType(TabBar).first);
    final tabController = DefaultTabController.of(tabBarElement);
    expect(tabController, isNotNull);
    tabController!.animateTo(2);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar_tab_notes')), findsOneWidget);
    expect(find.text('Select a workspace to view notes.'), findsOneWidget);
  });
}
