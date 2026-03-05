import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum AppMessageLevel { info, warn, error, success }

enum AppMessageSource { app, server, network }

class AppMessage {
  const AppMessage({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.title,
    this.details,
    this.read = false,
  });

  final String id;
  final DateTime timestamp;
  final AppMessageLevel level;
  final AppMessageSource source;
  final String? title;
  final String message;
  final Map<String, dynamic>? details;
  final bool read;

  AppMessage copyWith({bool? read}) {
    return AppMessage(
      id: id,
      timestamp: timestamp,
      level: level,
      source: source,
      title: title,
      message: message,
      details: details == null ? null : Map<String, dynamic>.from(details!),
      read: read ?? this.read,
    );
  }
}

class MessageCenter extends ChangeNotifier {
  MessageCenter._();

  static final MessageCenter instance = MessageCenter._();
  static const Uuid _uuid = Uuid();

  final List<AppMessage> _messages = <AppMessage>[];

  List<AppMessage> get messages => List<AppMessage>.unmodifiable(_messages);

  int get unreadCount => _messages.where((message) => !message.read).length;

  void log({
    required AppMessageLevel level,
    required AppMessageSource source,
    required String message,
    String? title,
    Map<String, dynamic>? details,
  }) {
    _messages.insert(
      0,
      AppMessage(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: level,
        source: source,
        title: title,
        message: message,
        details: details == null ? null : Map<String, dynamic>.from(details),
      ),
    );
    notifyListeners();
  }

  void markAllRead() {
    if (_messages.every((message) => message.read)) {
      return;
    }
    for (var i = 0; i < _messages.length; i++) {
      _messages[i] = _messages[i].copyWith(read: true);
    }
    notifyListeners();
  }

  void clear() {
    if (_messages.isEmpty) {
      return;
    }
    _messages.clear();
    notifyListeners();
  }
}
