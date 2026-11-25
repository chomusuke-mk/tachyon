import 'dart:async';
import 'package:tachyon/shared/utils/cancellation_token.dart';

/// Monotonic generation tracker managing track transition tokens.
///
/// Ensures rapid track changes (e.g. 1 -> 2 -> 3 -> 4 -> 5) immediately
/// cancel older in-flight or throttled operations, preventing stale lyric overwrites.
class LyricsGenerationTracker {
  int _activeToken = 0;
  CancellationToken? _activeCancellationToken;

  /// Monotonically increasing identifier of the current generation.
  int get activeToken => _activeToken;

  /// Cancellation token associated with the current generation, if any.
  CancellationToken? get activeCancellationToken => _activeCancellationToken;

  /// Advances generation counter, cancels previous token, and returns fresh token.
  CancellationToken nextGeneration() {
    _activeCancellationToken?.cancel();
    _activeToken++;
    final token = CancellationToken();
    _activeCancellationToken = token;
    return token;
  }

  /// Checks if given [token] matches current generation and has not been cancelled.
  bool isCurrent(int token) =>
      token == _activeToken &&
      !(_activeCancellationToken?.isCancelled ?? false);

  /// Cancels active token without advancing generation counter.
  void cancelCurrent() {
    _activeCancellationToken?.cancel();
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
  /// Clock function returning the current [DateTime] for cooldown calculations.
  final DateTime Function() nowProvider;

  DateTime? _cooldownExpiry;
  bool _isThresholdWaiting = false;
  int? _thresholdCountdownSeconds;
  Timer? _thresholdTimer;

  // Deferred retry state
  Timer? _deferredRetryTimer;
  Future<void> Function()? _deferredCallback;

  final StreamController<int?> _thresholdStreamController =
      StreamController<int?>.broadcast();

  /// Creates a [LyricsCooldownManager] with an optional custom clock for testing.
  LyricsCooldownManager({DateTime Function()? nowProvider})
    : nowProvider = nowProvider ?? DateTime.now;

  /// Current clock timestamp supplied by [nowProvider].
  DateTime get now => nowProvider();

  /// Timestamp when the current extended cooldown expires, if active.
  DateTime? get cooldownExpiry => _cooldownExpiry;

  /// Whether an extended cooldown (>10s) is currently active.
  bool get isCooldownActive =>
      _cooldownExpiry != null && _cooldownExpiry!.isAfter(now);

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
    required String trackFilePath,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    cancelDeferredRetry();
    if (_cooldownExpiry == null) return;

    final remainingMs = _cooldownExpiry!.difference(now).inMilliseconds;
    if (remainingMs <= 0) {
      onRetry();
      return;
    }

    _deferredCallback = onRetry;

    _deferredRetryTimer = Timer(Duration(milliseconds: remainingMs), () async {
      if (_deferredCallback != null) {
        final cb = _deferredCallback!;
        cancelDeferredRetry();
        await cb();
      }
    });
  }

  /// Cancels any scheduled deferred retry.
  void cancelDeferredRetry() {
    _deferredRetryTimer?.cancel();
    _deferredRetryTimer = null;
    _deferredCallback = null;
  }

  /// Updates active track for deferred retry if user skips songs during active cooldown.
  ///
  /// Defensively ensures that a running timer is scheduled if not already active.
  void updateDeferredTrack({
    required String trackFilePath,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    if (!isCooldownActive) return;
    _deferredCallback = onRetry;

    if (_deferredRetryTimer == null || !_deferredRetryTimer!.isActive) {
      final remainingMs = _cooldownExpiry!.difference(now).inMilliseconds;
      if (remainingMs <= 0) {
        onRetry();
      } else {
        _deferredRetryTimer = Timer(
          Duration(milliseconds: remainingMs),
          () async {
            if (_deferredCallback != null) {
              final cb = _deferredCallback!;
              cancelDeferredRetry();
              await cb();
            }
          },
        );
      }
    }
  }

  /// Disposes timers and closes streams.
  void dispose() {
    cancelThresholdCountdown();
    cancelDeferredRetry();
    _thresholdStreamController.close();
  }
}
