import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';

/// Bridges [PlaybackController] to [as_lib.BaseAudioHandler].
/// This acts as the unified system media controls bridge for Android, iOS,
/// Linux (MPRIS), and Windows (SMTC).
class TachyonAudioHandler extends as_lib.BaseAudioHandler
    with as_lib.SeekHandler, as_lib.QueueHandler {
  final PlaybackController playbackController;

  bool _isDisposed = false;
  String? _lastEmittedMediaSignature;
  List<ma.AudioSource<AudioPlayable>>? _lastSyncedPlayables;
  DateTime? _lastPositionUpdateTime;
  Duration _lastEmittedPosition = Duration.zero;

  bool? _lastPlaying;
  as_lib.AudioProcessingState? _lastProcessingState;
  double? _lastSpeed;
  as_lib.AudioServiceRepeatMode? _lastRepeatMode;
  as_lib.AudioServiceShuffleMode? _lastShuffleMode;

  TachyonAudioHandler({
    required this.playbackController,
  }) {
    playbackController.addListener(_syncFromPlaybackController);
    playbackController.positionListenable.addListener(_onPositionChanged);
    playbackController.liveMetadataListenable.addListener(
      _syncFromPlaybackController,
    );
    _syncFromPlaybackController();
  }

  void _onPositionChanged() {
    _onPositionUpdate(playbackController.position);
  }

  Duration _resolveBufferedPosition(Duration pos) {
    final bufEnd = playbackController.buffer.end;
    return bufEnd > pos ? bufEnd : pos;
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
            bufferedPosition: _resolveBufferedPosition(pos),
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

  static Uri? resolveArtworkUri(String? artworkUri) {
    if (artworkUri == null || artworkUri.trim().isEmpty) return null;
    final clean = artworkUri.trim();
    if (clean.startsWith('http://') ||
        clean.startsWith('https://') ||
        clean.startsWith('data:') ||
        clean.startsWith('blob:')) {
      return Uri.tryParse(clean);
    }
    if (kIsWeb) {
      final hash = p.basename(clean);
      final bytes = PersistentBinaryStorage.getCoverBytesSync(hash);
      if (bytes != null && bytes.isNotEmpty) {
        return Uri.dataFromBytes(bytes, mimeType: 'image/jpeg');
      }
      return null;
    }
    return Uri.file(clean);
  }

  void _syncFromPlaybackState(PlaybackState state, {Duration? position}) {
    if (_isDisposed) return;
    final playable = state.currentPlayable;

    if (playable != null) {
      final displayMeta = playbackController.currentDisplayMetadata;
      final effectiveTitle = displayMeta?.title ?? playable.title;
      final artistNames = displayMeta?.subtitle ?? playable.artistNames.join(', ');
      final albumName = displayMeta?.album ?? playable.albumTitle ?? '';
      final artworkUri = displayMeta?.artworkUri ?? playable.artworkUri ?? '';
      final signature =
          '${playable.filePath}|$effectiveTitle|$artistNames|$albumName|${playable.duration.inMilliseconds}|$artworkUri';

      if (signature != _lastEmittedMediaSignature) {
        _lastEmittedMediaSignature = signature;
        final uri = resolveArtworkUri(
          artworkUri.isNotEmpty ? artworkUri : null,
        );

        mediaItem.add(
          as_lib.MediaItem(
            id: playable.filePath,
            title: effectiveTitle,
            artist: artistNames.isNotEmpty ? artistNames : null,
            album: albumName.isNotEmpty ? albumName : null,
            duration: playable.isStream ? null : playable.duration,
            artUri: uri,
          ),
        );
      }
    } else if (_lastEmittedMediaSignature != null) {
      _lastEmittedMediaSignature = null;
      mediaItem.add(null);
    }

    if (_lastSyncedPlayables == null ||
        (!identical(state.queue, _lastSyncedPlayables) &&
            !listEquals(state.queue, _lastSyncedPlayables))) {
      _lastSyncedPlayables = state.queue;
      final bool shouldSyncQueue =
          !kIsWeb &&
          (PersistentBinaryStorage.isAndroid || PersistentBinaryStorage.isIOS);
      if (shouldSyncQueue) {
        final total = state.queue.length;
        final curr = state.currentIndex.clamp(0, total > 0 ? total - 1 : 0);
        final start = math.max(0, curr - 10);
        final end = math.min(total, curr + 40);
        final queueItems = <as_lib.MediaItem>[];
        for (var i = start; i < end; i++) {
          final entry = state.queue[i];
          final t = entry.track;
          if (t == null) continue;
          final artists = t.artistNames.join(', ');
          final uri = resolveArtworkUri(t.artworkUri);
          queueItems.add(
            as_lib.MediaItem(
              id: t.filePath,
              title: t.title,
              artist: artists.isNotEmpty ? artists : null,
              album: t.albumTitle,
              duration: t.duration,
              artUri: uri,
            ),
          );
        }
        queue.add(queueItems);
      }
    }

    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;

    as_lib.AudioProcessingState processingState;
    if (state.currentPlayable == null) {
      processingState = as_lib.AudioProcessingState.idle;
    } else if (isBuffering) {
      processingState = as_lib.AudioProcessingState.buffering;
    } else if (state.isCompleted) {
      processingState = as_lib.AudioProcessingState.completed;
    } else {
      processingState = as_lib.AudioProcessingState.ready;
    }

    final asRepeatMode = switch (state.loopMode) {
      LoopMode.off => as_lib.AudioServiceRepeatMode.none,
      LoopMode.one => as_lib.AudioServiceRepeatMode.one,
      LoopMode.all => as_lib.AudioServiceRepeatMode.all,
    };

    final asShuffleMode = state.isShuffled
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
        bufferedPosition: _resolveBufferedPosition(livePosition),
        speed: speed,
        repeatMode: asRepeatMode,
        shuffleMode: asShuffleMode,
      ),
    );
  }

  @override
  Future<void> play() => playbackController.play();

  @override
  Future<void> pause() => playbackController.pause();

  @override
  Future<void> stop() async {
    await playbackController.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: as_lib.AudioProcessingState.idle,
      ),
    );
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
      as_lib.AudioServiceRepeatMode.none => LoopMode.off,
      as_lib.AudioServiceRepeatMode.one => LoopMode.one,
      as_lib.AudioServiceRepeatMode.all ||
      as_lib.AudioServiceRepeatMode.group => LoopMode.all,
    };
    await playbackController.setLoopMode(targetLoop);
  }

  @override
  Future<void> setShuffleMode(
    as_lib.AudioServiceShuffleMode shuffleMode,
  ) async {
    final shouldShuffle = shuffleMode != as_lib.AudioServiceShuffleMode.none;
    await playbackController.setShuffle(shouldShuffle);
  }

  @override
  Future<void> onTaskRemoved() async {
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
    playbackController.liveMetadataListenable.removeListener(
      _syncFromPlaybackController,
    );
    playbackController.positionListenable.removeListener(_onPositionChanged);
    playbackController.removeListener(_syncFromPlaybackController);
  }
}
