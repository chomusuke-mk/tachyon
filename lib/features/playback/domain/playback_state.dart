import 'package:flutter/foundation.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'crossfade_config.dart';
import 'loop_mode.dart';
export 'loop_mode.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

@immutable
class PlaybackState {
  final int index;
  final List<PlaylistEntry> playables;
  final int? mixOffset;
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
  final double? audioBitrate;
  final int? audioSampleRate;
  final int? audioChannels;

  const PlaybackState({
    this.index = 0,
    this.playables = const [],
    this.mixOffset,
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
    this.audioBitrate,
    this.audioSampleRate,
    this.audioChannels,
  });

  const PlaybackState.initial() : this();

  PlaylistEntry? get currentEntry =>
      (index >= 0 && index < playables.length) ? playables[index] : null;

  Track? get currentTrack => currentEntry?.track;

  bool get hasNext =>
      loop == Loop.all || loop == Loop.one || index < playables.length - 1;
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
    int? mixOffset,
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
    double? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
  }) {
    return PlaybackState(
      index: index ?? this.index,
      playables: playables ?? this.playables,
      mixOffset: mixOffset ?? this.mixOffset,
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
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          listEquals(playables, other.playables) &&
          mixOffset == other.mixOffset &&
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
          audioBitrate == other.audioBitrate &&
          audioSampleRate == other.audioSampleRate &&
          audioChannels == other.audioChannels;

  @override
  int get hashCode => Object.hashAll([
    index,
    Object.hashAll(playables),
    mixOffset,
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
    audioBitrate,
    audioSampleRate,
    audioChannels,
  ]);
}
