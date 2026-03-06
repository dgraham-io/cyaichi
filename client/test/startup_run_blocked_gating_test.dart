import 'package:client/src/app.dart';
import 'package:client/messages/message_center.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MessageCenter.instance.clear();
  });

  testWidgets('run blocked banner is gated until run is attempted', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CyaichiApp());
    await tester.pumpAndSettle();

    final runBlockedMessagesBefore = MessageCenter.instance.messages
        .where((message) => message.message.contains('Run blocked'))
        .length;
    expect(runBlockedMessagesBefore, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final runBlockedMessagesAfter = MessageCenter.instance.messages
        .where((message) => message.message.contains('Run blocked'))
        .length;
    expect(runBlockedMessagesAfter, 1);
  });
}
