import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';

void main() {
  group('LyricsTranslationClient Unit Tests', () {
    // =========================================================================
    // 1. Trivial Inputs
    // =========================================================================
    group('1. Trivial Inputs', () {
      test('F9.U1: empty lines list returns [] immediately with zero HTTP calls', () async {
        int httpCalls = 0;
        final client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final result = await client.translateLines(
          [],
          targetLanguage: 'es',
        );

        expect(httpCalls, equals(0));
        expect(result, isEmpty);
      });

      test('F9.U2: whitespace-only lines list returns immediately without HTTP calls', () async {
        int httpCalls = 0;
        final client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );

        final input = ['', '   ', '\t'];
        final result = await client.translateLines(
          input,
          targetLanguage: 'es',
        );

        expect(httpCalls, equals(0));
        expect(result, equals(input));
      });
    });

    // =========================================================================
    // 2. Chunking Logic
    // =========================================================================
    group('2. Chunking Logic', () {
      test('F9.U3: short lines chunked into single batch and single HTTP call', () async {
        int httpCalls = 0;
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            httpCalls++;
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\nLínea 2\nLínea 3\nLínea 4',
                },
              }),
              200,
            );
          }),
        );

        final input = ['Line 1', 'Line 2', 'Line 3', 'Line 4'];
        final result = await client.translateLines(
          input,
          targetLanguage: 'es',
        );

        expect(httpCalls, equals(1));
        expect(result.length, equals(4));
        expect(result[0], equals('Línea 1'));
      });

      test('F9.U4: long lines chunked into multiple batches of <= 400 characters', () async {
        int httpCalls = 0;
        final recordedRequests = <Uri>[];
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            httpCalls++;
            recordedRequests.add(request.url);
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': 'Translated line'},
              }),
              200,
            );
          }),
        );

        // Three 250-character lines (cannot fit two in 400 characters)
        final lineA = 'A' * 250;
        final lineB = 'B' * 250;
        final lineC = 'C' * 250;

        final result = await client.translateLines(
          [lineA, lineB, lineC],
          targetLanguage: 'es',
        );

        expect(httpCalls, equals(3));
        expect(recordedRequests.length, equals(3));
        expect(result.length, equals(3));
      });

      test('F9.U5: single line exceeding 400 characters placed in its own batch without crashing', () async {
        final line500 = 'X' * 500;
        final batches = LyricsTranslationClient.chunkLines([line500]);

        expect(batches.length, equals(1));
        expect(batches[0].length, equals(1));
        expect(batches[0][0], equals(line500));
      });
    });

    // =========================================================================
    // 3. 1:1 Line Alignment & Whitespace Preservation
    // =========================================================================
    group('3. 1:1 Line Alignment & Whitespace Preservation', () {
      test('F9.U6: preserves blank lines at exact indices', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\n\nLínea 2',
                },
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1', '', 'Line 2'],
          targetLanguage: 'es',
        );

        expect(result.length, equals(3));
        expect(result[0], equals('Línea 1'));
        expect(result[1], equals(''));
        expect(result[2], equals('Línea 2'));
      });

      test('F9.U7: preserves whitespace-only lines', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\n   \nLínea 2',
                },
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1', '   ', 'Line 2'],
          targetLanguage: 'es',
        );

        expect(result.length, equals(3));
        expect(result[0], equals('Línea 1'));
        expect(result[1], equals('   '));
        expect(result[2], equals('Línea 2'));
      });

      test('F9.U8: normalizes Windows CRLF in response to guarantee line count alignment', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\r\nLínea 2\r\nLínea 3',
                },
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1', 'Line 2', 'Line 3'],
          targetLanguage: 'es',
        );

        expect(result.length, equals(3));
        expect(result[0], equals('Línea 1'));
        expect(result[1], equals('Línea 2'));
        expect(result[2], equals('Línea 3'));
      });

      test('F9.U9: defensive recovery when remote service drops empty lines', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            // API dropped empty line 2 and returned only 2 lines
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': 'Línea 1\nLínea 3',
                },
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1', '', 'Line 3'],
          targetLanguage: 'es',
        );

        expect(result.length, equals(3));
        expect(result[0], equals('Línea 1'));
        expect(result[1], equals(''));
        expect(result[2], equals('Línea 3'));
      });
    });

    // =========================================================================
    // 4. Request Parameters & Headers
    // =========================================================================
    group('4. Request Parameters & Headers', () {
      test('F9.U10: sends autodetect langpair and User-Agent header', () async {
        late Uri requestedUri;
        late Map<String, String> requestedHeaders;

        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            requestedHeaders = request.headers;
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': 'Hola'},
              }),
              200,
            );
          }),
        );

        await client.translateLines(['Hello'], targetLanguage: 'es');

        expect(requestedUri.queryParameters['langpair'], equals('autodetect|es'));
        expect(requestedUri.queryParameters['q'], equals('Hello'));
        expect(requestedHeaders['User-Agent'], contains('Tachyon/1.0.0'));
        expect(requestedHeaders['Accept'], equals('application/json'));
      });

      test('F9.U11: supports custom target languages (fr, de, ja)', () async {
        late Uri requestedUri;
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {'translatedText': 'Bonjour'},
              }),
              200,
            );
          }),
        );

        await client.translateLines(['Hello'], targetLanguage: 'fr');
        expect(requestedUri.queryParameters['langpair'], equals('autodetect|fr'));
      });
    });

    // =========================================================================
    // 5. Unicode Scripts & HTML Entity Unescaping
    // =========================================================================
    group('5. Unicode Scripts & HTML Entity Unescaping', () {
      test('F9.U12: preserves CJK, Arabic, Cyrillic glyphs without corruption', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText': '你好世界\nمرحبا بالعالم\nПривет мир',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1', 'Line 2', 'Line 3'],
          targetLanguage: 'es',
        );

        expect(result[0], equals('你好世界'));
        expect(result[1], equals('مرحبا بالعالم'));
        expect(result[2], equals('Привет мир'));
      });

      test('F9.U13: unescapes HTML entities (&quot;, &#39;, &amp;, &lt;, &gt;, &nbsp;)', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 200,
                'responseData': {
                  'translatedText':
                      'Don&#39;t &quot;stop&quot; &amp; &lt;go&gt;&nbsp;now',
                },
              }),
              200,
            );
          }),
        );

        final result = await client.translateLines(
          ['Line 1'],
          targetLanguage: 'es',
        );

        expect(result[0], equals('Don\'t "stop" & <go> now'));
      });

      test('F9.U14: unescapes numeric decimal and hex HTML entities', () {
        expect(LyricsTranslationClient.unescapeHtml('Hello&#33;'), equals('Hello!'));
        expect(LyricsTranslationClient.unescapeHtml('Hello&#x21;'), equals('Hello!'));
      });
    });

    // =========================================================================
    // 6. Error Handling & Safe Wrapper
    // =========================================================================
    group('6. Error Handling & Safe Wrapper', () {
      test('F9.U15: throws LyricsTranslationException on 403 length limit exceeded', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseStatus': 403,
                'responseDetails': 'QUERY LENGTH LIMIT EXCEEDED',
              }),
              403,
            );
          }),
        );

        expect(
          () => client.translateLines(['Hello'], targetLanguage: 'es'),
          throwsA(isA<LyricsTranslationException>()),
        );
      });

      test('F9.U16: throws LyricsTranslationException on network drop / SocketException', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            throw const SocketException('Connection reset by peer');
          }),
        );

        expect(
          () => client.translateLines(['Hello'], targetLanguage: 'es'),
          throwsA(isA<LyricsTranslationException>()),
        );
      });

      test('F9.U17: translate() safe wrapper returns TranslationResult.failure on error', () async {
        final client = LyricsTranslationClient(
          httpClient: MockClient((_) async {
            throw const SocketException('Network offline');
          }),
        );

        final result = await client.translate(
          ['Original line 1', 'Original line 2'],
          targetLanguage: 'es',
        );

        expect(result.isSuccess, isFalse);
        expect(result.originalLines, equals(['Original line 1', 'Original line 2']));
        expect(result.translatedLines, isEmpty);
        expect(result.errorMessage, contains('Network offline'));
      });

      test('F9.U18: translate() safe wrapper returns empty failure on empty lines input', () async {
        final client = LyricsTranslationClient();
        final result = await client.translate([], targetLanguage: 'es');

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('No lines provided'));
      });

      test('F9.U19: dispose() and close() succeed without error', () {
        final client = LyricsTranslationClient();
        expect(() => client.close(), returnsNormally);
        expect(() => client.dispose(), returnsNormally);
      });
    });
  });
}
