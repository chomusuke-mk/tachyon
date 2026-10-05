import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'lyrics_rate_limiter.dart';

/// Base sealed class representing the result of querying `lrclib.net`.
sealed class LrclibResponse {
  final int statusCode;
  final Map<String, String> headers;

  const LrclibResponse({required this.statusCode, this.headers = const {}});

  /// Whether the request completed successfully.
  bool get isSuccess => this is LrclibSuccess;

  /// Whether the track was not found on the server (HTTP 404).
  bool get isNotFound => this is LrclibNotFound;

  /// Whether the request was throttled by rate limit (HTTP 429).
  bool get isRateLimited => this is LrclibRateLimited;

  /// Whether the request failed due to a server or network error.
  bool get isError => this is LrclibError;

  /// Whether this error represents a transient failure (HTTP 429, 5xx, or network drop)
  /// that must NOT be permanently recorded as absent in persistence.
  bool get isTemporaryError => isRateLimited || isError;

  // Unified property accessors for caller convenience:
  int? get id => null;
  String? get trackName => null;
  String? get artistName => null;
  String? get albumName => null;
  double? get duration => null;
  bool get instrumental => false;
  String? get plainLyrics => null;
  String? get syncedLyrics => null;
  int? get retryAfterSeconds => null;
  String? get errorMessage => null;

  /// Whether synchronized LRC timestamps are available in the response.
  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  /// Whether plain text lyrics are available in the response.
  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  /// Whether any lyrics (synced or plain) are available.
  bool get hasAnyLyrics => hasSyncedLyrics || hasPlainLyrics;

  /// Convenience factory for a successful lyrics response.
  const factory LrclibResponse.success({
    int? id,
    String? trackName,
    String? artistName,
    String? albumName,
    double? duration,
    bool instrumental,
    String? plainLyrics,
    String? syncedLyrics,
    int statusCode,
    Map<String, String> headers,
  }) = LrclibSuccess;

  /// Convenience factory for a confirmed 404 Not Found response.
  const factory LrclibResponse.notFound({
    int statusCode,
    Map<String, String> headers,
    String errorMessage,
  }) = LrclibNotFound;

  /// Convenience factory for an HTTP 429 rate limit response.
  const factory LrclibResponse.rateLimited({
    int statusCode,
    int? retryAfterSeconds,
    Map<String, String> headers,
  }) = LrclibRateLimited;

  /// Convenience factory for server errors (5xx) or network exceptions.
  const factory LrclibResponse.error({
    required int statusCode,
    required String errorMessage,
    Object? cause,
    Map<String, String> headers,
  }) = LrclibError;
}

/// Successful HTTP 2xx response from `lrclib.net`.
class LrclibSuccess extends LrclibResponse {
  @override
  final int? id;
  @override
  final String? trackName;
  @override
  final String? artistName;
  @override
  final String? albumName;
  @override
  final double? duration;
  @override
  final bool instrumental;
  @override
  final String? plainLyrics;
  @override
  final String? syncedLyrics;

  const LrclibSuccess({
    this.id,
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
    super.statusCode = 200,
    super.headers = const {},
  });

  /// Deserializes JSON payload returned by `GET /api/get`.
  factory LrclibSuccess.fromJson(
    Map<String, dynamic> json, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) {
    return LrclibSuccess(
      id: (json['id'] as num?)?.toInt(),
      trackName: (json['trackName'] ?? json['name']) as String?,
      artistName: json['artistName'] as String?,
      albumName: json['albumName'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      instrumental: json['instrumental'] as bool? ?? false,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
      statusCode: statusCode,
      headers: headers,
    );
  }

  /// Verifies whether the returned track duration matches an [expectedSeconds]
  /// duration within a given tolerance window (default: ±2.0 seconds).
  bool isWithinDurationTolerance(
    num expectedSeconds, {
    double toleranceSeconds = 2.0,
  }) {
    if (duration == null) return true;
    return (duration! - expectedSeconds).abs() <= toleranceSeconds;
  }

  @override
  String toString() =>
      'LrclibSuccess(id: $id, track: $trackName, artist: $artistName, '
      'instrumental: $instrumental, synced: $hasSyncedLyrics, plain: $hasPlainLyrics)';
}

/// HTTP 404 response indicating lyrics are absent for this track.
class LrclibNotFound extends LrclibResponse {
  @override
  final String errorMessage;

