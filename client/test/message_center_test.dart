import 'package:client/messages/message_center.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('log adds message and unread count increments', () {
    final center = MessageCenter.instance;
    center.clear();

    center.log(
      level: AppMessageLevel.info,
      source: AppMessageSource.app,
      message: 'hello',
    );

    expect(center.messages.length, 1);
    expect(center.unreadCount, 1);
  });

  test('clear removes messages and resets unread count', () {
    final center = MessageCenter.instance;
    center.clear();
    center.log(
      level: AppMessageLevel.error,
      source: AppMessageSource.network,
      message: 'oops',
    );
    expect(center.unreadCount, 1);

    center.clear();
    expect(center.messages, isEmpty);
    expect(center.unreadCount, 0);
  });

  test('markAllRead clears unread count', () {
    final center = MessageCenter.instance;
    center.clear();
    center.log(
      level: AppMessageLevel.warn,
      source: AppMessageSource.server,
      message: 'warn',
    );
    center.markAllRead();
    expect(center.unreadCount, 0);
  });

  test('filter helper matches across message fields', () {
    final messages = <AppMessage>[
      AppMessage(
        id: '1',
        timestamp: DateTime(2026, 1, 1, 12, 0, 0),
        level: AppMessageLevel.error,
        source: AppMessageSource.network,
        title: 'HTTP error',
        message: 'Request failed',
        details: <String, dynamic>{'endpoint': '/api/v1/flows'},
      ),
      AppMessage(
        id: '2',
        timestamp: DateTime(2026, 1, 1, 12, 1, 0),
        level: AppMessageLevel.info,
        source: AppMessageSource.app,
        message: 'Workspace renamed',
      ),
    ];

    expect(filterDrawerMessages(messages, 'workspace').length, 1);
    expect(filterDrawerMessages(messages, 'error').length, 1);
    expect(filterDrawerMessages(messages, 'network').length, 1);
    expect(filterDrawerMessages(messages, '/api/v1/flows').length, 1);
    expect(filterDrawerMessages(messages, '').length, 2);
  });
}
