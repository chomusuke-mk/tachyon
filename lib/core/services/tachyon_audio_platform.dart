import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

/// Platform implementation of [JustAudioPlatform] backed by `package:media_kit`.
///
/// Fixes the `lavf: Failed to create file cache` error by explicitly configuring
/// `cache-on-disk=no`, `sub-auto=no`, and `audio-stream-silence=yes` on the
/// native libmpv instance upon creation, while routing logs cleanly.
class TachyonAudioPlatform extends JustAudioPlatform {
  final _players = <String, TachyonMediaKitPlayer>{};
  final _disposingPlayers = <String, Future<void>>{};

  /// Ensures native media_kit platform bindings and Tachyon audio player platform
  /// are registered on supported desktop platforms (Linux and Windows).
  static void ensureInitialized({String? libmpv}) {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      registerWith();
      MediaKit.ensureInitialized(libmpv: libmpv);
    }
  }

  /// Registers this platform implementation as [JustAudioPlatform.instance].
  static void registerWith() {
    JustAudioPlatform.instance = TachyonAudioPlatform();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(
        code: 'error',
        message: 'Player ${request.id} already exists!',
      );
    }

    developer.log(
      'Instantiating player ${request.id}',
      name: 'Tachyon.AudioPlatform',
    );
    final player = TachyonMediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.ready();
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    if (_disposingPlayers.containsKey(request.id)) {
      await _disposingPlayers[request.id]!;
      return DisposePlayerResponse();
    }

    final player = _players[request.id];
    if (player == null) {
      throw PlatformException(
        code: 'error',
        message: "Player ${request.id} doesn't exist.",
      );
    }

    final future = player.release();
    _players.remove(request.id);
    _disposingPlayers[request.id] = future;
    await future;
    _disposingPlayers.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    if (_players.isNotEmpty) {
      await Future.wait(_players.values.map((p) => p.release()));
      _players.clear();
    }
    return DisposeAllPlayersResponse();
  }
}

/// An [AudioPlayerPlatform] that wraps `package:media_kit`'s [Player] with
/// optimal properties for local audio playback:
/// - `cache-on-disk = no` (prevents FFmpeg lavf cache file creation failures)
/// - `sub-auto = no` (suppresses redundant subtitle scanning on music tracks)
/// - `audio-stream-silence = yes` (ensures continuous audio stream continuity)
/// - `bufferSize = 8MB`
class TachyonMediaKitPlayer extends AudioPlayerPlatform {
  static const kErrorCode = 1;

  late final Player _player;
  late final List<StreamSubscription> _streamSubscriptions;
  final _readyCompleter = Completer<void>();

  /// Completes when the player internals and MPV properties are initialized.
  Future<void> ready() => _readyCompleter.future;

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _mediaOpened = false;
  int? _errorCode;
  String? _errorMessage;
  Completer<Duration?>? _loadCompleter;

  int _currentIndex = 0;
  Duration? _setPosition;

  Media? get _currentMedia {
    final medias = _player.state.playlist.medias;
    if (medias.isEmpty) return null;
    return medias[_player.state.playlist.index];
  }

  TachyonMediaKitPlayer(super.id) {
    _player = Player(
      configuration: PlayerConfiguration(
        pitch: true,
        protocolWhitelist: const [
          'udp',
          'rtp',
          'tcp',
          'tls',
          'data',
          'file',
          'http',
          'https',
          'crypto',
        ],
        title: 'Tachyon Audio Player',
        bufferSize: 8 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
        ready: () async {
          if (_player.platform is NativePlayer) {
            final native = _player.platform as NativePlayer;
            await native.setProperty('cache-on-disk', 'no');
            await native.setProperty('sub-auto', 'no');
            await native.setProperty('audio-stream-silence', 'yes');
          }
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
          }
        },
      ),
    );

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        if (_currentMedia?.extras?['overrideDuration'] != null) return;

