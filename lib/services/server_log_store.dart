import 'package:flutter/foundation.dart';

enum ServerLogLevel {
  info,
  success,
  warning,
  error,
}

class ServerLogEntry {
  const ServerLogEntry({
    required this.level,
    required this.message,
    required this.createdAt,
    this.detail,
  });

  final ServerLogLevel level;
  final String message;
  final String? detail;
  final DateTime createdAt;
}

class ServerLogStore extends ChangeNotifier {
  ServerLogStore._();

  static final ServerLogStore instance = ServerLogStore._();

  final List<ServerLogEntry> _entries = [];

  List<ServerLogEntry> get entries => List.unmodifiable(_entries.reversed);

  void info(String message, {String? detail}) {
    _add(ServerLogLevel.info, message, detail: detail);
  }

  void success(String message, {String? detail}) {
    _add(ServerLogLevel.success, message, detail: detail);
  }

  void warning(String message, {String? detail}) {
    _add(ServerLogLevel.warning, message, detail: detail);
  }

  void error(String message, {String? detail}) {
    _add(ServerLogLevel.error, message, detail: detail);
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(ServerLogLevel level, String message, {String? detail}) {
    _entries.add(ServerLogEntry(
      level: level,
      message: message,
      detail: detail,
      createdAt: DateTime.now(),
    ));
    if (_entries.length > 200) {
      _entries.removeRange(0, _entries.length - 200);
    }
    notifyListeners();
  }
}
