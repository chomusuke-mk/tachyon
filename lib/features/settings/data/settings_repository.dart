import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
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
  static const _keyCrossfadeEnabled = 's_crossfade_enabled';
  static const _keyCrossfadeDuration = 's_crossfade_duration';
  static const _keyCrossfadeManualDuration = 's_crossfade_manual_duration';
  static const _keyCrossfadeCurve = 's_crossfade_curve';
  static const _keyVolume = 's_volume';
  static const _keyPlaybackRate = 's_playback_rate';
  static const _keyPlaybackPitch = 's_playback_pitch';
  static const _keyLoopMode = 's_loop_mode';
  static const _keyShuffle = 's_shuffle';
  static const _keySkipSilence = 's_skip_silence';
  static const _keyVolumeBoost = 's_volume_boost';
  static const _keyTheme = 's_theme';
  static const _keyLanguage = 's_language';
  static const _keyLastPlayedFilePath = 's_last_played_file_path';
  static const _keyLastPlayedUri = 's_last_played_uri';
  static const _keyLastPlayedPosition = 's_last_played_position';
  static const _keyEqualizerEnabled = 's_equalizer_enabled';
  static const _keyEqualizerGains = 's_equalizer_gains';
  static const _keyTrackSortBy = 's_track_sort_by';
  static const _keyTrackSortAscending = 's_track_sort_ascending';
  static const _keyLyricsDisplayMode = 's_lyrics_display_mode';
  static const _keyPlaybackShowLyrics = 's_playback_show_lyrics';
  static const _keyPlaybackShowQueue = 's_playback_show_queue';
  static const _keyLyricsTranslationTargetLang = 's_lyrics_translation_target_lang';
  static const _keyAudioOutputDeviceId = 's_audio_output_device_id';
  static const _keyEqualizerPreset = 's_equalizer_preset';

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
      crossfadeEnabled: _prefs.getBool(_keyCrossfadeEnabled) ?? true,
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
      volumeBoost: _prefs.getDouble(_keyVolumeBoost) ?? 100.0,
      themeMode: _getAppTheme(),
      appLanguage: _prefs.getString(_keyLanguage) ?? 'defaultOption',
      lyricsTranslationTargetLang:
          _prefs.getString(_keyLyricsTranslationTargetLang) ?? 'defaultOption',
      trackSortOption: TrackSortOption.fromString(_prefs.getString(_keyTrackSortBy)),
      trackSortAscending: _prefs.getBool(_keyTrackSortAscending) ?? true,
      lyricsDisplayMode: LyricsDisplayMode.values.firstWhere(
        (e) => e.name == _prefs.getString(_keyLyricsDisplayMode),
        orElse: () => LyricsDisplayMode.original,
      ),
      playbackShowLyrics: _prefs.getBool(_keyPlaybackShowLyrics) ?? false,
      playbackShowQueue: _prefs.getBool(_keyPlaybackShowQueue) ?? false,
      audioOutputDeviceId: _prefs.getString(_keyAudioOutputDeviceId),
      lastPlayedFilePath:
          _prefs.getString(_keyLastPlayedFilePath) ??
          _prefs.getString(_keyLastPlayedUri),
      lastPlayedPositionMs: _prefs.getInt(_keyLastPlayedPosition) ?? 0,
      equalizerEnabled: _prefs.getBool(_keyEqualizerEnabled) ?? false,
      equalizerPreset: _prefs.getString(_keyEqualizerPreset) ?? 'flat',
      equalizerGains: getEqualizerGains(),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final futures = <Future<bool>>[
      _prefs.setStringList(_keyMusicDirectories, settings.musicDirectories),
      _prefs.setBool(_keyCrossfadeEnabled, settings.crossfadeEnabled),
      _prefs.setInt(_keyCrossfadeDuration, settings.crossfadeDuration),
      _prefs.setInt(
        _keyCrossfadeManualDuration,
        settings.crossfadeManualDuration,
      ),
      _prefs.setString(_keyCrossfadeCurve, settings.crossfadeCurve.jsonValue),
      _prefs.setDouble(_keyVolume, settings.volume),
      _prefs.setDouble(_keyPlaybackRate, settings.playbackRate),
      _prefs.setDouble(_keyPlaybackPitch, settings.playbackPitch),
      _prefs.setInt(_keyLoopMode, settings.loopMode.index),
      _prefs.setBool(_keyShuffle, settings.shuffle),
      _prefs.setBool(_keySkipSilence, settings.skipSilence),
      _prefs.setDouble(_keyVolumeBoost, settings.volumeBoost),
      _prefs.setInt(_keyTheme, settings.themeMode.index),
      _prefs.setString(_keyLanguage, settings.appLanguage),
      _prefs.setString(
        _keyLyricsTranslationTargetLang,
        settings.lyricsTranslationTargetLang,
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
        _prefs.setString(_keyAudioOutputDeviceId, settings.audioOutputDeviceId!),
      );
    } else {
      futures.add(_prefs.remove(_keyAudioOutputDeviceId));
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

  bool getTrackSortAscending() => _prefs.getBool(_keyTrackSortAscending) ?? true;

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

  bool getPlaybackShowLyrics() => _prefs.getBool(_keyPlaybackShowLyrics) ?? false;

  Future<void> setPlaybackShowLyrics(bool show) =>
      _prefs.setBool(_keyPlaybackShowLyrics, show);

  bool getPlaybackShowQueue() => _prefs.getBool(_keyPlaybackShowQueue) ?? false;

  Future<void> setPlaybackShowQueue(bool show) =>
      _prefs.setBool(_keyPlaybackShowQueue, show);

  String getLyricsTranslationTargetLang() =>
      _prefs.getString(_keyLyricsTranslationTargetLang) ?? 'defaultOption';

  Future<void> setLyricsTranslationTargetLang(String lang) =>
      _prefs.setString(_keyLyricsTranslationTargetLang, lang);

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
      _prefs.setInt(_keyCrossfadeDuration, durationSeconds.clamp(2, 30));

  Future<void> setCrossfadeManualDuration(int durationSeconds) =>
      _prefs.setInt(_keyCrossfadeManualDuration, durationSeconds.clamp(0, 30));

  Future<void> setCrossfadeEnabled(bool enabled) =>
      _prefs.setBool(_keyCrossfadeEnabled, enabled);

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

  Future<void> setVolumeBoost(double boost) =>
      _prefs.setDouble(_keyVolumeBoost, boost.clamp(100, 200));

  Future<void> setThemeMode(ThemeMode theme) =>
      _prefs.setInt(_keyTheme, theme.index);

  Future<void> setAppLanguage(String language) =>
      _prefs.setString(_keyLanguage, language);

  Future<void> setLastPlayed({
    String? filePath,
    @Deprecated('Use filePath') String? uri,
    required int positionMs,
  }) async {
    final effectivePath = filePath ?? uri ?? '';
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