        if (_setPosition != null && duration.inSeconds > 0) {
          unawaited(_player.seek(_setPosition!));
          _setPosition = null;
        }
        _updateDuration(duration);
        _updatePlaybackEvent();
      }),
      _player.stream.position.listen((position) {
        _position = position;
        final start = _currentMedia?.start;
        if (start != null) _position -= start;
        if (_position < Duration.zero) _position = Duration.zero;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        final start = _currentMedia?.start;
        if (!isBuffering && start != null && _bufferedPosition <= start) {
          return;
        }
        if (_processingState == ProcessingStateMessage.loading) {
          if (!isBuffering && _mediaOpened) {
            _processingState = ProcessingStateMessage.ready;
            if (_loadCompleter?.isCompleted != true) {
              _loadCompleter?.complete(_duration);
            }
          }
        } else if (_processingState != ProcessingStateMessage.completed ||
            isBuffering) {
          _processingState = isBuffering
              ? ProcessingStateMessage.buffering
              : ProcessingStateMessage.ready;
          if (_duration == null) {
            _updateDuration(_player.state.duration);
          }
        }
        _errorCode = null;
        _errorMessage = null;
        _updatePlaybackEvent();
      }),
      _player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        final start = _currentMedia?.start;
        if (!_player.state.buffering &&
            _mediaOpened &&
            start != null &&
            _bufferedPosition > start) {
          _processingState = ProcessingStateMessage.ready;
          if (_loadCompleter?.isCompleted != true) {
            _loadCompleter?.complete(_duration);
          }
        }
        _updatePlaybackEvent();
      }),
      _player.stream.volume.listen((volume) {
        _dataController.add(PlayerDataMessage(volume: volume / 100.0));
      }),
      _player.stream.completed.listen((completed) {
        _bufferedPosition = _position = Duration.zero;
        if (completed &&
            _currentIndex == _player.state.playlist.medias.length - 1 &&
            _player.state.playlistMode == PlaylistMode.none) {
          _processingState = ProcessingStateMessage.completed;
        }
        _errorCode = null;
        _errorMessage = null;
        _updatePlaybackEvent();
      }),
      _player.stream.error.listen((error) {
        final errorUri = RegExp(r'Failed to open (.*)\.').firstMatch(error)?[1];
        if (errorUri == null || errorUri == _currentMedia?.uri) {
          _processingState = ProcessingStateMessage.idle;
          _errorCode = kErrorCode;
          _errorMessage = error;
          _updatePlaybackEvent();
        }
        developer.log(
          'Player error: $error',
          name: 'Tachyon.MPV',
          error: error,
        );
      }),
      _player.stream.playlist.listen((playlist) {
        if (_currentIndex != playlist.index) {
          _bufferedPosition = _position = Duration.zero;
          _currentIndex = playlist.index;
        }
        _duration = _currentMedia?.extras?['overrideDuration'];
        _updatePlaybackEvent();
      }),
      _player.stream.playlistMode.listen((playlistMode) {
        _dataController.add(
          PlayerDataMessage(loopMode: _playlistModeToLoopMode(playlistMode)),
        );
      }),
      _player.stream.pitch.listen((pitch) {
        _dataController.add(PlayerDataMessage(pitch: pitch));
      }),
      _player.stream.rate.listen((rate) {
        _dataController.add(PlayerDataMessage(speed: rate));
      }),
      _player.stream.log.listen((event) {
        // Suppress benign lavf cache warnings if any occur
        if (event.prefix == 'lavf' &&
            event.text.contains('Failed to create file cache')) {
          return;
        }
        developer.log(
          'MPV [${event.level}] ${event.prefix}: ${event.text}',
          name: 'Tachyon.MPV',
        );
      }),
    ];
  }

  void _updateDuration(Duration duration) {
    final start = _currentMedia?.start;
    final end = _currentMedia?.end;
    if (end != null) duration = end;
    if (start != null) duration -= start;
    _duration = duration;
  }

  PlaylistMode _loopModeToPlaylistMode(LoopModeMessage loopMode) {
    return switch (loopMode) {
      LoopModeMessage.off => PlaylistMode.none,
      LoopModeMessage.one => PlaylistMode.single,
      LoopModeMessage.all => PlaylistMode.loop,
    };
  }

  LoopModeMessage _playlistModeToLoopMode(PlaylistMode playlistMode) {
    return switch (playlistMode) {
      PlaylistMode.none => LoopModeMessage.off,
      PlaylistMode.single => LoopModeMessage.one,
      PlaylistMode.loop => LoopModeMessage.all,
    };
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  void _updatePlaybackEvent() {
    _eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _position,
      bufferedPosition: _bufferedPosition,
      duration: _duration,
      icyMetadata: null,
      currentIndex: _currentIndex,
      androidAudioSessionId: null,
      errorCode: _errorCode,
      errorMessage: _errorMessage,
    ));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _mediaOpened = false;
    _loadCompleter = Completer();
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _duration = null;
    _processingState = ProcessingStateMessage.loading;
    _errorCode = null;
    _errorMessage = null;
    _updatePlaybackEvent();

    if (request.audioSourceMessage is ConcatenatingAudioSourceMessage) {
      final audioSource =
          request.audioSourceMessage as ConcatenatingAudioSourceMessage;
      final playable = Playlist(
        audioSource.children.map(_convertAudioSourceIntoMediaKit).toList(),
        index: _currentIndex,
      );
      await _player.open(playable, play: _playing);
    } else {
      final playable =
          _convertAudioSourceIntoMediaKit(request.audioSourceMessage);
      await _player.open(playable, play: _playing);
    }
    _mediaOpened = true;

    if (request.initialPosition != null) {
      _setPosition = _position = request.initialPosition!;
    }

    _updatePlaybackEvent();
    final duration = await _loadCompleter?.future;
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playing = true;
    if (_mediaOpened) {
      await _player.play();
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing = false;
    if (_mediaOpened) {
      await _player.pause();
    }
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    return _player
        .setVolume(request.volume * 100.0)
        .then((_) => SetVolumeResponse());
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    return _player.setRate(request.speed).then((_) => SetSpeedResponse());
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) =>
      _player.setPitch(request.pitch).then((_) => SetPitchResponse());

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _player.setPlaylistMode(_loopModeToPlaylistMode(request.loopMode));
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    final shuffling = request.shuffleMode != ShuffleModeMessage.none;
    await _player.setShuffle(shuffling);
    _dataController.add(PlayerDataMessage(
      shuffleMode:
          shuffling ? ShuffleModeMessage.all : ShuffleModeMessage.none,
    ));
    return SetShuffleModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.index != null) {
      await _player.jump(request.index!);
      if (!_playing) await _player.pause();
    }

    final position = request.position;
    if (position != null) {
      _position = position;
      final start = _currentMedia?.start;
      var nativePosition = position;
      if (start != null) nativePosition += start;
      if (_player.state.duration.inSeconds > 0) {
        await _player.seek(nativePosition);
      } else {
        _setPosition = nativePosition;
      }
    } else {
      _position = Duration.zero;
    }

    _updatePlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async {
    for (final source in request.children) {
      await _player.add(_convertAudioSourceIntoMediaKit(source));
      final length = _player.state.playlist.medias.length;
      if (length == 0 || length == 1) continue;
      if (request.index < (length - 1) && request.index >= 0) {
        await _player.move(length, request.index);
      }
    }
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async {
    for (var i = request.startIndex; i < request.endIndex; i++) {
      await _player.remove(request.startIndex);
    }
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
    ConcatenatingMoveRequest request,
  ) {
    return _player
        .move(
          request.currentIndex,
          request.currentIndex > request.newIndex
              ? request.newIndex
              : request.newIndex + 1,
        )
        .then((_) => ConcatenatingMoveResponse());
  }

  /// Releases resources allocated by this player.
  Future<void> release() async {
    _mediaOpened = false;
    await _player.dispose();
    for (final StreamSubscription subscription in _streamSubscriptions) {
      unawaited(subscription.cancel());
    }
    _streamSubscriptions.clear();
  }

  Media _convertAudioSourceIntoMediaKit(AudioSourceMessage audioSource) {
    switch (audioSource) {
      case final UriAudioSourceMessage uriSource:
        return Media(uriSource.uri, httpHeaders: audioSource.headers);
      case final ClippingAudioSourceMessage clippingSource:
        return Media(
          clippingSource.child.uri,
          start: clippingSource.start,
          end: clippingSource.end,
        );
      default:
        throw UnsupportedError(
          '${audioSource.runtimeType} is currently not supported',
        );
    }
  }
}
