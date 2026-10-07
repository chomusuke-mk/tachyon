import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/backend/services/lrc_parser.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

import 'playback_controller.dart';

/// State Controller managing lyrics fetching, visibility gating, rapid skip token cancellation,
/// 429 threshold countdown and cooldown deferred upgrades, translation, O(log n) synchronization,
/// auto-scrolling, manual scroll lock with 5-second auto-resume timer, and tap-to-seek.
class LyricsController extends ChangeNotifier {
  final TachyonBackendClient backendClient;
  final PlaybackController playbackController;
  final LyricsCooldownManager cooldownManager;
  final SettingsRepository settingsRepository;
  final String Function()? localeSupplier;

  final ScrollController scrollController = ScrollController();

  // Visibility state: remote web queries execute ONLY when _isLyricsViewVisible == true.
  bool _isLyricsViewVisible = false;

  // Generation & Concurrency Token Tracker
  final LyricsGenerationTracker _generationTracker = LyricsGenerationTracker();
  LyricsCancellationToken? _currentCancellationToken;

  // Playback & Lyrics state (strictly O(1) RAM - single active track)
  ParsedLrc? _lyrics;
  LyricsSource? _currentLyricsSource;
  int? _currentLyricsId;
  String? _currentLyricsLang;
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

  // User calibration offset in ms (+/-)
  int _userOffsetMs = 0;

  bool _isDisposed = false;

