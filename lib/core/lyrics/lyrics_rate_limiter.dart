import 'dart:async';

/// Exception thrown when a throttled or in-flight lyrics request is cancelled
/// before execution or while waiting in the pacing queue.
class LyricsCancelledException implements Exception {
  final String message;
  const LyricsCancelledException([
    this.message = 'Lyrics request was cancelled',
  ]);

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
  LyricsCancellationToken? get activeCancellationToken =>
      _activeCancellationToken;

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
  int? get deferredGenerationToken => _deferredGenerationToken;

  final StreamController<int?> _thresholdStreamController =
      StreamController<int?>.broadcast();

  LyricsCooldownManager({DateTime Function()? nowProvider})
    : nowProvider = nowProvider ?? DateTime.now;

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
    required String trackFilePath,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    final effectivePath = trackFilePath;
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
    required String trackFilePath,
    required int token,
    required Future<void> Function() onRetry,
  }) {
    if (!isCooldownActive) return;
    final effectivePath = trackFilePath;
    _deferredTrackFilePath = effectivePath;
    _deferredGenerationToken = token;
    _deferredCallback = onRetry;

    // If timer is not running or completed, schedule a new timer for the remaining duration
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
