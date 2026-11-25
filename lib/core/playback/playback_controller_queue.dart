part of 'playback_controller.dart';

mixin _PlaybackControllerQueueMixin on _PlaybackControllerState {
  /// Queue entries currently loaded in the player engine.
  List<ma.AudioSource<AudioPlayable>> get queue =>
      _player != null ? _player!.state.queue : _state.queue;

  /// Active zero-based index within [queue].
  int get currentIndex => _player?.state.currentIndex ?? _state.currentIndex;

  /// Whether advancing to a next track is currently possible.
  bool get hasNext => _player?.state.hasNext ?? _state.hasNext;

  /// Whether navigating to a previous track is currently possible.
  bool get hasPrevious => _player?.state.hasPrevious ?? _state.hasPrevious;

  /// Whether infinite library mix auto-append is currently active.
  bool get isInfiniteMixEnabled => _isInfiniteMixEnabled;

  /// Enables or disables automatic infinite library mix playback.
  void setInfiniteMix(bool enabled) {
    _isInfiniteMixEnabled = enabled;
    _state = _state.copyWith(isInfiniteMixEnabled: enabled);
    _emitScoped([_controlsNotifier, _queueNotifier]);
    try {
      unawaited(
        player.action
            .setInfiniteMix(
              ma.InfiniteMixConfig(
                enabled: enabled,
                remainingTracksThreshold: 3,
              ),
            )
            .catchError((Object e) {
              debugPrint('[PlaybackController] setInfiniteMix error: $e');
            }),
      );
    } catch (e) {
      debugPrint('[PlaybackController] setInfiniteMix error: $e');
    }
  }

  /// Toggles infinite library mix mode.
  void toggleInfiniteMix() {
    setInfiniteMix(!isInfiniteMixEnabled);
  }

  /// Replaces the playback queue with [tracks] and optionally starts playing
  /// at [startIndex] with optional [shuffle].
  Future<void> openTracks(
    List<AudioPlayable> tracks, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    final canonicalTracks = [
      for (final t in tracks) _canonicalPlayable(t),
    ];
    final items = [for (final t in canonicalTracks) t.toAudioSource()];
    final int targetIdx =
        (startIndex != null &&
            startIndex >= 0 &&
            startIndex < canonicalTracks.length)
        ? startIndex
        : 0;
    await _ensureMetadataEnabledFor(canonicalTracks[targetIdx]);
    await player.action.setQueue(items);
    if (play) {
      await player.action.play(position: startIndex, shuffled: shuffle);
    } else if (shuffle) {
      await player.action.setShuffle(true);
    }
  }

  /// Plays [track], populating the queue from [contextTracks] when provided.
  Future<void> playTrack(
    AudioPlayable track, {
    List<AudioPlayable>? contextTracks,
  }) async {
    final trackList = (contextTracks != null && contextTracks.isNotEmpty)
        ? contextTracks
        : [track];

    var startIndex = trackList.indexWhere((t) => t.filePath == track.filePath);
    if (startIndex == -1) startIndex = 0;

    try {
      await openTracks(
        trackList,
        startIndex: startIndex,
        play: true,
        shuffle: (this as PlaybackController).isShuffled,
      );
    } catch (e) {
      debugPrint('[PlaybackController] Error in playTrack: $e');
    }
  }

  /// Replaces the queue with [tracks] and starts playback immediately.
  Future<void> playAll(
    List<AudioPlayable> tracks, {
    bool shuffle = false,
    int? startIndex,
  }) async {
    if (tracks.isEmpty) return;
    try {
      await openTracks(
        tracks,
        startIndex: startIndex,
        play: true,
        shuffle: shuffle,
      );
    } catch (e) {
      debugPrint('[PlaybackController] Error in playAll: $e');
    }
  }

  /// Inserts [track] immediately after the active track in the queue.
  Future<void> playNext(AudioPlayable track) async {
    try {
      final item = _canonicalPlayable(track).toAudioSource();
      await player.action.insertNext(item);
    } catch (e) {
      debugPrint('[PlaybackController] Error in playNext: $e');
    }
  }

  /// Appends a single [track] to the end of the playback queue.
  Future<void> addToQueue(AudioPlayable track) async {
    await appendTracks([track]);
  }

  /// Appends all [tracks] to the end of the playback queue.
  Future<void> appendTracks(List<AudioPlayable> tracks) async {
    if (tracks.isEmpty) return;
    try {
      final items = [
        for (final t in tracks) _canonicalPlayable(t).toAudioSource(),
      ];
      await player.action.append(items);
    } catch (e) {
      debugPrint('[PlaybackController] Error in appendTracks: $e');
    }
  }

  /// Removes the queue entry at [index].
  Future<void> removeFromQueue(int index) async {
    try {
      await player.action.removeAt(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in removeFromQueue: $e');
    }
  }

  /// Moves a queue entry from [from] to [to].
  Future<void> reorderQueue(int from, int to) async {
    try {
      await player.action.reorder(from, to);
    } catch (e) {
      debugPrint('[PlaybackController] Error in reorderQueue: $e');
    }
  }

  /// Clears every item from the playback queue.
  Future<void> clearQueue() async {
    try {
      await player.action.clearQueue();
    } catch (e) {
      debugPrint('[PlaybackController] Error in clearQueue: $e');
    }
  }

  /// Jumps directly to and plays the queue item at [index].
  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= queue.length) return;
    try {
      await _ensureMetadataEnabledFor(queue[index].data);
      await player.action.play(position: index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in skipToQueueIndex: $e');
    }
  }
}
