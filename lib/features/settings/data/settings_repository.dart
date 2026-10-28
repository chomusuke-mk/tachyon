import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/core/lyrics/domain/lyrics_display_mode.dart';
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/core/playback/domain/loop_mode.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

export 'package:tachyon/core/playback/domain/crossfade_config.dart'
    show CrossfadeCurve;

class SettingsRepository {
  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  static const _keyMusicDirectories = 's_music_directories';
  static const _keyCrossfadeDuration = 's_crossfade_duration';
  static const _keyCrossfadeManualDuration = 's_crossfade_manual_duration';
  static const _keyCrossfadeCurve = 's_crossfade_curve';
  static const _keyVolume = 's_volume';
  static const _keyPlaybackRate = 's_playback_rate';
  static const _keyPlaybackPitch = 's_playback_pitch';
  static const _keyLoopMode = 's_loop_mode';
  static const _keyShuffle = 's_shuffle';
  static const _keySkipSilence = 's_skip_silence';
  static const _keyVolumeNormalization = 's_volume_normalization';
  static const _keyPreamp = 's_preamp';
  static const _keyBalance = 's_balance';
  static const _keyMono = 's_mono';
  static const _keyCrossfeed = 's_crossfeed';
  static const _keySpatializer = 's_spatializer';
  static const _keyLimiter = 's_limiter';
  static const _keyReverbEnabled = 's_reverb_enabled';
  static const _keyReverbPreset = 's_reverb_preset';
  static const _keyReverbRoomSize = 's_reverb_room_size';
  static const _keyReverbDamping = 's_reverb_damping';
  static const _keyReverbWidth = 's_reverb_width';
  static const _keyReverbWet = 's_reverb_wet';
  static const _keyReverbDry = 's_reverb_dry';
  static const _keyVolumeBoost = 's_volume_boost';
  static const _keyTheme = 's_theme';
  static const _keyLanguage = 's_language';
  static const _keyLastPlayedFilePath = 's_last_played_file_path';
  static const _keyLastPlayedPosition = 's_last_played_position';
  static const _keyEqualizerEnabled = 's_equalizer_enabled';
  static const _keyEqualizerGains = 's_equalizer_gains';
  static const _keyTrackSortBy = 's_track_sort_by';
  static const _keyTrackSortAscending = 's_track_sort_ascending';
  static const _keyAlbumSortBy = 's_album_sort_by';
  static const _keyAlbumSortAscending = 's_album_sort_ascending';
  static const _keyArtistSortBy = 's_artist_sort_by';
  static const _keyArtistSortAscending = 's_artist_sort_ascending';
  static const _keyLyricsDisplayMode = 's_lyrics_display_mode';
  static const _keyPlaybackShowLyrics = 's_playback_show_lyrics';
  static const _keyPlaybackShowQueue = 's_playback_show_queue';
  static const _keyLyricsTranslationTargetLang =
      's_lyrics_translation_target_lang';
  static const _keyLyricsTranslationSourceLang =
      's_lyrics_translation_source_lang';
  static const _keyAudioOutputDeviceId = 's_audio_output_device_id';
  static const _keyPauseOnDeviceChange = 's_pause_on_device_change';
  static const _keyEqualizerPreset = 's_equalizer_preset';
  static const _keyAccentColor = 's_accent_color_val';
  static const _keyIsOledMode = 's_is_oled_mode';
  static const _keyCustomBackgroundPath = 's_custom_bg_path';
  static const _keyBackgroundBlurSigma = 's_bg_blur_sigma';
  static const _keyBackgroundDimOpacity = 's_bg_dim_opacity';

  ThemeMode _getAppTheme() {
    final themeIndex = _prefs.getInt(_keyTheme);
    if (themeIndex == null) return ThemeMode.system;
    return ThemeMode.values[themeIndex];
  }

