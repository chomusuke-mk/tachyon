import 'package:flutter/foundation.dart';

/// Ordered severity and verbosity levels supported by [AppLogger].
///
/// Release builds default to [error], debug and profile builds default to
/// [debug], and [verbose] can be enabled temporarily when tracing complex tests
/// or elusive runtime issues.
enum LogLevel {
  /// Fine-grained diagnostic tracing (rebuild ticks, position ticks, coalescing).
  verbose(0, 'VERBOSE'),

  /// Detailed state transitions, native bridge events, and lifecycle actions.
  debug(1, 'DEBUG'),

  /// Key startup and high-level lifecycle milestones.
  info(2, 'INFO'),

  /// Recoverable errors, missing optional capabilities, and fallback paths.
  warning(3, 'WARN'),

  /// Failures, uncaught exceptions, and unexpected error conditions.
  error(4, 'ERROR'),

  /// Disables all log output.
  off(5, 'OFF');

  /// Numeric ordering value used for threshold comparisons.
  final int priority;

  /// Fixed uppercase label displayed in formatted log records.
  final String label;

  /// Creates a [LogLevel] entry with [priority] and [label].
  const LogLevel(this.priority, this.label);

  /// Returns whether a record at this level passes [threshold].
  bool meets(LogLevel threshold) =>
      this != LogLevel.off &&
      threshold != LogLevel.off &&
      priority >= threshold.priority;
}

/// Immutable structured log entry emitted by [AppLogger].
@immutable
class LogRecord {
  /// Wall-clock timestamp captured when the log entry was created.
  final DateTime timestamp;

  /// Severity level of the entry.
  final LogLevel level;

  /// Subsystem or component identifier (for example `'AppLifecycle'`).
  final String tag;

  /// Human-readable log message.
  final String message;

  /// Optional error object associated with the event.
  final Object? error;

  /// Optional stack trace captured alongside [error].
  final StackTrace? stackTrace;

