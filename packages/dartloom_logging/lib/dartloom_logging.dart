abstract interface class AppLogger {
  void debug(String message);
  void info(String message);
  void warning(String message);
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

class LogEntry {
  const LogEntry(this.level, this.message, {this.error, this.stackTrace});
  final String level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

class MemoryLogger implements AppLogger {
  final List<LogEntry> entries = [];
  @override
  void debug(String message) => entries.add(LogEntry('debug', message));
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) => entries
      .add(LogEntry('error', message, error: error, stackTrace: stackTrace));
  @override
  void info(String message) => entries.add(LogEntry('info', message));
  @override
  void warning(String message) => entries.add(LogEntry('warning', message));
}
