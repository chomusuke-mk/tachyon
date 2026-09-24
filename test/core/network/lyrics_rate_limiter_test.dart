import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';

void main() {
  group('LyricsRateLimiter', () {
    test('dispatches first request immediately without artificial delay', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 500),
      );
      final sw = Stopwatch()..start();

      var executed = false;
      await limiter.runThrottled(() async {
        executed = true;
      });
      sw.stop();

      expect(executed, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(limiter.requestTimestamps.length, equals(1));
    });

    test('enforces minimum 500ms spacing between two sequential requests', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 500),
      );

      await limiter.runThrottled(() async => 1);
      final sw = Stopwatch()..start();
      await limiter.runThrottled(() async => 2);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(450));
      expect(limiter.requestTimestamps.length, equals(2));
      final spacing = limiter.requestTimestamps[1]
          .difference(limiter.requestTimestamps[0])
          .inMilliseconds;
      expect(spacing, greaterThanOrEqualTo(450));
    });

    test('processes burst requests in FIFO order with proper spacing', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 100),
      );
      final order = <int>[];

      final f1 = limiter.runThrottled(() async => order.add(1));
      final f2 = limiter.runThrottled(() async => order.add(2));
      final f3 = limiter.runThrottled(() async => order.add(3));

      await Future.wait([f1, f2, f3]);

      expect(order, equals([1, 2, 3]));
      expect(limiter.requestTimestamps.length, equals(3));
    });

    test('does not delay request if more than minInterval has already elapsed', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 200),
      );

      await limiter.runThrottled(() async => 'first');
      await Future.delayed(const Duration(milliseconds: 250));

      final sw = Stopwatch()..start();
      await limiter.runThrottled(() async => 'second');
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('cancellation token cancels queued request during pacing wait without executing action', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 300),
      );
      final token = LyricsCancellationToken();

      // First request runs immediately
      await limiter.runThrottled(() async => 'r1');

      // Second request enters pacing wait
      var actionCalled = false;
      final f2 = limiter.runThrottled(
        () async {
          actionCalled = true;
          return 'r2';
        },
        cancellationToken: token,
      );

      // Cancel token while waiting in queue
      token.cancel();

      await expectLater(f2, throwsA(isA<LyricsCancelledException>()));
      expect(actionCalled, isFalse);
    });

    test('recovering from action exceptions does not break subsequent queued requests', () async {
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 50),
      );

      final f1 = limiter.runThrottled(() async => throw Exception('Network error'));
      await expectLater(f1, throwsException);

      var nextCalled = false;
      final f2 = limiter.runThrottled(() async {
        nextCalled = true;
        return 'success';
      });

      final result = await f2;
      expect(nextCalled, isTrue);
      expect(result, equals('success'));
    });

    test('simulated time jump forward releases throttled request immediately', () async {
      var simulatedTime = DateTime(2026, 9, 23, 12, 0, 0);
      final limiter = LyricsRateLimiter(
        minInterval: const Duration(milliseconds: 500),
        nowProvider: () => simulatedTime,
      );

      await limiter.runThrottled(() async => 1);

      // Advance simulated time forward by 1 second
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));

      final sw = Stopwatch()..start();
      await limiter.runThrottled(() async => 2);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('dispose marks limiter as disposed and rejects new requests', () async {
      final limiter = LyricsRateLimiter();
      limiter.dispose();

      expect(limiter.isDisposed, isTrue);
      expect(() => limiter.runThrottled(() async => 1), throwsStateError);
    });
  });

  group('LyricsCancellationToken & GenerationTracker', () {
    test('token notifies listeners upon cancellation', () {
      final token = LyricsCancellationToken();
      var notified = false;
      token.onCancelled(() => notified = true);

      expect(token.isCancelled, isFalse);
      expect(notified, isFalse);

      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(notified, isTrue);
    });

    test('generation tracker cancels previous token and advances active token', () {
      final tracker = LyricsGenerationTracker();
      final t1 = tracker.nextGeneration();
      expect(tracker.activeToken, equals(1));
      expect(t1.isCancelled, isFalse);
      expect(tracker.isCurrent(1), isTrue);

      final t2 = tracker.nextGeneration();
      expect(tracker.activeToken, equals(2));
      expect(t1.isCancelled, isTrue);
      expect(t2.isCancelled, isFalse);
      expect(tracker.isCurrent(1), isFalse);
      expect(tracker.isCurrent(2), isTrue);
    });
  });

  group('LyricsCooldownManager', () {
    test('cooldown is inactive when cooldownExpiry is null', () {
      final manager = LyricsCooldownManager();
      expect(manager.isCooldownActive, isFalse);
      expect(manager.remainingCooldownSeconds, equals(0));
    });

    test('setCooldown sets expiry in future and activates cooldown', () {
      var now = DateTime(2026, 9, 23, 12, 0, 0);
      final manager = LyricsCooldownManager(nowProvider: () => now);

      manager.setCooldown(const Duration(seconds: 60));
      expect(manager.isCooldownActive, isTrue);
      expect(manager.remainingCooldownSeconds, equals(60));

      // Advance time by 30 seconds
      now = now.add(const Duration(seconds: 30));
      expect(manager.isCooldownActive, isTrue);
      expect(manager.remainingCooldownSeconds, equals(30));

      // Advance time by 35 seconds (past expiry)
      now = now.add(const Duration(seconds: 35));
      expect(manager.isCooldownActive, isFalse);
      expect(manager.remainingCooldownSeconds, equals(0));
    });

    test('setCooldown with longer duration extends expiry', () {
      var now = DateTime(2026, 9, 23, 12, 0, 0);
      final manager = LyricsCooldownManager(nowProvider: () => now);

      manager.setCooldown(const Duration(seconds: 30));
      final exp1 = manager.cooldownExpiry!;

      manager.setCooldown(const Duration(seconds: 120));
      final exp2 = manager.cooldownExpiry!;

      expect(exp2.isAfter(exp1), isTrue);
      expect(manager.remainingCooldownSeconds, equals(120));
    });

    test('clearCooldown resets cooldown and cancels deferred retry', () {
      final manager = LyricsCooldownManager();
      manager.setCooldown(const Duration(seconds: 60));
      expect(manager.isCooldownActive, isTrue);

      manager.clearCooldown();
      expect(manager.isCooldownActive, isFalse);
      expect(manager.cooldownExpiry, isNull);
    });

    test('threshold countdown ticks and triggers onAutoRetry when it reaches 0', () async {
      final manager = LyricsCooldownManager();
      var retryInvoked = false;

      manager.startThresholdCountdown(
        seconds: 1,
        onAutoRetry: () async {
          retryInvoked = true;
        },
      );

      expect(manager.isThresholdWaiting, isTrue);
      expect(manager.thresholdCountdownSeconds, equals(1));

      // Wait for countdown timer to finish
      await Future.delayed(const Duration(milliseconds: 1200));

      expect(retryInvoked, isTrue);
      expect(manager.isThresholdWaiting, isFalse);
    });

    test('cancelThresholdCountdown cancels timer and emits null to stream', () async {
      final manager = LyricsCooldownManager();
      final streamEvents = <int?>[];
      final sub = manager.thresholdStream.listen(streamEvents.add);

      manager.startThresholdCountdown(
        seconds: 5,
        onAutoRetry: () async {},
      );
      expect(manager.isThresholdWaiting, isTrue);

      manager.cancelThresholdCountdown();
      expect(manager.isThresholdWaiting, isFalse);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamEvents, contains(null));
      await sub.cancel();
    });

    test('deferred retry triggers onRetry callback when cooldown expires', () async {
      var now = DateTime(2026, 9, 23, 12, 0, 0);
      final manager = LyricsCooldownManager(nowProvider: () => now);
      manager.setCooldown(const Duration(seconds: 60));

      var upgradeTriggered = false;
      manager.scheduleDeferredRetry(
        trackUri: 'file:///song.mp3',
        token: 1,
        onRetry: () async {
          upgradeTriggered = true;
        },
      );

      // Trigger manual expiration test helper
      await manager.expireCooldownAndTriggerUpgrade();
      expect(upgradeTriggered, isTrue);
      expect(manager.isCooldownActive, isFalse);
    });

    test('updateDeferredTrack changes active target track for deferred retry', () async {
      final manager = LyricsCooldownManager();
      manager.setCooldown(const Duration(seconds: 60));

      var executedTrack = '';
      manager.scheduleDeferredRetry(
        trackUri: 'file:///track1.mp3',
        token: 1,
        onRetry: () async {
          executedTrack = 'track1';
        },
      );

      // Track switches to track2 during active cooldown
      manager.updateDeferredTrack(
        trackUri: 'file:///track2.mp3',
        token: 2,
        onRetry: () async {
          executedTrack = 'track2';
        },
      );

      await manager.expireCooldownAndTriggerUpgrade();
      expect(executedTrack, equals('track2'));
    });
  });

  group('parseRetryAfterHeader', () {
    test('parses integer seconds correctly', () {
      expect(parseRetryAfterHeader('5'), equals(5));
      expect(parseRetryAfterHeader('10'), equals(10));
      expect(parseRetryAfterHeader('60'), equals(60));
      expect(parseRetryAfterHeader('3600'), equals(3600));
    });

    test('returns defaultSeconds for null, empty or invalid string', () {
      expect(parseRetryAfterHeader(null, defaultSeconds: 5), equals(5));
      expect(parseRetryAfterHeader('', defaultSeconds: 5), equals(5));
      expect(parseRetryAfterHeader('   ', defaultSeconds: 5), equals(5));
      expect(parseRetryAfterHeader('invalid', defaultSeconds: 5), equals(5));
    });

    test('parses RFC 1123 HTTP-date relative to current time', () {
      final fixedNow = DateTime.utc(2026, 9, 23, 12, 0, 0);
      // Date 30 seconds into future: 12:00:30 GMT
      const httpDateStr = 'Wed, 23 Sep 2026 12:00:30 GMT';

      final seconds = parseRetryAfterHeader(
        httpDateStr,
        nowProvider: () => fixedNow,
      );

      expect(seconds, equals(30));
    });

    test('parses Map<String, String> header map', () {
      expect(parseRetryAfterHeader({'Retry-After': '15'}), equals(15));
      expect(parseRetryAfterHeader({'retry-after': '20'}), equals(20));
      expect(parseRetryAfterHeader({'other-header': '20'}), equals(5));
    });
  });
}
