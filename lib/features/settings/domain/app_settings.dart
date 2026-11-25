import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show
        Crossfeed,
        ReplayGainMode,
        Reverb,
        SilenceSkipConfig,
        SilenceSkipMode;
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/lyrics/domain/lyrics_display_mode.dart';
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/core/playback/domain/loop_mode.dart';

/// Immutable snapshot of user-configurable application, library, audio, and
/// appearance settings.
@immutable
class AppSettings {
  /// Configured local directory paths scanned for audio tracks.
  final List<String> musicDirectories;

  /// Configured individual local audio file paths and remote stream URLs.
  final List<String> musicFiles;

  /// Automatic track-to-track crossfade duration in seconds.
  ///
  /// Defaults to `5` (valid persisted range `0` to `30`).
  final int crossfadeDuration;

  /// Manual track-skip crossfade duration in seconds.
  ///
  /// Defaults to `1` (valid persisted range `0` to `5`).
  final int crossfadeManualDuration;

  /// Gain interpolation curve applied during crossfade transitions.
  ///
  /// Defaults to [CrossfadeCurve.equalPower].
  final CrossfadeCurve crossfadeCurve;

  /// Playback output volume factor in the range `0.0` to `1.0`.
  ///
  /// Defaults to `1.0`.
  final double volume;

  /// Playback speed multiplier in the range `0.5` to `1.5`.
  ///
  /// Defaults to `1.0`.
  final double playbackRate;

  /// Playback pitch multiplier in the range `0.5` to `1.5`.
  ///
  /// Defaults to `1.0`.
  final double playbackPitch;

  /// Active queue repeat mode.
  ///
  /// Defaults to [LoopMode.off].
  final LoopMode loopMode;

  /// Whether queue playback shuffling is enabled.
  final bool shuffle;

  /// Whether automatic silence skipping is enabled during playback.
  final bool skipSilence;

  /// Silence detection strategy applied when [skipSilence] is enabled.
  ///
  /// Defaults to [SilenceSkipMode.all].
  final SilenceSkipMode silenceSkipMode;

  /// Whether ReplayGain loudness normalization is enabled.
  final bool volumeNormalization;

  /// Pre-amplifier gain offset in decibels (`-12.0` to `+12.0` dB).
  ///
  /// Defaults to `0.0`.
  final double preampDb;

  /// Stereo left-to-right pan balance (`-1.0` full left to `1.0` full right).
  ///
  /// Defaults to `0.0`.
  final double balance;

  /// Whether stereo audio output is downmixed to mono.
  final bool mono;

  /// Headphone crossfeed configuration blending left and right channels.
  ///
  /// Defaults to [Crossfeed.off].
  final Crossfeed crossfeed;

  /// Stereo spatializer width factor (`0.0` to `2.0`).
  ///
  /// Defaults to `1.0`.
  final double spatializerWidth;

  /// Whether the output peak limiter is enabled to prevent clipping.
  final bool limiterEnabled;

  /// Additional volume boost multiplier (`1.0` to `2.0`).
  ///
  /// Defaults to `1.0`.
  final double volumeBoost;

  /// Whether Windows WASAPI exclusive audio output mode is enabled.
  final bool exclusiveAudio;

  /// Whether playback pauses automatically when the audio output device changes.
  final bool pauseOnDeviceChange;

  /// Identifier of the selected audio output device, or `null` for default.
  final String? audioOutputDeviceId;

  /// Active application brightness theme mode.
  ///
  /// Defaults to [ThemeMode.dark] in [AppSettings.new].
  final ThemeMode themeMode;

  /// ARGB integer value of the selected accent seed color.
  ///
  /// Defaults to `0xFF7C4DFF`.
  final int accentColorValue;

  /// Whether pure-black OLED surfaces are used in dark theme.
  final bool isOledMode;

  /// Path or storage key of the custom background image, or `null` if unset.
  final String? customBackgroundPath;

  /// Gaussian blur sigma applied to the custom background image.
  ///
  /// Defaults to `20.0`.
  final double backgroundBlurSigma;

  /// Darkening overlay opacity applied over the custom background image.
  ///
  /// Defaults to `0.65`.
  final double backgroundDimOpacity;

  /// Selected UI language code (`'defaultOption'`, `'en'`, `'es'`, etc.).
  final String appLanguage;

  /// Target language code for lyrics translation (`'defaultOption'`, `'en'`, `'es'`, etc.).
  final String lyricsTranslationTargetLang;

  /// Source language code for lyrics translation (`'auto'`, `'en'`, `'es'`, etc.).
  final String lyricsTranslationSourceLang;

  /// Active sort criterion for the tracks library view.
  final TrackSortOption trackSortOption;

  /// Whether tracks are sorted in ascending order.
  final bool trackSortAscending;

  /// Active sort criterion for the albums library view.
  final AlbumSortOption albumSortOption;

  /// Whether albums are sorted in ascending order.
  final bool albumSortAscending;

  /// Active sort criterion for the artists library view.
  final ArtistSortOption artistSortOption;

  /// Whether artists are sorted in ascending order.
  final bool artistSortAscending;

  /// Display mode controlling original and translated lyrics rendering.
  final LyricsDisplayMode lyricsDisplayMode;

  /// Whether the lyrics panel is visible on the now-playing view.
  final bool playbackShowLyrics;