  const LrclibNotFound({
    super.statusCode = 404,
    super.headers = const {},
    this.errorMessage = 'Track not found in lrclib.net',
  });

  @override
  String toString() => 'LrclibNotFound($errorMessage)';
}

/// HTTP 429 Too Many Requests response with parsed `Retry-After` duration.
class LrclibRateLimited extends LrclibResponse {
  @override
  final int? retryAfterSeconds;

  const LrclibRateLimited({
    super.statusCode = 429,
    this.retryAfterSeconds,
    super.headers = const {},
  });

  /// Whether the cooldown is short enough (<=10s) to show a live countdown
  /// and automatically retry without switching to the fallback provider.
  bool get shouldTriggerCountdown => (retryAfterSeconds ?? 5) <= 10;

  /// Whether the cooldown is long enough (>10s) to warrant immediately
  /// falling back to the secondary provider (`lyrics.ovh`).
  bool get shouldFallbackImmediately => !shouldTriggerCountdown;

  @override
  String toString() =>
      'LrclibRateLimited(retryAfter: ${retryAfterSeconds}s, '
      'countdown: $shouldTriggerCountdown)';
}

/// Network or server error (5xx or connection exception).
class LrclibError extends LrclibResponse {
  @override
  final String errorMessage;
  final Object? cause;

  const LrclibError({
    required super.statusCode,
    required this.errorMessage,
    this.cause,
    super.headers = const {},
  });

  @override
  String toString() =>
      'LrclibError(status: $statusCode, message: $errorMessage)';
}

/// Network client for the `lrclib.net` lyrics API.
///
/// Features:
/// - Target endpoint: `GET /api/get`.
/// - Automatic URL query formatting with percent-encoding.
/// - Integer seconds duration parameter with ±2s tolerance support.
/// - Required identifying `User-Agent` client header.
/// - Minimum 500ms pacing between consecutive requests (FIFO serialization).
/// - HTTP 429 `Retry-After` header parsing (integer and RFC 1123 HTTP-date).
/// - Comprehensive status code mapping (200, 404, 429, 5xx, network drops).
/// - Mockable HTTP client injection (`http.Client`).
class LrclibClient {
  static const String defaultBaseUrl = 'https://lrclib.net/api/get';
  static const String defaultUserAgent =
      'Tachyon/1.0.0 (https://github.com/chomusuke-mk/tachyon)';
  static const Duration defaultPacing = Duration(milliseconds: 500);
  static const int defaultRetryAfterSeconds = 5;

  final http.Client _httpClient;
  final bool _ownsClient;
  final Uri _baseUri;
  final String _userAgent;
  final Duration _minPacing;

  // Rate Limiting & Pacing queue state
  Future<void> _pacingFuture = Future.value();
  DateTime? _lastRequestTime;
  final List<DateTime> _requestTimestamps = [];
  final List<String> _requestedUserAgents = [];
  final List<Uri> _requestedUris = [];

