import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' show CrossfeedMode;
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'crossfade_config.dart';
import 'loop_mode.dart';
export 'package:miniaudio_player/miniaudio_player.dart' show CrossfeedMode;
export 'loop_mode.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

@immutable
class PlaybackState {
  final int index;
  final List<PlaylistEntry> playables;
  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;
  final Duration duration;
  final double rate;
  final double pitch;
  final double volume;
  final bool shuffle;
  final Loop loop;
  final Duration crossfadeDuration;
  final bool skipSilence;
  final bool volumeNormalization;
  final bool isInfiniteMixEnabled;
  final double? audioBitrate;
  final int? audioSampleRate;
  final int? audioChannels;
  final double preampDb;
  final double balance;
  final bool mono;
  final CrossfeedMode crossfeedMode;
  final double spatializerWidth;
  final bool limiterEnabled;

  const PlaybackState({
    this.index = 0,
    this.playables = const [],
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 100.0,
    this.shuffle = false,
    this.loop = Loop.off,
    this.crossfadeDuration = const Duration(seconds: 5),
    this.skipSilence = false,
    this.volumeNormalization = true,
    this.isInfiniteMixEnabled = false,
    this.audioBitrate,
    this.audioSampleRate,
    this.audioChannels,
    this.preampDb = 0.0,
    this.balance = 0.0,
    this.mono = false,
    this.crossfeedMode = CrossfeedMode.off,
    this.spatializerWidth = 1.0,
    this.limiterEnabled = true,
  });

  const PlaybackState.initial() : this();

  PlaylistEntry? get currentEntry =>
      (index >= 0 && index < playables.length) ? playables[index] : null;

  Track? get currentTrack => currentEntry?.track;

  bool get hasNext =>
      loop == Loop.all ||
      loop == Loop.one ||
      index < playables.length - 1 ||
      (isInfiniteMixEnabled && playables.isNotEmpty);
  bool get hasPrevious =>
      loop == Loop.all || index > 0 || position.inSeconds > 3;

  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  PlaybackStatus get status {
    if (buffering) return PlaybackStatus.loading;
    if (completed) return PlaybackStatus.completed;
    if (playing) return PlaybackStatus.playing;
    if (position > Duration.zero && !playing) return PlaybackStatus.paused;
    return PlaybackStatus.idle;
  }

  // Property aliases for interface contract & UI compatibility
  bool get isPlaying => playing;
  bool get isBuffering => buffering;
  bool get isCompleted => completed;
  List<PlaylistEntry> get queue => playables;
  int get currentIndex => index;
  Loop get loopMode => loop;
  bool get isShuffled => shuffle;
  CrossfadeConfig get crossfadeConfig =>
      CrossfadeConfig(duration: crossfadeDuration);

  PlaybackState copyWith({
    int? index,
    List<PlaylistEntry>? playables,
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
    double? rate,
    double? pitch,
    double? volume,
    bool? shuffle,
    Loop? loop,
    Duration? crossfadeDuration,
    CrossfadeConfig? crossfadeConfig,
    bool? skipSilence,
    bool? volumeNormalization,
    bool? isInfiniteMixEnabled,
    double? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    double? preampDb,
    double? balance,
    bool? mono,
    CrossfeedMode? crossfeedMode,
    double? spatializerWidth,
    bool? limiterEnabled,
  }) {
    return PlaybackState(
      index: index ?? this.index,
      playables: playables ?? this.playables,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      completed: completed ?? this.completed,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      shuffle: shuffle ?? this.shuffle,
      loop: loop ?? this.loop,
      crossfadeDuration:
          crossfadeConfig?.duration ??
          crossfadeDuration ??
          this.crossfadeDuration,
      skipSilence: skipSilence ?? this.skipSilence,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      isInfiniteMixEnabled: isInfiniteMixEnabled ?? this.isInfiniteMixEnabled,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      preampDb: preampDb ?? this.preampDb,
      balance: balance ?? this.balance,
      mono: mono ?? this.mono,
      crossfeedMode: crossfeedMode ?? this.crossfeedMode,
      spatializerWidth: spatializerWidth ?? this.spatializerWidth,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          listEquals(playables, other.playables) &&
          playing == other.playing &&
          buffering == other.buffering &&
          completed == other.completed &&
          position == other.position &&
          duration == other.duration &&
          rate == other.rate &&
          pitch == other.pitch &&
          volume == other.volume &&
          shuffle == other.shuffle &&
          loop == other.loop &&
          crossfadeDuration == other.crossfadeDuration &&
          skipSilence == other.skipSilence &&
          volumeNormalization == other.volumeNormalization &&
          isInfiniteMixEnabled == other.isInfiniteMixEnabled &&
          audioBitrate == other.audioBitrate &&
          audioSampleRate == other.audioSampleRate &&
          audioChannels == other.audioChannels &&
          preampDb == other.preampDb &&
          balance == other.balance &&
          mono == other.mono &&
          crossfeedMode == other.crossfeedMode &&
          spatializerWidth == other.spatializerWidth &&
          limiterEnabled == other.limiterEnabled;

  @override
  int get hashCode => Object.hashAll([
    index,
    Object.hashAll(playables),
    playing,
    buffering,
    completed,
    position,
    duration,
    rate,
    pitch,
    volume,
    shuffle,
    loop,
    crossfadeDuration,
    skipSilence,
    volumeNormalization,
    isInfiniteMixEnabled,
    audioBitrate,
    audioSampleRate,
    audioChannels,
    preampDb,
    balance,
    mono,
    crossfeedMode,
    spatializerWidth,
    limiterEnabled,
  ]);
}
