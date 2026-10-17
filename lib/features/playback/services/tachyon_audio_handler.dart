import 'dart:async';
import 'dart:io';

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
  String? _lastEmittedTrackPath;
  List<PlaylistEntry>? _lastSyncedPlayables;
  StreamSubscription<PlaybackState>? _backendStateSub;
  StreamSubscription<Duration>? _backendPositionSub;
  DateTime? _lastPositionUpdateTime;
  Duration _lastEmittedPosition = Duration.zero;

  TachyonAudioHandler({
    required this.backend,
    required this.playbackController,
  }) {
    playbackController.addListener(_syncFromPlaybackController);
    _backendStateSub = backend.playbackStateStream.listen((state) {
      _syncFromPlaybackState(state, position: state.position);
    });
    _backendPositionSub = backend.positionStream.listen((pos) {
      _onPositionUpdate(pos);
    });
    _syncFromPlaybackController();
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
      if (current.playing) {
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

  void _syncFromPlaybackState(PlaybackState state, {Duration? position}) {
    if (_isDisposed) return;
    final track = state.currentTrack;

    // 1. Sync Current MediaItem (using small / crisp thumbnail)
    if (track?.filePath != _lastEmittedTrackPath) {
      _lastEmittedTrackPath = track?.filePath;
      Uri? uri;
      if (track != null) {
        if (track.thumbnailHash != null && track.thumbnailHash!.isNotEmpty) {
          final mediumFile = File(
            MetadataUtils.getThumbnailFilePath(
              track.thumbnailHash!,
              quality: ThumbnailQuality.medium,
            ),
          );
          final lowFile = File(
            MetadataUtils.getThumbnailFilePath(
              track.thumbnailHash!,
              quality: ThumbnailQuality.low,
            ),
          );
          final highFile = File(
            MetadataUtils.getThumbnailFilePath(
              track.thumbnailHash!,
              quality: ThumbnailQuality.high,
            ),
          );
          final coverFile =
              (mediumFile.existsSync() && mediumFile.lengthSync() > 0)
                  ? mediumFile
                  : ((lowFile.existsSync() && lowFile.lengthSync() > 0)
                      ? lowFile
                      : ((highFile.existsSync() && highFile.lengthSync() > 0)
                          ? highFile
                          : null));
          uri = coverFile?.uri;
        }

        final artistNames = track.artists.map((a) => a.name).join(', ');

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
      } else {
        mediaItem.add(null);
      }
    }

    // 2. Sync Queue only when queue structure actually mutates (prevents UI isolate disk I/O on pause/skip)
    if (_lastSyncedPlayables == null ||
        (!identical(state.playables, _lastSyncedPlayables) &&
            !listEquals(state.playables, _lastSyncedPlayables))) {
      _lastSyncedPlayables = List<PlaylistEntry>.unmodifiable(state.playables);
      final queueItems = state.playables
          .map((entry) {
            final t = entry.track;
            if (t == null) return null;
            final artists = t.artists.map((a) => a.name).join(', ');
            Uri? uri;
            if (t.thumbnailHash != null && t.thumbnailHash!.isNotEmpty) {
              final mediumFile = File(
                MetadataUtils.getThumbnailFilePath(
                  t.thumbnailHash!,
                  quality: ThumbnailQuality.medium,
                ),
              );
              final lowFile = File(
                MetadataUtils.getThumbnailFilePath(
                  t.thumbnailHash!,
                  quality: ThumbnailQuality.low,
                ),
              );
              final cover =
                  (mediumFile.existsSync() && mediumFile.lengthSync() > 0)
                      ? mediumFile
                      : ((lowFile.existsSync() && lowFile.lengthSync() > 0)
                          ? lowFile
                          : null);
              uri = cover?.uri;
            }

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
    }

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

    final livePosition = position ?? state.position;
    _lastEmittedPosition = livePosition;
    _lastPositionUpdateTime = DateTime.now();

    playbackState.add(
      as_lib.PlaybackState(
        controls: controls,
        systemActions: actions,
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: livePosition,
        bufferedPosition: livePosition,
        speed: isPlaying ? state.rate : 0.0,
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
    _backendStateSub?.cancel();
    _backendPositionSub?.cancel();
    playbackController.removeListener(_syncFromPlaybackController);
  }
}
