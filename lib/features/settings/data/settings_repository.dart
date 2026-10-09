import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/loop_mode.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

enum CrossfadeCurve {
  equalPower('equal_power'),
  linear('linear');

  const CrossfadeCurve(this.jsonValue);
  final String jsonValue;

  static CrossfadeCurve fromString(String? val) {
    return CrossfadeCurve.values.firstWhere(
      (e) => e.jsonValue == val,
      orElse: () => CrossfadeCurve.equalPower,
    );
  }
}

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
  static const _keyVolumeBoost = 's_volume_boost';
  static const _keyTheme = 's_theme';
  static const _keyLanguage = 's_language';
  static const _keyLastPlayedFilePath = 's_last_played_file_path';
  static const _keyLastPlayedPosition = 's_last_played_position';
  static const _keyEqualizerEnabled = 's_equalizer_enabled';
  static const _keyEqualizerGains = 's_equalizer_gains';
  static const _keyTrackSortBy = 's_track_sort_by';
  static const _keyTrackSortAscending = 's_track_sort_ascending';
  static const _keyLyricsDisplayMode = 's_lyrics_display_mode';
  static const _keyPlaybackShowLyrics = 's_playback_show_lyrics';
  static const _keyPlaybackShowQueue = 's_playback_show_queue';
  static const _keyLyricsTranslationTargetLang =
      's_lyrics_translation_target_lang';
  static const _keyLyricsTranslationSourceLang =
      's_lyrics_translation_source_lang';
  static const _keyAudioOutputDeviceId = 's_audio_output_device_id';
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
      crossfadeManualDuration: _prefs.getInt(_keyCrossfadeManualDuration) ?? 3,
      crossfadeCurve: CrossfadeCurve.fromString(
        _prefs.getString(_keyCrossfadeCurve),
      ),
      volume: _prefs.getDouble(_keyVolume) ?? 100.0,
      playbackRate: _prefs.getDouble(_keyPlaybackRate) ?? 1.0,
      playbackPitch: _prefs.getDouble(_keyPlaybackPitch) ?? 1.0,
      loopMode: Loop.fromString(_prefs.getString(_keyLoopMode)),
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
      volumeBoost: _prefs.getDouble(_keyVolumeBoost) ?? 100.0,
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
      lyricsDisplayMode: LyricsDisplayMode.values.firstWhere(
        (e) => e.name == _prefs.getString(_keyLyricsDisplayMode),
        orElse: () => LyricsDisplayMode.original,
      ),
      playbackShowLyrics: _prefs.getBool(_keyPlaybackShowLyrics) ?? false,
      playbackShowQueue: _prefs.getBool(_keyPlaybackShowQueue) ?? false,
      audioOutputDeviceId: _prefs.getString(_keyAudioOutputDeviceId),
      lastPlayedFilePath: _prefs.getString(_keyLastPlayedFilePath),
      lastPlayedPositionMs: _prefs.getInt(_keyLastPlayedPosition) ?? 0,
      equalizerEnabled: _prefs.getBool(_keyEqualizerEnabled) ?? false,
      equalizerPreset: _prefs.getString(_keyEqualizerPreset) ?? 'flat',
      equalizerGains: getEqualizerGains(),
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
      _prefs.setString(_keyLyricsDisplayMode, settings.lyricsDisplayMode.name),
      _prefs.setBool(_keyPlaybackShowLyrics, settings.playbackShowLyrics),
      _prefs.setBool(_keyPlaybackShowQueue, settings.playbackShowQueue),
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

  Future<void> setAudioOutputDeviceId(String? id) async {
    if (id == null) {
      await _prefs.remove(_keyAudioOutputDeviceId);
    } else {
      await _prefs.setString(_keyAudioOutputDeviceId, id);
    }
  }

  Future<void> setMusicDirectories(List<String> dirs) =>
      _prefs.setStringList(_keyMusicDirectories, dirs);

  Future<void> setCrossfadeDuration(int durationSeconds) =>
      _prefs.setInt(_keyCrossfadeDuration, durationSeconds.clamp(0, 30));

  Future<void> setCrossfadeManualDuration(int durationSeconds) =>
      _prefs.setInt(_keyCrossfadeManualDuration, durationSeconds.clamp(0, 30));

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) =>
      _prefs.setString(_keyCrossfadeCurve, curve.jsonValue);

  Future<void> setVolume(double volume) =>
      _prefs.setDouble(_keyVolume, volume.clamp(0, 100));

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

  Future<void> resetToDefaults() async {
    await _prefs.clear();
  }
}