  /// Whether the playback queue panel is visible on the now-playing view.
  final bool playbackShowQueue;

  /// File path or URL of the last played track, or `null` if none was recorded.
  final String? lastPlayedFilePath;

  /// Last recorded playback position in milliseconds.
  final int lastPlayedPositionMs;

  /// Whether the 10-band graphic equalizer is enabled.
  final bool equalizerEnabled;

  /// Identifier of the active equalizer preset (for example `'flat'` or `'custom'`).
  final String equalizerPreset;

  /// Gain values in decibels (`-24.0` to `+24.0` dB) for each of the 10 equalizer bands.
  final List<double> equalizerGains;

  /// Whether the audio reverb effect is enabled.
  final bool reverbEnabled;

  /// Identifier of the active reverb preset (for example `'off'`, `'studio'`, or `'custom'`).
  final String reverbPreset;

  /// Reverb virtual room size parameter (`0.0` to `1.0`).
  final double reverbRoomSize;

  /// Reverb high-frequency damping factor (`0.0` to `1.0`).
  final double reverbDamping;

  /// Reverb stereo width factor (`0.0` to `1.0`).
  final double reverbWidth;

  /// Reverb wet signal mix level (`0.0` to `2.0`).
  final double reverbWet;

  /// Reverb dry signal mix level (`0.0` to `2.0`).
  final double reverbDry;

  /// Creates an immutable [AppSettings] instance.
  const AppSettings({
    this.musicDirectories = const [],
    this.musicFiles = const [],
    this.crossfadeDuration = 5,
    this.crossfadeManualDuration = 1,
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.volume = 1.0,
    this.playbackRate = 1.0,
    this.playbackPitch = 1.0,
    this.loopMode = LoopMode.off,
    this.shuffle = false,
    this.skipSilence = false,
    this.silenceSkipMode = SilenceSkipMode.all,
    this.volumeNormalization = true,
    this.preampDb = 0.0,
    this.balance = 0.0,
    this.mono = false,
    this.crossfeed = Crossfeed.off,
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

  /// Accent seed [Color] derived from [accentColorValue].
  Color get accentColor => Color(accentColorValue);

  /// Effective [SilenceSkipConfig] built from [skipSilence] and [silenceSkipMode].
  ///
  /// Falls back to [SilenceSkipMode.all] when [skipSilence] is `true` and
  /// [silenceSkipMode] is [SilenceSkipMode.disabled].
  SilenceSkipConfig get silenceSkipConfig => skipSilence
      ? SilenceSkipConfig(
          enabled: true,
          mode: silenceSkipMode == SilenceSkipMode.disabled
              ? SilenceSkipMode.all
              : silenceSkipMode,
        )
      : const SilenceSkipConfig.off();

  /// Effective [ReplayGainMode] derived from [volumeNormalization].
  ReplayGainMode get replayGainMode =>
      volumeNormalization ? ReplayGainMode.track : ReplayGainMode.disabled;

  /// Effective [Reverb] configuration built from [reverbEnabled], [reverbPreset],
  /// and the individual reverb parameters.
  ///
  /// Returns [Reverb.off] when reverb is disabled or [reverbPreset] is `'off'`.
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
          listEquals(musicFiles, other.musicFiles) &&
          crossfadeDuration == other.crossfadeDuration &&
          crossfadeManualDuration == other.crossfadeManualDuration &&
          crossfadeCurve == other.crossfadeCurve &&
          volume == other.volume &&
          playbackRate == other.playbackRate &&
          playbackPitch == other.playbackPitch &&
          loopMode == other.loopMode &&
          shuffle == other.shuffle &&
          skipSilence == other.skipSilence &&
          silenceSkipMode == other.silenceSkipMode &&
          volumeNormalization == other.volumeNormalization &&
          preampDb == other.preampDb &&
          balance == other.balance &&
          mono == other.mono &&
          crossfeed == other.crossfeed &&
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

  /// Returns a copy of this [AppSettings] with the specified fields updated.
  ///
  /// Pass [clearCustomBackground] as `true` to reset [customBackgroundPath] to
  /// `null`.
  AppSettings copyWith({
    List<String>? musicDirectories,
    List<String>? musicFiles,
    int? crossfadeDuration,
    int? crossfadeManualDuration,
    CrossfadeCurve? crossfadeCurve,
    double? volume,
    double? playbackRate,
    double? playbackPitch,
    LoopMode? loopMode,
    bool? shuffle,
    bool? skipSilence,
    SilenceSkipMode? silenceSkipMode,
    bool? volumeNormalization,
    double? preampDb,
    double? balance,
    bool? mono,
    Crossfeed? crossfeed,
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
      musicFiles: musicFiles ?? this.musicFiles,
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
      silenceSkipMode: silenceSkipMode ?? this.silenceSkipMode,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      preampDb: preampDb ?? this.preampDb,
      balance: balance ?? this.balance,
      mono: mono ?? this.mono,
      crossfeed: crossfeed ?? this.crossfeed,
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
    Object.hashAll(musicFiles),
    crossfadeDuration,
    crossfadeManualDuration,
    crossfadeCurve,
    volume,
    playbackRate,
    playbackPitch,
    loopMode,
    shuffle,
    skipSilence,
    silenceSkipMode,
    volumeNormalization,
    preampDb,
    balance,
    mono,
    crossfeed,
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