  List<double> getEqualizerGains() {
    final gainsStrings = _prefs.getStringList(_keyEqualizerGains);
    if (gainsStrings == null) {
      return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
    return gainsStrings.map((s) => double.tryParse(s) ?? 0.0).toList();
  }

  AppSettings getSettings() {
    return AppSettings(
      musicDirectories: _prefs.getStringList(_keyMusicDirectories) ?? [],
      crossfadeDuration: _prefs.getInt(_keyCrossfadeDuration) ?? 5,
      crossfadeManualDuration: _prefs.getInt(_keyCrossfadeManualDuration) ?? 1,
      crossfadeCurve: CrossfadeCurveExtension.fromString(
        _prefs.getString(_keyCrossfadeCurve),
      ),
      volume: () {
        final val = _prefs.getDouble(_keyVolume) ?? 1.0;
        return val > 1.0 ? (val / 100.0).clamp(0.0, 1.0) : val.clamp(0.0, 1.0);
      }(),
      playbackRate: _prefs.getDouble(_keyPlaybackRate) ?? 1.0,
      playbackPitch: _prefs.getDouble(_keyPlaybackPitch) ?? 1.0,
      loopMode: LoopModeExtension.fromString(_prefs.getString(_keyLoopMode)),
      shuffle: _prefs.getBool(_keyShuffle) ?? false,
      skipSilence: _prefs.getBool(_keySkipSilence) ?? false,
      volumeNormalization: _prefs.getBool(_keyVolumeNormalization) ?? true,
      preampDb: _prefs.getDouble(_keyPreamp) ?? 0.0,
      balance: _prefs.getDouble(_keyBalance) ?? 0.0,
      mono: _prefs.getBool(_keyMono) ?? false,
      crossfeedMode: CrossfeedMode.values.elementAtOrNull(
            _prefs.getInt(_keyCrossfeed) ?? 0,
          ) ??
          CrossfeedMode.off,
      spatializerWidth: _prefs.getDouble(_keySpatializer) ?? 1.0,
      limiterEnabled: _prefs.getBool(_keyLimiter) ?? true,
      volumeBoost: () {
        final val = _prefs.getDouble(_keyVolumeBoost) ?? 1.0;
        return val > 2.0 ? (val / 100.0).clamp(1.0, 2.0) : val.clamp(1.0, 2.0);
      }(),
      themeMode: _getAppTheme(),
      accentColorValue: _prefs.getInt(_keyAccentColor) ?? 0xFF7C4DFF,
      isOledMode: _prefs.getBool(_keyIsOledMode) ?? false,
      customBackgroundPath: _prefs.getString(_keyCustomBackgroundPath),
      backgroundBlurSigma: _prefs.getDouble(_keyBackgroundBlurSigma) ?? 20.0,
      backgroundDimOpacity: _prefs.getDouble(_keyBackgroundDimOpacity) ?? 0.65,
      appLanguage: _prefs.getString(_keyLanguage) ?? 'defaultOption',
      lyricsTranslationTargetLang:
          _prefs.getString(_keyLyricsTranslationTargetLang) ?? 'defaultOption',
      lyricsTranslationSourceLang:
          _prefs.getString(_keyLyricsTranslationSourceLang) ?? 'auto',
      trackSortOption: TrackSortOption.fromString(
        _prefs.getString(_keyTrackSortBy),
      ),
      trackSortAscending: _prefs.getBool(_keyTrackSortAscending) ?? true,
      albumSortOption: AlbumSortOption.fromString(
        _prefs.getString(_keyAlbumSortBy),
      ),
      albumSortAscending: _prefs.getBool(_keyAlbumSortAscending) ?? true,
      artistSortOption: ArtistSortOption.fromString(
        _prefs.getString(_keyArtistSortBy),
      ),
      artistSortAscending: _prefs.getBool(_keyArtistSortAscending) ?? true,
      lyricsDisplayMode: LyricsDisplayMode.values.firstWhere(
        (e) => e.name == _prefs.getString(_keyLyricsDisplayMode),
        orElse: () => LyricsDisplayMode.original,
      ),
      playbackShowLyrics: _prefs.getBool(_keyPlaybackShowLyrics) ?? false,
      playbackShowQueue: _prefs.getBool(_keyPlaybackShowQueue) ?? false,
      pauseOnDeviceChange: _prefs.getBool(_keyPauseOnDeviceChange) ?? true,
      audioOutputDeviceId: _prefs.getString(_keyAudioOutputDeviceId),
      lastPlayedFilePath: _prefs.getString(_keyLastPlayedFilePath),
      lastPlayedPositionMs: _prefs.getInt(_keyLastPlayedPosition) ?? 0,
      equalizerEnabled: _prefs.getBool(_keyEqualizerEnabled) ?? true,
      equalizerPreset: _prefs.getString(_keyEqualizerPreset) ?? 'flat',
      equalizerGains: getEqualizerGains(),
      reverbEnabled: _prefs.getBool(_keyReverbEnabled) ?? false,
      reverbPreset: _prefs.getString(_keyReverbPreset) ?? 'off',
      reverbRoomSize: _prefs.getDouble(_keyReverbRoomSize) ?? 0.5,
      reverbDamping: _prefs.getDouble(_keyReverbDamping) ?? 0.5,
      reverbWidth: _prefs.getDouble(_keyReverbWidth) ?? 1.0,
      reverbWet: _prefs.getDouble(_keyReverbWet) ?? 0.33,
      reverbDry: _prefs.getDouble(_keyReverbDry) ?? 1.0,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final futures = <Future<bool>>[
      _prefs.setStringList(_keyMusicDirectories, settings.musicDirectories),
      _prefs.setInt(_keyCrossfadeDuration, settings.crossfadeDuration),
      _prefs.setInt(
        _keyCrossfadeManualDuration,
        settings.crossfadeManualDuration,
      ),
      _prefs.setString(_keyCrossfadeCurve, settings.crossfadeCurve.jsonValue),
      _prefs.setDouble(_keyVolume, settings.volume),
      _prefs.setDouble(_keyPlaybackRate, settings.playbackRate),
      _prefs.setDouble(_keyPlaybackPitch, settings.playbackPitch),
      _prefs.setString(_keyLoopMode, settings.loopMode.repr),
      _prefs.setBool(_keyShuffle, settings.shuffle),
      _prefs.setBool(_keySkipSilence, settings.skipSilence),
      _prefs.setBool(_keyVolumeNormalization, settings.volumeNormalization),
      _prefs.setDouble(_keyPreamp, settings.preampDb),
      _prefs.setDouble(_keyBalance, settings.balance),
      _prefs.setBool(_keyMono, settings.mono),
      _prefs.setInt(_keyCrossfeed, settings.crossfeedMode.index),
      _prefs.setDouble(_keySpatializer, settings.spatializerWidth),
      _prefs.setBool(_keyLimiter, settings.limiterEnabled),
      _prefs.setBool(_keyReverbEnabled, settings.reverbEnabled),
      _prefs.setString(_keyReverbPreset, settings.reverbPreset),
      _prefs.setDouble(_keyReverbRoomSize, settings.reverbRoomSize),
      _prefs.setDouble(_keyReverbDamping, settings.reverbDamping),
      _prefs.setDouble(_keyReverbWidth, settings.reverbWidth),
      _prefs.setDouble(_keyReverbWet, settings.reverbWet),
      _prefs.setDouble(_keyReverbDry, settings.reverbDry),
      _prefs.setDouble(_keyVolumeBoost, settings.volumeBoost),
      _prefs.setInt(_keyTheme, settings.themeMode.index),
      _prefs.setInt(_keyAccentColor, settings.accentColorValue),
      _prefs.setBool(_keyIsOledMode, settings.isOledMode),
      _prefs.setDouble(_keyBackgroundBlurSigma, settings.backgroundBlurSigma),
      _prefs.setDouble(_keyBackgroundDimOpacity, settings.backgroundDimOpacity),
      _prefs.setString(_keyLanguage, settings.appLanguage),
      _prefs.setString(
        _keyLyricsTranslationTargetLang,
        settings.lyricsTranslationTargetLang,
      ),
      _prefs.setString(
        _keyLyricsTranslationSourceLang,
        settings.lyricsTranslationSourceLang,
      ),
      _prefs.setString(_keyTrackSortBy, settings.trackSortOption.name),
      _prefs.setBool(_keyTrackSortAscending, settings.trackSortAscending),
      _prefs.setString(_keyAlbumSortBy, settings.albumSortOption.name),
      _prefs.setBool(_keyAlbumSortAscending, settings.albumSortAscending),
      _prefs.setString(_keyArtistSortBy, settings.artistSortOption.name),
      _prefs.setBool(_keyArtistSortAscending, settings.artistSortAscending),
      _prefs.setString(_keyLyricsDisplayMode, settings.lyricsDisplayMode.name),
      _prefs.setBool(_keyPlaybackShowLyrics, settings.playbackShowLyrics),
      _prefs.setBool(_keyPlaybackShowQueue, settings.playbackShowQueue),
      _prefs.setBool(_keyPauseOnDeviceChange, settings.pauseOnDeviceChange),
      _prefs.setInt(_keyLastPlayedPosition, settings.lastPlayedPositionMs),
      _prefs.setBool(_keyEqualizerEnabled, settings.equalizerEnabled),
      _prefs.setString(_keyEqualizerPreset, settings.equalizerPreset),
      _prefs.setStringList(
        _keyEqualizerGains,
        settings.equalizerGains.map((g) => g.toString()).toList(),
      ),
    ];

    if (settings.audioOutputDeviceId != null) {
      futures.add(
        _prefs.setString(
          _keyAudioOutputDeviceId,
          settings.audioOutputDeviceId!,
        ),
      );
    } else {
      futures.add(_prefs.remove(_keyAudioOutputDeviceId));
    }

    if (settings.customBackgroundPath != null) {
      futures.add(
        _prefs.setString(
          _keyCustomBackgroundPath,
          settings.customBackgroundPath!,
        ),
      );
    } else {
      futures.add(_prefs.remove(_keyCustomBackgroundPath));
    }

    if (settings.lastPlayedFilePath != null) {
      futures.add(
        _prefs.setString(_keyLastPlayedFilePath, settings.lastPlayedFilePath!),
      );
    } else {
      futures.add(_prefs.remove(_keyLastPlayedFilePath));
    }

    await Future.wait(futures);
  }

  TrackSortOption getTrackSortOption() {
    return TrackSortOption.fromString(_prefs.getString(_keyTrackSortBy));
  }

  Future<void> setTrackSortOption(TrackSortOption option) =>
      _prefs.setString(_keyTrackSortBy, option.name);

  bool getTrackSortAscending() =>
      _prefs.getBool(_keyTrackSortAscending) ?? true;

  Future<void> setTrackSortAscending(bool ascending) =>
      _prefs.setBool(_keyTrackSortAscending, ascending);

  AlbumSortOption getAlbumSortOption() {
    return AlbumSortOption.fromString(_prefs.getString(_keyAlbumSortBy));
  }

  Future<void> setAlbumSortOption(AlbumSortOption option) =>
      _prefs.setString(_keyAlbumSortBy, option.name);

  bool getAlbumSortAscending() =>
      _prefs.getBool(_keyAlbumSortAscending) ?? true;

  Future<void> setAlbumSortAscending(bool ascending) =>
      _prefs.setBool(_keyAlbumSortAscending, ascending);

  ArtistSortOption getArtistSortOption() {
    return ArtistSortOption.fromString(_prefs.getString(_keyArtistSortBy));
  }

  Future<void> setArtistSortOption(ArtistSortOption option) =>
      _prefs.setString(_keyArtistSortBy, option.name);

  bool getArtistSortAscending() =>
      _prefs.getBool(_keyArtistSortAscending) ?? true;

  Future<void> setArtistSortAscending(bool ascending) =>
      _prefs.setBool(_keyArtistSortAscending, ascending);

  LyricsDisplayMode getLyricsDisplayMode() {
    final modeName = _prefs.getString(_keyLyricsDisplayMode);
    return LyricsDisplayMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => LyricsDisplayMode.original,
    );
  }

  Future<void> setLyricsDisplayMode(LyricsDisplayMode mode) =>
      _prefs.setString(_keyLyricsDisplayMode, mode.name);

  bool getPlaybackShowLyrics() =>
      _prefs.getBool(_keyPlaybackShowLyrics) ?? false;

  Future<void> setPlaybackShowLyrics(bool show) =>
      _prefs.setBool(_keyPlaybackShowLyrics, show);

  bool getPlaybackShowQueue() => _prefs.getBool(_keyPlaybackShowQueue) ?? false;

  Future<void> setPlaybackShowQueue(bool show) =>
      _prefs.setBool(_keyPlaybackShowQueue, show);

  String getLyricsTranslationTargetLang() =>
      _prefs.getString(_keyLyricsTranslationTargetLang) ?? 'defaultOption';

  Future<void> setLyricsTranslationTargetLang(String lang) =>
      _prefs.setString(_keyLyricsTranslationTargetLang, lang);

  String getLyricsTranslationSourceLang() =>
      _prefs.getString(_keyLyricsTranslationSourceLang) ?? 'auto';

  Future<void> setLyricsTranslationSourceLang(String lang) =>
      _prefs.setString(_keyLyricsTranslationSourceLang, lang);

  String? getAudioOutputDeviceId() => _prefs.getString(_keyAudioOutputDeviceId);

  bool getPauseOnDeviceChange() =>
      _prefs.getBool(_keyPauseOnDeviceChange) ?? true;

  Future<void> setPauseOnDeviceChange(bool pause) =>
      _prefs.setBool(_keyPauseOnDeviceChange, pause);

  Future<void> setAudioOutputDeviceId(String? id) async {
    if (id == null) {
      await _prefs.remove(_keyAudioOutputDeviceId);
    } else {
      await _prefs.setString(_keyAudioOutputDeviceId, id);
    }
  }

  Future<void> setMusicDirectories(List<String> dirs) =>
      _prefs.setStringList(_keyMusicDirectories, dirs);

  /// Whether the music directories list has ever been persisted
  /// (even as an empty list after the user removed all folders).
  bool get hasMusicDirectoriesBeenSet =>
      _prefs.containsKey(_keyMusicDirectories);

  Future<void> setCrossfadeDuration(int durationSeconds) =>
      _prefs.setInt(_keyCrossfadeDuration, durationSeconds.clamp(0, 30));

  Future<void> setCrossfadeManualDuration(int durationSeconds) =>
      _prefs.setInt(_keyCrossfadeManualDuration, durationSeconds.clamp(0, 5));

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) =>
      _prefs.setString(_keyCrossfadeCurve, curve.jsonValue);

