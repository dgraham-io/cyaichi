import 'package:client/src/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ErrorBanner renders and copies full text', (
    WidgetTester tester,
  ) async {
    String? clipboardText;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardText = args['text'] as String?;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );

    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const copyText = 'status_code: 502\nmessage: llm.chat request timed out';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            title: 'Run failed',
            message: 'llm.chat request timed out after 5s',
            copyText: copyText,
          ),
        ),
      ),
    );

    expect(find.text('Run failed'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboardText, copyText);
    expect(find.text('Copied'), findsOneWidget);
  });
}
