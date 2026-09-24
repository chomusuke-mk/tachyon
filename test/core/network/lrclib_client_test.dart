import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/network/lrclib_client.dart';

void main() {
  group('LrclibClient Unit Tests', () {
    // =========================================================================
    // 1. Query Parameters & URI Encoding
    // =========================================================================
    group('1. Query Parameters & URI Encoding', () {
      test('1.1 constructs valid GET URI with track and artist', () async {
        late Uri requestedUri;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(
          trackName: 'Bohemian Rhapsody',
          artistName: 'Queen',
        );

        expect(requestedUri.scheme, equals('https'));
        expect(requestedUri.host, equals('lrclib.net'));
        expect(requestedUri.path, equals('/api/get'));
        expect(
          requestedUri.queryParameters['track_name'],
          equals('Bohemian Rhapsody'),
        );
        expect(requestedUri.queryParameters['artist_name'], equals('Queen'));
        expect(requestedUri.queryParameters.containsKey('album_name'), isFalse);
        expect(requestedUri.queryParameters.containsKey('duration'), isFalse);
      });

      test('1.2 includes album_name and duration when supplied', () async {
        late Uri requestedUri;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(
          trackName: 'Bohemian Rhapsody',
          artistName: 'Queen',
          albumName: 'A Night at the Opera',
          durationSeconds: 354,
        );

        expect(
          requestedUri.queryParameters['album_name'],
          equals('A Night at the Opera'),
        );
        expect(requestedUri.queryParameters['duration'], equals('354'));
      });

      test('1.3 properly encodes special characters and unicode without corruption', () async {
        late Uri requestedUri;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(
          trackName: 'AC/DC - Rock "N" Roll, Pt. 1 & 2',
          artistName: 'Artist & Co. / 宇多田ヒカル',
          albumName: "Album's Best",
          durationSeconds: 240,
        );

        expect(
          requestedUri.queryParameters['track_name'],
          equals('AC/DC - Rock "N" Roll, Pt. 1 & 2'),
        );
        expect(
          requestedUri.queryParameters['artist_name'],
          equals('Artist & Co. / 宇多田ヒカル'),
        );
        expect(
          requestedUri.queryParameters['album_name'],
          equals("Album's Best"),
        );
      });

      test('1.4 omits albumName when empty or whitespace only', () async {
        late Uri requestedUri;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(
          trackName: 'Song',
          artistName: 'Artist',
          albumName: '   ',
        );

        expect(requestedUri.queryParameters.containsKey('album_name'), isFalse);
      });

      test('1.5 omits duration when <= 0', () async {
        late Uri requestedUri;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(
          trackName: 'Song',
          artistName: 'Artist',
          durationSeconds: 0,
        );

        expect(requestedUri.queryParameters.containsKey('duration'), isFalse);
      });
    });

    // =========================================================================
    // 2. User-Agent Header
    // =========================================================================
    group('2. User-Agent Header', () {
      test('2.1 sends default User-Agent containing Tachyon identifier and repo URL', () async {
        late Map<String, String> requestHeaders;
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestHeaders = request.headers;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        await client.getLyrics(trackName: 'Song', artistName: 'Artist');

        expect(
          requestHeaders['User-Agent'],
          equals(LrclibClient.defaultUserAgent),
        );
        expect(requestHeaders['User-Agent'], contains('Tachyon/1.0.0'));
        expect(requestHeaders['Accept'], equals('application/json'));
      });

      test('2.2 sends custom User-Agent when configured in constructor', () async {
        late Map<String, String> requestHeaders;
        const customUa = 'CustomClient/2.0.0';
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            requestHeaders = request.headers;
            return http.Response('{}', 200);
          }),
          userAgent: customUa,
          minPacing: Duration.zero,
        );

        await client.getLyrics(trackName: 'Song', artistName: 'Artist');

        expect(requestHeaders['User-Agent'], equals(customUa));
      });
    });

    // =========================================================================
    // 3. 200 OK Response Parsing & Duration Tolerance
    // =========================================================================
    group('3. 200 OK Response Parsing & Duration Tolerance', () {
      test('3.1 parses complete synced lyrics response correctly', () async {
        final mockJson = jsonEncode({
          'id': 1001,
          'name': 'Bohemian Rhapsody',
          'trackName': 'Bohemian Rhapsody',
          'artistName': 'Queen',
          'albumName': 'A Night at the Opera',
          'duration': 354.5,
          'instrumental': false,
          'plainLyrics': 'Is this the real life?\nIs this just fantasy?',
          'syncedLyrics':
              '[00:01.00]Is this the real life?\n[00:04.50]Is this just fantasy?',
        });

        final client = LrclibClient(
          httpClient: MockClient((request) async {
            return http.Response(mockJson, 200);
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'Bohemian Rhapsody',
          artistName: 'Queen',
        );

        expect(response.isSuccess, isTrue);
        expect(response.isNotFound, isFalse);
        expect(response.isRateLimited, isFalse);
        expect(response.isError, isFalse);
        expect(response.id, equals(1001));
        expect(response.trackName, equals('Bohemian Rhapsody'));
        expect(response.artistName, equals('Queen'));
        expect(response.albumName, equals('A Night at the Opera'));
        expect(response.duration, equals(354.5));
        expect(response.instrumental, isFalse);
        expect(response.hasSyncedLyrics, isTrue);
        expect(response.hasPlainLyrics, isTrue);
        expect(response.syncedLyrics, contains('[00:01.00]'));
        expect(response.plainLyrics, contains('Is this the real life?'));
      });

      test('3.2 parses plain-only lyrics response', () async {
        final mockJson = jsonEncode({
          'id': 1002,
          'trackName': 'Yesterday',
          'artistName': 'The Beatles',
          'duration': 125.0,
          'instrumental': false,
          'plainLyrics': 'Yesterday, all my troubles seemed so far away',
          'syncedLyrics': null,
        });

        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'Yesterday',
          artistName: 'The Beatles',
        );

        expect(response.isSuccess, isTrue);
        expect(response.hasSyncedLyrics, isFalse);
        expect(response.hasPlainLyrics, isTrue);
        expect(
          response.plainLyrics,
          equals('Yesterday, all my troubles seemed so far away'),
        );
      });

      test('3.3 handles instrumental track with instrumental=true and no lyrics', () async {
        final mockJson = jsonEncode({
          'id': 1003,
          'trackName': 'Orion',
          'artistName': 'Metallica',
          'duration': 500.0,
          'instrumental': true,
          'plainLyrics': null,
          'syncedLyrics': null,
        });

        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'Orion',
          artistName: 'Metallica',
        );

        expect(response.isSuccess, isTrue);
        expect(response.instrumental, isTrue);
        expect(response.hasSyncedLyrics, isFalse);
        expect(response.hasPlainLyrics, isFalse);
        expect(response.hasAnyLyrics, isFalse);
      });

      test('3.4 duration tolerance verification: validates within +/-2s window', () async {
        const success = LrclibSuccess(
          id: 1,
          trackName: 'Song',
          artistName: 'Artist',
          duration: 200.0,
        );

        // Exact match
        expect(success.isWithinDurationTolerance(200), isTrue);
        // Edge: +2s
        expect(success.isWithinDurationTolerance(198), isTrue);
        // Edge: -2s
        expect(success.isWithinDurationTolerance(202), isTrue);
        // Outside tolerance (+2.5s)
        expect(success.isWithinDurationTolerance(197.4), isFalse);
        // Outside tolerance (-2.5s)
        expect(success.isWithinDurationTolerance(202.6), isFalse);
      });

      test('3.5 returns LrclibError when response body is not valid JSON', () async {
        final client = LrclibClient(
          httpClient: MockClient(
            (_) async => http.Response('<html>502 Bad Gateway</html>', 200),
          ),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isError, isTrue);
        expect(response.isSuccess, isFalse);
        expect(response.errorMessage, contains('Failed to decode JSON'));
      });
    });

    // =========================================================================
    // 4. 404 Not Found Handling
    // =========================================================================
    group('4. 404 Not Found Handling', () {
      test('4.1 returns LrclibNotFound when lrclib returns 404', () async {
        final mockJson = jsonEncode({
          'statusCode': 404,
          'error': 'Not Found',
          'message': 'Failed to find specified track',
        });

        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 404)),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'Non-existent Song',
          artistName: 'Unknown',
        );

        expect(response.isNotFound, isTrue);
        expect(response.isSuccess, isFalse);
        expect(response.isRateLimited, isFalse);
        expect(response.statusCode, equals(404));
        expect(response.errorMessage, equals('Failed to find specified track'));
      });
    });

    // =========================================================================
    // 5. 429 Too Many Requests & Retry-After Parsing
    // =========================================================================
    group('5. 429 Too Many Requests & Retry-After Parsing', () {
      test('5.1 Retry-After <= 10s sets countdown flag (e.g. 5s)', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Rate limit exceeded', 429, headers: {
              'Retry-After': '5',
            });
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isRateLimited, isTrue);
        expect(response.isTemporaryError, isTrue);
        expect(response.isNotFound, isFalse);
        expect(response.retryAfterSeconds, equals(5));
        expect((response as LrclibRateLimited).shouldTriggerCountdown, isTrue);
        expect(response.shouldFallbackImmediately, isFalse);
      });

      test('5.2 Retry-After boundary of exactly 10s triggers countdown', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Too Many Requests', 429, headers: {
              'retry-after': '10',
            });
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.retryAfterSeconds, equals(10));
        expect((response as LrclibRateLimited).shouldTriggerCountdown, isTrue);
        expect(response.shouldFallbackImmediately, isFalse);
      });

      test('5.3 Retry-After boundary of 11s triggers immediate fallback (>10s rule)', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Too Many Requests', 429, headers: {
              'retry-after': '11',
            });
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.retryAfterSeconds, equals(11));
        expect((response as LrclibRateLimited).shouldTriggerCountdown, isFalse);
        expect(response.shouldFallbackImmediately, isTrue);
      });

      test('5.4 Retry-After of 60s triggers immediate fallback', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Too Many Requests', 429, headers: {
              'retry-after': '60',
            });
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.retryAfterSeconds, equals(60));
        expect(
          (response as LrclibRateLimited).shouldFallbackImmediately,
          isTrue,
        );
      });

      test('5.5 missing Retry-After header defaults to safe default (5 seconds, <=10s)', () async {
        final client = LrclibClient(
          httpClient: MockClient(
            (_) async => http.Response('Too Many Requests', 429),
          ),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isRateLimited, isTrue);
        expect(response.retryAfterSeconds, equals(5));
        expect((response as LrclibRateLimited).shouldTriggerCountdown, isTrue);
      });

      test('5.6 unparseable Retry-After header defaults to 5 seconds', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Too Many Requests', 429, headers: {
              'retry-after': 'invalid-date-string',
            });
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.retryAfterSeconds, equals(5));
      });

      test('5.7 parses RFC 1123 HTTP-date header format', () {
        final target = DateTime.now().add(const Duration(seconds: 8));
        final httpDateString = HttpDate.format(target);

        final parsedSeconds = LrclibClient.parseRetryAfterHeader({
          'Retry-After': httpDateString,
        });

        expect(parsedSeconds, inInclusiveRange(6, 9));
      });

      test('5.8 header case insensitivity (UPPERCASE, lowercase, CamelCase)', () {
        expect(
          LrclibClient.parseRetryAfterHeader({'RETRY-AFTER': '7'}),
          equals(7),
        );
        expect(
          LrclibClient.parseRetryAfterHeader({'retry-after': '7'}),
          equals(7),
        );
        expect(
          LrclibClient.parseRetryAfterHeader({'Retry-After': '7'}),
          equals(7),
        );
      });
    });

    // =========================================================================
    // 6. 5xx Server Errors & Network Drops
    // =========================================================================
    group('6. 5xx Server Errors & Network Drops', () {
      test('6.1 HTTP 500 returns LrclibError with status 500 and isTemporaryError=true', () async {
        final client = LrclibClient(
          httpClient: MockClient(
            (_) async => http.Response('Internal Server Error', 500),
          ),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isError, isTrue);
        expect(response.isTemporaryError, isTrue);
        expect(response.isNotFound, isFalse);
        expect(response.statusCode, equals(500));
      });

      test('6.2 HTTP 503 Service Unavailable returns LrclibError', () async {
        final client = LrclibClient(
          httpClient: MockClient(
            (_) async => http.Response('Service Unavailable', 503),
          ),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isError, isTrue);
        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(503));
      });

      test('6.3 Network socket/client exception returns LrclibError with status 0', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            throw const SocketException('Connection refused');
          }),
          minPacing: Duration.zero,
        );

        final response = await client.getLyrics(
          trackName: 'T',
          artistName: 'A',
        );

        expect(response.isError, isTrue);
        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(0));
        expect(response.errorMessage, contains('Connection refused'));
      });
    });

    // =========================================================================
    // 7. Rate Limiting (500ms Pacing)
    // =========================================================================
    group('7. Rate Limiting (500ms Pacing)', () {
      test('7.1 first request proceeds immediately without pacing delay', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: const Duration(milliseconds: 500),
        );

        final sw = Stopwatch()..start();
        await client.getLyrics(trackName: 'T1', artistName: 'A');
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(350));
        expect(client.requestTimestamps.length, equals(1));
      });

      test('7.2 second sequential request is delayed to satisfy 500ms spacing', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: const Duration(milliseconds: 500),
        );

        await client.getLyrics(trackName: 'T1', artistName: 'A');
        final sw = Stopwatch()..start();
        await client.getLyrics(trackName: 'T2', artistName: 'A');
        sw.stop();

        expect(client.requestTimestamps.length, equals(2));
        final diff = client.requestTimestamps[1]
            .difference(client.requestTimestamps[0])
            .inMilliseconds;
        expect(diff, greaterThanOrEqualTo(450));
        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(450));
      });

      test('7.3 does not delay when more than 500ms has elapsed since prior request', () async {
        final client = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: const Duration(milliseconds: 500),
        );

        await client.getLyrics(trackName: 'T1', artistName: 'A');
        await Future.delayed(const Duration(milliseconds: 550));

        final sw = Stopwatch()..start();
        await client.getLyrics(trackName: 'T2', artistName: 'A');
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(350));
      });

      test('7.4 concurrent requests are queued and executed in strict FIFO order', () async {
        final recordedTracks = <String>[];
        final client = LrclibClient(
          httpClient: MockClient((request) async {
            recordedTracks.add(request.url.queryParameters['track_name']!);
            return http.Response('{}', 200);
          }),
          minPacing: const Duration(milliseconds: 100),
        );

        await Future.wait([
          client.getLyrics(trackName: 'First', artistName: 'A'),
          client.getLyrics(trackName: 'Second', artistName: 'A'),
          client.getLyrics(trackName: 'Third', artistName: 'A'),
        ]);

        expect(recordedTracks, equals(['First', 'Second', 'Third']));
      });
    });

    // =========================================================================
    // 8. Cancellation & Rapid Skip
    // =========================================================================
    group('8. Cancellation & Rapid Skip', () {
      test('8.1 cancels request before pacing wait if isCancelled returns true', () async {
        int networkCalls = 0;
        final client = LrclibClient(
          httpClient: MockClient((_) async {
            networkCalls++;
            return http.Response('{}', 200);
          }),
          minPacing: const Duration(milliseconds: 500),
        );

        final response = await client.getLyrics(
          trackName: 'Skipped',
          artistName: 'A',
          isCancelled: () => true,
        );

        expect(networkCalls, equals(0));
        expect(response.isError, isTrue);
        expect(response.statusCode, equals(499));
      });

      test('8.2 dispose() cleans up owned resources without throwing', () {
        final client = LrclibClient(minPacing: Duration.zero);
        expect(() => client.dispose(), returnsNormally);
      });
    });
  });
}
