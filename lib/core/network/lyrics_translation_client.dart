import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Exception thrown when a lyrics translation operation fails.
class LyricsTranslationException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const LyricsTranslationException(
    this.message, {
    this.statusCode,
    this.cause,
  });

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
  final bool isSuccess;
  final String? errorMessage;

  const TranslationResult({
    required this.originalLines,
    required this.translatedLines,
    required this.targetLanguage,
    this.isSuccess = true,
    this.errorMessage,
  });

  const TranslationResult.failure({
    required this.originalLines,
    required this.targetLanguage,
    required this.errorMessage,
  })  : translatedLines = const [],
        isSuccess = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationResult &&
          runtimeType == other.runtimeType &&
          listEquals(originalLines, other.originalLines) &&
          listEquals(translatedLines, other.translatedLines) &&
          targetLanguage == other.targetLanguage &&
          isSuccess == other.isSuccess &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(originalLines),
        Object.hashAll(translatedLines),
        targetLanguage,
        isSuccess,
        errorMessage,
      );

  @override
  String toString() =>
      'TranslationResult(isSuccess: $isSuccess, lines: ${translatedLines.length}/${originalLines.length}, error: $errorMessage)';
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
    this.timeout = const Duration(seconds: 12),
    this.myMemoryBaseUrl = defaultBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

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
  }) async {
    if (lines.isEmpty) return const [];

    // Normalize any line breaks inside individual line strings
    final cleanLines = lines
        .map((l) => l.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .toList();

    // If all lines are empty or whitespace, return immediately
    if (cleanLines.every((l) => l.trim().isEmpty)) {
      return List<String>.from(cleanLines);
    }

    final batches = chunkLines(cleanLines, maxBatchChars: 400);
    final allTranslated = <String>[];

    for (final batch in batches) {
      final translatedBatch = await _translateBatch(batch, targetLanguage);
      allTranslated.addAll(translatedBatch);
    }

    return allTranslated;
  }

  /// Safe translation method that catches exceptions and returns [TranslationResult].
  Future<TranslationResult> translate(
    List<String> lines, {
    required String targetLanguage,
  }) async {
    if (lines.isEmpty) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        errorMessage: 'No lines provided for translation',
      );
    }

    try {
      final translated = await translateLines(
        lines,
        targetLanguage: targetLanguage,
      );
      return TranslationResult(
        originalLines: lines,
        translatedLines: translated,
        targetLanguage: targetLanguage,
        isSuccess: true,
      );
    } on LyricsTranslationException catch (e) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        errorMessage: e.message,
      );
    } catch (e) {
      return TranslationResult.failure(
        originalLines: lines,
        targetLanguage: targetLanguage,
        errorMessage: 'Unexpected translation error: $e',
      );
    }
  }

  Future<List<String>> _translateBatch(
    List<String> batch,
    String targetLanguage,
  ) async {
    // If batch contains only empty or whitespace lines, preserve them directly
    if (batch.every((line) => line.trim().isEmpty)) {
      return List<String>.from(batch);
    }

    final batchText = batch.join('\n');
    final uri = Uri.parse(myMemoryBaseUrl).replace(
      queryParameters: {
        'q': batchText,
        'langpair': 'autodetect|$targetLanguage',
      },
    );

    try {
      final response = await _httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': defaultUserAgent,
        },
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw LyricsTranslationException(
          'Translation HTTP error: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      String bodyString;
      try {
        bodyString = utf8.decode(response.bodyBytes);
      } catch (_) {
        bodyString = response.body;
      }

      final decoded = jsonDecode(bodyString);
      if (decoded is! Map<String, dynamic>) {
        throw const LyricsTranslationException('Invalid JSON response format');
      }

      final responseStatus = decoded['responseStatus'] as int? ?? 200;
      if (responseStatus != 200) {
        final details = decoded['responseDetails'] as String? ??
            'Translation service error $responseStatus';
        throw LyricsTranslationException(details, statusCode: responseStatus);
      }

      final responseData = decoded['responseData'] as Map<String, dynamic>?;
      final rawTranslatedText = responseData?['translatedText'] as String?;
      if (rawTranslatedText == null) {
        throw const LyricsTranslationException('Missing translatedText in response');
      }

      final unescaped = unescapeHtml(rawTranslatedText);
      final normalized =
          unescaped.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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

      return splitLines;
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
