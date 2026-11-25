import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';

/// Bridges [PlaybackController] to [as_lib.BaseAudioHandler].
/// This acts as the unified system media controls bridge for Android, iOS,
/// Linux (MPRIS), and Windows (SMTC).
class TachyonAudioHandler extends as_lib.BaseAudioHandler
    with as_lib.SeekHandler, as_lib.QueueHandler {
  static const _log = ScopedLogger('AudioHandler');

  /// Controller providing playback state, metadata, and transport actions.
  final PlaybackController playbackController;

  /// Optional callback invoked when the mobile task is removed while playing.
  Future<void> Function()? onTaskRemovedWhilePlaying;

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

  /// Creates a [TachyonAudioHandler] wired to [playbackController].
  TachyonAudioHandler({
    required this.playbackController,
    this.onTaskRemovedWhilePlaying,
  }) {
    playbackController.addListener(_syncFromPlaybackController);
    playbackController.systemPositionListenable.addListener(_onPositionChanged);
    playbackController.liveMetadataListenable.addListener(
      _syncFromPlaybackController,
    );
    _syncFromPlaybackController();
  }

  void _onPositionChanged() {
    _onPositionUpdate(playbackController.systemPositionListenable.value);
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
        _log.vLazy(
          () => 'System position update: pos=${pos.inMilliseconds}ms jumped=$jumped',
        );
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
      position: playbackController.lifecycleMode == AppLifecycleMode.active
          ? playbackController.position
          : playbackController.systemPositionListenable.value,
    );
  }

  /// Converts [artworkUri] into a [Uri] suitable for system media controls.
  ///
  /// Preserves HTTP(S), `data:`, and `blob:` URIs, converts local file paths to
  /// `file://` URIs on native platforms, and returns `null` on web for OPFS
  /// paths that require asynchronous resolution.
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
      // OPFS cover bytes are read asynchronously on demand rather than cached in RAM.
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

        final item = as_lib.MediaItem(
          id: playable.filePath,
          title: effectiveTitle,
          artist: artistNames.isNotEmpty ? artistNames : null,
          album: albumName.isNotEmpty ? albumName : null,
          duration: playable.isStream ? null : playable.duration,
          artUri: uri,
        );
        _log.d('Emitting MediaItem: id=${item.id} title="${item.title}" artist=${item.artist}');
        mediaItem.add(item);

        if (kIsWeb && uri == null && artworkUri.isNotEmpty) {
          final capturedSignature = signature;
          unawaited(
            PersistentBinaryStorage.resolveCoverDataUriAsync(artworkUri)
                .then((dataUri) {
                  if (_isDisposed ||
                      dataUri == null ||
                      _lastEmittedMediaSignature != capturedSignature) {
                    return;
                  }
                  mediaItem.add(item.copyWith(artUri: dataUri));
                })
                .catchError((Object _) {}),
          );
        }
      }
    } else if (_lastEmittedMediaSignature != null) {
      _lastEmittedMediaSignature = null;
      _log.d('Clearing MediaItem (null)');
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

    _log.d(
      'Emitting PlaybackState: playing=$isPlaying proc=${processingState.name} '
      'pos=${livePosition.inMilliseconds}ms repeat=${asRepeatMode.name} shuffle=${asShuffleMode.name}',
    );
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
  Future<void> play() {
    _log.d('OS media command: play');
    return playbackController.play();
  }

  @override
  Future<void> pause() {
    _log.d('OS media command: pause');
    return playbackController.pause();
  }

  @override
  Future<void> stop() async {
    _log.d('OS media command: stop');
    await playbackController.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: as_lib.AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) {
    _log.d('OS media command: seek(${position.inMilliseconds}ms)');
    return playbackController.seek(position);
  }

  @override
  Future<void> skipToNext() {
    _log.d('OS media command: skipToNext');
    return playbackController.next();
  }

  @override
  Future<void> skipToPrevious() {
    _log.d('OS media command: skipToPrevious');
    return playbackController.previous();
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _log.d('OS media command: skipToQueueItem($index)');
    return playbackController.skipToQueueIndex(index);
  }

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
    _log.d('onTaskRemoved (playing=${playbackState.value.playing})');
    if (!playbackState.value.playing) {
      await stop();
    } else if (onTaskRemovedWhilePlaying != null) {
      await onTaskRemovedWhilePlaying!.call();
    }
  }

  @override
  Future<void> onNotificationDeleted() async {
    _log.d('onNotificationDeleted -> stop');
    await stop();
  }

  /// Detaches controller listeners and prevents further state emission.
  void dispose() {
    _isDisposed = true;
    playbackController.liveMetadataListenable.removeListener(
      _syncFromPlaybackController,
    );
    playbackController.systemPositionListenable.removeListener(
      _onPositionChanged,
    );
    playbackController.removeListener(_syncFromPlaybackController);
  }
}
