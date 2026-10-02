import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';

void main() {
  group('Empirical Challenger M2.2 — Adversarial Test Suite', () {
    // =========================================================================
    // 1. LyricsOvhClient URL Component Encoding & Adversarial Inputs
    // =========================================================================
    group('1. LyricsOvhClient URL Component Encoding & Adversarial Inputs', () {
      test('ADV-OVH-1: Slashes in artist and title (AC/DC, Run-D.M.C., Highway/Hell)', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Rock & Roll'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: 'AC/DC',
          title: 'Highway / Hell',
        );

        expect(response.isSuccess, isTrue);
        expect(requestedUri.path, equals('/v1/AC%2FDC/Highway%20%2F%20Hell'));
        // Verify path segments contain exactly 3 segments: 'v1', 'AC/DC', 'Highway / Hell'
        expect(requestedUri.pathSegments, equals(['v1', 'AC/DC', 'Highway / Hell']));
        // Raw URL must not have bare forward slashes inside components
        expect(requestedUri.toString(), isNot(contains('/AC/DC/')));
        expect(requestedUri.toString(), isNot(contains('/Highway/Hell')));
      });

      test('ADV-OVH-2: Query parameters injected into artist and title', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Param Test'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: 'Artist?query=attack&drop=tables',
          title: 'Title?key=val#frag',
        );

        expect(response.isSuccess, isTrue);
        // ? and & must be encoded so they do NOT become actual URL query parameters
        expect(requestedUri.queryParameters, isEmpty);
        expect(requestedUri.query, isEmpty);
        expect(requestedUri.fragment, isEmpty);
        expect(requestedUri.path, contains('Artist%3Fquery%3Dattack%26drop%3Dtables'));
        expect(requestedUri.path, contains('Title%3Fkey%3Dval%23frag'));
      });

      test('ADV-OVH-3: URL fragments (#) injected into artist and title', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Hash'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: 'Blink-182#1',
          title: '#Selfie',
        );

        expect(response.isSuccess, isTrue);
        expect(requestedUri.fragment, isEmpty);
        expect(requestedUri.path, contains('/Blink-182%231/%23Selfie'));
      });

      test('ADV-OVH-4: Percent signs (%) and pre-encoded sequences (100%, %20, %2F)', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Percent'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: '100% Cotton',
          title: '%20Double%20Encoded%2F',
        );

        expect(response.isSuccess, isTrue);
        // % must be encoded to %25
        expect(requestedUri.path, contains('100%25%20Cotton'));
        expect(requestedUri.path, contains('%2520Double%2520Encoded%252F'));
        expect(requestedUri.pathSegments[1], equals('100% Cotton'));
        expect(requestedUri.pathSegments[2], equals('%20Double%20Encoded%2F'));
      });

      test('ADV-OVH-5: Multilingual non-Latin Unicode scripts and Emoji', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode({'lyrics': 'Unicode Lyrics'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );

        final response = await client.getLyrics(
          artist: 'Кино (Kino) 宇多田ヒカル عمرو دياب 🔥',
          title: 'Группа крови / First Love 🚀',
        );

        expect(response.isSuccess, isTrue);
        // Encoded path segments should decode back to original unicode strings
        expect(requestedUri.pathSegments[1], equals('Кино (Kino) 宇多田ヒカル عمرو دياب 🔥'));
        expect(requestedUri.pathSegments[2], equals('Группа крови / First Love 🚀'));
      });

      test('ADV-OVH-6: Path traversal attempts (../../etc/passwd)', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Safe'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: '../../etc/passwd',
          title: '../../../root',
        );

        expect(response.isSuccess, isTrue);
        // Slashes are encoded, preventing directory traversal in HTTP URL
        expect(requestedUri.path, contains('..%2F..%2Fetc%2Fpasswd'));
        expect(requestedUri.path, contains('..%2F..%2F..%2Froot'));
        expect(requestedUri.pathSegments.length, equals(3));
      });

      test('ADV-OVH-7: Dangerous punctuation and control characters', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Punctuation'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: 'A;B:C&D=E+F*G~H(I)J\'K',
          title: r'`cat /dev/urandom` | $(id) \ {test} [remix] "quotes"',
        );

        expect(response.isSuccess, isTrue);
        expect(requestedUri.pathSegments.length, equals(3));
        expect(requestedUri.pathSegments[1], equals('A;B:C&D=E+F*G~H(I)J\'K'));
        expect(
          requestedUri.pathSegments[2],
          equals(r'`cat /dev/urandom` | $(id) \ {test} [remix] "quotes"'),
        );
      });

      test('ADV-OVH-8: Whitespace anomalies (consecutive spaces, tabs, internal newlines)', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Spacing'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: '  The    Beatles\tBand\nSection  ',
          title: '\t\tLet   It   Be\n\n\t',
        );

        expect(response.isSuccess, isTrue);
        expect(requestedUri.pathSegments.length, equals(3));
        expect(requestedUri.pathSegments[1], equals('The    Beatles\tBand\nSection'));
        expect(requestedUri.pathSegments[2], equals('Let   It   Be'));
      });

      test('ADV-OVH-9: Malformed JSON responses (not a map, raw scalar, HTML error page)', () async {
        // Primitive string JSON
        var client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('"plain string json"', 200)),
        );
        var res = await client.getLyrics(artist: 'A', title: 'T');
        expect(res.isNotFound, isTrue);

        // JSON array
        client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('[{"lyrics": "abc"}]', 200)),
        );
        res = await client.getLyrics(artist: 'A', title: 'T');
        expect(res.isNotFound, isTrue);

        // Completely invalid JSON
        client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('<html>502 Bad Gateway</html>', 200)),
        );
        res = await client.getLyrics(artist: 'A', title: 'T');
        expect(res.isTemporaryError, isTrue);
      });

      test('ADV-OVH-10: BaseUrl with trailing slash does not generate double slashes', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          baseUrl: 'https://api.lyrics.ovh/v1/',
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Rock'}), 200);
          }),
        );

        final response = await client.getLyrics(artist: 'Queen', title: 'Bohemian Rhapsody');
        expect(response.isSuccess, isTrue);
        expect(requestedUri.path, isNot(contains('/v1//Queen')));
        expect(requestedUri.pathSegments, equals(['v1', 'Queen', 'Bohemian Rhapsody']));
      });
    });

    // =========================================================================
    // 2. LyricsTranslationClient Edge Cases & Adversarial Robustness
    // =========================================================================
    group('2. LyricsTranslationClient Edge Cases & Adversarial Robustness', () {
      test('ADV-TR-1: Lines exceeding 400 characters (401, 600, 1000 chars) are isolated and translated', () async {
        final line500 = 'A' * 500;
        final line600 = 'B' * 600;
        final shortLine = 'Short line';

        final batches = LyricsTranslationClient.chunkLines([line500, shortLine, line600]);
        // line500 should be in its own batch, shortLine in batch 2, line600 in batch 3
        expect(batches.length, equals(3));
        expect(batches[0], equals([line500]));
        expect(batches[1], equals([shortLine]));
        expect(batches[2], equals([line600]));

        int requestsCount = 0;
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            requestsCount++;
            final q = request.url.queryParameters['q'] ?? '';
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': 'Trans: $q'},
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          [line500, shortLine, line600],
          targetLanguage: 'es',
        );

        expect(requestsCount, equals(3));
        expect(result.length, equals(3));
        expect(result[0], equals('Trans: $line500'));
        expect(result[1], equals('Trans: $shortLine'));
        expect(result[2], equals('Trans: $line600'));
      });

      test('ADV-TR-2: Text with only blank/whitespace lines skips HTTP entirely', () async {
        int httpCalls = 0;
        final client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final input = ['', '   ', '\t', '\r\n', '    \t  '];
        final result = await client.translateLines(input, targetLanguage: 'es');

        expect(httpCalls, equals(0));
        expect(result.length, equals(input.length));
      });

      test('ADV-TR-3: Leading, trailing, and interspersed blank lines preservation', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            final q = request.url.queryParameters['q'] ?? '';
            final nonBlank = q.split('\n').where((l) => l.trim().isNotEmpty).toList();
            // Simulate an API that drops empty lines in its translation
            final translated = nonBlank.map((l) => 'TR_$l').join('\n');
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': translated},
              }),
              200,
            );
          }),
        );

        final input = [
          '',
          'Verse 1 Line 1',
          '',
          'Verse 1 Line 2',
          '',
          '',
          'Chorus Line 1',
          '',
        ];

        final result = await client.translateLines(input, targetLanguage: 'es');

        expect(result.length, equals(input.length));
        expect(result[0], equals(''));
        expect(result[1], equals('TR_Verse 1 Line 1'));
        expect(result[2], equals(''));
        expect(result[3], equals('TR_Verse 1 Line 2'));
        expect(result[4], equals(''));
        expect(result[5], equals(''));
        expect(result[6], equals('TR_Chorus Line 1'));
        expect(result[7], equals(''));
      });

      test('ADV-TR-4: HTML entity bomb attack (&quot;&amp;&lt;&gt;&#39;&#x2F; and hex/dec entities)', () {
        const attackString = '&quot;&amp;&lt;&gt;&#39;&#x2F;';
        final unescaped = LyricsTranslationClient.unescapeHtml(attackString);
        expect(unescaped, equals('"&<>\'/'));

        // Additional standard HTML entities
        expect(LyricsTranslationClient.unescapeHtml('&apos;&nbsp;'), equals('\' '));
        // Numeric decimal entity for exclamation and slash
        expect(LyricsTranslationClient.unescapeHtml('&#33;&#47;'), equals('!/'));
        // Numeric hex entity (lowercase and uppercase hex digits)
        expect(LyricsTranslationClient.unescapeHtml('&#x21;&#x2F;&#x3a;'), equals('!/:'));
      });

      test('ADV-TR-9: Entity order and double-unescaping vulnerability (&amp;lt; -> &lt;, not <)', () {
        // When text contains an escaped entity like &amp;lt;, it should decode to &lt;
        // Replacing &amp; before &lt; causes double-decoding to <
        const input = '&amp;lt;tag&amp;gt;';
        final result = LyricsTranslationClient.unescapeHtml(input);
        expect(result, equals('&lt;tag&gt;'));
      });

      test('ADV-TR-10: Uppercase hex entities (&#X2F;) per W3C HTML5 / XML spec', () {
        expect(LyricsTranslationClient.unescapeHtml('&#X2F;'), equals('/'));
      });

      test('ADV-TR-5: Out-of-range numeric entities and invalid formats do not crash unescapeHtml', () {
        // Out of unicode range or very large numbers
        expect(() => LyricsTranslationClient.unescapeHtml('&#99999999999999999999;'), returnsNormally);
        expect(() => LyricsTranslationClient.unescapeHtml('&#x99999999999999999999;'), returnsNormally);
        expect(() => LyricsTranslationClient.unescapeHtml('&#1114112;'), returnsNormally);
        expect(() => LyricsTranslationClient.unescapeHtml('&#x110000;'), returnsNormally);
        expect(() => LyricsTranslationClient.unescapeHtml('&notanentity;'), returnsNormally);
      });

      test('ADV-TR-6: Line count mismatch recovery when API returns fewer lines than batch', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            // Returns only 1 line when 3 were requested
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': 'Línea Única'},
              }),
              200,
            );
          }),
        );

        final input = ['Line 1', 'Line 2', 'Line 3'];
        final result = await client.translateLines(input, targetLanguage: 'es');

        expect(result.length, equals(3));
        expect(result[0], equals('Línea Única'));
        // Missing lines fallback to original input
        expect(result[1], equals('Line 2'));
        expect(result[2], equals('Line 3'));
      });

      test('ADV-TR-7: Line count mismatch recovery when API returns more lines than batch', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            // Returns 4 lines when 2 were requested
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\nExtra A\nLínea 2\nExtra B',
                },
              }),
              200,
            );
          }),
        );

        final input = ['Line 1', 'Line 2'];
        final result = await client.translateLines(input, targetLanguage: 'es');

        expect(result.length, equals(2));
        expect(result[0], equals('Línea 1'));
        expect(result[1], equals('Extra A'));
      });

      test('ADV-TR-8: Safe translate() wrapper resilience against 429, 500, timeouts, and network errors', () async {
        // 429 Rate limited
        var client = LyricsTranslationClient(
          httpClient: MockClient((_) async => http.Response('Rate limited', 429)),
        );
        var res = await client.translate(['Line 1'], targetLanguage: 'es');
        expect(res.isSuccess, isFalse);
        expect(res.translatedLines, isEmpty);
        expect(res.originalLines, equals(['Line 1']));

        // 500 Server error
        client = LyricsTranslationClient(
          httpClient: MockClient((_) async => http.Response('Internal error', 500)),
        );
        res = await client.translate(['Line 1'], targetLanguage: 'es');
        expect(res.isSuccess, isFalse);

        // Timeout
        client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            await Future.delayed(const Duration(milliseconds: 100));
            return http.Response('{}', 200);
          }),
          timeout: const Duration(milliseconds: 10),
        );
        res = await client.translate(['Line 1'], targetLanguage: 'es');
        expect(res.isSuccess, isFalse);
        expect(res.errorMessage, contains('timed out'));
      });
    });

    // =========================================================================
    // 3. LyricsCooldownManager Deferred Retries & Transition Robustness
    // =========================================================================
    group('3. LyricsCooldownManager Deferred Retries & Transition Robustness', () {
      test('ADV-CD-1: scheduleDeferredRetry executes callback when time expires', () async {
        var simulatedNow = DateTime(2026, 9, 23, 12, 0, 0);
        final manager = LyricsCooldownManager(nowProvider: () => simulatedNow);

        manager.setCooldown(const Duration(seconds: 30));
        expect(manager.isCooldownActive, isTrue);

        var retryCalled = false;
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            retryCalled = true;
          },
        );

        expect(manager.deferredTrackFilePath, equals('file:///track1.mp3'));
        expect(manager.deferredGenerationToken, equals(1));

        // Use manual expiration helper
        await manager.expireCooldownAndTriggerUpgrade();
        expect(retryCalled, isTrue);
        expect(manager.isCooldownActive, isFalse);
        expect(manager.deferredTrackFilePath, isNull);
      });

      test('ADV-CD-2: updateDeferredTrack during active cooldown redirects callback to newest track', () async {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 60));

        final executed = <String>[];

        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async => executed.add('track1'),
        );

        // User rapidly advances tracks 1 -> 2 -> 3 -> 4 -> 5
        manager.updateDeferredTrack(
          trackFilePath: 'file:///track2.mp3',
          token: 2,
          onRetry: () async => executed.add('track2'),
        );
        manager.updateDeferredTrack(
          trackFilePath: 'file:///track3.mp3',
          token: 3,
          onRetry: () async => executed.add('track3'),
        );
        manager.updateDeferredTrack(
          trackFilePath: 'file:///track4.mp3',
          token: 4,
          onRetry: () async => executed.add('track4'),
        );
        manager.updateDeferredTrack(
          trackFilePath: 'file:///track5.mp3',
          token: 5,
          onRetry: () async => executed.add('track5'),
        );

        expect(manager.deferredTrackFilePath, equals('file:///track5.mp3'));
        expect(manager.deferredGenerationToken, equals(5));

        await manager.expireCooldownAndTriggerUpgrade();

        // ONLY track5 callback should have executed
        expect(executed, equals(['track5']));
      });

      test('ADV-CD-3: cancelDeferredRetry prevents callback execution upon cooldown clear', () async {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 30));

        var retryCalled = false;
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            retryCalled = true;
          },
        );

        manager.cancelDeferredRetry();
        expect(manager.deferredTrackFilePath, isNull);
        expect(manager.deferredGenerationToken, isNull);

        await manager.expireCooldownAndTriggerUpgrade();
        expect(retryCalled, isFalse);
      });

      test('ADV-CD-4: clearCooldown cancels both cooldown state and deferred retry', () async {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 60));

        var retryCalled = false;
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            retryCalled = true;
          },
        );

        manager.clearCooldown();
        expect(manager.isCooldownActive, isFalse);
        expect(manager.cooldownExpiry, isNull);
        expect(manager.deferredTrackFilePath, isNull);

        await manager.expireCooldownAndTriggerUpgrade();
        expect(retryCalled, isFalse);
      });

      test('ADV-CD-5: scheduleDeferredRetry when cooldown has already expired triggers onRetry immediately', () async {
        var simulatedNow = DateTime(2026, 9, 23, 12, 0, 0);
        final manager = LyricsCooldownManager(nowProvider: () => simulatedNow);

        manager.setCooldown(const Duration(seconds: 10));
        // Advance time past cooldown
        simulatedNow = simulatedNow.add(const Duration(seconds: 20));

        var retryExecuted = false;
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            retryExecuted = true;
          },
        );

        expect(retryExecuted, isTrue);
      });

      test('ADV-CD-6: Multiple calls to expireCooldownAndTriggerUpgrade execute callback only once', () async {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 30));

        int executionCount = 0;
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            executionCount++;
          },
        );

        await manager.expireCooldownAndTriggerUpgrade();
        await manager.expireCooldownAndTriggerUpgrade();
        await manager.expireCooldownAndTriggerUpgrade();

        expect(executionCount, equals(1));
      });

      test('ADV-CD-7: dispose() cancels both threshold timer and deferred retry timer cleanly', () {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 60));
        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {},
        );
        manager.startThresholdCountdown(
          seconds: 5,
          onAutoRetry: () async {},
        );

        expect(manager.isThresholdWaiting, isTrue);
        expect(manager.deferredTrackFilePath, isNotNull);

        manager.dispose();

        expect(manager.isThresholdWaiting, isFalse);
        expect(manager.deferredTrackFilePath, isNull);
      });

      test('ADV-CD-8: Defensive exception handling in deferred retry callback', () async {
        final manager = LyricsCooldownManager();
        manager.setCooldown(const Duration(seconds: 30));

        manager.scheduleDeferredRetry(
          trackFilePath: 'file:///track1.mp3',
          token: 1,
          onRetry: () async {
            throw Exception('Network error during auto-upgrade');
          },
        );

        // When triggering manual upgrade, does it rethrow or should it be caught?
        expect(
          () => manager.expireCooldownAndTriggerUpgrade(),
          throwsA(isA<Exception>()),
        );
      });

      test('ADV-CD-9: isStillValid returning false aborts threshold countdown without auto-retry', () async {
        final manager = LyricsCooldownManager();
        var retryCalled = false;
        var valid = false;

        manager.startThresholdCountdown(
          seconds: 2,
          onAutoRetry: () async {
            retryCalled = true;
          },
          isStillValid: () => valid,
        );

        await Future.delayed(const Duration(milliseconds: 1100));
        expect(manager.isThresholdWaiting, isFalse);
        expect(retryCalled, isFalse);
      });
    });
  });
}
