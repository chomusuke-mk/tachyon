import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter/foundation.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';

/// Bridges [PlaybackController] and [TachyonBackendClient] to [as_lib.BaseAudioHandler].
/// This acts as the unified system media controls bridge for Android, iOS,
/// Linux (MPRIS), and Windows (SMTC).
class TachyonAudioHandler extends as_lib.BaseAudioHandler
    with as_lib.SeekHandler, as_lib.QueueHandler {
  final TachyonBackendClient backend;
  final PlaybackController playbackController;

  bool _isDisposed = false;
  String? _lastEmittedMediaSignature;
  List<PlaylistEntry>? _lastSyncedPlayables;
  DateTime? _lastPositionUpdateTime;
  Duration _lastEmittedPosition = Duration.zero;

  // Deduplication fields for PlaybackState
  bool? _lastPlaying;
  as_lib.AudioProcessingState? _lastProcessingState;
  double? _lastSpeed;
  as_lib.AudioServiceRepeatMode? _lastRepeatMode;
  as_lib.AudioServiceShuffleMode? _lastShuffleMode;

  TachyonAudioHandler({
    required this.backend,
    required this.playbackController,
  }) {
    playbackController.addListener(_syncFromPlaybackController);
    playbackController.positionListenable.addListener(_onPositionChanged);
    _syncFromPlaybackController();
  }

  void _onPositionChanged() {
    _onPositionUpdate(playbackController.position);
  }

  void _onPositionUpdate(Duration pos) {
    if (_isDisposed) return;
    final now = DateTime.now();
    final jumped =
        (pos - _lastEmittedPosition).abs() > const Duration(seconds: 2);
    if (jumped ||
        _lastPositionUpdateTime == null ||
        now.difference(_lastPositionUpdateTime!) >= const Duration(seconds: 2)) {
      _lastPositionUpdateTime = now;
      _lastEmittedPosition = pos;
      final current = playbackState.value;
      if (current.playing || jumped) {
        playbackState.add(
          current.copyWith(
            updatePosition: pos,
            bufferedPosition: pos,
          ),
        );
      }
    }
  }

  void _syncFromPlaybackController() {
    if (_isDisposed) return;
    _syncFromPlaybackState(
      playbackController.state,
      position: playbackController.position,
    );
  }

  static Uri? resolveLowQualityArtUri(
    String? thumbnailHash, [
    String? albumThumbnailHash,
  ]) {
    if (MetadataUtils.thumbnailsDirectory == null) return null;
    final hash = (thumbnailHash != null && thumbnailHash.isNotEmpty)
        ? thumbnailHash
        : ((albumThumbnailHash != null && albumThumbnailHash.isNotEmpty)
            ? albumThumbnailHash
            : null);
    if (hash == null) return null;
    return Uri.file(
      MetadataUtils.getThumbnailFilePath(
        hash,
        quality: ThumbnailQuality.low,
      ),
    );
  }

  void _syncFromPlaybackState(PlaybackState state, {Duration? position}) {
    if (_isDisposed) return;
    final track = state.currentTrack;

    // 1. Sync Current MediaItem (using O(1) in-memory hydrated low-quality thumbnail)
    if (track != null) {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final albumName = track.album?.name ?? '';
      final hash = (track.thumbnailHash != null &&
              track.thumbnailHash!.isNotEmpty)
          ? track.thumbnailHash!
          : (track.album?.thumbnailHash ?? '');
      final signature =
          '${track.filePath}|${track.title}|$artistNames|$albumName|${track.durationMs}|$hash';

      if (signature != _lastEmittedMediaSignature) {
        _lastEmittedMediaSignature = signature;
        final uri = resolveLowQualityArtUri(
          track.thumbnailHash,
          track.album?.thumbnailHash,
        );

        mediaItem.add(
          as_lib.MediaItem(
            id: track.filePath,
            title: track.title,
            artist: artistNames.isNotEmpty ? artistNames : null,
            album: track.album?.name,
            duration: Duration(milliseconds: track.durationMs),
            artUri: uri,
          ),
        );
      }
    } else if (_lastEmittedMediaSignature != null) {
      _lastEmittedMediaSignature = null;
      mediaItem.add(null);
    }

    // 2. Sync Queue only when queue structure actually mutates and platform supports/needs it.
    // Desktop OS integrations (Linux MPRIS & Windows SMTC) have no queue consumer and only
    // read mediaItem; serializing large queues over the method channel causes heavy UI freezes.
    // On mobile (Android/iOS), window the queue to a safe limit (<= 50 items) without blocking disk I/O
    // to prevent Android Binder TransactionTooLargeException.
    if (_lastSyncedPlayables == null ||
        (!identical(state.playables, _lastSyncedPlayables) &&
            !listEquals(state.playables, _lastSyncedPlayables))) {
      _lastSyncedPlayables = state.playables;
      final bool shouldSyncQueue =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (shouldSyncQueue) {
        final total = state.playables.length;
        final curr = state.index.clamp(0, total > 0 ? total - 1 : 0);
        final start = math.max(0, curr - 10);
        final end = math.min(total, curr + 40);
        final queueItems = <as_lib.MediaItem>[];
        for (var i = start; i < end; i++) {
          final entry = state.playables[i];
          final t = entry.track;
          if (t == null) continue;
          final artists = t.artists.map((a) => a.name).join(', ');
          final uri = resolveLowQualityArtUri(
            t.thumbnailHash,
            t.album?.thumbnailHash,
          );
          queueItems.add(
            as_lib.MediaItem(
              id: t.filePath,
              title: t.title,
              artist: artists.isNotEmpty ? artists : null,
              album: t.album?.name,
              duration: Duration(milliseconds: t.durationMs),
              artUri: uri,
            ),
          );
        }
        queue.add(queueItems);
      }
    }

    // 3. Sync PlaybackState (deduplicated)
    final isPlaying = state.isPlaying;
    final isBuffering = state.buffering;

    as_lib.AudioProcessingState processingState;
    if (state.currentTrack == null) {
      processingState = as_lib.AudioProcessingState.idle;
    } else if (isBuffering) {
      processingState = as_lib.AudioProcessingState.buffering;
    } else if (state.completed) {
      processingState = as_lib.AudioProcessingState.completed;
    } else {
      processingState = as_lib.AudioProcessingState.ready;
    }

    final asRepeatMode = switch (state.loop) {
      Loop.off => as_lib.AudioServiceRepeatMode.none,
      Loop.one => as_lib.AudioServiceRepeatMode.one,
      Loop.all => as_lib.AudioServiceRepeatMode.all,
    };

    final asShuffleMode = state.shuffle
        ? as_lib.AudioServiceShuffleMode.all
        : as_lib.AudioServiceShuffleMode.none;

    final speed = isPlaying ? state.rate : 0.0;
    final livePosition = position ?? state.position;
    final positionJumped =
        (livePosition - _lastEmittedPosition).abs() > const Duration(seconds: 2);

    if (_lastPlaying == isPlaying &&
        _lastProcessingState == processingState &&
        _lastSpeed == speed &&
        _lastRepeatMode == asRepeatMode &&
        _lastShuffleMode == asShuffleMode &&
        !positionJumped) {
      return;
    }

    _lastPlaying = isPlaying;
    _lastProcessingState = processingState;
    _lastSpeed = speed;
    _lastRepeatMode = asRepeatMode;
    _lastShuffleMode = asShuffleMode;
    _lastEmittedPosition = livePosition;
    _lastPositionUpdateTime = DateTime.now();

    final controls = <as_lib.MediaControl>[
      as_lib.MediaControl.skipToPrevious,
      if (isPlaying) as_lib.MediaControl.pause else as_lib.MediaControl.play,
      as_lib.MediaControl.skipToNext,
      as_lib.MediaControl.stop,
    ];

    final actions = <as_lib.MediaAction>{
      as_lib.MediaAction.seek,
      as_lib.MediaAction.seekForward,
      as_lib.MediaAction.seekBackward,
      as_lib.MediaAction.setRepeatMode,
      as_lib.MediaAction.setShuffleMode,
    };

    playbackState.add(
      as_lib.PlaybackState(
        controls: controls,
        systemActions: actions,
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: livePosition,
        bufferedPosition: livePosition,
        speed: speed,
        repeatMode: asRepeatMode,
        shuffleMode: asShuffleMode,
      ),
    );
  }

  @override
  Future<void> play() => backend.play();

  @override
  Future<void> pause() => backend.pause();

  @override
  Future<void> stop() async {
    await backend.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: as_lib.AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) => backend.seek(position);

  @override
  Future<void> skipToNext() => backend.next();

  @override
  Future<void> skipToPrevious() => backend.previous();

  @override
  Future<void> skipToQueueItem(int index) => backend.skipToIndex(index);

  @override
  Future<void> setRepeatMode(as_lib.AudioServiceRepeatMode repeatMode) async {
    final targetLoop = switch (repeatMode) {
      as_lib.AudioServiceRepeatMode.none => Loop.off,
      as_lib.AudioServiceRepeatMode.one => Loop.one,
      as_lib.AudioServiceRepeatMode.all ||
      as_lib.AudioServiceRepeatMode.group => Loop.all,
    };
    await backend.setLoopMode(targetLoop);
  }

  @override
  Future<void> setShuffleMode(
    as_lib.AudioServiceShuffleMode shuffleMode,
  ) async {
    final shouldShuffle = shuffleMode != as_lib.AudioServiceShuffleMode.none;
    await backend.setShuffle(shouldShuffle);
  }

  @override
  Future<void> onTaskRemoved() async {
    // If not playing, stop the foreground service so Android can release the process.
    // If playing, keep running! The foreground service preserves playback in headless mode.
    if (!playbackState.value.playing) {
      await stop();
    }
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  void dispose() {
    _isDisposed = true;
    playbackController.positionListenable.removeListener(_onPositionChanged);
    playbackController.removeListener(_syncFromPlaybackController);
  }
}
