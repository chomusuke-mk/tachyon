import 'dart:async';
import 'dart:io';

/// Exception thrown when a throttled or in-flight lyrics request is cancelled
/// before execution or while waiting in the pacing queue.
class LyricsCancelledException implements Exception {
  final String message;
  const LyricsCancelledException([this.message = 'Lyrics request was cancelled']);

  @override
  String toString() => 'LyricsCancelledException: $message';
}

/// Lightweight cancellation token used to abort pending throttled requests,
/// countdown timers, and in-flight operations when rapid track skips occur.
class LyricsCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  /// Marks this token as cancelled and notifies all registered listeners.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }

  /// Registers a listener callback invoked immediately if already cancelled,
  /// or when [cancel] is called.
  void onCancelled(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }
}

/// Monotonic generation tracker managing track transition tokens.
///
/// Ensures rapid track changes (e.g. 1 -> 2 -> 3 -> 4 -> 5) immediately
/// cancel older in-flight or throttled operations, preventing stale lyric overwrites.
class LyricsGenerationTracker {
  int _activeToken = 0;
  LyricsCancellationToken? _activeCancellationToken;

  int get activeToken => _activeToken;
  LyricsCancellationToken? get activeCancellationToken => _activeCancellationToken;

  /// Advances generation counter, cancels previous token, and returns fresh token.
  LyricsCancellationToken nextGeneration() {
    _activeCancellationToken?.cancel();
    _activeToken++;
    final token = LyricsCancellationToken();
    _activeCancellationToken = token;
    return token;
  }

  /// Checks if given [token] matches current generation and has not been cancelled.
  bool isCurrent(int token) =>
      token == _activeToken && !(_activeCancellationToken?.isCancelled ?? false);

  /// Cancels active token without advancing generation counter.
  void cancelCurrent() {
    _activeCancellationToken?.cancel();
  }
}

/// Rate limiter enforcing sequential pacing (minimum 500ms spacing) between
/// outgoing requests to remote lyrics APIs (specifically `lrclib.net`).
///
/// Features:
/// - Immediate dispatch for first request or requests issued after interval elapses.
/// - FIFO queuing with delay adjustment for burst requests.
/// - Cancellation token integration: cancelled requests in queue are aborted without
///   invoking network callbacks.
/// - Injectable [nowProvider] for deterministic time testing.
class LyricsRateLimiter {
  /// Minimum time interval required between the start of consecutive dispatched requests.
  final Duration minInterval;

  /// Clock provider function (defaults to [DateTime.now]).
  final DateTime Function() nowProvider;

  DateTime? _lastDispatchedTime;
  Future<void> _queueChain = Future.value();
  bool _isDisposed = false;

  /// Monotonic record of timestamps when requests were dispatched.
  final List<DateTime> requestTimestamps = [];

  LyricsRateLimiter({
    this.minInterval = const Duration(milliseconds: 500),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  DateTime get now => nowProvider();
  bool get isDisposed => _isDisposed;
  DateTime? get lastDispatchedTime => _lastDispatchedTime;

  /// Executes [action] after ensuring [minInterval] has elapsed since the previous dispatch.
  ///
  /// If [cancellationToken] is cancelled before the action dispatches (e.g. during pacing wait),
  /// [action] is NOT invoked, and the returned future completes with [LyricsCancelledException].
  Future<T> runThrottled<T>(
    Future<T> Function() action, {
    LyricsCancellationToken? cancellationToken,
  }) {
    if (_isDisposed) {
      throw StateError('LyricsRateLimiter is disposed');
    }
    if (cancellationToken != null && cancellationToken.isCancelled) {
      return Future.error(const LyricsCancelledException('Cancelled before entering queue'));
    }

    final completer = Completer<T>();

    _queueChain = _queueChain.then((_) async {
      if (_isDisposed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('LyricsRateLimiter disposed during queue wait'));
        }
        return;
      }
      if (cancellationToken != null && cancellationToken.isCancelled) {
        if (!completer.isCompleted) {
          completer.completeError(const LyricsCancelledException('Cancelled while waiting in queue'));
        }
        return;
      }

      final currentTime = now;
      if (_lastDispatchedTime != null && minInterval > Duration.zero) {
        final elapsed = currentTime.difference(_lastDispatchedTime!);
        if (elapsed < minInterval) {
          final waitDuration = minInterval - elapsed;
          if (waitDuration > Duration.zero) {
            if (cancellationToken != null) {
              final delayCompleter = Completer<void>();
              final timer = Timer(waitDuration, () {
                if (!delayCompleter.isCompleted) delayCompleter.complete();
              });
              cancellationToken.onCancelled(() {
                timer.cancel();
                if (!delayCompleter.isCompleted) delayCompleter.complete();
              });
              await delayCompleter.future;
            } else {
              await Future.delayed(waitDuration);
            }
            if (_isDisposed) {
              if (!completer.isCompleted) {
                completer.completeError(StateError('LyricsRateLimiter disposed during delay'));
              }
              return;
            }
            if (cancellationToken != null && cancellationToken.isCancelled) {
              if (!completer.isCompleted) {
                completer.completeError(const LyricsCancelledException('Cancelled during pacing wait'));
              }
              return;
            }
          }
        }
      }

      final dispatchTime = now;
      _lastDispatchedTime = dispatchTime;
      requestTimestamps.add(dispatchTime);

      try {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    }).catchError((_) {
      // Absorb errors in queue pipeline to prevent subsequent items from stalling
    });

    return completer.future;
  }

  /// Resets internal dispatch timer and clears recorded timestamps.
  void reset() {
    _lastDispatchedTime = null;
    requestTimestamps.clear();
    _queueChain = Future.value();
  }

  /// Disposes the limiter and marks it as unusable.
  void dispose() {
    _isDisposed = true;
    reset();
  }
}

/// Helper parsing HTTP `Retry-After` header values (integer seconds or HTTP date).
///
/// Accepts either a [String] header value or a [Map<String, String>] headers map.
int parseRetryAfterHeader(
  Object? headerValueOrHeaders, {
  DateTime Function()? nowProvider,
  int defaultSeconds = 5,
}) {
  String? headerValue;
  if (headerValueOrHeaders is Map<String, String>) {
    for (final entry in headerValueOrHeaders.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        headerValue = entry.value;
        break;
      }
    }
  } else if (headerValueOrHeaders is String) {
    headerValue = headerValueOrHeaders;
  }

