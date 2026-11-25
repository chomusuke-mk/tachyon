import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/logging/app_logger.dart';

void main() {
  tearDown(() {
    AppLogger.reset();
  });

  group('LogLevel', () {
    test('ordering is strictly monotonic from verbose to off', () {
      expect(LogLevel.verbose.priority, lessThan(LogLevel.debug.priority));
      expect(LogLevel.debug.priority, lessThan(LogLevel.info.priority));
      expect(LogLevel.info.priority, lessThan(LogLevel.warning.priority));
      expect(LogLevel.warning.priority, lessThan(LogLevel.error.priority));
      expect(LogLevel.error.priority, lessThan(LogLevel.off.priority));
    });

    test('meets respects threshold and off disables all levels', () {
      expect(LogLevel.verbose.meets(LogLevel.verbose), isTrue);
      expect(LogLevel.verbose.meets(LogLevel.debug), isFalse);
      expect(LogLevel.debug.meets(LogLevel.debug), isTrue);
      expect(LogLevel.info.meets(LogLevel.debug), isTrue);
      expect(LogLevel.warning.meets(LogLevel.error), isFalse);
      expect(LogLevel.error.meets(LogLevel.error), isTrue);

      for (final level in LogLevel.values) {
        expect(level.meets(LogLevel.off), isFalse);
        expect(LogLevel.off.meets(level), isFalse);
      }
    });
  });

  group('AppLogger filtering and formatting', () {
    test('defaults to LogLevel.debug in non-release tests', () {
      expect(AppLogger.defaultLevel, LogLevel.debug);
      expect(AppLogger.minLevel, LogLevel.debug);

      final records = <LogRecord>[];
      AppLogger.sink = records.add;

      AppLogger.v('Test', 'hidden verbose');
      AppLogger.d('Test', 'visible debug');
      AppLogger.i('Test', 'visible info');
      AppLogger.w('Test', 'visible warn');
      AppLogger.e('Test', 'visible error');

      expect(records.map((r) => r.level).toList(), [
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]);
      expect(records.map((r) => r.message).toList(), [
        'visible debug',
        'visible info',
        'visible warn',
        'visible error',
      ]);
    });

    test('release threshold LogLevel.error blocks non-error logs', () {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;
      AppLogger.minLevel = LogLevel.error;

      AppLogger.v('Test', 'v');
      AppLogger.d('Test', 'd');
      AppLogger.i('Test', 'i');
      AppLogger.w('Test', 'w');
      AppLogger.e('Test', 'e');

      expect(records, hasLength(1));
      expect(records.single.level, LogLevel.error);
      expect(records.single.message, 'e');
    });

    test('LogLevel.off blocks all records including errors', () {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;
      AppLogger.minLevel = LogLevel.off;

      AppLogger.v('Test', 'v');
      AppLogger.d('Test', 'd');
      AppLogger.i('Test', 'i');
      AppLogger.w('Test', 'w');
      AppLogger.e('Test', 'e');

      expect(records, isEmpty);
    });

    test('vLazy skips message builder below verbose and invokes it at verbose', () {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;

      var calls = 0;
      AppLogger.minLevel = LogLevel.debug;
      AppLogger.vLazy('Trace', () {
        calls++;
        return 'expensive detail';
      });
      expect(calls, 0);
      expect(records, isEmpty);

      AppLogger.minLevel = LogLevel.verbose;
      AppLogger.vLazy('Trace', () {
        calls++;
        return 'expensive detail';
      });
      expect(calls, 1);
      expect(records, hasLength(1));
      expect(records.single.level, LogLevel.verbose);
      expect(records.single.message, 'expensive detail');
    });

    test('parseLevel parses aliases case-insensitively and rejects unknown input', () {
      expect(AppLogger.parseLevel('v'), LogLevel.verbose);
      expect(AppLogger.parseLevel('VERBOSE'), LogLevel.verbose);
      expect(AppLogger.parseLevel('  d '), LogLevel.debug);
      expect(AppLogger.parseLevel('debug'), LogLevel.debug);
      expect(AppLogger.parseLevel('I'), LogLevel.info);
      expect(AppLogger.parseLevel('Info'), LogLevel.info);
      expect(AppLogger.parseLevel('w'), LogLevel.warning);
      expect(AppLogger.parseLevel('warn'), LogLevel.warning);
      expect(AppLogger.parseLevel('WARNING'), LogLevel.warning);
      expect(AppLogger.parseLevel('e'), LogLevel.error);
      expect(AppLogger.parseLevel('err'), LogLevel.error);
      expect(AppLogger.parseLevel('Error'), LogLevel.error);
      expect(AppLogger.parseLevel('off'), LogLevel.off);
      expect(AppLogger.parseLevel('NONE'), LogLevel.off);

      expect(AppLogger.parseLevel(null), isNull);
      expect(AppLogger.parseLevel(''), isNull);
      expect(AppLogger.parseLevel('trace'), isNull);
    });

    test('runWithLevel temporarily overrides threshold and restores on exception', () {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;
      AppLogger.minLevel = LogLevel.warning;

      final value = AppLogger.runWithLevel(LogLevel.verbose, () {
        expect(AppLogger.minLevel, LogLevel.verbose);
        AppLogger.v('SyncTrace', 'inside override');
        return 42;
      });

      expect(value, 42);
      expect(AppLogger.minLevel, LogLevel.warning);
      expect(records.single.message, 'inside override');

      expect(
        () => AppLogger.runWithLevel(LogLevel.verbose, () {
          expect(AppLogger.minLevel, LogLevel.verbose);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(AppLogger.minLevel, LogLevel.warning);
    });

    test('runWithLevelAsync temporarily overrides threshold and restores on error', () async {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;
      AppLogger.minLevel = LogLevel.error;

      final value = await AppLogger.runWithLevelAsync(
        LogLevel.verbose,
        () async {
          await Future<void>.delayed(Duration.zero);
          AppLogger.v('AsyncTrace', 'async inside override');
          return 'ok';
        },
      );

      expect(value, 'ok');
      expect(AppLogger.minLevel, LogLevel.error);
      expect(records.single.message, 'async inside override');

      await expectLater(
        () => AppLogger.runWithLevelAsync<void>(
          LogLevel.verbose,
          () async {
            await Future<void>.delayed(Duration.zero);
            throw ArgumentError('async boom');
          },
        ),
        throwsArgumentError,
      );
      expect(AppLogger.minLevel, LogLevel.error);
    });

    test('LogRecord.format includes timestamp, padded level, tag, error, and stack', () {
      final trace = StackTrace.fromString('#0 foo (bar.dart:1)');
      final record = LogRecord(
        timestamp: DateTime(2026, 11, 25, 9, 4, 5, 7),
        level: LogLevel.info,
        tag: 'AppLifecycle',
        message: 'Mode transition: active -> suspended',
        error: 'sample error',
        stackTrace: trace,
      );

      final formatted = record.format();
      expect(
        formatted,
        '[09:04:05.007] [INFO   ] [AppLifecycle] Mode transition: active -> suspended\n'
        '  error: sample error\n'
        '#0 foo (bar.dart:1)',
      );
    });

    test('ScopedLogger tags emitted records at each severity level', () {
      final records = <LogRecord>[];
      AppLogger.sink = records.add;
      AppLogger.minLevel = LogLevel.verbose;

      const log = ScopedLogger('MyComponent');
      log.v('msg-v');
      log.vLazy(() => 'msg-vlazy');
      log.d('msg-d');
      log.i('msg-i');
      log.w('msg-w');
      log.e('msg-e', error: 'err');

      expect(records, hasLength(6));
      for (final r in records) {
        expect(r.tag, 'MyComponent');
      }
      expect(records.last.error, 'err');
    });
  });
}
