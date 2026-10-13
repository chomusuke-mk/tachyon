import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/backend/services/lrc_parser.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

import 'playback_controller.dart';

/// State controller for the lyrics panel.
///
/// Responsibilities (UI-agnostic, no scrolling math):
/// - On-demand loading gated by [isLyricsViewVisible], with generation tokens so
///   rapid skips (1 → 2 → 3 → 4 → 5) only resolve the final track.
/// - 429 threshold countdown and cooldown deferred upgrades.
/// - Phase 2 translation.
/// - Active line resolution in O(log n): [currentIndex] is always derived from
///   the playback position by [_syncIndex], whatever the lyrics source was.
/// - Manual scroll lock flag. Centering the active line is done by `LyricsView`,
///   which owns the scroll position and measures the real rendered lines.
class LyricsController extends ChangeNotifier {
  final TachyonBackendClient backendClient;
  final PlaybackController playbackController;
  final LyricsCooldownManager cooldownManager;
  final SettingsRepository settingsRepository;
  final String Function()? localeSupplier;

  final LyricsGenerationTracker _generationTracker = LyricsGenerationTracker();
  LyricsCancellationToken? _translationToken;

  bool _isLyricsViewVisible = false;
  String? _currentTrackFilePath;

  // Active lyrics (strictly O(1) RAM: single active track).
  ParsedLrc? _lyrics;
  LyricsSource? _currentLyricsSource;
  int? _currentLyricsId;
  String? _currentLyricsLang;
  bool _isLoading = false;
  String? _errorMessage;
  int _currentIndex = 0;

  // Source configuration flags.
  bool _enableLocalSources = true;
  bool _enableLrclib = true;
  bool _enableLyricsOvh = true;

  // Translation state.
  LyricsDisplayMode _displayMode;
  bool _isTranslating = false;
  List<String> _translatedLines = const [];
  String? _translationError;

  bool _isUserScrollLocked = false;
  int _userOffsetMs = 0;
  bool _isDisposed = false;