  LrclibClient({
    http.Client? httpClient,
    Uri? baseUri,
    String? userAgent,
    Duration? minPacing,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _baseUri = baseUri ?? Uri.parse(defaultBaseUrl),
       _userAgent = userAgent ?? defaultUserAgent,
       _minPacing = minPacing ?? defaultPacing;

  /// Timestamps of all dispatched outgoing network requests (useful for pacing verification).
  List<DateTime> get requestTimestamps => List.unmodifiable(_requestTimestamps);

  /// User-Agent headers recorded for outgoing requests.
  List<String> get requestedUserAgents =>
      List.unmodifiable(_requestedUserAgents);

  /// Exact URIs dispatched to the HTTP client.
  List<Uri> get requestedUris => List.unmodifiable(_requestedUris);

  /// Configured minimum pacing duration between consecutive queries.
  Duration get minPacing => _minPacing;

  /// Configured client User-Agent string.
  String get userAgent => _userAgent;

  /// Fetches lyrics from `lrclib.net` for the specified track.
  ///
  /// Parameters:
  /// - [trackName]: Track title (required).
  /// - [artistName]: Artist name (required).
  /// - [albumName]: Album title (optional, omitted from query if null or empty).
  /// - [durationSeconds]: Duration in integer seconds (optional, omitted if null or <= 0).
  /// - [cancellationToken]: Optional cancellation token for rapid skip cancellation.
  /// - [isCancelled]: Optional callback returning true if the request was cancelled
  ///   due to a rapid track skip, preventing unnecessary network traffic.
  Future<LrclibResponse> getLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() =>
        (cancellationToken != null && cancellationToken.isCancelled) ||
        (isCancelled != null && isCancelled());

    // 1. Check early cancellation before waiting in pacing queue
    if (cancelled()) {
      return const LrclibError(
        statusCode: 499,
        errorMessage: 'Request cancelled before pacing queue',
      );
    }

    // 2. Enforce 500ms pacing queue
    await _enforcePacing(
      cancellationToken: cancellationToken,
      isCancelled: isCancelled,
    );

    // 3. Check cancellation after pacing delay
    if (cancelled()) {
      return const LrclibError(
        statusCode: 499,
        errorMessage: 'Request cancelled after pacing wait',
      );
    }

    // 4. Construct request URI
    final requestUri = buildRequestUri(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      durationSeconds: durationSeconds,
    );

    // 5. Track request metadata
    final now = DateTime.now();
    _requestTimestamps.add(now);
    _lastRequestTime = now;
    _requestedUris.add(requestUri);
    _requestedUserAgents.add(_userAgent);

    final headers = {'User-Agent': _userAgent, 'Accept': 'application/json'};

    // 6. Execute HTTP request
    try {
      final response = await _httpClient.get(requestUri, headers: headers);

      // Check cancellation after HTTP call completes
      if (cancelled()) {
        return const LrclibError(
          statusCode: 499,
          errorMessage: 'Request cancelled during network call',
        );
      }

      return _processHttpResponse(response);
    } catch (e) {
      return LrclibError(
        statusCode: 0,
        errorMessage: 'Network exception: $e',
        cause: e,
      );
    }
  }

  /// Builds the parameterized [Uri] for querying `lrclib.net`.
  Uri buildRequestUri({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) {
    final queryParams = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };

    if (albumName != null && albumName.trim().isNotEmpty) {
      queryParams['album_name'] = albumName.trim();
    }

    if (durationSeconds != null && durationSeconds > 0) {
      queryParams['duration'] = durationSeconds.toString();
    }

    return _baseUri.replace(queryParameters: queryParams);
  }

  /// Processes the [http.Response] into a typed [LrclibResponse].
  LrclibResponse _processHttpResponse(http.Response response) {
    final statusCode = response.statusCode;
    final headers = response.headers;

    // 200 OK: parse JSON payload
    if (statusCode >= 200 && statusCode < 300) {
      try {
        final body = utf8.decode(response.bodyBytes);
        final dynamic decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return LrclibSuccess.fromJson(
            decoded,
            statusCode: statusCode,
            headers: headers,
          );
        }
        return LrclibError(
          statusCode: statusCode,
          errorMessage: 'Unexpected JSON root type (expected Object)',
          headers: headers,
        );
      } catch (e) {
        return LrclibError(
          statusCode: statusCode,
          errorMessage: 'Failed to decode JSON response: $e',
          cause: e,
          headers: headers,
        );
      }
    }

    // 404 Not Found
    if (statusCode == 404) {
      String notFoundMsg = 'Track not found in lrclib.net';
      try {
        final body = utf8.decode(response.bodyBytes);
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded['message'] is String) {
          notFoundMsg = decoded['message'] as String;
        }
      } catch (_) {}
      return LrclibNotFound(
        statusCode: 404,
        headers: headers,
        errorMessage: notFoundMsg,
      );
    }

