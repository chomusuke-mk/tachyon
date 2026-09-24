import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';

void main() {
  group('LyricsOvhClient Unit Tests', () {
    // =========================================================================
    // 1. URL Encoding & Formatting
    // =========================================================================
    group('1. URL Encoding & Formatting', () {
      test('F5.U1: forward slashes are component-encoded', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Rock'}), 200);
          }),
        );

        final response = await client.getLyrics(
          artist: 'AC/DC',
          title: 'Back in Black',
        );

        expect(response.isSuccess, isTrue);
        expect(requestedUri.toString(), contains('/v1/AC%2FDC/Back%20in%20Black'));
        expect(requestedUri.toString(), isNot(contains('/v1/AC/DC/')));
      });

      test('F5.U2: question mark and hash encoded properly', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Question'}), 200);
          }),
        );

        await client.getLyrics(artist: 'Artist', title: 'Why? #1');

        expect(requestedUri.toString(), contains('/Why%3F%20%231'));
      });

      test('F5.U3: trims leading and trailing whitespace', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Radio'}), 200);
          }),
        );

        await client.getLyrics(
          artist: '  Queen  ',
          title: '  Radio Ga Ga  ',
        );

        expect(requestedUri.toString(), contains('/v1/Queen/Radio%20Ga%20Ga'));
      });

      test('F5.U4: encodes special symbols (&, +, =)', () async {
        late Uri requestedUri;
        final client = LyricsOvhClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(jsonEncode({'lyrics': 'Sound'}), 200);
          }),
        );

        await client.getLyrics(
          artist: 'Simon & Garfunkel',
          title: 'A+B=C',
        );

        expect(
          requestedUri.toString(),
          contains('/Simon%20%26%20Garfunkel/A%2BB%3DC'),
        );
      });
    });

    // =========================================================================
    // 2. Input Validation
    // =========================================================================
    group('2. Input Validation', () {
      test('F5.U5: empty artist returns notFound without making HTTP call', () async {
        int httpCalls = 0;
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final response = await client.getLyrics(artist: '', title: 'Song');

        expect(httpCalls, equals(0));
        expect(response.isNotFound, isTrue);
        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(404));
      });

      test('F5.U6: whitespace artist returns notFound without making HTTP call', () async {
        int httpCalls = 0;
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final response = await client.getLyrics(artist: '   ', title: 'Song');

        expect(httpCalls, equals(0));
        expect(response.isNotFound, isTrue);
      });

      test('F5.U7: empty title returns notFound without making HTTP call', () async {
        int httpCalls = 0;
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final response = await client.getLyrics(artist: 'Artist', title: '');

        expect(httpCalls, equals(0));
        expect(response.isNotFound, isTrue);
      });
    });

    // =========================================================================
    // 3. 200 OK Response Parsing
    // =========================================================================
    group('3. 200 OK Response Parsing', () {
      test('F5.U8: standard multiline lyrics parsed correctly', () async {
        final mockJson = jsonEncode({'lyrics': 'Line 1\nLine 2\nLine 3'});
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isSuccess, isTrue);
        expect(response.isNotFound, isFalse);
        expect(response.isTemporaryError, isFalse);
        expect(response.lyrics, equals('Line 1\nLine 2\nLine 3'));
        expect(response.statusCode, equals(200));
      });

      test('F5.U9: Windows CRLF normalized to standard newline', () async {
        final mockJson = jsonEncode({'lyrics': 'Line 1\r\nLine 2\r\nLine 3'});
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.lyrics, equals('Line 1\nLine 2\nLine 3'));
        expect(response.lyrics, isNot(contains('\r')));
      });

      test('F5.U10: UTF-8 characters decoded without corruption', () async {
        final mockJson = jsonEncode({'lyrics': 'Café con leche\nПривет мир\n日本語の歌詞'});
        final client = LyricsOvhClient(
          httpClient: MockClient(
            (_) async => http.Response(
              mockJson,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.lyrics, contains('Café con leche'));
        expect(response.lyrics, contains('Привет мир'));
        expect(response.lyrics, contains('日本語の歌詞'));
      });

      test('F5.U11: empty string lyrics treated as notFound', () async {
        final mockJson = jsonEncode({'lyrics': ''});
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isNotFound, isTrue);
        expect(response.isSuccess, isFalse);
      });

      test('F5.U12: whitespace-only lyrics treated as notFound', () async {
        final mockJson = jsonEncode({'lyrics': '   \n\t  '});
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 200)),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isNotFound, isTrue);
        expect(response.isSuccess, isFalse);
      });
    });

    // =========================================================================
    // 4. 404 Not Found Handling
    // =========================================================================
    group('4. 404 Not Found Handling', () {
      test('F5.U13: 404 with error JSON returns notFound with error message', () async {
        final mockJson = jsonEncode({'error': 'No lyrics found'});
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response(mockJson, 404)),
        );

        final response = await client.getLyrics(artist: 'Unknown', title: 'Unknown');

        expect(response.isNotFound, isTrue);
        expect(response.isSuccess, isFalse);
        expect(response.isTemporaryError, isFalse);
        expect(response.statusCode, equals(404));
        expect(response.error, equals('No lyrics found'));
      });

      test('F5.U14: 404 with empty body returns notFound', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isNotFound, isTrue);
        expect(response.statusCode, equals(404));
      });
    });

    // =========================================================================
    // 5. 5xx Server Errors & Rate Limits
    // =========================================================================
    group('5. 5xx Server Errors & Rate Limits', () {
      test('F5.U15: HTTP 500 returns temporaryError (not notFound)', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient(
            (_) async => http.Response('Internal Server Error', 500),
          ),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isTemporaryError, isTrue);
        expect(response.isNotFound, isFalse);
        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(500));
      });

      test('F5.U16: HTTP 504 Gateway Timeout returns temporaryError with status 504', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient(
            (_) async => http.Response('Gateway Timeout', 504),
          ),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(504));
      });

      test('F5.U17: HTTP 429 returns temporaryError with status 429', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient(
            (_) async => http.Response('Too Many Requests', 429),
          ),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(429));
      });
    });

    // =========================================================================
    // 6. Network Exceptions & Timeouts
    // =========================================================================
    group('6. Network Exceptions & Timeouts', () {
      test('F5.U18: SocketException returns temporaryError with status 0 without crashing', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async {
            throw const SocketException('Connection refused');
          }),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(0));
        expect(response.error, contains('Connection refused'));
      });

      test('F5.U19: client TimeoutException returns temporaryError with status 504', () async {
        final client = LyricsOvhClient(
          httpClient: MockClient((_) async {
            await Future.delayed(const Duration(milliseconds: 100));
            return http.Response('{}', 200);
          }),
          timeout: const Duration(milliseconds: 10),
        );

        final response = await client.getLyrics(artist: 'A', title: 'S');

        expect(response.isTemporaryError, isTrue);
        expect(response.statusCode, equals(504));
        expect(response.error, contains('timed out'));
      });
    });

    // =========================================================================
    // 7. Helper Methods & Lifecycle
    // =========================================================================
    group('7. Helper Methods & Lifecycle', () {
      test('F5.U20: getPlainLyrics returns String on success and null on error/404', () async {
        final clientSuccess = LyricsOvhClient(
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'lyrics': 'Hello world'}), 200),
          ),
        );
        final lyrics = await clientSuccess.getPlainLyrics(
          artist: 'A',
          title: 'S',
        );
        expect(lyrics, equals('Hello world'));

        final clientNotFound = LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        );
        final notFoundLyrics = await clientNotFound.getPlainLyrics(
          artist: 'A',
          title: 'S',
        );
        expect(notFoundLyrics, isNull);
      });

      test('F5.U21: dispose() and close() succeed without error', () {
        final client = LyricsOvhClient();
        expect(() => client.close(), returnsNormally);
        expect(() => client.dispose(), returnsNormally);
      });
    });
  });
}
