import 'package:client/messages/message_center.dart';
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
}
