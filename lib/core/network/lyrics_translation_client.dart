import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';

/// Exception thrown when a lyrics translation operation fails.
class LyricsTranslationException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const LyricsTranslationException(this.message, {this.statusCode, this.cause});

  bool get isRateLimited => statusCode == 429;

  @override
  String toString() =>
      'LyricsTranslationException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}

/// Structured result of a lyrics translation operation.
@immutable
class TranslationResult {
  final List<String> originalLines;
  final List<String> translatedLines;
  final String targetLanguage;
  final String? sourceLanguage;
  final bool isSuccess;
  final bool isSameLanguage;
  final int? statusCode;
  final String? errorMessage;

  const TranslationResult({
    required this.originalLines,
    required this.translatedLines,
    required this.targetLanguage,
    this.sourceLanguage,
    this.isSuccess = true,
    this.isSameLanguage = false,
    this.statusCode,
    this.errorMessage,
  });

  const TranslationResult.failure({
    required this.originalLines,
    required this.targetLanguage,
    this.sourceLanguage,
    required this.errorMessage,
    this.statusCode,
  }) : translatedLines = const [],
       isSuccess = false,
       isSameLanguage = false;

  bool get isRateLimited => statusCode == 429;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationResult &&
          runtimeType == other.runtimeType &&
          listEquals(originalLines, other.originalLines) &&
          listEquals(translatedLines, other.translatedLines) &&
          targetLanguage == other.targetLanguage &&
          sourceLanguage == other.sourceLanguage &&
          isSuccess == other.isSuccess &&
          isSameLanguage == other.isSameLanguage &&
          statusCode == other.statusCode &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(originalLines),
    Object.hashAll(translatedLines),
    targetLanguage,
    sourceLanguage,
    isSuccess,
    isSameLanguage,
    statusCode,
    errorMessage,
  );

  @override
  String toString() =>
      'TranslationResult(isSuccess: $isSuccess, isSameLanguage: $isSameLanguage, status: $statusCode, lines: ${translatedLines.length}/${originalLines.length}, error: $errorMessage)';
}

/// Free public lyrics translation client requiring zero credentials.
///
/// Uses the public MyMemory API (https://api.mymemory.translated.net/get) with:
/// - Batches chunked to <= 400 characters joined by '\n' (safely below 500-char limit).
/// - 1:1 line alignment preserving blank lines, whitespace, and timestamp synchronization.
/// - HTML entity unescaping for decoded characters.
/// - Windows CRLF normalization.
/// - Safe error handling preserving original lyrics on failure.
class LyricsTranslationClient {
  static const String defaultBaseUrl =
      'https://api.mymemory.translated.net/get';
  static const String defaultUserAgent =
      'Tachyon/1.0.0 (https://github.com/tachyon-player/tachyon)';

  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration timeout;
  final String myMemoryBaseUrl;

  LyricsTranslationClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
    this.myMemoryBaseUrl = defaultBaseUrl,
  }) : _httpClient =
           httpClient ?? _defaultClient(timeout: const Duration(seconds: 5)),
       _ownsClient = httpClient == null;

  static http.Client _defaultClient({required Duration timeout}) {
    try {
      final io = HttpClient()..connectionTimeout = timeout;
      return IOClient(io);
    } catch (_) {
      return http.Client();
    }
  }

  /// Chunks [lines] into batches where total character count joined by '\n'
  /// does not exceed [maxBatchChars].
  ///
  /// Lines that individually exceed [maxBatchChars] are isolated into single-line batches.
  static List<List<String>> chunkLines(
    List<String> lines, {
    int maxBatchChars = 400,
  }) {
    if (lines.isEmpty) return const [];

    final batches = <List<String>>[];
    var currentBatch = <String>[];
    var currentLength = 0;

    for (final line in lines) {
      final lineLen = line.length;
      final projectedLen =
          currentLength + (currentBatch.isEmpty ? 0 : 1) + lineLen;

      if (projectedLen > maxBatchChars && currentBatch.isNotEmpty) {
        batches.add(currentBatch);
        currentBatch = [];
        currentLength = 0;
      }

      currentBatch.add(line);
      currentLength += (currentBatch.length == 1 ? 0 : 1) + lineLen;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    return batches;
  }

  /// Translates [lines] to [targetLanguage], returning a 1:1 aligned list of translated lines.
  ///
  /// Throws [LyricsTranslationException] on network or API failure.
  Future<List<String>> translateLines(
    List<String> lines, {
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final res = await translate(
      lines,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
    );
    if (!res.isSuccess) {
      throw LyricsTranslationException(
        res.errorMessage ?? 'Translation failed',
        statusCode: res.statusCode,
      );
    }
    return res.translatedLines;
  }

  /// Safe translation method that catches exceptions and returns [TranslationResult].
  Future<TranslationResult> translate(
    List<String> lines, {
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (lines.isEmpty) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        errorMessage: 'No lines provided for translation',
      );
    }

    final cleanLines = lines
        .map((l) => l.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .toList();

    if (cleanLines.every((l) => l.trim().isEmpty)) {
      return TranslationResult(
        originalLines: lines,
        translatedLines: List<String>.from(cleanLines),
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        isSuccess: true,
      );
    }

    final src =
        (sourceLanguage == null ||
            sourceLanguage == 'auto' ||
            sourceLanguage == 'autodetect')
        ? 'autodetect'
        : sourceLanguage;

    if (src != 'autodetect' && src == targetLanguage) {
      return TranslationResult(
        originalLines: lines,
        translatedLines: List<String>.from(cleanLines),
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        isSameLanguage: true,
        isSuccess: true,
      );
    }

    try {
      final batches = chunkLines(cleanLines, maxBatchChars: 400);
      final allTranslated = <String>[];

      for (var i = 0; i < batches.length; i++) {
        if (i > 0) {
          // Pacing delay between batches to avoid burst rate limiting
          await Future.delayed(const Duration(milliseconds: 300));
        }
        final batch = batches[i];
        final res = await _translateBatch(
          batch,
          targetLanguage,
          sourceLanguage: sourceLanguage,
        );
        if (res.isSameLanguage) {
          // Early exit: The service indicated that the source and target are the same language.
          // There is no need to make further requests for subsequent batches.
          return TranslationResult(
            originalLines: lines,
            translatedLines: List<String>.from(cleanLines),
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
            isSameLanguage: true,
            isSuccess: true,
          );
        }
        allTranslated.addAll(res.lines);
      }

      return TranslationResult(
        originalLines: lines,
        translatedLines: allTranslated,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        isSameLanguage: false,
        isSuccess: true,
      );
    } on LyricsTranslationException catch (e) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        statusCode: e.statusCode,
        errorMessage: e.message,
      );
    } catch (e) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        errorMessage: 'Unexpected translation error: $e',
      );
    }
  }

  Future<({List<String> lines, bool isSameLanguage})> _translateBatch(
    List<String> batch,
    String targetLanguage, {
    String? sourceLanguage,
  }) async {
    // If batch contains only empty or whitespace lines, preserve them directly
    if (batch.every((line) => line.trim().isEmpty)) {
      return (lines: List<String>.from(batch), isSameLanguage: false);
    }

    final src =
        (sourceLanguage == null ||
            sourceLanguage == 'auto' ||
            sourceLanguage == 'autodetect')
        ? 'autodetect'
        : sourceLanguage;

    if (src != 'autodetect' && src == targetLanguage) {
      return (lines: List<String>.from(batch), isSameLanguage: true);
    }

    final batchText = batch.join('\n');
    final uri = Uri.parse(myMemoryBaseUrl).replace(
      queryParameters: {'q': batchText, 'langpair': '$src|$targetLanguage'},
    );

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        final response = await _httpClient
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'User-Agent': defaultUserAgent,
              },
            )
            .timeout(timeout);

        if (response.statusCode == 429) {
          if (attempt == 0) continue;
          throw const LyricsTranslationException(
            'Rate limit exceeded (Too many requests)',
            statusCode: 429,
          );
        }

        String bodyString;
        try {
          bodyString = utf8.decode(response.bodyBytes);
        } catch (_) {
          bodyString = response.body;
        }

        if (bodyString.toUpperCase().contains(
          'PLEASE SELECT TWO DISTINCT LANGUAGES',
        )) {
          return (lines: List<String>.from(batch), isSameLanguage: true);
        }

        if (response.statusCode != 200) {
          throw LyricsTranslationException(
            'Translation HTTP error: ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }

        final decoded = jsonDecode(bodyString);
        if (decoded is! Map<String, dynamic>) {
          throw const LyricsTranslationException(
            'Invalid JSON response format',
          );
        }

        final responseStatus =
            ParserUtils.parseInt(decoded['responseStatus']) ?? 200;
        if (responseStatus == 429) {
          if (attempt == 0) continue;
          throw const LyricsTranslationException(
            'Rate limit exceeded (Too many requests)',
            statusCode: 429,
          );
        }
        if (responseStatus != 200) {
          final details =
              decoded['responseDetails'] as String? ??
              'Translation service error $responseStatus';
          if (details.toUpperCase().contains(
            'PLEASE SELECT TWO DISTINCT LANGUAGES',
          )) {
            return (lines: List<String>.from(batch), isSameLanguage: true);
          }
          throw LyricsTranslationException(details, statusCode: responseStatus);
        }

        final responseData = decoded['responseData'] as Map<String, dynamic>?;
        final rawTranslatedText = ParserUtils.parseString(
          responseData?['translatedText'],
        );
        if (rawTranslatedText == null) {
          throw const LyricsTranslationException(
            'Missing translatedText in response',
          );
        }

        final unescaped = unescapeHtml(rawTranslatedText);
        final normalized = unescaped
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
        var splitLines = normalized.split('\n');

        // Reconcile line count to guarantee 1:1 alignment with input batch
        if (splitLines.length != batch.length) {
          final reconciled = <String>[];
          var splitIndex = 0;
          for (int i = 0; i < batch.length; i++) {
            if (batch[i].trim().isEmpty) {
              // Keep original blank/whitespace line
              reconciled.add(batch[i]);
            } else if (splitIndex < splitLines.length) {
              reconciled.add(splitLines[splitIndex]);
              splitIndex++;
            } else {
              reconciled.add(batch[i]); // Fallback to original line
            }
          }
          splitLines = reconciled;
        }

        return (lines: splitLines, isSameLanguage: false);
      }

      throw const LyricsTranslationException(
        'Rate limit exceeded (Too many requests)',
        statusCode: 429,
      );
    } on TimeoutException {
      throw const LyricsTranslationException(
        'Translation request timed out',
        statusCode: 504,
      );
    } on SocketException catch (e) {
      throw LyricsTranslationException(
        'Network connection failed: ${e.message}',
        statusCode: 0,
        cause: e,
      );
    } on http.ClientException catch (e) {
      throw LyricsTranslationException(
        'HTTP client error: ${e.message}',
        statusCode: 0,
        cause: e,
      );
    }
  }

  /// Unescapes common HTML entities returned by translation APIs.
  static String unescapeHtml(String input) {
    if (!input.contains('&')) return input;
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          final code = int.tryParse(match.group(1)!);
          if (code != null && code >= 0 && code <= 0x10ffff) {
            try {
              return String.fromCharCode(code);
            } catch (_) {
              return match.group(0)!;
            }
          }
          return match.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (match) {
          final code = int.tryParse(match.group(1)!, radix: 16);
          if (code != null && code >= 0 && code <= 0x10ffff) {
            try {
              return String.fromCharCode(code);
            } catch (_) {
              return match.group(0)!;
            }
          }
          return match.group(0)!;
        })
        .replaceAll('&amp;', '&');
  }

  /// Closes the HTTP client if this instance owns it.
  void close() {
    dispose();
  }

  /// Disposes the HTTP client if this instance owns it.
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
