import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

import '../../playback/domain/playback_state.dart';
import '../../playback/domain/queue_item.dart';

typedef LoopMode = Loop;

@immutable
class AppSettings {
  // Library Paths
  final List<String> musicDirectories;

  // Audio Playback
  final bool crossfadeEnabled;
  final int crossfadeDuration; // 1 to 12 seconds (default 5)
  final CrossfadeCurve crossfadeCurve; // 'equal_power' or 'linear'
  final double volume; // 0.0 to 100.0 (default 100.0)
  final double playbackRate; // 0.5 to 1.5 (default 1.0)
  final double playbackPitch; // 0.5 to 1.5 (default 1.0)
  final Loop loopMode; // Loop.off (default)
  final bool shuffle; // default false
  final ReplayGainMode replayGain; // ReplayGainMode.off
  final double replayGainPreamp; // -15.0 to +15.0 dB (default 0.0)
  final double volumeBoost; // 100.0% to 200.0% (default 100.0)
  final bool exclusiveAudio; // Windows WASAPI exclusive (default false)

  // Appearance & Localization
  final ThemeMode themeMode; // ThemeMode.dark (default)
  final String appLanguage; // 'defaultOption', 'en', 'es'

  // Restorable Playback State
  final String? lastPlayedUri;
  final int lastPlayedPositionMs;

  // Equalizer
  final bool equalizerEnabled;
  final List<double> equalizerGains; // 10 bands (-12.0 to +12.0 dB)

  const AppSettings({
    this.musicDirectories = const [],
    this.crossfadeEnabled = true,
    this.crossfadeDuration = 5,
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.volume = 100.0,
    this.playbackRate = 1.0,
    this.playbackPitch = 1.0,
    this.loopMode = Loop.off,
    this.shuffle = false,
    this.replayGain = ReplayGainMode.off,
    this.replayGainPreamp = 0.0,
    this.volumeBoost = 100.0,
    this.exclusiveAudio = false,
    this.themeMode = ThemeMode.dark,
    this.appLanguage = 'defaultOption',
    this.lastPlayedUri,
    this.lastPlayedPositionMs = 0,
    this.equalizerEnabled = false,
    this.equalizerGains = const [
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
    ],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          listEquals(musicDirectories, other.musicDirectories) &&
          crossfadeEnabled == other.crossfadeEnabled &&
          crossfadeDuration == other.crossfadeDuration &&
          crossfadeCurve == other.crossfadeCurve &&
          volume == other.volume &&
          playbackRate == other.playbackRate &&
          playbackPitch == other.playbackPitch &&
          loopMode == other.loopMode &&
          shuffle == other.shuffle &&
          replayGain == other.replayGain &&
          replayGainPreamp == other.replayGainPreamp &&
          volumeBoost == other.volumeBoost &&
          exclusiveAudio == other.exclusiveAudio &&
          themeMode == other.themeMode &&
          appLanguage == other.appLanguage &&
          lastPlayedUri == other.lastPlayedUri &&
          lastPlayedPositionMs == other.lastPlayedPositionMs &&
          equalizerEnabled == other.equalizerEnabled &&
          listEquals(equalizerGains, other.equalizerGains);

  AppSettings copyWith({
    List<String>? musicDirectories,
    bool? crossfadeEnabled,
    int? crossfadeDuration,
    CrossfadeCurve? crossfadeCurve,
    double? volume,
    double? playbackRate,
    double? playbackPitch,
    Loop? loopMode,
    bool? shuffle,
    ReplayGainMode? replayGain,
    double? replayGainPreamp,
    double? volumeBoost,
    bool? exclusiveAudio,
    ThemeMode? themeMode,
    String? appLanguage,
    String? lastPlayedUri,
    int? lastPlayedPositionMs,
    bool? equalizerEnabled,
    List<double>? equalizerGains,
  }) {
    return AppSettings(
      musicDirectories: musicDirectories ?? this.musicDirectories,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
      playbackPitch: playbackPitch ?? this.playbackPitch,
      loopMode: loopMode ?? this.loopMode,
      shuffle: shuffle ?? this.shuffle,
      replayGain: replayGain ?? this.replayGain,
      replayGainPreamp: replayGainPreamp ?? this.replayGainPreamp,
      volumeBoost: volumeBoost ?? this.volumeBoost,
      exclusiveAudio: exclusiveAudio ?? this.exclusiveAudio,
      themeMode: themeMode ?? this.themeMode,
      appLanguage: appLanguage ?? this.appLanguage,
      lastPlayedUri: lastPlayedUri ?? this.lastPlayedUri,
      lastPlayedPositionMs: lastPlayedPositionMs ?? this.lastPlayedPositionMs,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerGains: equalizerGains ?? this.equalizerGains,
    );
  }

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(musicDirectories),
    crossfadeEnabled,
    crossfadeDuration,
    crossfadeCurve,
    volume,
    playbackRate,
    playbackPitch,
    loopMode,
    shuffle,
    replayGain,
    replayGainPreamp,
    volumeBoost,
    exclusiveAudio,
    themeMode,
    appLanguage,
    lastPlayedUri,
    lastPlayedPositionMs,
    equalizerEnabled,
    Object.hashAll(equalizerGains),
  ]);
}
