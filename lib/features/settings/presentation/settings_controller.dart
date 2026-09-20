import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tachyon/core/constants/app_defaults.dart';

import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final AudioEngineService _audioEngine;

  late AppSettings _settings;

  SettingsController({
    required SettingsRepository settingsRepository,
    required AudioEngineService audioEngineService,
  }) : _repository = settingsRepository,
       _audioEngine = audioEngineService {
    _settings = _repository.getSettings();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  AppSettings get settings => _settings;

  List<String> get musicDirectories => _settings.musicDirectories;
  bool get crossfadeEnabled => _settings.crossfadeEnabled;
  int get crossfadeDuration => _settings.crossfadeDuration;
  CrossfadeCurve get crossfadeCurve => _settings.crossfadeCurve;
  double get volume => _settings.volume;
  double get playbackRate => _settings.playbackRate;
  double get playbackPitch => _settings.playbackPitch;
  Loop get loopMode => _settings.loopMode;
  bool get shuffle => _settings.shuffle;
  bool get skipSilence => _settings.skipSilence;
  double get volumeBoost => _settings.volumeBoost;
  bool get exclusiveAudio => _settings.exclusiveAudio;
  ThemeMode get themeMode => _settings.themeMode;
  String get appLanguage => _settings.appLanguage;
  bool get equalizerEnabled => _settings.equalizerEnabled;
  List<double> get equalizerGains => _settings.equalizerGains;

  // ---------------------------------------------------------------------------
  // Initialization & Service Sync
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    _settings = _repository.getSettings();

    // Sync loaded settings with AudioEngineService
    await _audioEngine.setCrossfadeConfig(
      CrossfadeConfig(
        enabled: _settings.crossfadeEnabled,
        duration: Duration(seconds: _settings.crossfadeDuration),
        curve: _settings.crossfadeCurve,
      ),
    );
    await _audioEngine.setVolume(_settings.volume);
    await _audioEngine.setRate(_settings.playbackRate);
    await _audioEngine.setPitch(_settings.playbackPitch);
    await _audioEngine.setSkipSilence(_settings.skipSilence);
    await _audioEngine.setLoopMode(_settings.loopMode);

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Music Directories Management
  // ---------------------------------------------------------------------------
  Future<bool> addMusicDirectory(String directoryPath) async {
    final cleanPath = directoryPath.trim();
    if (cleanPath.isEmpty) return false;

    final dir = Directory(cleanPath);
    if (!await dir.exists()) return false;

    if (_settings.musicDirectories.contains(cleanPath)) return true;

    final updated = List<String>.from(_settings.musicDirectories)
      ..add(cleanPath);
    _settings = _settings.copyWith(musicDirectories: updated);
    await _repository.setMusicDirectories(updated);
    notifyListeners();
    return true;
  }

  Future<void> removeMusicDirectory(String directoryPath) async {
    final updated = List<String>.from(_settings.musicDirectories)
      ..remove(directoryPath);
    _settings = _settings.copyWith(musicDirectories: updated);
    await _repository.setMusicDirectories(updated);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Audio Engine Preferences
  // ---------------------------------------------------------------------------
  Future<void> setCrossfadeDuration(int seconds) async {
    final clamped = seconds.clamp(
      AppDefaults.crossfadeMinDuration,
      AppDefaults.crossfadeMaxDuration,
    );
    _settings = _settings.copyWith(crossfadeDuration: clamped);
    await _repository.setCrossfadeDuration(clamped);
    await _audioEngine.setCrossfadeConfig(
      CrossfadeConfig(
        enabled: _settings.crossfadeEnabled,
        duration: Duration(seconds: clamped),
        curve: _settings.crossfadeCurve,
      ),
    );
    notifyListeners();
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    _settings = _settings.copyWith(crossfadeEnabled: enabled);
    await _repository.setCrossfadeEnabled(enabled);
    await _audioEngine.setCrossfadeConfig(
      CrossfadeConfig(
        enabled: enabled,
        duration: Duration(seconds: _settings.crossfadeDuration),
        curve: _settings.crossfadeCurve,
      ),
    );
    notifyListeners();
  }

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async {
    _settings = _settings.copyWith(crossfadeCurve: curve);
    await _repository.setCrossfadeCurve(curve);
    await _audioEngine.setCrossfadeConfig(
      CrossfadeConfig(
        enabled: _settings.crossfadeEnabled,
        duration: Duration(seconds: _settings.crossfadeDuration),
        curve: curve,
      ),
    );
    notifyListeners();
  }

  Future<void> setSkipSilence(bool enabled) async {
    _settings = _settings.copyWith(skipSilence: enabled);
    await _repository.setSkipSilence(enabled);
    await _audioEngine.setSkipSilence(enabled);
    notifyListeners();
  }

  Future<void> setVolumeBoost(double boost) async {
    final clamped = boost.clamp(
      AppDefaults.volumeBoostMin,
      AppDefaults.volumeBoostMax,
    );
    _settings = _settings.copyWith(volumeBoost: clamped);
    await _repository.setVolumeBoost(clamped);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Appearance & Localization
  // ---------------------------------------------------------------------------
  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _repository.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setAppLanguage(String languageCode) async {
    _settings = _settings.copyWith(appLanguage: languageCode);
    await _repository.setAppLanguage(languageCode);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
    await init();
  }
}
