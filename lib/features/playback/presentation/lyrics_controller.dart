import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/services/lrc_parser.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'playback_controller.dart';

/// State Controller managing lyrics fetching, visibility gating, rapid skip token cancellation,
/// 429 threshold countdown and cooldown deferred upgrades, translation, O(log n) synchronization,
/// auto-scrolling, manual scroll lock with 5-second auto-resume timer, and tap-to-seek.
class LyricsController extends ChangeNotifier {
  final LyricsService lyricsService;
  final PlaybackController playbackController;
  final LyricsCooldownManager cooldownManager;
  final LyricsTranslationClient translationClient;

  final ScrollController scrollController = ScrollController();

  // Visibility state: remote web queries execute ONLY when _isLyricsViewVisible == true.
  bool _isLyricsViewVisible = false;

  // Generation & Concurrency Token Tracker
  final LyricsGenerationTracker _generationTracker = LyricsGenerationTracker();
  LyricsCancellationToken? _currentCancellationToken;

  // Playback & Lyrics state
  ParsedLrc? _lyrics;
  LyricsSource? _currentLyricsSource;
  bool _isLoading = false;
  String? _errorMessage;
  int _currentIndex = 0;
  String? _currentTrackFilePath;

  // Source configuration flags
  bool _enableLocalSources = true;
  bool _enableLrclib = true;
  bool _enableLyricsOvh = true;

  // Translation State
  bool _isTranslated = false;
  bool _isInterleaved = false;
  bool _isTranslating = false;
  List<String> _translatedLines = const [];
  String? _translationError;

  // Manual scroll lock state
  bool _isUserScrollLocked = false;
  Timer? _userScrollLockTimer;
  static const Duration scrollLockDuration = Duration(seconds: 5);

  // User calibration offset in ms (+/-)
  int _userOffsetMs = 0;

  bool _isDisposed = false;