  LyricsController({
    required this.backendClient,
    required this.playbackController,
    required this.settingsRepository,
    this.localeSupplier,
    LyricsCooldownManager? cooldownManager,
  }) : cooldownManager = cooldownManager ?? LyricsCooldownManager(),
       _displayMode = settingsRepository.getLyricsDisplayMode() {
    playbackController.addListener(_onPlaybackUpdated);
    playbackController.positionListenable.addListener(_syncIndex);
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
  int? get currentLyricsId => _currentLyricsId;
  String? get currentLyricsLang => _currentLyricsLang;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentIndex => _currentIndex;
  bool get isUserScrollLocked => _isUserScrollLocked;
  int get userOffsetMs => _userOffsetMs;

  bool get enableLocalSources => _enableLocalSources;
  bool get enableLrclib => _enableLrclib;
  bool get enableLyricsOvh => _enableLyricsOvh;

  LyricsDisplayMode get displayMode => _displayMode;
  bool get isTranslated => _displayMode != LyricsDisplayMode.original;
  bool get isInterleaved => _displayMode == LyricsDisplayMode.interleaved;
  bool get isTranslating => _isTranslating;
  List<String> get translatedLines => _translatedLines;
  String? get translationError => _translationError;

  bool get isThresholdWaiting => cooldownManager.isThresholdWaiting;
  int? get thresholdCountdownSeconds =>
      cooldownManager.thresholdCountdownSeconds;
  Stream<int?> get thresholdStream => cooldownManager.thresholdStream;
  bool get isCooldownActive => cooldownManager.isCooldownActive;

  LyricLine? get currentLine {
    if (_currentIndex < 0 || _currentIndex >= lines.length) return null;
    return lines[_currentIndex];
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------
  /// Notifies listeners, deferring to the end of the frame when called while
  /// the widget tree is building.
  void _notify() {
    if (_isDisposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _notify());
      return;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Visibility lifecycle
  // ---------------------------------------------------------------------------
  /// Remote queries only run while the lyrics view is visible.
  void setLyricsViewVisible(bool visible) {
    if (_isDisposed) return;
    final changed = _isLyricsViewVisible != visible;
    _isLyricsViewVisible = visible;

    if (!visible) {
      if (!changed) return;
      _isUserScrollLocked = false;
      _cancelInFlight();
      cooldownManager.cancelThresholdCountdown();
      cooldownManager.cancelDeferredRetry();
      _isLoading = false;
      _notify();
      return;
    }

    if (changed) _isUserScrollLocked = false;
    if (playbackController.currentTrack != null &&
        _lyrics == null &&
        !_isLoading) {
      ensureLyricsLoaded();
      return;
    }
    _syncIndex(forceNotify: changed);
  }

  /// Called when `LyricsView` mounts (player opened / un-minimized).
  void onLyricsViewMounted() => setLyricsViewVisible(true);

  void _cancelInFlight() {
    _generationTracker.cancelCurrent();
    _cancelTranslation();
  }

  void _cancelTranslation() {
    _translationToken?.cancel();
    _translationToken = null;
    _isTranslating = false;
  }

  // ---------------------------------------------------------------------------
  // Playback listener & active line resolution
  // ---------------------------------------------------------------------------
  void _onPlaybackUpdated() {
    if (_isDisposed) return;
    final track = playbackController.currentTrack;
    if (track?.filePath == _currentTrackFilePath) {
      _syncIndex();
      return;
    }

    // Track transition: drop everything that belongs to the previous track.
    _currentTrackFilePath = track?.filePath;
    _isUserScrollLocked = false;
    _clearLyrics();
    _displayMode = settingsRepository.getLyricsDisplayMode();
    cooldownManager.cancelThresholdCountdown();

    if (_isLyricsViewVisible && track != null) {
      _loadLyricsForTrack(track, _generationTracker.nextGeneration());
    } else {
      // Not visible: 100% demand-driven, never query in the background.
      _generationTracker.cancelCurrent();
      _isLoading = false;
      _notify();
    }
  }

  void _clearLyrics() {
    _cancelTranslation();
    _lyrics = null;
    _currentLyricsSource = null;
    _currentLyricsId = null;
    _currentLyricsLang = null;
    _translatedLines = const [];
    _translationError = null;
    _errorMessage = null;
    _currentIndex = 0;
  }

  /// Single source of truth for [currentIndex]: derived from the live playback
  /// position for whatever lyrics are currently loaded.
  void _syncIndex({bool forceNotify = false}) {
    if (_isDisposed) return;
    final lyrics = _lyrics;
    var changed = false;
    if (lyrics != null && lyrics.isSynced && lyrics.isNotEmpty) {
      final index = lyrics.activeIndexAt(
        playbackController.position + Duration(milliseconds: _userOffsetMs),
      );
      if (index >= 0 && index != _currentIndex) {
        _currentIndex = index;
        changed = true;
      }
    }
    if (changed || forceNotify) _notify();
  }

  // ---------------------------------------------------------------------------
  // On-demand lyrics loading
  // ---------------------------------------------------------------------------
  Future<void> ensureLyricsLoaded({bool forceRefresh = false}) async {
    final track = playbackController.currentTrack;
    if (track == null) return;
    if (!forceRefresh &&
        _currentTrackFilePath == track.filePath &&
        (_isLoading || hasLyrics)) {
      return;
    }
    await _loadLyricsForTrack(
      track,
      _generationTracker.nextGeneration(),
      forceRefresh: forceRefresh,
    );
  }

  bool _isStale(LyricsCancellationToken token, Track track) =>
      _isDisposed ||
      token.isCancelled ||
      _currentTrackFilePath != track.filePath;

  Future<void> _loadLyricsForTrack(
    Track track,
    LyricsCancellationToken token, {
    bool forceRefresh = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final result = await backendClient.resolveLyrics(
        trackId: track.id ?? 0,
        filePath: track.filePath,
        title: track.title,
        artist: track.artists.map((a) => a.name).join(', '),
        album: track.album?.name,
        durationMs: track.duration.inMilliseconds,
        allowRemote: _isLyricsViewVisible,
        bypassCache: forceRefresh,
        allowedSources: {
          if (_enableLocalSources) ...[LyricsSource.embedded, LyricsSource.file],
          if (_enableLrclib) LyricsSource.lrclib,
          if (_enableLyricsOvh) LyricsSource.lyricsOvh,
        },
        cancellationToken: token,
        onThresholdCountdown: (seconds) {
          if (_isStale(token, track)) return;
          _startThresholdCountdown(track, seconds);
        },
      );
      if (_isStale(token, track)) return;
      _applyResult(result);
      _scheduleDeferredUpgradeIfNeeded(track);
    } catch (e) {
      if (_isStale(token, track)) return;
      _clearLyrics();
      _isLoading = false;
      _errorMessage = e.toString();
      _notify();
    }
  }

  /// Applies a resolved result. Every source (DB cache, `.lrc`, embedded or a
  /// remote API) goes through here, so the active line is always computed from
  /// the live position at the moment the lyrics become available.
  void _applyResult(LyricsResult? result) {
    _clearLyrics();
    _lyrics = result?.lyrics;
    _currentLyricsSource = result?.source;
    _currentLyricsId = result?.lyricsId;
    _currentLyricsLang = result?.lang;
    _isLoading = false;
    _syncIndex(forceNotify: true);

    if (isTranslated && _currentLyricsId != null && hasLyrics) {
      _loadOrFetchTranslation();
    }
  }

  void _startThresholdCountdown(Track track, int seconds) {
    bool stillValid() =>
        !_isDisposed &&
        _isLyricsViewVisible &&
        _currentTrackFilePath == track.filePath;
    cooldownManager.startThresholdCountdown(
      seconds: seconds,
      isStillValid: stillValid,
      onAutoRetry: () async {
        if (!stillValid()) return;
        await _loadLyricsForTrack(track, _generationTracker.nextGeneration());
      },
    );
    _notify();
  }

  /// While lrclib is in cooldown the plain-text fallback is shown; retry the
  /// synced source once the cooldown expires if the track is still active.
  void _scheduleDeferredUpgradeIfNeeded(Track track) {
    if (_currentLyricsSource != LyricsSource.lyricsOvh ||
        !cooldownManager.isCooldownActive ||
        !_enableLrclib) {
      return;
    }
    cooldownManager.scheduleDeferredRetry(
      trackFilePath: track.filePath,
      token: _generationTracker.activeToken,
      onRetry: () async {
        if (_isDisposed ||
            !_isLyricsViewVisible ||
            _currentTrackFilePath != track.filePath ||
            (_currentLyricsSource?.isLocal ?? false)) {
          return;
        }
        await _loadLyricsForTrack(
          track,
          _generationTracker.nextGeneration(),
          forceRefresh: true,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Sources config & manual re-search
  // ---------------------------------------------------------------------------
  void setSourcesConfig({bool? local, bool? lrclib, bool? lyricsOvh}) {
    if (local != null) _enableLocalSources = local;
    if (lrclib != null) _enableLrclib = lrclib;
    if (lyricsOvh != null) _enableLyricsOvh = lyricsOvh;

    if (!_enableLrclib) {
      cooldownManager.cancelThresholdCountdown();
      cooldownManager.cancelDeferredRetry();
    }
    _notify();
  }

  Future<void> forceReSearch() async {
    final track = playbackController.currentTrack;
    if (track == null) return;
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
    await _loadLyricsForTrack(
      track,
      _generationTracker.nextGeneration(),
      forceRefresh: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------
  Future<void> translateLyrics({
    String? targetLanguage,
    String? sourceLanguage,
    bool force = false,
  }) => _loadOrFetchTranslation(
    targetLanguage: targetLanguage,
    sourceLanguage: sourceLanguage,
    force: force,
  );

  String _resolveTargetLang(String? targetLanguage) {
    final target =
        targetLanguage ?? settingsRepository.getLyricsTranslationTargetLang();
    return target == 'defaultOption'
        ? (localeSupplier?.call() ?? 'en')
        : target;
  }

  Future<void> _loadOrFetchTranslation({
    String? targetLanguage,
    String? sourceLanguage,
    bool force = false,
  }) async {
    final lyricsId = _currentLyricsId;
    if (!hasLyrics || lyricsId == null) return;
    if (_isTranslating && !force) return;

    final targetLang = _resolveTargetLang(targetLanguage);
    final sourceLang =
        sourceLanguage ?? settingsRepository.getLyricsTranslationSourceLang();
    final rawLines = lines.map((l) => l.text).toList();

    // Short-circuit if lyrics are already in the target language.
    final isSameLanguage =
        _currentLyricsLang == targetLang ||
        (sourceLang != 'autodetect' && sourceLang == targetLang);
    if (isSameLanguage && !force) {
      _translatedLines = rawLines;
      _translationError = null;
      _notify();
      return;
    }

    _cancelTranslation();
    final token = LyricsCancellationToken();
    _translationToken = token;
    _isTranslating = true;
    _translationError = null;
    _notify();

    try {
      final res = await backendClient
          .translateLyrics(
            lyricsId: lyricsId,
            targetLang: targetLang,
            sourceLang: sourceLang,
            rawLines: rawLines,
          )
          .timeout(const Duration(seconds: 8));
      if (_isDisposed || token.isCancelled) return;

      if (res != null) {
        _translatedLines = res;
        if (listEquals(res, rawLines)) _currentLyricsLang = targetLang;
      } else {
        _translationError = 'Failed to translate lyrics';
      }
    } catch (e) {
      if (_isDisposed || token.isCancelled) return;
      final err = e.toString();
      final lower = err.toLowerCase();
      if (e is TimeoutException || lower.contains('timed out')) {
        _translationError = 'timeout';
      } else if (err.contains('429') ||
          lower.contains('rate limit') ||
          lower.contains('too many requests')) {
        _translationError = 'rate_limit';
      } else {
        _translationError = err;
      }
    } finally {
      // A superseded call must not clear the flag of the call that replaced it.
      if (!_isDisposed && identical(_translationToken, token)) {
        _translationToken = null;
        _isTranslating = false;
        _notify();
      }
    }
  }

  void setTranslationDisplayMode(LyricsDisplayMode mode) {
    settingsRepository.setLyricsDisplayMode(mode);
    _displayMode = mode;
    if (isTranslated && _translatedLines.isEmpty) {
      _loadOrFetchTranslation();
    }
    _notify();
  }

  /// Cycles translation modes: original -> translated -> interleaved -> original.
  Future<void> toggleTranslation() async {
    setTranslationDisplayMode(switch (_displayMode) {
      LyricsDisplayMode.original => LyricsDisplayMode.translated,
      LyricsDisplayMode.translated => LyricsDisplayMode.interleaved,
      LyricsDisplayMode.interleaved => LyricsDisplayMode.original,
    });
  }

  void toggleInterleaved() {
    setTranslationDisplayMode(
      isInterleaved
          ? LyricsDisplayMode.translated
          : LyricsDisplayMode.interleaved,
    );
  }

  /// Dismisses active threshold countdown and aborts auto-retry timer.
  void dismissThresholdBanner() {
    cooldownManager.cancelThresholdCountdown();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Tap-to-seek & manual scroll lock
  // ---------------------------------------------------------------------------
  Future<void> seekToLine(int index) async {
    if (index < 0 || index >= lines.length) return;
    final line = lines[index];
    if (!line.isSynced) return;
    await playbackController.seek(line.timestamp);
    _isUserScrollLocked = false;
    _currentIndex = index;
    _notify();
  }

  void onUserScroll() {
    if (!isSynced || _isUserScrollLocked) return;
    _isUserScrollLocked = true;
    _notify();
  }

  void resumeAutoScroll() {
    if (!_isUserScrollLocked) return;
    _isUserScrollLocked = false;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // User offset calibration
  // ---------------------------------------------------------------------------
  void adjustOffset(int deltaMs) {
    _userOffsetMs += deltaMs;
    _syncIndex(forceNotify: true);
  }

  void resetOffset() {
    _userOffsetMs = 0;
    _syncIndex(forceNotify: true);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _isDisposed = true;
    _cancelInFlight();
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
    playbackController.removeListener(_onPlaybackUpdated);
    playbackController.positionListenable.removeListener(_syncIndex);
    super.dispose();
  }
}