    // 429 Too Many Requests
    if (statusCode == 429) {
      final retryAfter = parseRetryAfterHeader(
        headers,
        defaultSeconds: defaultRetryAfterSeconds,
      );
      return LrclibRateLimited(
        statusCode: 429,
        retryAfterSeconds: retryAfter,
        headers: headers,
      );
    }

    // 5xx Server Errors
    if (statusCode >= 500 && statusCode < 600) {
      return LrclibError(
        statusCode: statusCode,
        errorMessage: 'Server error $statusCode from lrclib.net',
        headers: headers,
      );
    }

    // Other unexpected codes
    return LrclibError(
      statusCode: statusCode,
      errorMessage: 'Unexpected HTTP status $statusCode from lrclib.net',
      headers: headers,
    );
  }

  /// Parses the `Retry-After` header value from [headers].
  ///
  /// Supports:
  /// 1. Decimal integer seconds (e.g. `"5"`, `"10"`, `"60"`).
  /// 2. RFC 1123 / IMF-fixdate HTTP-date (e.g. `"Wed, 23 Sep 2026 06:30:00 GMT"`).
  /// 3. Defaults to [defaultSeconds] (5s) if header is missing, empty, or unparseable.
  static int parseRetryAfterHeader(
    Map<String, String> headers, {
    int defaultSeconds = defaultRetryAfterSeconds,
  }) {
    String? headerValue;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        headerValue = entry.value.trim();
        break;
      }
    }

    if (headerValue == null || headerValue.isEmpty) {
      return defaultSeconds;
    }

    // Check integer seconds
    final intValue = int.tryParse(headerValue);
    if (intValue != null) {
      return intValue >= 0 ? intValue : defaultSeconds;
    }

    // Check RFC 1123 HTTP-date
    try {
      final date = HttpDate.parse(headerValue);
      final diff = date.difference(DateTime.now()).inSeconds;
      return diff > 0 ? diff : defaultSeconds;
    } catch (_) {
      return defaultSeconds;
    }
  }

  /// Serializes outgoing requests to satisfy the [_minPacing] (500ms) rule.
  /// Aborts immediately in <1ms if [cancellationToken] is cancelled.
  Future<void> _enforcePacing({
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
  }) {
    if (_minPacing <= Duration.zero) {
      return Future.value();
    }

    final completer = Completer<void>();
    final previous = _pacingFuture;
    _pacingFuture = completer.future;

    return previous
        .then((_) async {
          if (cancellationToken?.isCancelled == true ||
              isCancelled?.call() == true) {
            completer.complete();
            return;
          }

          if (_lastRequestTime != null) {
            final elapsed = DateTime.now().difference(_lastRequestTime!);
            if (elapsed < _minPacing) {
              final wait = _minPacing - elapsed;
              if (wait > Duration.zero) {
                if (cancellationToken != null) {
                  final delayCompleter = Completer<void>();
                  final timer = Timer(wait, () {
                    if (!delayCompleter.isCompleted) delayCompleter.complete();
                  });
                  cancellationToken.onCancelled(() {
                    timer.cancel();
                    if (!delayCompleter.isCompleted) delayCompleter.complete();
                  });
                  await delayCompleter.future;
                } else {
                  await Future.delayed(wait);
                }
              }
            }
          }
          completer.complete();
        })
        .catchError((_) {
          completer.complete();
        });
  }

  /// Resets pacing state and timestamps (useful for isolated unit tests).
  void resetPacing() {
    _lastRequestTime = null;
    _pacingFuture = Future.value();
    _requestTimestamps.clear();
    _requestedUserAgents.clear();
    _requestedUris.clear();
  }

  /// Closes the underlying HTTP client if this instance owns it.
  void close() {
    dispose();
  }

  /// Disposes the underlying HTTP client if this instance owns it.
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