  LyricsController({
    required this.lyricsService,
    required this.playbackController,
    LyricsCooldownManager? cooldownManager,
    LyricsTranslationClient? translationClient,
  })  : cooldownManager = cooldownManager ?? lyricsService.cooldownManager,
        translationClient = translationClient ?? LyricsTranslationClient() {
    playbackController.addListener(_onPlaybackUpdated);
    playbackController.positionListenable.addListener(_onPositionUpdated);
    _onPlaybackUpdated();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  bool get isLyricsViewVisible => _isLyricsViewVisible;

  ParsedLrc? get lyrics => _lyrics;
  List<LyricLine> get lines => _lyrics?.lines ?? const [];
  bool get isSynced => _lyrics?.isSynced ?? false;
  bool get hasLyrics => _lyrics != null && _lyrics!.isNotEmpty;
  LyricsSource? get currentLyricsSource => _currentLyricsSource;
  LyricsSource? get source => _currentLyricsSource;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentIndex => _currentIndex;
  bool get isUserScrollLocked => _isUserScrollLocked;
  int get userOffsetMs => _userOffsetMs;

  bool get enableLocalSources => _enableLocalSources;
  bool get enableLrclib => _enableLrclib;
  bool get enableLyricsOvh => _enableLyricsOvh;

  bool get isTranslated => _isTranslated;
  bool get isInterleaved => _isInterleaved;
  bool get isTranslating => _isTranslating;
  List<String> get translatedLines => _translatedLines;
  String? get translationError => _translationError;

  LyricsDisplayMode get displayMode {
    if (!_isTranslated) return LyricsDisplayMode.original;
    return _isInterleaved
        ? LyricsDisplayMode.interleaved
        : LyricsDisplayMode.translated;
  }

  /// Builds effective display lines according to active [displayMode],
  /// safeguarding against length mismatches between original and translated lines.
  List<LyricLine> get effectiveDisplayLines {
    if (_lyrics == null) return const [];
    final originalLines = _lyrics!.lines;
    if (displayMode == LyricsDisplayMode.original || _translatedLines.isEmpty) {
      return originalLines;
    }

    if (displayMode == LyricsDisplayMode.translated) {
      return List.generate(originalLines.length, (i) {
        final original = originalLines[i];
        final trans = (i < _translatedLines.length && _translatedLines[i].isNotEmpty)
            ? _translatedLines[i]
            : original.text;
        return original.copyWith(text: trans, translation: trans);
      });
    }

    // Interleaved mode: original line followed by translation line
    final interleaved = <LyricLine>[];
    for (int i = 0; i < originalLines.length; i++) {
      final original = originalLines[i];
      final trans = (i < _translatedLines.length && _translatedLines[i].isNotEmpty)
          ? _translatedLines[i]
          : null;
      interleaved.add(original.copyWith(translation: trans));
      if (trans != null) {
        interleaved.add(
          LyricLine(
            timestampMs: original.timestampMs,
            text: trans,
            isSynced: false,
            translation: trans,
          ),
        );
      }
    }
    return interleaved;
  }

  bool get isThresholdWaiting => cooldownManager.isThresholdWaiting;
  int? get thresholdCountdownSeconds =>
      cooldownManager.thresholdCountdownSeconds;
  Stream<int?> get thresholdStream => cooldownManager.thresholdStream;
  bool get isCooldownActive => cooldownManager.isCooldownActive;

  LyricLine? get currentLine {
    if (_lyrics == null || _currentIndex < 0 || _currentIndex >= lines.length) {
      return null;
    }
    return lines[_currentIndex];
  }

  // ---------------------------------------------------------------------------
  // Visibility Lifecycle Hook
  // ---------------------------------------------------------------------------
  void setLyricsViewVisible(bool visible) {
    if (_isLyricsViewVisible == visible) return;
    _isLyricsViewVisible = visible;

    if (!visible) {
      // 1. Cancel in-flight cancellation token
      _cancelInFlight();

      // 2. Dismiss active 429 threshold countdown
      cooldownManager.cancelThresholdCountdown();

      // 3. Cancel any pending deferred upgrade retry
      cooldownManager.cancelDeferredRetry();

      // 4. Reset loading indicator if a remote fetch was interrupted
      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
    } else {
      notifyListeners();
      // 4. View opened: ensure lyrics are loaded on-demand for active track
      if (playbackController.currentTrack != null) {
        if (_lyrics == null ||
            (_currentLyricsSource != null && _currentLyricsSource!.isLocal)) {
          ensureLyricsLoaded();
        }
      }
    }
  }

  void _cancelInFlight() {
    _currentCancellationToken?.cancel();
    _currentCancellationToken = null;
    _generationTracker.cancelCurrent();
  }

  // ---------------------------------------------------------------------------
  // Playback Listener & Active Line Resolution
  // ---------------------------------------------------------------------------
  void _onPlaybackUpdated() {
    if (_isDisposed) return;

    final track = playbackController.currentTrack;
    final trackFilePath = track?.filePath;

    // 1. Check for track transition
    if (trackFilePath != _currentTrackFilePath) {
      _currentTrackFilePath = trackFilePath;
      _resetScrollLock();
      _currentIndex = 0;
      _translatedLines = const [];
      _isTranslated = false;
      _isInterleaved = false;
      _translationError = null;

      // Cancel any active threshold waiting for prior track
      cooldownManager.cancelThresholdCountdown();

      // Mint new token and cancel previous token immediately
      final token = _generationTracker.nextGeneration();
      _currentCancellationToken = token;

      if (_isLyricsViewVisible) {
        // View is visible: load full 4-tier lyrics immediately
        _loadLyricsForTrack(track, token);
      } else {
        // View is NOT visible: passive background playback
        // Clear remote lyrics, resolve local only with fresh token
        _lyrics = null;
        _currentLyricsSource = null;
        _isLoading = false;
        _errorMessage = null;

        if (track != null && _enableLocalSources) {
          _resolveLocalSourcesOnly(track, token);
        } else {
          notifyListeners();
        }
      }
      return;
    }

    // 2. Resolve active lyric line based on current playback position
    _updateActiveLyricLine();
  }

  void _onPositionUpdated() {
    if (_isDisposed) return;
    _updateActiveLyricLine();
  }

  void _updateActiveLyricLine() {
    if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
      final effectivePos =
          playbackController.position + Duration(milliseconds: _userOffsetMs);
      final newIndex = _lyrics!.activeIndexAt(effectivePos);

      if (newIndex != _currentIndex && newIndex >= 0) {
        _currentIndex = newIndex;
        notifyListeners();

        // Perform animated auto-scroll if user has not engaged manual scroll lock
        if (!_isUserScrollLocked && _isLyricsViewVisible) {
          _scrollToIndex(_currentIndex, animated: true);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // On-Demand Lyrics Loading
  // ---------------------------------------------------------------------------
  Future<void> ensureLyricsLoaded({bool forceRefresh = false}) async {
    final track = playbackController.currentTrack;
    if (track == null) return;

    if (!forceRefresh &&
        _currentTrackFilePath == track.filePath &&
        _lyrics != null &&
        _lyrics!.isNotEmpty &&
        _currentLyricsSource != null &&
        !_currentLyricsSource!.isLocal) {
      return;
    }

    final token = _generationTracker.nextGeneration();
    _currentCancellationToken = token;
    await _loadLyricsForTrack(track, token, forceRefresh: forceRefresh);
  }

  Future<void> _resolveLocalSourcesOnly(
    QueueItem track,
    LyricsCancellationToken token,
  ) async {
    try {
      final result = await lyricsService.resolveLocalLyricsOnly(track);
      if (_isDisposed ||
          token.isCancelled ||
          !_generationTracker.isCurrent(_generationTracker.activeToken)) {
        return;
      }
      if (_currentTrackFilePath != track.filePath) return;

      if (result != null) {
        _lyrics = result.lyrics;
        _currentLyricsSource = result.source;
        _currentIndex = 0;
        if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
          _currentIndex = _lyrics!.activeIndexAt(playbackController.position);
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadLyricsForTrack(
    QueueItem? track,
    LyricsCancellationToken token, {
    bool forceRefresh = false,
  }) async {
    _resetScrollLock();
    _currentIndex = 0;

    if (track == null) {
      _lyrics = null;
      _currentLyricsSource = null;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final effectiveSources = <LyricsSource>{
        if (_enableLocalSources) ...[LyricsSource.embedded, LyricsSource.file],
        if (_enableLrclib) LyricsSource.lrclib,
        if (_enableLyricsOvh) LyricsSource.lyricsOvh,
      };

      final result = await lyricsService.resolveLyricsByFilePath(
        filePath: track.filePath,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration.inMilliseconds,
        embeddedLyrics: track.extras['lyrics'] as String?,
        allowRemote: _isLyricsViewVisible,
        forceRefresh: forceRefresh,
        enabledSources: effectiveSources,
        cancellationToken: token,
        onThresholdCountdown: (seconds) {
          if (_isDisposed || token.isCancelled) return;
          cooldownManager.startThresholdCountdown(
            seconds: seconds,
            onAutoRetry: () async {
              if (_isDisposed || !_isLyricsViewVisible) return;
              if (_currentTrackFilePath == track.filePath &&
                  _generationTracker
                      .isCurrent(_generationTracker.activeToken)) {
                final retryToken = _generationTracker.nextGeneration();
                _currentCancellationToken = retryToken;
                await _loadLyricsForTrack(track, retryToken);
              }
            },
            isStillValid: () =>
                !_isDisposed &&
                _isLyricsViewVisible &&
                _currentTrackFilePath == track.filePath &&
                _generationTracker.isCurrent(_generationTracker.activeToken),
          );
          notifyListeners();
        },
      );

      // Concurrency check: discard if token was cancelled or generation changed
      if (_isDisposed ||
          token.isCancelled ||
          !_generationTracker.isCurrent(_generationTracker.activeToken)) {
        return;
      }

      if (_currentTrackFilePath != track.filePath) {
        return;
      }

      _lyrics = result?.lyrics;
      _currentLyricsSource = result?.source;
      _isLoading = false;
      _currentIndex = 0;

      if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
        _currentIndex = _lyrics!.activeIndexAt(playbackController.position);
      }

      notifyListeners();

      // Center initial line after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && !_isUserScrollLocked && _isLyricsViewVisible) {
          _scrollToIndex(_currentIndex, animated: false);
        }
      });

      // Schedule deferred upgrade if plain text fallback is currently used during cooldown
      if (_currentLyricsSource == LyricsSource.lyricsOvh &&
          cooldownManager.isCooldownActive &&
          _enableLrclib) {
        cooldownManager.scheduleDeferredRetry(
          trackFilePath: track.filePath,
          token: _generationTracker.activeToken,
          onRetry: () async {
            if (_isDisposed || !_isLyricsViewVisible) return;
            if (_currentTrackFilePath == track.filePath &&
                _generationTracker.isCurrent(_generationTracker.activeToken) &&
                (_currentLyricsSource == null ||
                    !_currentLyricsSource!.isLocal)) {
              final upgradeToken = _generationTracker.nextGeneration();
              _currentCancellationToken = upgradeToken;
              await _loadLyricsForTrack(track, upgradeToken, forceRefresh: true);
            }
          },
        );
      }
    } catch (e) {
      if (_isDisposed ||
          token.isCancelled ||
          !_generationTracker.isCurrent(_generationTracker.activeToken)) {
        return;
      }
      _lyrics = null;
      _currentLyricsSource = null;
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sources Config & Manual Re-search
  // ---------------------------------------------------------------------------
  void setSourcesConfig({bool? local, bool? lrclib, bool? lyricsOvh}) {
    if (local != null) _enableLocalSources = local;
    if (lrclib != null) _enableLrclib = lrclib;
    if (lyricsOvh != null) _enableLyricsOvh = lyricsOvh;

    if (_enableLrclib == false) {
      cooldownManager.cancelThresholdCountdown();
      cooldownManager.cancelDeferredRetry();
    }
    notifyListeners();
  }

  Future<void> forceReSearch() async {
    final track = playbackController.currentTrack;
    if (track == null) return;
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
    final token = _generationTracker.nextGeneration();
    _currentCancellationToken = token;
    await _loadLyricsForTrack(track, token, forceRefresh: true);
  }

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------
  Future<void> translateLyrics({String targetLanguage = 'es'}) async {
    if (_lyrics == null || lines.isEmpty) return;
    _isTranslating = true;
    _translationError = null;
    notifyListeners();

    try {
      final originalTexts = lines.map((l) => l.text).toList();
      final result = await translationClient.translate(
        originalTexts,
        targetLanguage: targetLanguage,
      );
      if (_isDisposed) return;
      _isTranslating = false;
      if (result.isSuccess) {
        _translatedLines = result.translatedLines;
        _isTranslated = true;
      } else {
        _translationError = result.errorMessage;
      }
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;
      _isTranslating = false;
      _translationError = e.toString();
      notifyListeners();
    }
  }

  void setTranslationDisplayMode(LyricsDisplayMode mode) {
    switch (mode) {
      case LyricsDisplayMode.original:
        _isTranslated = false;
        _isInterleaved = false;
        break;
      case LyricsDisplayMode.translated:
        _isTranslated = true;
        _isInterleaved = false;
        if (_translatedLines.isEmpty && !_isTranslating && hasLyrics) {
          translateLyrics();
        }
        break;
      case LyricsDisplayMode.interleaved:
        _isTranslated = true;
        _isInterleaved = true;
        if (_translatedLines.isEmpty && !_isTranslating && hasLyrics) {
          translateLyrics();
        }
        break;
    }
    notifyListeners();
  }

  /// Cycles translation modes: original -> translated -> interleaved -> original.
  ///
  /// Automatically fetches translation via [translateLyrics] if not already cached.
  Future<void> toggleTranslation() async {
    if (!_isTranslated) {
      _isTranslated = true;
      _isInterleaved = false;
      notifyListeners();
      if (_translatedLines.isEmpty && !_isTranslating && hasLyrics) {
        await translateLyrics();
      }
    } else if (!_isInterleaved) {
      _isInterleaved = true;
      notifyListeners();
      if (_translatedLines.isEmpty && !_isTranslating && hasLyrics) {
        await translateLyrics();
      }
    } else {
      _isTranslated = false;
      _isInterleaved = false;
      notifyListeners();
    }
  }

  void toggleInterleaved() {
    _isInterleaved = !_isInterleaved;
    notifyListeners();
  }

  /// Dismisses active threshold countdown and aborts auto-retry timer.
  void dismissThresholdBanner() {
    cooldownManager.cancelThresholdCountdown();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Tap-to-Seek
  // ---------------------------------------------------------------------------
  Future<void> seekToLine(int index) async {
    if (_lyrics == null || index < 0 || index >= lines.length) return;
    final line = lines[index];
    if (!line.isSynced) return;

    // Seek audio playback to timestamp
    await playbackController.seek(line.timestamp);

    // Release scroll lock and center immediately
    _resetScrollLock();
    _currentIndex = index;
    notifyListeners();
    _scrollToIndex(index, animated: true);
  }

  // ---------------------------------------------------------------------------
  // Auto-Scroll & Viewport Centering Math
  // ---------------------------------------------------------------------------
  void _scrollToIndex(int index, {bool animated = true}) {
    if (!scrollController.hasClients) return;
    if (lines.isEmpty || index < 0 || index >= lines.length) return;

    const double estimatedLineHeight = 56.0;
    final viewportHeight = scrollController.position.viewportDimension;
    final targetOffset =
        (index * estimatedLineHeight) -
        (viewportHeight / 2) +
        (estimatedLineHeight / 2);

    final clampedOffset = targetOffset.clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );

    if (animated) {
      scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      scrollController.jumpTo(clampedOffset);
    }
  }

  // ---------------------------------------------------------------------------
  // User Manual Scroll Lock (5-Second Timer Protocol)
  // ---------------------------------------------------------------------------
  void onUserScroll() {
    if (!_isUserScrollLocked) {
      _isUserScrollLocked = true;
      notifyListeners();
    }

    _userScrollLockTimer?.cancel();
    _userScrollLockTimer = Timer(scrollLockDuration, () {
      if (_isDisposed) return;
      _isUserScrollLocked = false;
      notifyListeners();
      _scrollToIndex(_currentIndex, animated: true);
    });
  }

  void resumeAutoScroll() {
    _resetScrollLock();
    _scrollToIndex(_currentIndex, animated: true);
  }

  void _resetScrollLock() {
    _userScrollLockTimer?.cancel();
    _userScrollLockTimer = null;
    if (_isUserScrollLocked) {
      _isUserScrollLocked = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // User Offset Calibration
  // ---------------------------------------------------------------------------
  void adjustOffset(int deltaMs) {
    _userOffsetMs += deltaMs;
    _onPlaybackUpdated();
    notifyListeners();
  }

  void resetOffset() {
    _userOffsetMs = 0;
    _onPlaybackUpdated();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle & Resource Cleanup
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _isDisposed = true;
    _cancelInFlight();
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
    playbackController.removeListener(_onPlaybackUpdated);
    playbackController.positionListenable.removeListener(_onPositionUpdated);
    _userScrollLockTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }
}