  /// Creates an immutable [LogRecord].
  const LogRecord({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  static String _twoDigits(int n) => n < 10 ? '0$n' : '$n';

  static String _threeDigits(int n) {
    if (n >= 100) return '$n';
    if (n >= 10) return '0$n';
    return '00$n';
  }

  /// Formats this record as `[HH:mm:ss.SSS] [LEVEL  ] [Tag] message`,
  /// appending error and stack trace details when present.
  String format() {
    final hh = _twoDigits(timestamp.hour);
    final mm = _twoDigits(timestamp.minute);
    final ss = _twoDigits(timestamp.second);
    final ms = _threeDigits(timestamp.millisecond);
    final paddedLevel = level.label.padRight(7);
    final buffer = StringBuffer(
      '[$hh:$mm:$ss.$ms] [$paddedLevel] [$tag] $message',
    );
    if (error != null) {
      buffer.write('\n  error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Callback invoked for every [LogRecord] that passes the active threshold.
typedef LogSink = void Function(LogRecord record);

/// Centralized level-filtered application logger.
///
/// Defaults to [LogLevel.error] in release builds and [LogLevel.debug] in debug
/// and profile builds, and honors `--dart-define=TACHYON_LOG_LEVEL=<level>`.
abstract final class AppLogger {
  /// Compile-time `--dart-define=TACHYON_LOG_LEVEL=...` override string.
  static const String envLogLevel = String.fromEnvironment('TACHYON_LOG_LEVEL');

  /// Default minimum [LogLevel] resolved from [envLogLevel] and [kReleaseMode].
  static LogLevel get defaultLevel =>
      parseLevel(envLogLevel) ??
      (kReleaseMode ? LogLevel.error : LogLevel.debug);

  /// Currently active minimum [LogLevel] threshold.
  static LogLevel minLevel = defaultLevel;

  /// Optional custom [LogSink] receiving accepted [LogRecord] instances.
  ///
  /// When `null`, records are formatted and printed via [debugPrint].
  static LogSink? sink;

  /// Returns `true` when [level] would be emitted under [minLevel].
  static bool isEnabled(LogLevel level) => level.meets(minLevel);

  /// Parses a case-insensitive log level string such as `'verbose'`,
  /// `'debug'`, `'info'`, `'warn'`, `'warning'`, `'error'`, or `'off'`.
  ///
  /// Returns `null` when [raw] is `null` or does not match a known alias.
  static LogLevel? parseLevel(String? raw) {
    if (raw == null) return null;
    return switch (raw.trim().toLowerCase()) {
      'v' || 'verbose' => LogLevel.verbose,
      'd' || 'debug' => LogLevel.debug,
      'i' || 'info' => LogLevel.info,
      'w' || 'warn' || 'warning' => LogLevel.warning,
      'e' || 'err' || 'error' => LogLevel.error,
      'off' || 'none' => LogLevel.off,
      _ => null,
    };
  }

  /// Restores [minLevel] to [defaultLevel] and clears any custom [sink].
  static void reset() {
    minLevel = defaultLevel;
    sink = null;
  }

  /// Runs [body] with [minLevel] temporarily set to [level] and restores the
  /// previous threshold afterward (even if [body] throws).
  static T runWithLevel<T>(LogLevel level, T Function() body) {
    final previous = minLevel;
    minLevel = level;
    try {
      return body();
    } finally {
      minLevel = previous;
    }
  }

  /// Runs asynchronous [body] with [minLevel] temporarily set to [level] and
  /// restores the previous threshold when the returned future settles.
  static Future<T> runWithLevelAsync<T>(
    LogLevel level,
    Future<T> Function() body,
  ) async {
    final previous = minLevel;
    minLevel = level;
    try {
      return await body();
    } finally {
      minLevel = previous;
    }
  }

  /// Emits a log record at [level] for [tag] if enabled by [minLevel].
  static void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level)) return;
    final record = LogRecord(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    final customSink = sink;
    if (customSink != null) {
      customSink(record);
    } else {
      debugPrint(record.format());
    }
  }

  /// Logs a [LogLevel.verbose] message for [tag].
  static void v(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.verbose,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Evaluates [messageBuilder] and logs at [LogLevel.verbose] only when
  /// verbose logging is currently enabled.
  static void vLazy(String tag, String Function() messageBuilder) {
    if (!isEnabled(LogLevel.verbose)) return;
    log(LogLevel.verbose, tag, messageBuilder());
  }

  /// Logs a [LogLevel.debug] message for [tag].
  static void d(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(LogLevel.debug, tag, message, error: error, stackTrace: stackTrace);

  /// Logs a [LogLevel.info] message for [tag].
  static void i(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(LogLevel.info, tag, message, error: error, stackTrace: stackTrace);

  /// Logs a [LogLevel.warning] message for [tag].
  static void w(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.warning,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs a [LogLevel.error] message for [tag].
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);

  /// Returns a [ScopedLogger] bound to [tag].
  static ScopedLogger scoped(String tag) => ScopedLogger(tag);
}

/// Tag-bound logger helper forwarding calls to [AppLogger].
class ScopedLogger {
  /// Component tag attached to every record emitted through this helper.
  final String tag;

  /// Creates a [ScopedLogger] bound to [tag].
  const ScopedLogger(this.tag);

  /// Logs a [LogLevel.verbose] message.
  void v(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.v(tag, message, error: error, stackTrace: stackTrace);

  /// Lazily evaluates [messageBuilder] and logs at [LogLevel.verbose] when
  /// verbose logging is enabled.
  void vLazy(String Function() messageBuilder) =>
      AppLogger.vLazy(tag, messageBuilder);

  /// Logs a [LogLevel.debug] message.
  void d(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.d(tag, message, error: error, stackTrace: stackTrace);

  /// Logs a [LogLevel.info] message.
  void i(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.i(tag, message, error: error, stackTrace: stackTrace);

  /// Logs a [LogLevel.warning] message.
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.w(tag, message, error: error, stackTrace: stackTrace);

  /// Logs a [LogLevel.error] message.
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.e(tag, message, error: error, stackTrace: stackTrace);
}
