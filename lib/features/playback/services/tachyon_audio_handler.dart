import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';

/// Bridges [PlaybackController] and [TachyonBackendClient] to [as_lib.BaseAudioHandler].
/// This acts as the unified system media controls bridge for Android, iOS,
/// Linux (MPRIS), and Windows (SMTC).
class TachyonAudioHandler extends as_lib.BaseAudioHandler
    with as_lib.SeekHandler, as_lib.QueueHandler {
  final TachyonBackendClient backend;
  final PlaybackController playbackController;

  bool _isDisposed = false;
  String? _lastEmittedTrackPath;

  TachyonAudioHandler({
    required this.backend,
    required this.playbackController,
  }) {
    playbackController.addListener(_syncFromPlaybackController);
    _syncFromPlaybackController();
  }

  void _syncFromPlaybackController() {
    if (_isDisposed) return;
    final state = playbackController.state;
    final track = state.currentTrack;

    // 1. Sync Current MediaItem
    if (track?.filePath != _lastEmittedTrackPath) {
      _lastEmittedTrackPath = track?.filePath;
      if (track != null) {
        File? coverFile;
        if (track.thumbnailHash != null && track.thumbnailHash!.isNotEmpty) {
          coverFile = CoverUtils.getCoverFile(
            track.thumbnailHash!,
            quality: ThumbnailQuality.medium,
          );
        } else {
          coverFile = CoverUtils.getTrackFiles(track.filePath).mq;
        }

        final uri =
            (coverFile.existsSync() && coverFile.lengthSync() > 0)
                ? coverFile.uri
                : null;
        final artistNames = track.artists.map((a) => a.name).join(', ');

        mediaItem.add(as_lib.MediaItem(
          id: track.filePath,
          title: track.title,
          artist: artistNames.isNotEmpty ? artistNames : null,
          album: track.album?.name,
          duration: Duration(milliseconds: track.durationMs),
          artUri: uri,
        ));
      } else {
        mediaItem.add(null);
      }
    }

    // 2. Sync Queue
    final queueItems = state.playables
        .map((entry) {
          final t = entry.track;
          if (t == null) return null;
          final artists = t.artists.map((a) => a.name).join(', ');
          File? cover;
          if (t.thumbnailHash != null && t.thumbnailHash!.isNotEmpty) {
            cover = CoverUtils.getCoverFile(
              t.thumbnailHash!,
              quality: ThumbnailQuality.low,
            );
          } else {
            cover = CoverUtils.getTrackFiles(t.filePath).lq;
          }

          final uri =
              (cover.existsSync() && cover.lengthSync() > 0) ? cover.uri : null;

          return as_lib.MediaItem(
            id: t.filePath,
            title: t.title,
            artist: artists.isNotEmpty ? artists : null,
            album: t.album?.name,
            duration: Duration(milliseconds: t.durationMs),
            artUri: uri,
          );
        })
        .whereType<as_lib.MediaItem>()
        .toList();

    queue.add(queueItems);

    // 3. Sync PlaybackState
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

    final asRepeatMode = switch (state.loop) {
      Loop.off => as_lib.AudioServiceRepeatMode.none,
      Loop.one => as_lib.AudioServiceRepeatMode.one,
      Loop.all => as_lib.AudioServiceRepeatMode.all,
    };

    final asShuffleMode = state.shuffle
        ? as_lib.AudioServiceShuffleMode.all
        : as_lib.AudioServiceShuffleMode.none;

    playbackState.add(as_lib.PlaybackState(
      controls: controls,
      systemActions: actions,
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: isPlaying,
      updatePosition: state.position,
      bufferedPosition: state.position,
      speed: isPlaying ? state.rate : 0.0,
      repeatMode: asRepeatMode,
      shuffleMode: asShuffleMode,
    ));
  }

  @override
  Future<void> play() => playbackController.play();

  @override
  Future<void> pause() => playbackController.pause();

  @override
  Future<void> stop() async {
    await backend.pause();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: as_lib.AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> seek(Duration position) => playbackController.seek(position);

  @override
  Future<void> skipToNext() => playbackController.next();

  @override
  Future<void> skipToPrevious() => playbackController.previous();

  @override
  Future<void> skipToQueueItem(int index) =>
      playbackController.skipToQueueIndex(index);

  @override
  Future<void> setRepeatMode(as_lib.AudioServiceRepeatMode repeatMode) async {
    final targetLoop = switch (repeatMode) {
      as_lib.AudioServiceRepeatMode.none => Loop.off,
      as_lib.AudioServiceRepeatMode.one => Loop.one,
      as_lib.AudioServiceRepeatMode.all ||
      as_lib.AudioServiceRepeatMode.group => Loop.all,
    };
    await playbackController.setLoopMode(targetLoop);
  }

  @override
  Future<void> setShuffleMode(as_lib.AudioServiceShuffleMode shuffleMode) async {
    final shouldShuffle = shuffleMode != as_lib.AudioServiceShuffleMode.none;
    if (playbackController.state.shuffle != shouldShuffle) {
      await playbackController.toggleShuffle();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // If not playing, stop the foreground service so Android can release the process.
    // If playing, keep running! The foreground service preserves playback in headless mode.
    if (!playbackController.state.isPlaying) {
      await stop();
    }
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  void dispose() {
    _isDisposed = true;
    playbackController.removeListener(_syncFromPlaybackController);
  }
}