  if (headerValue == null || headerValue.trim().isEmpty) {
    return defaultSeconds;
  }
  final trimmed = headerValue.trim();

  // Try parsing integer seconds
  final parsedInt = int.tryParse(trimmed);
  if (parsedInt != null) {
    return parsedInt >= 0 ? parsedInt : defaultSeconds;
  }

  // Try parsing HTTP date (RFC 1123, RFC 850, asctime)
  try {
    final httpDate = HttpDate.parse(trimmed);
    final now = (nowProvider ?? DateTime.now)();
    final diff = httpDate.difference(now).inSeconds;
    return diff > 0 ? diff : defaultSeconds;
  } catch (_) {
    return defaultSeconds;
  }
}

/// In-memory manager for tracking HTTP 429 rate limit states, live countdown banners,
/// cooldown expiry, and deferred retry callbacks for `lrclib.net`.
///
/// Rules:
/// - `Retry-After <= 10s`: Triggers live countdown ([isThresholdWaiting] == true).
///   Ticks every second on [thresholdStream]. Auto-retries primary API when countdown reaches 0.
/// - `Retry-After > 10s`: Activates memory cooldown ([isCooldownActive] == true).
///   Tracks [cooldownExpiry]. Prompts immediate fallback to secondary API and schedules
///   deferred upgrade when cooldown expires if track is still active.
class LyricsCooldownManager {
  final DateTime Function() nowProvider;

  DateTime? _cooldownExpiry;
  bool _isThresholdWaiting = false;
  int? _thresholdCountdownSeconds;
  Timer? _thresholdTimer;

  // Deferred retry state
  Timer? _deferredRetryTimer;
  String? _deferredTrackFilePath;
  int? _deferredGenerationToken;
  Future<void> Function()? _deferredCallback;

  String? get deferredTrackFilePath => _deferredTrackFilePath;
  @Deprecated('Use deferredTrackFilePath instead')
  String? get deferredTrackUri => _deferredTrackFilePath;
  int? get deferredGenerationToken => _deferredGenerationToken;

  final StreamController<int?> _thresholdStreamController =
      StreamController<int?>.broadcast();