  LyricsController({
    required this.backendClient,
    required this.playbackController,
    required this.settingsRepository,
    this.localeSupplier,
    LyricsCooldownManager? cooldownManager,
  }) : cooldownManager = cooldownManager ?? LyricsCooldownManager() {
    final initialMode = settingsRepository.getLyricsDisplayMode();
    _isTranslated = initialMode != LyricsDisplayMode.original;
    _isInterleaved = initialMode == LyricsDisplayMode.interleaved;
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
        final trans =
            (i < _translatedLines.length && _translatedLines[i].isNotEmpty)
            ? _translatedLines[i]
            : original.text;
        return original.copyWith(text: trans, translation: trans);
      });
    }

    // Interleaved mode: original line followed by translation line
    final interleaved = <LyricLine>[];
    for (int i = 0; i < originalLines.length; i++) {
      final original = originalLines[i];
      final trans =
          (i < _translatedLines.length && _translatedLines[i].isNotEmpty)
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
  void _safeNotifyListeners() {
    if (_isDisposed) return;
    try {
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks ||
          scheduler.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
        scheduler.addPostFrameCallback((_) {
          if (!_isDisposed) {
            notifyListeners();
          }
        });
        return;
      }
    } catch (_) {}
    notifyListeners();
  }

  void setLyricsViewVisible(bool visible) {
    if (_isDisposed) return;
    if (_isLyricsViewVisible == visible) return;
    _isLyricsViewVisible = visible;

    if (!visible) {
      _resetScrollLock();
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
      _isTranslating = false;
      _safeNotifyListeners();
    } else {
      _resetScrollLock();
      _safeNotifyListeners();
      // 4. View opened: ensure lyrics are loaded on-demand for active track
      if (playbackController.currentTrack != null) {
        if (_lyrics == null && !_isLoading) {
          ensureLyricsLoaded();
        } else {
          // Re-evaluate active line for current playback position and center immediately
          if (_lyrics!.isSynced && lines.isNotEmpty) {
            final effectivePos =
                playbackController.position +
                Duration(milliseconds: _userOffsetMs);
            final resolvedIndex = _lyrics!.activeIndexAt(effectivePos);
            if (resolvedIndex >= 0) {
              _currentIndex = resolvedIndex;
            }
          }
          _safeNotifyListeners();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_isDisposed && !_isUserScrollLocked && _isLyricsViewVisible) {
              _scrollToIndex(_currentIndex, animated: false);
            }
          });
        }
      }
    }
  }

  /// Called when [LyricsView] mounts in the widget tree (e.g. player opened/unminimized).
  void onLyricsViewMounted() {
    if (_isDisposed) return;
    _isLyricsViewVisible = true;
    _resetScrollLock();
    if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
      final effectivePos =
          playbackController.position + Duration(milliseconds: _userOffsetMs);
      final resolvedIndex = _lyrics!.activeIndexAt(effectivePos);
      if (resolvedIndex >= 0) {
        _currentIndex = resolvedIndex;
      }
      notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && !_isUserScrollLocked && _isLyricsViewVisible) {
          _scrollToIndex(_currentIndex, animated: false);
        }
      });
    } else if (playbackController.currentTrack != null &&
        _lyrics == null &&
        !_isLoading) {
      ensureLyricsLoaded();
    }
  }

  void _cancelInFlight() {
    _currentCancellationToken?.cancel();
    _currentCancellationToken = null;
    _generationTracker.cancelCurrent();
    _isTranslating = false;
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
      _lyrics = null;
      _currentLyricsSource = null;
      _currentLyricsId = null;
      _currentLyricsLang = null;
      _translatedLines = const [];
      if (scrollController.hasClients) {
        scrollController.jumpTo(0.0);
      }
      final savedMode = settingsRepository.getLyricsDisplayMode();
      _isTranslated = savedMode != LyricsDisplayMode.original;
      _isInterleaved = savedMode == LyricsDisplayMode.interleaved;
      _translationError = null;
      _isTranslating = false;

      // Cancel any active threshold waiting for prior track
      cooldownManager.cancelThresholdCountdown();

      // Mint new token and cancel previous token immediately
      final token = _generationTracker.nextGeneration();
      _currentCancellationToken = token;

      if (_isLyricsViewVisible) {
        // View is visible: load full 4-tier lyrics immediately on-demand
        _loadLyricsForTrack(track, token);
      } else {
        // View is NOT visible: 100% demand-driven; do NOT query in the background!
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
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
        final wasLargeJump = (_currentIndex - newIndex).abs() > 3;
        _currentIndex = newIndex;
        notifyListeners();

        // Perform jump to neighborhood if a large skip occurred or if current viewport
        // is far from active index, and user is not scroll-locked
        if (!_isUserScrollLocked && _isLyricsViewVisible) {
          bool needsJump = wasLargeJump;
          if (!needsJump && scrollController.hasClients) {
            final double estimatedLineHeight = _isInterleaved ? 64.0 : 42.0;
            final targetOffset = _currentIndex * estimatedLineHeight;
            final currentOffset = scrollController.offset;
            final viewportHeight =
                scrollController.position.hasViewportDimension
                ? scrollController.position.viewportDimension
                : 600.0;
            if ((currentOffset - targetOffset).abs() > (viewportHeight * 0.5)) {
              needsJump = true;
            }
          }

          if (needsJump) {
            _scrollToIndex(_currentIndex, animated: false);
          }
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
        (_isLoading || (_lyrics != null && _lyrics!.isNotEmpty))) {
      return;
    }

    final token = _generationTracker.nextGeneration();
    _currentCancellationToken = token;
    await _loadLyricsForTrack(track, token, forceRefresh: forceRefresh);
  }

  Future<void> _loadLyricsForTrack(
    Track? track,
    LyricsCancellationToken token, {
    bool forceRefresh = false,
  }) async {
    _resetScrollLock();
    _currentIndex = 0;

    if (track == null) {
      _lyrics = null;
      _currentLyricsSource = null;
      _currentLyricsId = null;
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

      // Phase 1: Resolve original lyrics via backend RPC
      final result = await backendClient.resolveLyrics(
        trackId: track.id ?? 0,
        filePath: track.filePath,
        title: track.title,
        artist: track.artists.map((a) => a.name).join(', '),
        album: track.album?.name,
        durationMs: track.duration.inMilliseconds,
        allowRemote: _isLyricsViewVisible,
        bypassCache: forceRefresh,
        allowedSources: effectiveSources,
        cancellationToken: token,
        onThresholdCountdown: (seconds) {
          if (_isDisposed || token.isCancelled) return;
          cooldownManager.startThresholdCountdown(
            seconds: seconds,
            onAutoRetry: () async {
              if (_isDisposed || !_isLyricsViewVisible) return;
              if (_currentTrackFilePath == track.filePath &&
                  _generationTracker.isCurrent(
                    _generationTracker.activeToken,
                  )) {
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

      // Store resolved original lyrics immediately
      _lyrics = result?.lyrics;
      _currentLyricsSource = result?.source;
      _currentLyricsId = result?.lyricsId;
      _currentLyricsLang = result?.lang;
      _translatedLines = const [];
      _translationError = null;
      _isLoading = false;
      _currentIndex = 0;

      if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
        _currentIndex = _lyrics!.activeIndexAt(playbackController.position);
      }

      // Render original lyrics immediately (non-blocking)
      notifyListeners();

      // Phase 2: Asynchronously trigger translation without blocking original lyrics
      if (_isTranslated &&
          _currentLyricsId != null &&
          _lyrics != null &&
          lines.isNotEmpty) {
        _loadOrFetchTranslation(token: token);
      }

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
              await _loadLyricsForTrack(
                track,
                upgradeToken,
                forceRefresh: true,
              );
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
      _currentLyricsId = null;
      _currentLyricsLang = null;
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
    _translatedLines = const [];
    _currentLyricsId = null;
    _currentLyricsLang = null;
    _translationError = null;
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
    final token = _generationTracker.nextGeneration();
    _currentCancellationToken = token;
    await _loadLyricsForTrack(track, token, forceRefresh: true);
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

  Future<void> _loadOrFetchTranslation({
    String? targetLanguage,
    String? sourceLanguage,
    LyricsCancellationToken? token,
    bool force = false,
  }) async {
    if (_lyrics == null || lines.isEmpty) return;
    if (_isTranslating && !force) return;
    if (_isTranslating && force) {
      _cancelInFlight();
    }
    final lyricsId = _currentLyricsId;
    if (lyricsId == null) return;

    final String targetLang;
    if (targetLanguage != null) {
      targetLang = targetLanguage == 'defaultOption'
          ? (localeSupplier?.call() ?? 'en')
          : targetLanguage;
    } else {
      final savedTarget = settingsRepository.getLyricsTranslationTargetLang();
      targetLang = savedTarget == 'defaultOption'
          ? (localeSupplier?.call() ?? 'en')
          : savedTarget;
    }
    final sourceLang =
        sourceLanguage ?? settingsRepository.getLyricsTranslationSourceLang();
    final callToken =
        token ??
        _currentCancellationToken ??
        _generationTracker.nextGeneration();
    _currentCancellationToken = callToken;

    // Short-circuit if lyrics are already in target language
    final isSameLanguage =
        (_currentLyricsLang != null && _currentLyricsLang == targetLang) ||
        (sourceLang != 'autodetect' && sourceLang == targetLang);

    if (isSameLanguage && !force) {
      _translatedLines = lines.map((l) => l.text).toList();
      _translationError = null;
      _safeNotifyListeners();
      return;
    }

    _isTranslating = true;
    _translationError = null;
    notifyListeners();

    try {
      final rawLines = lines.map((l) => l.text).toList();
      final res = await backendClient
          .translateLyrics(
            lyricsId: lyricsId,
            targetLang: targetLang,
            sourceLang: sourceLang,
            rawLines: rawLines,
          )
          .timeout(const Duration(seconds: 8));

      if (_isDisposed) return;
      if (callToken.isCancelled) {
        return;
      }

      if (res != null) {
        _translatedLines = res;
        _translationError = null;
        if (res.length == rawLines.length &&
            List.generate(
              res.length,
              (i) => res[i] == rawLines[i],
            ).every((b) => b)) {
          _currentLyricsLang = targetLang;
        }
      } else {
        _translationError = 'Failed to translate lyrics';
      }
    } catch (e) {
      if (_isDisposed) return;
      if (callToken.isCancelled) {
        return;
      }
      final err = e.toString();
      if (e is TimeoutException ||
          err.contains('TimeoutException') ||
          err.contains('timed out')) {
        _translationError = 'timeout';
      } else if (err.contains('429') ||
          err.toLowerCase().contains('rate limit') ||
          err.toLowerCase().contains('too many requests')) {
        _translationError = 'rate_limit';
      } else {
        _translationError = err;
      }
    } finally {
      if (!_isDisposed) {
        _isTranslating = false;
        notifyListeners();
      }
    }
  }

  void setTranslationDisplayMode(LyricsDisplayMode mode) {
    settingsRepository.setLyricsDisplayMode(mode);
    switch (mode) {
      case LyricsDisplayMode.original:
        _isTranslated = false;
        _isInterleaved = false;
        break;
      case LyricsDisplayMode.translated:
        _isTranslated = true;
        _isInterleaved = false;
        if (_translatedLines.isEmpty &&
            !_isTranslating &&
            hasLyrics &&
            _currentLyricsId != null) {
          _loadOrFetchTranslation();
        }
        break;
      case LyricsDisplayMode.interleaved:
        _isTranslated = true;
        _isInterleaved = true;
        if (_translatedLines.isEmpty &&
            !_isTranslating &&
            hasLyrics &&
            _currentLyricsId != null) {
          _loadOrFetchTranslation();
        }
        break;
    }
    notifyListeners();
  }

  /// Cycles translation modes: original -> translated -> interleaved -> original.
  ///
  /// Automatically fetches translation via [_loadOrFetchTranslation] if not already cached.
  Future<void> toggleTranslation() async {
    if (!_isTranslated) {
      setTranslationDisplayMode(LyricsDisplayMode.translated);
      if (_translatedLines.isEmpty && hasLyrics && _currentLyricsId != null) {
        await _loadOrFetchTranslation();
      }
    } else if (!_isInterleaved) {
      setTranslationDisplayMode(LyricsDisplayMode.interleaved);
      if (_translatedLines.isEmpty && hasLyrics && _currentLyricsId != null) {
        await _loadOrFetchTranslation();
      }
    } else {
      setTranslationDisplayMode(LyricsDisplayMode.original);
    }
  }

  void toggleInterleaved() {
    if (_isInterleaved) {
      setTranslationDisplayMode(LyricsDisplayMode.translated);
    } else {
      setTranslationDisplayMode(LyricsDisplayMode.interleaved);
    }
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

    final double estimatedLineHeight = _isInterleaved ? 64.0 : 42.0;
    final targetOffset = index * estimatedLineHeight;

    // Do NOT clamp to scrollController.position.maxScrollExtent,
    // because in a lazy ListView.builder, maxScrollExtent only reflects
    // already-laid-out items and expands as layout advances!
    final double maxPossibleScroll = lines.length * estimatedLineHeight;
    final clampedOffset = targetOffset.clamp(0.0, maxPossibleScroll);

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
  // User Manual Scroll Lock Protocol
  // ---------------------------------------------------------------------------
  void onUserScroll() {
    if (!isSynced) return;
    if (!_isUserScrollLocked) {
      _isUserScrollLocked = true;
      notifyListeners();
    }
  }

  void resumeAutoScroll() {
    _resetScrollLock();
    _scrollToIndex(_currentIndex, animated: true);
  }

  void _resetScrollLock() {
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
    scrollController.dispose();
    super.dispose();
  }
}
