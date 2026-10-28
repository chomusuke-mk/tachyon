import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/store/domain/track.dart';

import 'crossfade_config.dart';
import 'loop_mode.dart';

export 'package:miniaudio_player/miniaudio_player.dart' show CrossfeedMode;
export 'package:tachyon/core/playback/domain/audio_playable.dart';
export 'crossfade_config.dart';
export 'loop_mode.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

@immutable
class PlaybackState {
  final int currentIndex;
  final List<ma.EngineItem<AudioPlayable>> queue;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final double rate;
  final double pitch;
  final double volume;
  final bool isShuffled;
  final LoopMode loopMode;
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
  final ma.CrossfeedMode crossfeedMode;
  final double spatializerWidth;
  final bool limiterEnabled;

  const PlaybackState({
    this.currentIndex = 0,
    this.queue = const [],
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.isShuffled = false,
    this.loopMode = LoopMode.off,
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
    this.crossfeedMode = ma.CrossfeedMode.off,
    this.spatializerWidth = 1.0,
    this.limiterEnabled = true,
  });

  const PlaybackState.initial() : this();

  ma.EngineItem<AudioPlayable>? get currentEntry =>
      (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;

  AudioPlayable? get currentPlayable => currentEntry?.data;

  Track? get currentTrack =>
      currentPlayable is Track ? currentPlayable as Track : null;

  bool get hasNext =>
      loopMode == LoopMode.all ||
      loopMode == LoopMode.one ||
      currentIndex < queue.length - 1 ||
      (isInfiniteMixEnabled && queue.isNotEmpty);
  bool get hasPrevious =>
      loopMode == LoopMode.all || currentIndex > 0 || position.inSeconds > 3;

  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  PlaybackStatus get status {
    if (isBuffering) return PlaybackStatus.loading;
    if (isCompleted) return PlaybackStatus.completed;
    if (isPlaying) return PlaybackStatus.playing;
    if (position > Duration.zero && !isPlaying) return PlaybackStatus.paused;
    return PlaybackStatus.idle;
  }

  CrossfadeConfig get crossfadeConfig =>
      CrossfadeConfig(duration: crossfadeDuration);

  PlaybackState copyWith({
    int? currentIndex,
    List<ma.EngineItem<AudioPlayable>>? queue,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
    double? rate,
    double? pitch,
    double? volume,
    bool? isShuffled,
    LoopMode? loopMode,
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
    ma.CrossfeedMode? crossfeedMode,
    double? spatializerWidth,
    bool? limiterEnabled,
  }) {
    return PlaybackState(
      currentIndex: currentIndex ?? this.currentIndex,
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      isShuffled: isShuffled ?? this.isShuffled,
      loopMode: loopMode ?? this.loopMode,
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
          currentIndex == other.currentIndex &&
          listEquals(queue, other.queue) &&
          isPlaying == other.isPlaying &&
          isBuffering == other.isBuffering &&
          isCompleted == other.isCompleted &&
          position == other.position &&
          duration == other.duration &&
          rate == other.rate &&
          pitch == other.pitch &&
          volume == other.volume &&
          isShuffled == other.isShuffled &&
          loopMode == other.loopMode &&
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
    currentIndex,
    Object.hashAll(queue),
    isPlaying,
    isBuffering,
    isCompleted,
    position,
    duration,
    rate,
    pitch,
    volume,
    isShuffled,
    loopMode,
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
