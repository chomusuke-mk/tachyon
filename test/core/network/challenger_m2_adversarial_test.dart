import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';

void main() {
  group('Adversarial Challenge M2.1: Empirical Stress Harness', () {
    // =========================================================================
    // Challenge 1: LyricsRateLimiter Extreme Concurrency & Pacing Invariants
    // =========================================================================
    group('Challenge 1: LyricsRateLimiter High Concurrency & Pacing Invariants', () {
      test('1.1 50 parallel requests enforce pacing >= minInterval between every dispatch and preserve FIFO order', () async {
        const intervalMs = 25;
        const totalRequests = 50;
        final limiter = LyricsRateLimiter(
          minInterval: const Duration(milliseconds: intervalMs),
        );

        final executionOrder = <int>[];
        final dispatchStopwatch = Stopwatch()..start();

        // Launch all 50 requests concurrently in the same microtask/event turn
        final futures = List.generate(totalRequests, (index) {
          return limiter.runThrottled(() async {
            executionOrder.add(index);
            return index;
          });
        });

        final results = await Future.wait(futures);
        dispatchStopwatch.stop();

        // Verification 1: All 50 requests completed successfully
        expect(results.length, equals(totalRequests));
        expect(limiter.requestTimestamps.length, equals(totalRequests));

        // Verification 2: Strict FIFO order preserved across all 50 concurrent dispatches
        expect(executionOrder, equals(List.generate(totalRequests, (i) => i)));

        // Verification 3: Spacing between every consecutive pair (i, i-1) >= minInterval
        // Allow tiny 5ms OS scheduling tolerance for system timer ticks
        for (int i = 1; i < totalRequests; i++) {
          final diff = limiter.requestTimestamps[i]
              .difference(limiter.requestTimestamps[i - 1])
              .inMilliseconds;
          expect(
            diff,
            greaterThanOrEqualTo(intervalMs - 5),
            reason: 'Dispatch spacing between request $i and ${i - 1} was ${diff}ms, expected >= ${intervalMs - 5}ms',
          );
        }

        // Verification 4: Total elapsed time >= (50 - 1) * 20ms = 980ms
        expect(
          dispatchStopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo((totalRequests - 1) * (intervalMs - 5)),
        );
      });

      test('1.2 High-concurrency burst of 30 requests with interleaved cancellations', () async {
        final limiter = LyricsRateLimiter(
          minInterval: const Duration(milliseconds: 20),
        );

        final cancelledIndices = {2, 5, 7, 11, 15, 19, 23, 27};
        final tokens = List.generate(30, (_) => LyricsCancellationToken());
        final executedIndices = <int>[];

        // Launch 30 requests concurrently
        final futures = List.generate(30, (i) {
          return limiter.runThrottled(
            () async {
              executedIndices.add(i);
              return i;
            },
            cancellationToken: tokens[i],
          );
        });

        // Cancel specific tokens immediately while queued
        for (final idx in cancelledIndices) {
          tokens[idx].cancel();
        }

        int cancelledCount = 0;
        int successCount = 0;

        for (int i = 0; i < 30; i++) {
          try {
            await futures[i];
            successCount++;
          } on LyricsCancelledException {
            cancelledCount++;
          }
        }

        expect(cancelledCount, equals(cancelledIndices.length));
        expect(successCount, equals(30 - cancelledIndices.length));

        // Ensure none of the cancelled items executed their action
        for (final idx in cancelledIndices) {
          expect(executedIndices.contains(idx), isFalse);
        }

        // Ensure executed items preserved FIFO relative order
        final expectedRemaining = List.generate(30, (i) => i)
            .where((i) => !cancelledIndices.contains(i))
            .toList();
        expect(executedIndices, equals(expectedRemaining));
      });

      test('1.3 Disposing limiter while requests are queued terminates all pending items with StateError', () async {
        final limiter = LyricsRateLimiter(
          minInterval: const Duration(milliseconds: 100),
        );

        // First request starts and runs
        final f1 = await limiter.runThrottled(() async => 'first');
        expect(f1, equals('first'));

        Object? err2;
        Object? err3;

        // Queue subsequent items with immediate error listeners attached
        final f2 = limiter.runThrottled(() async => 'second').catchError((e) {
          err2 = e;
          return 'caught2';
        });
        final f3 = limiter.runThrottled(() async => 'third').catchError((e) {
          err3 = e;
          return 'caught3';
        });

        // Dispose limiter while f2 and f3 are waiting in queue
        limiter.dispose();

        // Pending items in queue must complete with error, not stall forever
        await Future.wait([f2, f3]);

        expect(err2, isStateError);
        expect(err3, isStateError);

        // New items after dispose must be rejected immediately
        expect(() => limiter.runThrottled(() async => 'fourth'), throwsStateError);
      });
    });

    // =========================================================================
    // Challenge 2: Rapid Track Skip Concurrency ($1 \to 2 \to 3 \to 4 \to 5$ in < 100ms)
    // =========================================================================
    group('Challenge 2: Rapid Track Skip Concurrency (1 -> 2 -> 3 -> 4 -> 5)', () {
      test('2.1 Track 1 in-flight network call: rapid skips 2, 3, 4 are aborted immediately and only Track 5 dispatches', () async {
        final limiter = LyricsRateLimiter(
          minInterval: const Duration(milliseconds: 50),
        );
        final tracker = LyricsGenerationTracker();

        final dispatchedActions = <int>[];
        final completedActions = <int>[];

        // Track 1 starts and takes 60ms to simulate network latency
        final t1Token = tracker.nextGeneration();
        final f1 = limiter.runThrottled(
          () async {
            dispatchedActions.add(1);
            await Future.delayed(const Duration(milliseconds: 60));
            completedActions.add(1);
            return 'track1';
          },
          cancellationToken: t1Token,
        );

        // While Track 1 is in-flight, user rapidly skips: 2 -> 3 -> 4 -> 5 within 40ms
        await Future.delayed(const Duration(milliseconds: 10));
        final t2Token = tracker.nextGeneration();
        final f2 = limiter.runThrottled(
          () async {
            dispatchedActions.add(2);
            completedActions.add(2);
            return 'track2';
          },
          cancellationToken: t2Token,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        final t3Token = tracker.nextGeneration();
        final f3 = limiter.runThrottled(
          () async {
            dispatchedActions.add(3);
            completedActions.add(3);
            return 'track3';
          },
          cancellationToken: t3Token,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        final t4Token = tracker.nextGeneration();
        final f4 = limiter.runThrottled(
          () async {
            dispatchedActions.add(4);
            completedActions.add(4);
            return 'track4';
          },
          cancellationToken: t4Token,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        final t5Token = tracker.nextGeneration();
        final f5 = limiter.runThrottled(
          () async {
            dispatchedActions.add(5);
            completedActions.add(5);
            return 'track5';
          },
          cancellationToken: t5Token,
        );

        // Await f1
        final res1 = await f1;
        expect(res1, equals('track1'));

        // Tracks 2, 3, 4 must throw LyricsCancelledException
        await expectLater(f2, throwsA(isA<LyricsCancelledException>()));
        await expectLater(f3, throwsA(isA<LyricsCancelledException>()));
        await expectLater(f4, throwsA(isA<LyricsCancelledException>()));

        // Track 5 must execute successfully
        final res5 = await f5;
        expect(res5, equals('track5'));

        // Crucial empirical invariant: Tracks 2, 3, 4 were NEVER dispatched!
        expect(dispatchedActions, equals([1, 5]));
        expect(completedActions, equals([1, 5]));
      });

      test('2.2 Track 1 in pacing wait: rapid skips 1..4 are all aborted and Track 5 executes immediately without multi-interval delay', () async {
        final limiter = LyricsRateLimiter(
          minInterval: const Duration(milliseconds: 200),
        );
        final tracker = LyricsGenerationTracker();

        // Request prior track to establish lastDispatchedTime
        await limiter.runThrottled(() async => 'prior');

        final dispatched = <int>[];

        // Track 1 enters pacing wait (must wait 200ms)
        Object? err1;
        Object? err2;
        Object? err3;
        Object? err4;

        final t1 = tracker.nextGeneration();
        final f1 = limiter.runThrottled(
          () async {
            dispatched.add(1);
            return 't1';
          },
          cancellationToken: t1,
        ).catchError((e) {
          err1 = e;
          return 'err1';
        });

        // Rapid skipping occurs within 30ms (well before 200ms pacing wait finishes)
        await Future.delayed(const Duration(milliseconds: 10));
        final t2 = tracker.nextGeneration();
        final f2 = limiter.runThrottled(
          () async {
            dispatched.add(2);
            return 't2';
          },
          cancellationToken: t2,
        ).catchError((e) {
          err2 = e;
          return 'err2';
        });

        await Future.delayed(const Duration(milliseconds: 5));
        final t3 = tracker.nextGeneration();
        final f3 = limiter.runThrottled(
          () async {
            dispatched.add(3);
            return 't3';
          },
          cancellationToken: t3,
        ).catchError((e) {
          err3 = e;
          return 'err3';
        });

        await Future.delayed(const Duration(milliseconds: 5));
        final t4 = tracker.nextGeneration();
        final f4 = limiter.runThrottled(
          () async {
            dispatched.add(4);
            return 't4';
          },
          cancellationToken: t4,
        ).catchError((e) {
          err4 = e;
          return 'err4';
        });

        await Future.delayed(const Duration(milliseconds: 5));
        final t5 = tracker.nextGeneration();
        final sw = Stopwatch()..start();
        final f5 = limiter.runThrottled(
          () async {
            dispatched.add(5);
            return 't5';
          },
          cancellationToken: t5,
        );

        final res5 = await f5;
        sw.stop();

        await Future.wait([f1, f2, f3, f4]);

        expect(err1, isA<LyricsCancelledException>());
        expect(err2, isA<LyricsCancelledException>());
        expect(err3, isA<LyricsCancelledException>());
        expect(err4, isA<LyricsCancelledException>());

        expect(res5, equals('t5'));
        // Only Track 5 was dispatched among 1..5!
        expect(dispatched, equals([5]));

        // Elapsed time for Track 5 should satisfy the initial 200ms pacing from 'prior',
        // NOT 5 * 200ms = 1000ms!
        expect(sw.elapsedMilliseconds, lessThan(400));
      });

      test('2.3 Rapid track skipping through LrclibClient: intermediate queries never reach HTTP transport', () async {
        final httpRequestedTracks = <String>[];
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            final track = request.url.queryParameters['track_name']!;
            httpRequestedTracks.add(track);
            // Simulate brief 20ms network latency
            await Future.delayed(const Duration(milliseconds: 20));
            return http.Response('{"trackName": "$track"}', 200);
          }),
          minPacing: const Duration(milliseconds: 100),
        );

        final tracker = LyricsGenerationTracker();
        final responses = <Future<LrclibResponse>>[];

        // Rapidly dispatch 5 tracks in < 40ms
        for (int i = 1; i <= 5; i++) {
          final token = tracker.nextGeneration();
          responses.add(
            client.getLyrics(
              trackName: 'Track $i',
              artistName: 'Artist',
              cancellationToken: token,
            ),
          );
          await Future.delayed(const Duration(milliseconds: 5));
        }

        final results = await Future.wait(responses);

        // Tracks 1, 2, 3, 4 should be cancelled (status 499)
        expect(results[0].statusCode, equals(499));
        expect(results[1].statusCode, equals(499));
        expect(results[2].statusCode, equals(499));
        expect(results[3].statusCode, equals(499));

        // Track 5 should succeed (status 200)
        expect(results[4].statusCode, equals(200));
        expect(results[4].isSuccess, isTrue);

        // The HTTP transport should ONLY have received Track 5 (and at most Track 1 if started),
        // but NEVER Track 2, 3, 4!
        expect(httpRequestedTracks.contains('Track 2'), isFalse);
        expect(httpRequestedTracks.contains('Track 3'), isFalse);
        expect(httpRequestedTracks.contains('Track 4'), isFalse);
        expect(httpRequestedTracks, contains('Track 5'));
      });

      test('2.4 Skip cycle back to earlier track (1 -> 2 -> 3 -> 1) resolves Track 1 under active generation', () async {
        final tracker = LyricsGenerationTracker();
        final t1 = tracker.nextGeneration();
        expect(tracker.activeToken, equals(1));
        expect(tracker.isCurrent(1), isTrue);

        final t2 = tracker.nextGeneration();
        expect(tracker.isCurrent(1), isFalse);
        expect(t1.isCancelled, isTrue);
        expect(tracker.isCurrent(2), isTrue);

        final t3 = tracker.nextGeneration();
        expect(t2.isCancelled, isTrue);
        expect(tracker.isCurrent(3), isTrue);

        // User jumps back to Track 1 (generates new token 4)
        final t4 = tracker.nextGeneration();
        expect(t3.isCancelled, isTrue);
        expect(tracker.isCurrent(1), isFalse); // old generation 1 is dead
        expect(tracker.isCurrent(4), isTrue);  // new generation 4 is active
        expect(t4.isCancelled, isFalse);
      });
    });

    // =========================================================================
    // Challenge 3: parseRetryAfterHeader Matrix (Edge Dates, Malformed, Bounds)
    // =========================================================================
    group('Challenge 3: parseRetryAfterHeader Edge Case Matrix', () {
      final fixedClock = DateTime.utc(2026, 9, 23, 12, 0, 0);

      test('3.1 RFC 1123 HTTP-date format parsing with future offset', () {
        // Wed, 23 Sep 2026 12:00:45 GMT -> 45 seconds ahead
        const header = 'Wed, 23 Sep 2026 12:00:45 GMT';
        final seconds = parseRetryAfterHeader(
          header,
          nowProvider: () => fixedClock,
        );
        expect(seconds, equals(45));
      });

      test('3.2 RFC 850 HTTP-date format parsing', () {
        // Wednesday, 23-Sep-26 12:01:00 GMT
        // Note: HttpDate.parse interprets 2-digit years according to Dart SDK logic.
        const header = 'Wednesday, 23-Sep-26 12:01:00 GMT';
        DateTime? parsed;
        try {
          parsed = HttpDate.parse(header);
        } catch (e) {
          // print exception if any
        }
        // Let's verify what HttpDate.parse does
        final seconds = parseRetryAfterHeader(
          header,
          nowProvider: () => fixedClock,
        );
        // If HttpDate.parse interprets '26' as year 1926 or year 2026:
        if (parsed != null && parsed.year == 2026) {
          expect(seconds, equals(60));
        } else {
          // In standard dart:io, HttpDate.parse('... 26 ...') may parse as 1926, which is in the past!
          // Thus difference is negative and returns defaultSeconds (5), preventing negative cooldowns!
          expect(seconds, equals(5));
        }
      });

      test('3.3 ANSI C asctime() format parsing', () {
        // Wed Sep 23 12:00:25 2026 -> 25 seconds ahead
        const header = 'Wed Sep 23 12:00:25 2026';
        final seconds = parseRetryAfterHeader(
          header,
          nowProvider: () => fixedClock,
        );
        expect(seconds, equals(25));
      });

      test('3.4 Past HTTP-date returns defaultSeconds (prevents negative countdowns)', () {
        // 1 hour in the past: 11:00:00 GMT
        const header = 'Wed, 23 Sep 2026 11:00:00 GMT';
        final seconds = parseRetryAfterHeader(
          header,
          nowProvider: () => fixedClock,
          defaultSeconds: 7,
        );
        expect(seconds, equals(7));
      });

      test('3.5 Negative integer seconds returns defaultSeconds', () {
        expect(parseRetryAfterHeader('-1', defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader('-100', defaultSeconds: 10), equals(10));
      });

      test('3.6 Decimal/float strings fall back safely to defaultSeconds', () {
        expect(parseRetryAfterHeader('5.5', defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader('10.0', defaultSeconds: 5), equals(5));
      });

      test('3.7 Whitespace, tabs, and newlines are safely trimmed', () {
        expect(parseRetryAfterHeader('  \t 42 \r\n '), equals(42));
      });

      test('3.8 Arbitrary non-numeric strings return defaultSeconds', () {
        expect(parseRetryAfterHeader('five-seconds', defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader('undefined', defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader('null', defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader('NaN', defaultSeconds: 5), equals(5));
      });

      test('3.9 Extremely large integer strings do not crash with overflow', () {
        // Exceeds 64-bit int max
        const massive = '99999999999999999999999999999999999999999999';
        expect(parseRetryAfterHeader(massive, defaultSeconds: 5), equals(5));
      });

      test('3.10 Boundary values for LrclibRateLimited countdown (<= 10s) vs fallback (> 10s)', () {
        // 0s boundary
        const r0 = LrclibRateLimited(retryAfterSeconds: 0);
        expect(r0.shouldTriggerCountdown, isTrue);
        expect(r0.shouldFallbackImmediately, isFalse);

        // 9s boundary
        const r9 = LrclibRateLimited(retryAfterSeconds: 9);
        expect(r9.shouldTriggerCountdown, isTrue);
        expect(r9.shouldFallbackImmediately, isFalse);

        // 10s exact threshold boundary
        const r10 = LrclibRateLimited(retryAfterSeconds: 10);
        expect(r10.shouldTriggerCountdown, isTrue);
        expect(r10.shouldFallbackImmediately, isFalse);

        // 11s exact threshold boundary
        const r11 = LrclibRateLimited(retryAfterSeconds: 11);
        expect(r11.shouldTriggerCountdown, isFalse);
        expect(r11.shouldFallbackImmediately, isTrue);

        // 60s fallback
        const r60 = LrclibRateLimited(retryAfterSeconds: 60);
        expect(r60.shouldTriggerCountdown, isFalse);
        expect(r60.shouldFallbackImmediately, isTrue);

        // 180s (3 minutes) fallback
        const r180 = LrclibRateLimited(retryAfterSeconds: 180);
        expect(r180.shouldTriggerCountdown, isFalse);
        expect(r180.shouldFallbackImmediately, isTrue);
      });

      test('3.11 Map-based header lookup case insensitivity and missing keys', () {
        expect(parseRetryAfterHeader({'RETRY-AFTER': '12'}), equals(12));
        expect(parseRetryAfterHeader({'retry-after': '12'}), equals(12));
        expect(parseRetryAfterHeader({'Retry-After': '12'}), equals(12));
        expect(parseRetryAfterHeader({'rEtRy-AfTeR': '12'}), equals(12));
        expect(parseRetryAfterHeader({'x-rate-limit': '12'}, defaultSeconds: 5), equals(5));
        expect(parseRetryAfterHeader(<String, String>{}, defaultSeconds: 5), equals(5));
      });
    });

    // =========================================================================
    // Challenge 4: Auxiliary Network Edge Cases (Duration Tolerance, Ovh, Translation)
    // =========================================================================
    group('Challenge 4: Auxiliary Network Edge Cases', () {
      test('4.1 LrclibSuccess.isWithinDurationTolerance exact boundary precision', () {
        const s = LrclibSuccess(duration: 180.0);

        // Exact matches
        expect(s.isWithinDurationTolerance(180), isTrue);
        expect(s.isWithinDurationTolerance(182.0), isTrue);
        expect(s.isWithinDurationTolerance(178.0), isTrue);

        // Strict outside tolerance
        expect(s.isWithinDurationTolerance(182.0001), isFalse);
        expect(s.isWithinDurationTolerance(177.9999), isFalse);

        // When duration is null from server, always returns true
        const sNull = LrclibSuccess(duration: null);
        expect(sNull.isWithinDurationTolerance(180), isTrue);
      });

      test('4.2 LyricsOvhClient handles problematic characters and URL encoding', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{"lyrics": "Some lyrics"}', 200);
          }),
        );

        await client.getLyrics(
          artist: 'AC/DC',
          title: 'Thunderstruck / Live?',
        );

        // Path must have exactly 3 segments: ['v1', 'AC/DC', 'Thunderstruck / Live?']
        // Slashes within artist/title must NOT split into additional path segments
        expect(requestedUri.pathSegments.length, equals(3));
        expect(requestedUri.pathSegments[0], equals('v1'));
        expect(requestedUri.pathSegments[1], equals('AC/DC'));
        expect(requestedUri.pathSegments[2], equals('Thunderstruck / Live?'));

        // Over-the-wire URI string must contain component-encoded segments
        expect(requestedUri.toString(), contains('AC%2FDC'));
        expect(requestedUri.toString(), contains('Thunderstruck%20%2F%20Live%3F'));
      });

      test('4.3 LyricsTranslationClient handles massive single line > 400 characters', () {
        final longLine = 'A' * 500;
        final lines = ['Short line', longLine, 'Another line'];

        final batches = LyricsTranslationClient.chunkLines(lines, maxBatchChars: 400);

        expect(batches.length, equals(3));
        expect(batches[0], equals(['Short line']));
        expect(batches[1], equals([longLine]));
        expect(batches[2], equals(['Another line']));
      });

      test('4.4 LyricsTranslationClient HTML unescaping decodes mixed entities', () {
        const raw = '&quot;Rock &amp; Roll&#39;s finest&quot; &lt;band&gt; &#65;&#x42;';
        final unescaped = LyricsTranslationClient.unescapeHtml(raw);
        expect(unescaped, equals('"Rock & Roll\'s finest" <band> AB'));
      });

      test('4.5 LyricsTranslationClient preserves 1:1 line alignment with blank lines', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            // Simulated MyMemory response that strips blank lines
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea uno\nLínea dos',
                },
              }),
              200,
            );
          }),
        );

        // Input has 3 lines with a blank line in between
        final input = ['Line one', '', 'Line two'];
        final result = await client.translate(input, targetLanguage: 'es');

        expect(result.isSuccess, isTrue);
        expect(result.translatedLines.length, equals(3));
        expect(result.translatedLines[0], equals('Línea uno'));
        expect(result.translatedLines[1], equals(''));
        expect(result.translatedLines[2], equals('Línea dos'));
      });
    });
  });
}