  LyricsCooldownManager({
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  DateTime get now => nowProvider();

  DateTime? get cooldownExpiry => _cooldownExpiry;

  /// Whether an extended cooldown (>10s) is currently active.
  bool get isCooldownActive =>
      _cooldownExpiry != null && _cooldownExpiry!.isAfter(now);

  /// Seconds remaining until the extended cooldown expires (0 if inactive).
  int get remainingCooldownSeconds {
    if (!isCooldownActive || _cooldownExpiry == null) return 0;
    final diff = _cooldownExpiry!.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Whether the short-term threshold countdown (<= 10s) is active.
  bool get isThresholdWaiting => _isThresholdWaiting;

  /// Current remaining seconds in the live threshold countdown.
  int? get thresholdCountdownSeconds => _thresholdCountdownSeconds;

  /// Broadcast stream emitting updated remaining seconds (or null when dismissed).
  Stream<int?> get thresholdStream => _thresholdStreamController.stream;

  /// Sets or extends an in-memory cooldown duration.
  void setCooldown(Duration duration) {
    final candidate = now.add(duration);
    if (_cooldownExpiry == null || candidate.isAfter(_cooldownExpiry!)) {
      _cooldownExpiry = candidate;
    }
  }

  /// Clears active cooldown and cancels any deferred retry.
  void clearCooldown() {
    _cooldownExpiry = null;
    cancelDeferredRetry();
  }

  /// Starts a live threshold countdown for `retryAfterSeconds` <= 10.
  ///
  /// Emits decremented seconds on [thresholdStream] every second.
  /// When countdown reaches 0, [onAutoRetry] is invoked if [isStillValid] returns true.
  void startThresholdCountdown({
    required int seconds,
    required Future<void> Function() onAutoRetry,
    bool Function()? isStillValid,
  }) {
    cancelThresholdCountdown();

    _isThresholdWaiting = true;
    _thresholdCountdownSeconds = seconds;
    if (!_thresholdStreamController.isClosed) {
      _thresholdStreamController.add(seconds);
    }

    _thresholdTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (isStillValid != null && !isStillValid()) {
        cancelThresholdCountdown();
        return;
      }

      _thresholdCountdownSeconds = (_thresholdCountdownSeconds ?? 1) - 1;
      if (!_thresholdStreamController.isClosed) {
        _thresholdStreamController.add(_thresholdCountdownSeconds);
      }

      if ((_thresholdCountdownSeconds ?? 0) <= 0) {
        cancelThresholdCountdown();
        if (isStillValid == null || isStillValid()) {
          await onAutoRetry();
        }
      }
    });
  }

  /// Cancels live threshold countdown and hides banner.
  void cancelThresholdCountdown() {
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    _isThresholdWaiting = false;
    _thresholdCountdownSeconds = null;
    if (!_thresholdStreamController.isClosed) {
      _thresholdStreamController.add(null);
    }
  }

  /// Schedules a deferred upgrade retry when cooldown expires.
  void scheduleDeferredRetry({
    String? trackFilePath,
    @Deprecated('Use trackFilePath instead') String? trackUri,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    final effectivePath = trackFilePath ?? trackUri ?? '';
    cancelDeferredRetry();
    if (_cooldownExpiry == null) return;

    final remainingMs = _cooldownExpiry!.difference(now).inMilliseconds;
    if (remainingMs <= 0) {
      onRetry();
      return;
    }

    _deferredTrackFilePath = effectivePath;
    _deferredGenerationToken = token;
    _deferredCallback = onRetry;

    _deferredRetryTimer = Timer(Duration(milliseconds: remainingMs), () async {
      if (_deferredCallback != null) {
        final cb = _deferredCallback!;
        cancelDeferredRetry();
        await cb();
      }
    });
  }

  /// Whether a deferred upgrade timer is currently active.
  bool get isDeferredRetryScheduled =>
      _deferredRetryTimer != null && _deferredRetryTimer!.isActive;

  /// Cancels any scheduled deferred retry.
  void cancelDeferredRetry() {
    _deferredRetryTimer?.cancel();
    _deferredRetryTimer = null;
    _deferredTrackFilePath = null;
    _deferredGenerationToken = null;
    _deferredCallback = null;
  }

  /// Updates active track for deferred retry if user skips songs during active cooldown.
  /// Defensively ensures that a running timer is scheduled if not already active.
  void updateDeferredTrack({
    String? trackFilePath,
    @Deprecated('Use trackFilePath instead') String? trackUri,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    if (!isCooldownActive) return;
    final effectivePath = trackFilePath ?? trackUri ?? '';
    _deferredTrackFilePath = effectivePath;
    _deferredGenerationToken = token;
    _deferredCallback = onRetry;

    // If timer is not running or completed, schedule a new timer for the remaining duration
    if (_deferredRetryTimer == null || !_deferredRetryTimer!.isActive) {
      final remainingMs = _cooldownExpiry!.difference(now).inMilliseconds;
      if (remainingMs <= 0) {
        onRetry();
      } else {
        _deferredRetryTimer =
            Timer(Duration(milliseconds: remainingMs), () async {
              if (_deferredCallback != null) {
                final cb = _deferredCallback!;
                cancelDeferredRetry();
                await cb();
              }
            });
      }
    }
  }

  /// Manually expires active cooldown immediately and triggers deferred callback (test helper).
  Future<void> expireCooldownAndTriggerUpgrade() async {
    if (_cooldownExpiry == null) return;
    _cooldownExpiry = now.subtract(const Duration(seconds: 1));
    final cb = _deferredCallback;
    cancelDeferredRetry();
    if (cb != null) {
      await cb();
    }
  }

  /// Disposes timers and closes streams.
  void dispose() {
    cancelThresholdCountdown();
    cancelDeferredRetry();
    _thresholdStreamController.close();
  }
}