  Future<void> setVolume(double volume) =>
      _prefs.setDouble(_keyVolume, volume.clamp(0.0, 2.0));

  Future<void> setPlaybackRate(double rate) =>
      _prefs.setDouble(_keyPlaybackRate, rate.clamp(0.5, 1.5));

  Future<void> setPlaybackPitch(double pitch) =>
      _prefs.setDouble(_keyPlaybackPitch, pitch.clamp(0.5, 1.5));

  Future<void> setLoopMode(Loop mode) =>
      _prefs.setString(_keyLoopMode, mode.repr);

  Future<void> setShuffle(bool shuffle) => _prefs.setBool(_keyShuffle, shuffle);

  Future<void> setSkipSilence(bool skip) =>
      _prefs.setBool(_keySkipSilence, skip);

  Future<void> setVolumeNormalization(bool normalize) =>
      _prefs.setBool(_keyVolumeNormalization, normalize);

  Future<void> setPreamp(double preampDb) =>
      _prefs.setDouble(_keyPreamp, preampDb.clamp(-12.0, 12.0));

  Future<void> setBalance(double balance) =>
      _prefs.setDouble(_keyBalance, balance.clamp(-1.0, 1.0));

  Future<void> setMono(bool mono) => _prefs.setBool(_keyMono, mono);

