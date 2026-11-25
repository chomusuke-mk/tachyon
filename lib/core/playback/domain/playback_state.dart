import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/store/domain/track.dart';

import 'crossfade_config.dart';
import 'loop_mode.dart';

export 'package:miniaudio_player/miniaudio_player.dart'
    show
        Crossfeed,
        SilenceSkipMode,
        ReplayGainMode,
        Buffer,
        VisualizerData,
        AudioMetadata,
        AudioInfo;
export 'package:tachyon/core/playback/domain/audio_playable.dart';
export 'crossfade_config.dart';
export 'loop_mode.dart';

/// High-level transport lifecycle status derived from [PlaybackState].
enum PlaybackStatus {
  /// No active playback or playback was stopped at zero position.
  idle,

  /// Engine is currently loading or buffering audio data.
  loading,

  /// Audio is actively playing.
  playing,

  /// Playback is paused mid-track.
  paused,

  /// Playback reached the end of the active track or queue.
  completed,
}

/// Immutable snapshot of audio playback, queue, and DSP configuration state.
@immutable
class PlaybackState {
  /// Zero-based index of the active item in [queue].
  final int currentIndex;

  /// Current list of audio sources in the playback queue.
  final List<ma.AudioSource<AudioPlayable>> queue;

  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Whether the engine is currently buffering stream or track data.
  final bool isBuffering;

  /// Whether playback completed naturally at the end of the queue.
  final bool isCompleted;

  /// Current playback position within the active item.
  final Duration position;

  /// Total duration of the active item, or [Duration.zero] if unknown.
  final Duration duration;

  /// Playback speed multiplier.
  final double rate;

  /// Pitch multiplier independent of playback speed.
  final double pitch;

  /// Master output volume multiplier.
  final double volume;

  /// Whether queue shuffle order is enabled.
  final bool isShuffled;

  /// Active queue repeat mode.
  final LoopMode loopMode;

  /// Automatic crossfade transition duration between tracks.
  final Duration crossfadeDuration;

  /// Whether silence skipping is enabled.
  final bool skipSilence;

  /// Active silence skipping mode.
  final ma.SilenceSkipMode silenceSkipMode;

  /// Whether ReplayGain loudness normalization is enabled.
  final bool volumeNormalization;

  /// Active ReplayGain loudness normalization mode.
  final ma.ReplayGainMode replayGainMode;

  /// Whether infinite library mix auto-append is enabled.
  final bool isInfiniteMixEnabled;

  /// Detected audio bitrate in bits per second, if available.
  final double? audioBitrate;

  /// Detected audio sample rate in Hz, if available.
  final int? audioSampleRate;

  /// Number of audio channels in the active stream, if available.
  final int? audioChannels;

  /// Digital preamp gain offset in decibels.
  final double preampDb;

  /// Stereo channel balance in `[-1.0, 1.0]`.
  final double balance;

  /// Whether stereo-to-mono downmixing is enabled.
  final bool mono;

  /// Active Bauer stereo-to-binaural crossfeed preset.
  final ma.Crossfeed crossfeed;

  /// Stereo field spatializer width factor.
  final double spatializerWidth;

  /// Whether the true-peak output limiter is enabled.
  final bool limiterEnabled;

  /// Creates an immutable [PlaybackState] snapshot.
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
    this.silenceSkipMode = ma.SilenceSkipMode.disabled,
    this.volumeNormalization = true,
    this.replayGainMode = ma.ReplayGainMode.track,
    this.isInfiniteMixEnabled = false,
    this.audioBitrate,
    this.audioSampleRate,
    this.audioChannels,
    this.preampDb = 0.0,
    this.balance = 0.0,
    this.mono = false,
    this.crossfeed = ma.Crossfeed.off,
    this.spatializerWidth = 1.0,
    this.limiterEnabled = true,
  });

  /// Creates the default initial [PlaybackState] before playback starts.
  const PlaybackState.initial() : this();

  /// Active queue entry at [currentIndex], or `null` when out of bounds.
  ma.AudioSource<AudioPlayable>? get currentEntry =>
      (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;

  /// Active [AudioPlayable] from [currentEntry], or `null` if unavailable.
  AudioPlayable? get currentPlayable => currentEntry?.data;

  /// Active library [Track], or `null` if idle or playing a non-track source.
  Track? get currentTrack =>
      currentPlayable is Track ? currentPlayable as Track : null;

  /// Whether the active item is a continuous live stream.
  bool get isLiveStream =>
      currentPlayable?.isStream ?? (currentEntry?.data?.isStream ?? false);

  /// Whether skipping forward to a next item is possible.
  bool get hasNext =>
      loopMode == LoopMode.all ||
      loopMode == LoopMode.one ||
      currentIndex < queue.length - 1 ||
      (isInfiniteMixEnabled && queue.isNotEmpty);

  /// Whether navigating to a previous item or restarting the track is possible.
  bool get hasPrevious =>
      loopMode == LoopMode.all || currentIndex > 0 || position.inSeconds > 3;

  /// Normalized playback progress in `[0.0, 1.0]`.
  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  /// Remaining duration before the end of the active track.
  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  /// High-level [PlaybackStatus] derived from the current transport flags.
  PlaybackStatus get status {
    if (isBuffering) return PlaybackStatus.loading;
    if (isCompleted) return PlaybackStatus.completed;
    if (isPlaying) return PlaybackStatus.playing;
    if (position > Duration.zero && !isPlaying) return PlaybackStatus.paused;
    return PlaybackStatus.idle;
  }

  /// Crossfade configuration derived from [crossfadeDuration].
  CrossfadeConfig get crossfadeConfig =>
      CrossfadeConfig(duration: crossfadeDuration);

  /// Returns a copy of this state with the given fields replaced.
  PlaybackState copyWith({
    int? currentIndex,
    List<ma.AudioSource<AudioPlayable>>? queue,
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
    ma.SilenceSkipMode? silenceSkipMode,
    bool? volumeNormalization,
    ma.ReplayGainMode? replayGainMode,
    bool? isInfiniteMixEnabled,
    double? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    double? preampDb,
    double? balance,
    bool? mono,
    ma.Crossfeed? crossfeed,
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
      silenceSkipMode: silenceSkipMode ?? this.silenceSkipMode,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      replayGainMode: replayGainMode ?? this.replayGainMode,
      isInfiniteMixEnabled: isInfiniteMixEnabled ?? this.isInfiniteMixEnabled,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      preampDb: preampDb ?? this.preampDb,
      balance: balance ?? this.balance,
      mono: mono ?? this.mono,
      crossfeed: crossfeed ?? this.crossfeed,
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
          silenceSkipMode == other.silenceSkipMode &&
          volumeNormalization == other.volumeNormalization &&
          replayGainMode == other.replayGainMode &&
          isInfiniteMixEnabled == other.isInfiniteMixEnabled &&
          audioBitrate == other.audioBitrate &&
          audioSampleRate == other.audioSampleRate &&
          audioChannels == other.audioChannels &&
          preampDb == other.preampDb &&
          balance == other.balance &&
          mono == other.mono &&
          crossfeed == other.crossfeed &&
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
    silenceSkipMode,
    volumeNormalization,
    replayGainMode,
    isInfiniteMixEnabled,
    audioBitrate,
    audioSampleRate,
    audioChannels,
    preampDb,
    balance,
    mono,
    crossfeed,
    spatializerWidth,
    limiterEnabled,
  ]);
}
