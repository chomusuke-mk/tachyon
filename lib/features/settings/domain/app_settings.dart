import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/loop_mode.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

typedef LoopMode = Loop;

@immutable
class AppSettings {
  // Library Paths
  final List<String> musicDirectories;

  // Audio Playback
  final bool crossfadeEnabled;
  final int crossfadeDuration; // 2 to 30 seconds (default 5)
  final int crossfadeManualDuration; // 0 to 30 seconds (default 3)
  final CrossfadeCurve crossfadeCurve; // 'equal_power' or 'linear'
  final double volume; // 0.0 to 100.0 (default 100.0)
  final double playbackRate; // 0.5 to 1.5 (default 1.0)
  final double playbackPitch; // 0.5 to 1.5 (default 1.0)
  final Loop loopMode; // Loop.off (default)
  final bool shuffle; // default false
  final bool skipSilence; // default false
  final double volumeBoost; // 100.0% to 200.0% (default 100.0)
  final bool exclusiveAudio; // Windows WASAPI exclusive (default false)
  final String? audioOutputDeviceId;

  // Appearance & Localization
  final ThemeMode themeMode; // ThemeMode.dark (default)
  final int accentColorValue; // default 0xFF7C4DFF (TachyonColors.electricVioletSeed)
  final bool isOledMode; // default false
  final String? customBackgroundPath; // default null
  final double backgroundBlurSigma; // default 20.0
  final double backgroundDimOpacity; // default 0.65
  final String appLanguage; // 'defaultOption', 'en', 'es'
  final String lyricsTranslationTargetLang; // 'defaultOption', 'es', 'en', etc.
  final String lyricsTranslationSourceLang; // 'auto', 'en', 'es', etc.

  // Library Sorting
  final TrackSortOption trackSortOption;
  final bool trackSortAscending;

  // Playback & Lyrics View Persistence
  final LyricsDisplayMode lyricsDisplayMode;
  final bool playbackShowLyrics;
  final bool playbackShowQueue;

  // Restorable Playback State
  final String? lastPlayedFilePath;
  final int lastPlayedPositionMs;

  // Equalizer
  final bool equalizerEnabled;
  final String equalizerPreset;
  final List<double> equalizerGains; // 10 bands (-24.0 to +24.0 dB)

