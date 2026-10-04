import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tachyon/core/network/lyrics_translation_client.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      requests.add(request);
      final response = await handler(request);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }
    throw UnimplementedError();
  }
}

void main() {
  group('LyricsTranslationClient', () {
    test('chunkLines chunks lines within char limits', () {
      final lines = [
        'Line 1: A short line',
        'Line 2: Another short line',
        'Line 3: Yet another line',
      ];
      final batches = LyricsTranslationClient.chunkLines(lines, maxBatchChars: 30);
      expect(batches.length, 3);
      expect(batches[0], [lines[0]]);
      expect(batches[1], [lines[1]]);
      expect(batches[2], [lines[2]]);
    });

    test('same language source and target returns original lines with zero network requests', () async {
      var called = false;
      final mock = MockHttpClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      final client = LyricsTranslationClient(httpClient: mock);

      final res = await client.translate(
        ['Hola', 'Mundo'],
        targetLanguage: 'es',
        sourceLanguage: 'es',
      );

      expect(called, isFalse);
      expect(res.isSuccess, isTrue);
      expect(res.isSameLanguage, isTrue);
      expect(res.translatedLines, ['Hola', 'Mundo']);
    });

    test('detected same language terminates early and does not send subsequent batches', () async {
      int requestCount = 0;
      final mock = MockHttpClient((req) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'responseStatus': 403,
            'responseDetails': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
            'responseData': {'translatedText': ''},
          }),
          200,
        );
      });

      // 4 lines with maxBatchChars: 10 will produce multiple batches
      final client = LyricsTranslationClient(httpClient: mock);
      final lines = [
        'Línea uno larga',
        'Línea dos larga',
        'Línea tres larga',
        'Línea cuatro larga',
      ];

      final res = await client.translate(
        lines,
        targetLanguage: 'es',
        sourceLanguage: 'auto',
      );

      expect(requestCount, 1, reason: 'Should stop immediately on first batch indicating same language');
      expect(res.isSuccess, isTrue);
      expect(res.isSameLanguage, isTrue);
      expect(res.translatedLines, lines);
    });

    test('retries on HTTP 429 and succeeds on second attempt', () async {
      int requestCount = 0;
      final mock = MockHttpClient((req) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'responseStatus': 429,
              'responseDetails': 'Too Many Requests',
            }),
            429,
          );
        }
        return http.Response(
          jsonEncode({
            'responseStatus': 200,
            'responseData': {'translatedText': 'Hola'},
          }),
          200,
        );
      });

      final client = LyricsTranslationClient(httpClient: mock);
      final res = await client.translate(
        ['Hello'],
        targetLanguage: 'es',
        sourceLanguage: 'en',
      );

      expect(requestCount, 2);
      expect(res.isSuccess, isTrue);
      expect(res.translatedLines, ['Hola']);
    });

    test('fails with rate limit error after retrying on HTTP 429', () async {
      int requestCount = 0;
      final mock = MockHttpClient((req) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'responseStatus': 429,
            'responseDetails': 'Too Many Requests',
          }),
          429,
        );
      });

      final client = LyricsTranslationClient(httpClient: mock);
      final res = await client.translate(
        ['Hello'],
        targetLanguage: 'es',
        sourceLanguage: 'en',
      );

      expect(requestCount, 2);
      expect(res.isSuccess, isFalse);
      expect(res.isRateLimited, isTrue);
      expect(res.statusCode, 429);
    });

    test('unescapeHtml decodes HTML entities properly', () {
      expect(LyricsTranslationClient.unescapeHtml('&quot;Hello &amp; World&#39;'), '"Hello & World\'');
      expect(LyricsTranslationClient.unescapeHtml('&#60;tag&#62;'), '<tag>');
      expect(LyricsTranslationClient.unescapeHtml('&#x26;'), '&');
    });

    test('times out and returns failure with status 504 when request takes longer than timeout', () async {
      final mock = MockHttpClient((req) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });

      final client = LyricsTranslationClient(
        httpClient: mock,
        timeout: const Duration(milliseconds: 50),
      );

      final res = await client.translate(
        ['Hello'],
        targetLanguage: 'es',
        sourceLanguage: 'en',
      );

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 504);
      expect(res.errorMessage, contains('timed out'));
    });
  });
}
