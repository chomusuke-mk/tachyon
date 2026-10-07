import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Structured response from lyrics.ovh API.
@immutable
class LyricsOvhResponse {
  final String? lyrics;
  final int statusCode;
  final String? error;
  final bool _isTemporary;

  const LyricsOvhResponse({
    this.lyrics,
    this.statusCode = 200,
    this.error,
    this._isTemporary = false,
  });

  /// Factory for a successful lyrics match.
  const LyricsOvhResponse.success(this.lyrics)
    : statusCode = 200,
      error = null,
      _isTemporary = false;

  /// Factory for a confirmed not-found result (404 or empty content).
  const LyricsOvhResponse.notFound({String? error})
    : lyrics = null,
      statusCode = 404,
      error = error ?? 'No lyrics found',
      _isTemporary = false;

  /// Factory for temporary network, server, or rate-limit errors.
  const LyricsOvhResponse.temporaryError({required this.statusCode, this.error})
    : lyrics = null,
      _isTemporary = true;

  /// Whether lyrics were successfully retrieved with non-empty content.
  bool get isSuccess =>
      !_isTemporary &&
      statusCode == 200 &&
      lyrics != null &&
      lyrics!.trim().isNotEmpty;

  /// Whether the lyrics were confirmed not found on the server.
  bool get isNotFound =>
      !_isTemporary &&
      (statusCode == 404 ||
          (statusCode == 200 &&
              error == null &&
              (lyrics == null || lyrics!.trim().isEmpty)));

  /// Whether the query failed due to a transient network or server error.
  bool get isTemporaryError => _isTemporary || (!isSuccess && !isNotFound);

  /// Alias for error check, matching e2e model interface.
  bool get isError => isTemporaryError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsOvhResponse &&
          runtimeType == other.runtimeType &&
          lyrics == other.lyrics &&
          statusCode == other.statusCode &&
          error == other.error &&
          _isTemporary == other._isTemporary;

  @override
  int get hashCode => Object.hash(lyrics, statusCode, error, _isTemporary);

  @override
  String toString() =>
      'LyricsOvhResponse(statusCode: $statusCode, isSuccess: $isSuccess, isNotFound: $isNotFound, error: $error)';
}

/// Fallback plain-text lyrics client querying https://api.lyrics.ovh/v1.
///
/// Features:
/// - URL-encodes artist and song title path segments (e.g. `AC/DC` -> `AC%2FDC`).
/// - Rejects empty inputs immediately without issuing network calls.
/// - Discriminated response: FOUND, NOT_FOUND, TEMPORARY_ERROR.
/// - Handles HTTP 404, 5xx server errors, rate limits, timeouts, and connection drops.
/// - Normalizes Windows CRLF line endings.
/// - Provides [getPlainLyrics] helper matching PROJECT.md interface contract.
class LyricsOvhClient {
  static const String defaultBaseUrl = 'https://api.lyrics.ovh/v1';
  static const String defaultUserAgent =
      'Tachyon/1.0.0 (https://github.com/chomusuke-mk/tachyon)';

  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration timeout;
  final String baseUrl;

  LyricsOvhClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
    String baseUrl = defaultBaseUrl,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Fetches structured lyrics response from lyrics.ovh for [artist] and [title].
  Future<LyricsOvhResponse> getLyrics({
    required String artist,
    required String title,
  }) async {
    final cleanArtist = artist.trim();
    final cleanTitle = title.trim();

    if (cleanArtist.isEmpty || cleanTitle.isEmpty) {
      return const LyricsOvhResponse.notFound(
        error: 'Artist and title must not be empty',
      );
    }

    final encodedArtist = Uri.encodeComponent(cleanArtist);
    final encodedTitle = Uri.encodeComponent(cleanTitle);
    final url = '$baseUrl/$encodedArtist/$encodedTitle';
    final uri = Uri.parse(url);

    try {
      debugPrint(
        'Fetching lyrics from $url at ${DateTime.now().toIso8601String()}',
      );
      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': defaultUserAgent,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        try {
          String bodyString;
          try {
            bodyString = utf8.decode(response.bodyBytes);
          } catch (_) {
            bodyString = response.body;
          }
          final decoded = jsonDecode(bodyString);
          if (decoded is Map<String, dynamic>) {
            final rawLyrics = decoded['lyrics'] as String?;
            if (rawLyrics == null || rawLyrics.trim().isEmpty) {
              return const LyricsOvhResponse.notFound(
                error: 'Empty lyrics content in 200 response',
              );
            }
            final normalized = rawLyrics.replaceAll('\r\n', '\n');
            return LyricsOvhResponse.success(normalized);
          }
          return const LyricsOvhResponse.notFound(
            error: 'Malformed JSON payload',
          );
        } catch (e) {
          return LyricsOvhResponse.temporaryError(
            statusCode: 200,
            error: 'Failed to decode JSON: $e',
          );
        }
      } else if (response.statusCode == 404) {
        String? errorMsg;
        try {
          String bodyString;
          try {
            bodyString = utf8.decode(response.bodyBytes);
          } catch (_) {
            bodyString = response.body;
          }
          final decoded = jsonDecode(bodyString);
          if (decoded is Map<String, dynamic>) {
            errorMsg = decoded['error'] as String?;
          }
        } catch (_) {}
        return LyricsOvhResponse.notFound(error: errorMsg);
      } else {
        return LyricsOvhResponse.temporaryError(
          statusCode: response.statusCode,
          error: 'HTTP error ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException {
      return const LyricsOvhResponse.temporaryError(
        statusCode: 504,
        error: 'Request timed out',
      );
    } on SocketException catch (e) {
      return LyricsOvhResponse.temporaryError(
        statusCode: 0,
        error: 'Network connection failed: ${e.message}',
      );
    } on http.ClientException catch (e) {
      return LyricsOvhResponse.temporaryError(
        statusCode: 0,
        error: 'HTTP client exception: ${e.message}',
      );
    } catch (e) {
      return LyricsOvhResponse.temporaryError(
        statusCode: 0,
        error: 'Unexpected error: $e',
      );
    }
  }

  /// Convenience method matching PROJECT.md interface contract.
  Future<String?> getPlainLyrics({
    required String artist,
    required String title,
  }) async {
    final response = await getLyrics(artist: artist, title: title);
    return response.isSuccess ? response.lyrics : null;
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