  const AppSettings({
    this.musicDirectories = const [],
    this.crossfadeEnabled = true,
    this.crossfadeDuration = 5,
    this.crossfadeManualDuration = 3,
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.volume = 100.0,
    this.playbackRate = 1.0,
    this.playbackPitch = 1.0,
    this.loopMode = Loop.off,
    this.shuffle = false,
    this.skipSilence = false,
    this.volumeBoost = 100.0,
    this.exclusiveAudio = false,
    this.audioOutputDeviceId,
    this.themeMode = ThemeMode.dark,
    this.accentColorValue = 0xFF7C4DFF,
    this.isOledMode = false,
    this.customBackgroundPath,
    this.backgroundBlurSigma = 20.0,
    this.backgroundDimOpacity = 0.65,
    this.appLanguage = 'defaultOption',
    this.lyricsTranslationTargetLang = 'defaultOption',
    this.lyricsTranslationSourceLang = 'auto',
    this.trackSortOption = TrackSortOption.title,
    this.trackSortAscending = true,
    this.lyricsDisplayMode = LyricsDisplayMode.original,
    this.playbackShowLyrics = false,
    this.playbackShowQueue = false,
    required this.lastPlayedFilePath,
    this.lastPlayedPositionMs = 0,
    this.equalizerEnabled = false,
    this.equalizerPreset = 'flat',
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

  Color get accentColor => Color(accentColorValue);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          listEquals(musicDirectories, other.musicDirectories) &&
          crossfadeEnabled == other.crossfadeEnabled &&
          crossfadeDuration == other.crossfadeDuration &&
          crossfadeManualDuration == other.crossfadeManualDuration &&
          crossfadeCurve == other.crossfadeCurve &&
          volume == other.volume &&
          playbackRate == other.playbackRate &&
          playbackPitch == other.playbackPitch &&
          loopMode == other.loopMode &&
          shuffle == other.shuffle &&
          skipSilence == other.skipSilence &&
          volumeBoost == other.volumeBoost &&
          exclusiveAudio == other.exclusiveAudio &&
          audioOutputDeviceId == other.audioOutputDeviceId &&
          themeMode == other.themeMode &&
          accentColorValue == other.accentColorValue &&
          isOledMode == other.isOledMode &&
          customBackgroundPath == other.customBackgroundPath &&
          backgroundBlurSigma == other.backgroundBlurSigma &&
          backgroundDimOpacity == other.backgroundDimOpacity &&
          appLanguage == other.appLanguage &&
          lyricsTranslationTargetLang == other.lyricsTranslationTargetLang &&
          lyricsTranslationSourceLang == other.lyricsTranslationSourceLang &&
          trackSortOption == other.trackSortOption &&
          trackSortAscending == other.trackSortAscending &&
          lyricsDisplayMode == other.lyricsDisplayMode &&
          playbackShowLyrics == other.playbackShowLyrics &&
          playbackShowQueue == other.playbackShowQueue &&
          lastPlayedFilePath == other.lastPlayedFilePath &&
          lastPlayedPositionMs == other.lastPlayedPositionMs &&
          equalizerEnabled == other.equalizerEnabled &&
          equalizerPreset == other.equalizerPreset &&
          listEquals(equalizerGains, other.equalizerGains);

  AppSettings copyWith({
    List<String>? musicDirectories,
    bool? crossfadeEnabled,
    int? crossfadeDuration,
    int? crossfadeManualDuration,
    CrossfadeCurve? crossfadeCurve,
    double? volume,
    double? playbackRate,
    double? playbackPitch,
    Loop? loopMode,
    bool? shuffle,
    bool? skipSilence,
    double? volumeBoost,
    bool? exclusiveAudio,
    String? audioOutputDeviceId,
    ThemeMode? themeMode,
    int? accentColorValue,
    bool? isOledMode,
    String? customBackgroundPath,
    bool clearCustomBackground = false,
    double? backgroundBlurSigma,
    double? backgroundDimOpacity,
    String? appLanguage,
    String? lyricsTranslationTargetLang,
    String? lyricsTranslationSourceLang,
    TrackSortOption? trackSortOption,
    bool? trackSortAscending,
    LyricsDisplayMode? lyricsDisplayMode,
    bool? playbackShowLyrics,
    bool? playbackShowQueue,
    String? lastPlayedFilePath,
    int? lastPlayedPositionMs,
    bool? equalizerEnabled,
    String? equalizerPreset,
    List<double>? equalizerGains,
  }) {
    return AppSettings(
      musicDirectories: musicDirectories ?? this.musicDirectories,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      crossfadeManualDuration:
          crossfadeManualDuration ?? this.crossfadeManualDuration,
      crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
      playbackPitch: playbackPitch ?? this.playbackPitch,
      loopMode: loopMode ?? this.loopMode,
      shuffle: shuffle ?? this.shuffle,
      skipSilence: skipSilence ?? this.skipSilence,
      volumeBoost: volumeBoost ?? this.volumeBoost,
      exclusiveAudio: exclusiveAudio ?? this.exclusiveAudio,
      audioOutputDeviceId: audioOutputDeviceId ?? this.audioOutputDeviceId,
      themeMode: themeMode ?? this.themeMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      isOledMode: isOledMode ?? this.isOledMode,
      customBackgroundPath: clearCustomBackground
          ? null
          : (customBackgroundPath ?? this.customBackgroundPath),
      backgroundBlurSigma: backgroundBlurSigma ?? this.backgroundBlurSigma,
      backgroundDimOpacity: backgroundDimOpacity ?? this.backgroundDimOpacity,
      appLanguage: appLanguage ?? this.appLanguage,
      lyricsTranslationTargetLang:
          lyricsTranslationTargetLang ?? this.lyricsTranslationTargetLang,
      lyricsTranslationSourceLang:
          lyricsTranslationSourceLang ?? this.lyricsTranslationSourceLang,
      trackSortOption: trackSortOption ?? this.trackSortOption,
      trackSortAscending: trackSortAscending ?? this.trackSortAscending,
      lyricsDisplayMode: lyricsDisplayMode ?? this.lyricsDisplayMode,
      playbackShowLyrics: playbackShowLyrics ?? this.playbackShowLyrics,
      playbackShowQueue: playbackShowQueue ?? this.playbackShowQueue,
      lastPlayedFilePath: lastPlayedFilePath ?? this.lastPlayedFilePath,
      lastPlayedPositionMs: lastPlayedPositionMs ?? this.lastPlayedPositionMs,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      equalizerGains: equalizerGains ?? this.equalizerGains,
    );
  }

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(musicDirectories),
    crossfadeEnabled,
    crossfadeDuration,
    crossfadeManualDuration,
    crossfadeCurve,
    volume,
    playbackRate,
    playbackPitch,
    loopMode,
    shuffle,
    skipSilence,
    volumeBoost,
    exclusiveAudio,
    audioOutputDeviceId,
    themeMode,
    accentColorValue,
    isOledMode,
    customBackgroundPath,
    backgroundBlurSigma,
    backgroundDimOpacity,
    appLanguage,
    lyricsTranslationTargetLang,
    lyricsTranslationSourceLang,
    trackSortOption,
    trackSortAscending,
    lyricsDisplayMode,
    playbackShowLyrics,
    playbackShowQueue,
    lastPlayedFilePath,
    lastPlayedPositionMs,
    equalizerEnabled,
    equalizerPreset,
    Object.hashAll(equalizerGains),
  ]);
}