  Future<void> setCrossfeed(CrossfeedMode mode) =>
      _prefs.setInt(_keyCrossfeed, mode.index);

  Future<void> setSpatializer(double width) =>
      _prefs.setDouble(_keySpatializer, width.clamp(0.0, 2.0));

  Future<void> setLimiter(bool limiter) => _prefs.setBool(_keyLimiter, limiter);

  Future<void> setVolumeBoost(double boost) =>
      _prefs.setDouble(_keyVolumeBoost, boost.clamp(100, 200));

  Future<void> setThemeMode(ThemeMode theme) =>
      _prefs.setInt(_keyTheme, theme.index);

  Future<void> setAccentColor(int colorValue) =>
      _prefs.setInt(_keyAccentColor, colorValue);

  Future<void> setIsOledMode(bool isOled) =>
      _prefs.setBool(_keyIsOledMode, isOled);

  Future<void> setCustomBackgroundPath(String? path) async {
    if (path == null) {
      await _prefs.remove(_keyCustomBackgroundPath);
    } else {
      await _prefs.setString(_keyCustomBackgroundPath, path);
    }
  }

  Future<void> setBackgroundBlurSigma(double sigma) =>
      _prefs.setDouble(_keyBackgroundBlurSigma, sigma);

  Future<void> setBackgroundDimOpacity(double opacity) =>
      _prefs.setDouble(_keyBackgroundDimOpacity, opacity);

