import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:logger/logger.dart';

final class LoggerAppLogger implements AppLogger {
  LoggerAppLogger({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  void debug(String message) => _logger.d(message);
  @override
  void info(String message) => _logger.i(message);
  @override
  void warning(String message) => _logger.w(message);
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}
