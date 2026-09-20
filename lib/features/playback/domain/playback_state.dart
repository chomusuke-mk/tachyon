import 'package:flutter/foundation.dart';
import 'package:tachyon/core/constants/app_defaults.dart';

import 'crossfade_config.dart';
import 'queue_item.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

@immutable
class PlaybackState {
  final int index;
  final List<QueueItem> playables;
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

  QueueItem? get currentTrack =>
      (index >= 0 && index < playables.length) ? playables[index] : null;

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
  List<QueueItem> get queue => playables;
  int get currentIndex => index;
  Loop get loopMode => loop;
  bool get isShuffled => shuffle;
  CrossfadeConfig get crossfadeConfig =>
      CrossfadeConfig(duration: crossfadeDuration);

  PlaybackState copyWith({
    int? index,
    List<QueueItem>? playables,
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

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'playables': playables.map((p) => p.toJson()).toList(),
      'mixOffset': mixOffset,
      'playing': playing,
      'buffering': buffering,
      'completed': completed,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'rate': rate,
      'pitch': pitch,
      'volume': volume,
      'shuffle': shuffle,
      'loop': loop.index,
      'crossfadeDurationMs': crossfadeDuration.inMilliseconds,
      'skipSilence': skipSilence,
      'audioBitrate': audioBitrate,
      'audioSampleRate': audioSampleRate,
      'audioChannels': audioChannels,
    };
  }

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      index: json['index'] as int? ?? 0,
      playables:
          (json['playables'] as List<dynamic>?)
              ?.map((e) => QueueItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      mixOffset: json['mixOffset'] as int?,
      playing: json['playing'] as bool? ?? false,
      buffering: json['buffering'] as bool? ?? false,
      completed: json['completed'] as bool? ?? false,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      rate:
          (json['rate'] as num?)?.toDouble() ?? AppDefaults.playbackRateDefault,
      pitch:
          (json['pitch'] as num?)?.toDouble() ??
          AppDefaults.playbackPitchDefault,
      volume: (json['volume'] as num?)?.toDouble() ?? AppDefaults.volumeDefault,
      shuffle: json['shuffle'] as bool? ?? false,
      loop: Loop.fromString(json['loop'] as String?),
      crossfadeDuration: Duration(
        milliseconds:
            ((json['crossfadeDurationMs'] ??
                        AppDefaults.crossfadeDefaultDuration * 1000)
                    as num)
                .toInt(),
      ),
      skipSilence: json['skipSilence'] as bool? ?? false,
      audioBitrate: (json['audioBitrate'] as num?)?.toDouble(),
      audioSampleRate: json['audioSampleRate'] as int?,
      audioChannels: json['audioChannels'] as int?,
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