  Future<void> setAppLanguage(String language) =>
      _prefs.setString(_keyLanguage, language);

  Future<void> setLastPlayed({
    required String filePath,
    required int positionMs,
  }) async {
    final effectivePath = filePath;
    await _prefs.setString(_keyLastPlayedFilePath, effectivePath);
    await _prefs.setInt(_keyLastPlayedPosition, positionMs);
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _prefs.setBool(_keyEqualizerEnabled, enabled);

  String getEqualizerPreset() =>
      _prefs.getString(_keyEqualizerPreset) ?? 'flat';

  Future<void> setEqualizerPreset(String preset) =>
      _prefs.setString(_keyEqualizerPreset, preset);

  Future<void> setEqualizerGains(List<double> gains) => _prefs.setStringList(
    _keyEqualizerGains,
    gains.map((g) => g.toString()).toList(),
  );

  Future<void> setReverbEnabled(bool enabled) =>
      _prefs.setBool(_keyReverbEnabled, enabled);

  String getReverbPreset() =>
      _prefs.getString(_keyReverbPreset) ?? 'off';

  Future<void> setReverbPreset(String preset) =>
      _prefs.setString(_keyReverbPreset, preset);

  Future<void> setReverbRoomSize(double val) =>
      _prefs.setDouble(_keyReverbRoomSize, val.clamp(0.0, 1.0));

  Future<void> setReverbDamping(double val) =>
      _prefs.setDouble(_keyReverbDamping, val.clamp(0.0, 1.0));

  Future<void> setReverbWidth(double val) =>
      _prefs.setDouble(_keyReverbWidth, val.clamp(0.0, 1.0));

  Future<void> setReverbWet(double val) =>
      _prefs.setDouble(_keyReverbWet, val.clamp(0.0, 2.0));

  Future<void> setReverbDry(double val) =>
      _prefs.setDouble(_keyReverbDry, val.clamp(0.0, 2.0));

  Future<void> resetToDefaults() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('s_')).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}
