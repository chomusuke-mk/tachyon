import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show CrossfeedMode, Reverb;
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/lyrics/domain/lyrics_display_mode.dart';
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/core/playback/domain/loop_mode.dart';

export 'package:miniaudio_player/miniaudio_player.dart'
    show CrossfeedMode, Reverb;
export 'package:tachyon/core/playback/domain/crossfade_config.dart'
    show CrossfadeCurve;
export 'package:tachyon/core/playback/domain/loop_mode.dart'
    show Loop, LoopMode;

@immutable
class AppSettings {
  // Library Paths
  final List<String> musicDirectories;

  // Audio Playback
  final int crossfadeDuration; // 0 to 30 seconds (default 5)
  final int crossfadeManualDuration; // 0 to 5 seconds (default 1)
  final CrossfadeCurve crossfadeCurve; // 'equal_power' or 'linear'
  final double volume; // 0.0 to 1.0 (default 1.0)
  final double playbackRate; // 0.5 to 1.5 (default 1.0)
  final double playbackPitch; // 0.5 to 1.5 (default 1.0)
  final LoopMode loopMode; // LoopMode.off (default)
  final bool shuffle; // default false
  final bool skipSilence; // default false
  final bool volumeNormalization; // default true
  final double preampDb; // -12.0 to +12.0 dB (default 0.0)
  final double balance; // -1.0 to +1.0 (default 0.0)
  final bool mono; // default false
  final CrossfeedMode crossfeedMode; // CrossfeedMode.off (default)
  final double spatializerWidth; // 0.0 to 2.0 (default 1.0)
  final bool limiterEnabled; // default true
  final double volumeBoost; // 1.0 to 2.0 (default 1.0)
  final bool exclusiveAudio; // Windows WASAPI exclusive (default false)
  final bool pauseOnDeviceChange; // default true
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
  final AlbumSortOption albumSortOption;
  final bool albumSortAscending;
  final ArtistSortOption artistSortOption;
  final bool artistSortAscending;

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

  // Reverb
  final bool reverbEnabled;
  final String reverbPreset;
  final double reverbRoomSize;
  final double reverbDamping;
  final double reverbWidth;
  final double reverbWet;
  final double reverbDry;

  const AppSettings({
    this.musicDirectories = const [],
    this.crossfadeDuration = 5,
    this.crossfadeManualDuration = 1,
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.volume = 1.0,
    this.playbackRate = 1.0,
    this.playbackPitch = 1.0,
    this.loopMode = Loop.off,
    this.shuffle = false,
    this.skipSilence = false,
    this.volumeNormalization = true,
    this.preampDb = 0.0,
    this.balance = 0.0,
    this.mono = false,
    this.crossfeedMode = CrossfeedMode.off,
    this.spatializerWidth = 1.0,
    this.limiterEnabled = true,
    this.volumeBoost = 1.0,
    this.exclusiveAudio = false,
    this.pauseOnDeviceChange = true,
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
    this.albumSortOption = AlbumSortOption.title,
    this.albumSortAscending = true,
    this.artistSortOption = ArtistSortOption.name,
    this.artistSortAscending = true,
    this.lyricsDisplayMode = LyricsDisplayMode.original,
    this.playbackShowLyrics = false,
    this.playbackShowQueue = false,
    required this.lastPlayedFilePath,
    this.lastPlayedPositionMs = 0,
    this.equalizerEnabled = true,
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
    this.reverbEnabled = false,
    this.reverbPreset = 'off',
    this.reverbRoomSize = 0.0,
    this.reverbDamping = 0.0,
    this.reverbWidth = 1.0,
    this.reverbWet = 0.0,
    this.reverbDry = 1.0,
  });

  Color get accentColor => Color(accentColorValue);

  Reverb get reverbConfig => (reverbEnabled && reverbPreset != 'off')
      ? Reverb(
          enabled: true,
          roomSize: reverbRoomSize,
          damping: reverbDamping,
          width: reverbWidth,
          wet: reverbWet,
          dry: reverbDry,
        )
      : Reverb.off;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          listEquals(musicDirectories, other.musicDirectories) &&
          crossfadeDuration == other.crossfadeDuration &&
          crossfadeManualDuration == other.crossfadeManualDuration &&
          crossfadeCurve == other.crossfadeCurve &&
          volume == other.volume &&
          playbackRate == other.playbackRate &&
          playbackPitch == other.playbackPitch &&
          loopMode == other.loopMode &&
          shuffle == other.shuffle &&
          skipSilence == other.skipSilence &&
          volumeNormalization == other.volumeNormalization &&
          preampDb == other.preampDb &&
          balance == other.balance &&
          mono == other.mono &&
          crossfeedMode == other.crossfeedMode &&
          spatializerWidth == other.spatializerWidth &&
          limiterEnabled == other.limiterEnabled &&
          volumeBoost == other.volumeBoost &&
          exclusiveAudio == other.exclusiveAudio &&
          pauseOnDeviceChange == other.pauseOnDeviceChange &&
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
          albumSortOption == other.albumSortOption &&
          albumSortAscending == other.albumSortAscending &&
          artistSortOption == other.artistSortOption &&
          artistSortAscending == other.artistSortAscending &&
          lyricsDisplayMode == other.lyricsDisplayMode &&
          playbackShowLyrics == other.playbackShowLyrics &&
          playbackShowQueue == other.playbackShowQueue &&
          lastPlayedFilePath == other.lastPlayedFilePath &&
          lastPlayedPositionMs == other.lastPlayedPositionMs &&
          equalizerEnabled == other.equalizerEnabled &&
          equalizerPreset == other.equalizerPreset &&
          listEquals(equalizerGains, other.equalizerGains) &&
          reverbEnabled == other.reverbEnabled &&
          reverbPreset == other.reverbPreset &&
          reverbRoomSize == other.reverbRoomSize &&
          reverbDamping == other.reverbDamping &&
          reverbWidth == other.reverbWidth &&
          reverbWet == other.reverbWet &&
          reverbDry == other.reverbDry;

