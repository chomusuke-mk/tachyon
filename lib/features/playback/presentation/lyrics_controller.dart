import 'dart:async';
import 'package:flutter/material.dart';
import 'playback_controller.dart';
import '../../../core/services/lrc_parser.dart';
import '../../../core/services/lyrics_service.dart';
import '../domain/lyric_line.dart';
import '../domain/queue_item.dart';

/// State Controller managing lyrics fetching, O(log n) synchronization,
/// auto-scrolling, manual scroll lock with 5-second auto-resume timer, and tap-to-seek.
class LyricsController extends ChangeNotifier {
  final LyricsService lyricsService;
  final PlaybackController playbackController;

  final ScrollController scrollController = ScrollController();

  ParsedLrc? _lyrics;
  bool _isLoading = false;
  String? _errorMessage;
  int _currentIndex = 0;
  String? _currentTrackUri;

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
  }) {
    playbackController.addListener(_onPlaybackUpdated);
    _onPlaybackUpdated();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  ParsedLrc? get lyrics => _lyrics;
  List<LyricLine> get lines => _lyrics?.lines ?? const [];
  bool get isSynced => _lyrics?.isSynced ?? false;
  bool get hasLyrics => _lyrics != null && _lyrics!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentIndex => _currentIndex;
  bool get isUserScrollLocked => _isUserScrollLocked;
  int get userOffsetMs => _userOffsetMs;

  LyricLine? get currentLine {
    if (_lyrics == null || _currentIndex < 0 || _currentIndex >= lines.length) {
      return null;
    }
    return lines[_currentIndex];
  }

  // ---------------------------------------------------------------------------
  // Playback Listener & Active Line Resolution
  // ---------------------------------------------------------------------------
  void _onPlaybackUpdated() {
    if (_isDisposed) return;

    final track = playbackController.currentTrack;
    final trackUri = track?.uri;

    // 1. Check for track transition
    if (trackUri != _currentTrackUri) {
      _currentTrackUri = trackUri;
      _loadLyricsForTrack(track);
      return;
    }

    // 2. Resolve active lyric line based on current playback position
    if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
      final effectivePos = playbackController.position + Duration(milliseconds: _userOffsetMs);
      final newIndex = _lyrics!.activeIndexAt(effectivePos);

      if (newIndex != _currentIndex && newIndex >= 0) {
        _currentIndex = newIndex;
        notifyListeners();

        // Perform animated auto-scroll if user has not engaged manual scroll lock
        if (!_isUserScrollLocked) {
          _scrollToIndex(_currentIndex, animated: true);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Lyrics Ingestion
  // ---------------------------------------------------------------------------
  Future<void> _loadLyricsForTrack(QueueItem? track) async {
    _resetScrollLock();
    _currentIndex = 0;

    if (track == null) {
      _lyrics = null;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await lyricsService.getLyricsForQueueItem(track);
      if (_isDisposed) return;

      _lyrics = result;
      _isLoading = false;
      _currentIndex = 0;

      // Check current playback position immediately
      if (_lyrics != null && _lyrics!.isSynced && lines.isNotEmpty) {
        _currentIndex = _lyrics!.activeIndexAt(playbackController.position);
      }

      notifyListeners();

      // Center initial line after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && !_isUserScrollLocked) {
          _scrollToIndex(_currentIndex, animated: false);
        }
      });
    } catch (e) {
      if (_isDisposed) return;
      _lyrics = null;
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
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

    // Standard list item height in logical pixels
    const double estimatedLineHeight = 56.0;
    final viewportHeight = scrollController.position.viewportDimension;
    final targetOffset = (index * estimatedLineHeight) - (viewportHeight / 2) + (estimatedLineHeight / 2);

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
  /// Called by UI ScrollNotification listener when user drags, flings, or wheels the lyrics list.
  void onUserScroll() {
    if (!_isUserScrollLocked) {
      _isUserScrollLocked = true;
      notifyListeners();
    }

    // Reset 5-second countdown on each gesture interaction
    _userScrollLockTimer?.cancel();
    _userScrollLockTimer = Timer(scrollLockDuration, () {
      if (_isDisposed) return;
      _isUserScrollLocked = false;
      notifyListeners();
      _scrollToIndex(_currentIndex, animated: true);
    });
  }

  /// Allows user to manually dismiss lock and resume auto-scroll immediately.
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
    playbackController.removeListener(_onPlaybackUpdated);
    _userScrollLockTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }
}