  AppSettings copyWith({
    List<String>? musicDirectories,
    int? crossfadeDuration,
    int? crossfadeManualDuration,
    CrossfadeCurve? crossfadeCurve,
    double? volume,
    double? playbackRate,
    double? playbackPitch,
    Loop? loopMode,
    bool? shuffle,
    bool? skipSilence,
    bool? volumeNormalization,
    double? preampDb,
    double? balance,
    bool? mono,
    CrossfeedMode? crossfeedMode,
    double? spatializerWidth,
    bool? limiterEnabled,
    double? volumeBoost,
    bool? exclusiveAudio,
    bool? pauseOnDeviceChange,
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
    AlbumSortOption? albumSortOption,
    bool? albumSortAscending,
    ArtistSortOption? artistSortOption,
    bool? artistSortAscending,
    LyricsDisplayMode? lyricsDisplayMode,
    bool? playbackShowLyrics,
    bool? playbackShowQueue,
    String? lastPlayedFilePath,
    int? lastPlayedPositionMs,
    bool? equalizerEnabled,
    String? equalizerPreset,
    List<double>? equalizerGains,
    bool? reverbEnabled,
    String? reverbPreset,
    double? reverbRoomSize,
    double? reverbDamping,
    double? reverbWidth,
    double? reverbWet,
    double? reverbDry,
  }) {
    return AppSettings(
      musicDirectories: musicDirectories ?? this.musicDirectories,
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
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      preampDb: preampDb ?? this.preampDb,
      balance: balance ?? this.balance,
      mono: mono ?? this.mono,
      crossfeedMode: crossfeedMode ?? this.crossfeedMode,
      spatializerWidth: spatializerWidth ?? this.spatializerWidth,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      volumeBoost: volumeBoost ?? this.volumeBoost,
      exclusiveAudio: exclusiveAudio ?? this.exclusiveAudio,
      pauseOnDeviceChange: pauseOnDeviceChange ?? this.pauseOnDeviceChange,
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
      albumSortOption: albumSortOption ?? this.albumSortOption,
      albumSortAscending: albumSortAscending ?? this.albumSortAscending,
      artistSortOption: artistSortOption ?? this.artistSortOption,
      artistSortAscending: artistSortAscending ?? this.artistSortAscending,
      lyricsDisplayMode: lyricsDisplayMode ?? this.lyricsDisplayMode,
      playbackShowLyrics: playbackShowLyrics ?? this.playbackShowLyrics,
      playbackShowQueue: playbackShowQueue ?? this.playbackShowQueue,
      lastPlayedFilePath: lastPlayedFilePath ?? this.lastPlayedFilePath,
      lastPlayedPositionMs: lastPlayedPositionMs ?? this.lastPlayedPositionMs,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      equalizerGains: equalizerGains ?? this.equalizerGains,
      reverbEnabled: reverbEnabled ?? this.reverbEnabled,
      reverbPreset: reverbPreset ?? this.reverbPreset,
      reverbRoomSize: reverbRoomSize ?? this.reverbRoomSize,
      reverbDamping: reverbDamping ?? this.reverbDamping,
      reverbWidth: reverbWidth ?? this.reverbWidth,
      reverbWet: reverbWet ?? this.reverbWet,
      reverbDry: reverbDry ?? this.reverbDry,
    );
  }

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(musicDirectories),
    crossfadeDuration,
    crossfadeManualDuration,
    crossfadeCurve,
    volume,
    playbackRate,
    playbackPitch,
    loopMode,
    shuffle,
    skipSilence,
    volumeNormalization,
    preampDb,
    balance,
    mono,
    crossfeedMode,
    spatializerWidth,
    limiterEnabled,
    volumeBoost,
    exclusiveAudio,
    pauseOnDeviceChange,
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
    albumSortOption,
    albumSortAscending,
    artistSortOption,
    artistSortAscending,
    lyricsDisplayMode,
    playbackShowLyrics,
    playbackShowQueue,
    lastPlayedFilePath,
    lastPlayedPositionMs,
    equalizerEnabled,
    equalizerPreset,
    Object.hashAll(equalizerGains),
    reverbEnabled,
    reverbPreset,
    reverbRoomSize,
    reverbDamping,
    reverbWidth,
    reverbWet,
    reverbDry,
  ]);
}
