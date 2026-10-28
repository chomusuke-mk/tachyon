// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';
import 'package:tachyon/shared/utils/folder_utils.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final PlaybackController? _playbackController;

  late AppSettings _settings;

  SettingsController({
    required SettingsRepository repository,
    PlaybackController? playbackController,
  }) : _repository = repository,
       _playbackController = playbackController {
    _settings = _repository.getSettings();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  AppSettings get settings => _settings;

  List<String> get musicDirectories => _settings.musicDirectories;
  int get crossfadeDuration => _settings.crossfadeDuration;
  int get crossfadeManualDuration => _settings.crossfadeManualDuration;
  CrossfadeCurve get crossfadeCurve => _settings.crossfadeCurve;
  double get volume => _settings.volume;
  double get playbackRate => _settings.playbackRate;
  double get playbackPitch => _settings.playbackPitch;
  Loop get loopMode => _settings.loopMode;
  bool get shuffle => _settings.shuffle;
  bool get skipSilence => _settings.skipSilence;
  bool get volumeNormalization => _settings.volumeNormalization;
  double get preampDb => _settings.preampDb;
  double get balance => _settings.balance;
  bool get mono => _settings.mono;
  CrossfeedMode get crossfeedMode => _settings.crossfeedMode;
  double get spatializerWidth => _settings.spatializerWidth;
  bool get limiterEnabled => _settings.limiterEnabled;
  double get volumeBoost => _settings.volumeBoost;
  ThemeMode get themeMode => _settings.themeMode;
  int get accentColorValue => _settings.accentColorValue;
  Color get accentColor => _settings.accentColor;
  bool get isOledMode => _settings.isOledMode;
  String? get customBackgroundPath => _settings.customBackgroundPath;
  double get backgroundBlurSigma => _settings.backgroundBlurSigma;
  double get backgroundDimOpacity => _settings.backgroundDimOpacity;
  String get appLanguage => _settings.appLanguage;
  String get lyricsTranslationTargetLang => _settings.lyricsTranslationTargetLang;
  String get lyricsTranslationSourceLang => _settings.lyricsTranslationSourceLang;
  String? get audioOutputDeviceId => _settings.audioOutputDeviceId;
  bool get pauseOnDeviceChange => _settings.pauseOnDeviceChange;
  bool get equalizerEnabled => _settings.equalizerEnabled;
  String get equalizerPreset => _settings.equalizerPreset;
  List<double> get equalizerGains => _settings.equalizerGains;
  bool get reverbEnabled => _settings.reverbEnabled;
  String get reverbPreset => _settings.reverbPreset;
  double get reverbRoomSize => _settings.reverbRoomSize;
  double get reverbDamping => _settings.reverbDamping;
  double get reverbWidth => _settings.reverbWidth;
  double get reverbWet => _settings.reverbWet;
  double get reverbDry => _settings.reverbDry;
  Reverb get reverbConfig => _settings.reverbConfig;

  // ---------------------------------------------------------------------------
  // Initialization & Service Sync
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    _settings = _repository.getSettings();

    final pb = _playbackController;
    if (pb != null) {
      await pb.setCrossfadeConfig(
        CrossfadeConfig(
          duration: Duration(seconds: _settings.crossfadeDuration),
          manualDuration: Duration(seconds: _settings.crossfadeManualDuration),
          curve: _settings.crossfadeCurve,
        ),
      );
      await pb.setVolume(_settings.volume);
      await pb.setRate(_settings.playbackRate);
      await pb.setPitch(_settings.playbackPitch);
      await pb.setSkipSilence(_settings.skipSilence);
      await pb.setVolumeNormalization(_settings.volumeNormalization);
      await pb.setPreamp(_settings.preampDb);
      await pb.setBalance(_settings.balance);
      await pb.setMono(_settings.mono);
      await pb.setCrossfeed(_settings.crossfeedMode);
      await pb.setSpatializer(_settings.spatializerWidth);
      await pb.setLimiter(_settings.limiterEnabled);
      await pb.setPauseOnDeviceChange(_settings.pauseOnDeviceChange);
      await pb.setReverb(_settings.reverbConfig);
      await pb.setLoopMode(_settings.loopMode);

      if (_settings.equalizerEnabled) {
        await pb.setEqualizer(Equalizer.fromList(_settings.equalizerGains));
      } else {
        await pb.setEqualizer(Equalizer.flat);
      }
    }

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

  /// Adds the platform's default music directory when [musicDirectories]
  /// has never been set. Returns `true` if a directory was added.
  Future<bool> ensureDefaultMusicDirectory() async {
    if (_repository.hasMusicDirectoriesBeenSet) return false;
    final musicDir = await FolderUtils.getMusicDirectory();
    if (musicDir == null) return false;
    return addMusicDirectory(musicDir.path);
  }

  // ---------------------------------------------------------------------------
  // Audio Engine Preferences
  // ---------------------------------------------------------------------------
  Future<void> setCrossfadeDuration(int seconds) async {
    final clamped = seconds.clamp(
      AppDefaults.crossfadeMinDuration,
      AppDefaults.crossfadeMaxDuration,
    );
    _settings = _settings.copyWith(
      crossfadeDuration: clamped,
    );
    await _repository.setCrossfadeDuration(clamped);
    await _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: clamped),
        manualDuration: Duration(seconds: _settings.crossfadeManualDuration),
        curve: _settings.crossfadeCurve,
      ),
    );
    notifyListeners();
  }

  Future<void> setCrossfadeManualDuration(int durationSeconds) async {
    _settings = _settings.copyWith(crossfadeManualDuration: durationSeconds);
    await _repository.setCrossfadeManualDuration(durationSeconds);
    await _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: _settings.crossfadeDuration),
        manualDuration: Duration(seconds: durationSeconds),
        curve: _settings.crossfadeCurve,
      ),
    );
    notifyListeners();
  }

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async {
    _settings = _settings.copyWith(crossfadeCurve: curve);
    await _repository.setCrossfadeCurve(curve);
    await _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: _settings.crossfadeDuration),
        manualDuration: Duration(seconds: _settings.crossfadeManualDuration),
        curve: curve,
      ),
    );
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _settings = _settings.copyWith(equalizerEnabled: enabled);
    await _repository.setEqualizerEnabled(enabled);
    if (enabled) {
      await _playbackController?.setEqualizer(
        Equalizer.fromList(_settings.equalizerGains),
      );
    } else {
      await _playbackController?.setEqualizer(Equalizer.flat);
    }
    notifyListeners();
  }

  Future<void> setEqualizerGains(List<double> gains) async {
    _settings = _settings.copyWith(
      equalizerGains: gains,
      equalizerEnabled: true,
    );
    await _repository.setEqualizerGains(gains);
    await _repository.setEqualizerEnabled(true);
    await _playbackController?.setEqualizer(Equalizer.fromList(gains));
    notifyListeners();
  }

  Future<void> setEqualizerPreset(String preset) async {
    _settings = _settings.copyWith(equalizerPreset: preset);
    await _repository.setEqualizerPreset(preset);
    List<double> gains;
    switch (preset) {
      case 'rock':
        gains = Equalizer.rock.toList();
        break;
      case 'pop':
        gains = Equalizer.pop.toList();
        break;
      case 'jazz':
        gains = Equalizer.jazz.toList();
        break;
      case 'classical':
        gains = Equalizer.classical.toList();
        break;
      case 'bassBoost':
        gains = Equalizer.bassBoost.toList();
        break;
      case 'flat':
        gains = Equalizer.flat.toList();
        break;
      default:
        gains = _settings.equalizerGains;
    }
    await setEqualizerGains(gains);
  }

  Future<void> setEqualizerBandGain(int bandIndex, double gain) async {
    if (bandIndex < 0 || bandIndex >= 10) return;
    final newGains = List<double>.from(_settings.equalizerGains);
    while (newGains.length < 10) {
      newGains.add(0.0);
    }
    newGains[bandIndex] = gain;
    _settings = _settings.copyWith(equalizerPreset: 'custom');
    await _repository.setEqualizerPreset('custom');
    await setEqualizerGains(newGains);
  }

  Future<void> setAudioOutputDeviceId(String? deviceId) async {
    _settings = _settings.copyWith(audioOutputDeviceId: deviceId);
    await _repository.setAudioOutputDeviceId(deviceId);
    notifyListeners();
  }

  Future<void> setPauseOnDeviceChange(bool pause) async {
    _settings = _settings.copyWith(pauseOnDeviceChange: pause);
    await _repository.setPauseOnDeviceChange(pause);
    await _playbackController?.setPauseOnDeviceChange(pause);
    notifyListeners();
  }

  Future<void> setSkipSilence(bool enabled) async {
    _settings = _settings.copyWith(skipSilence: enabled);
    await _repository.setSkipSilence(enabled);
    await _playbackController?.setSkipSilence(enabled);
    notifyListeners();
  }

  Future<void> setVolumeNormalization(bool enabled) async {
    _settings = _settings.copyWith(volumeNormalization: enabled);
    await _repository.setVolumeNormalization(enabled);
    await _playbackController?.setVolumeNormalization(enabled);
    notifyListeners();
  }

  Future<void> setPreamp(double preampDb) async {
    final clamped = preampDb.clamp(-12.0, 12.0);
    _settings = _settings.copyWith(preampDb: clamped);
    await _repository.setPreamp(clamped);
    await _playbackController?.setPreamp(clamped);
    notifyListeners();
  }

  Future<void> setBalance(double balance) async {
    final clamped = balance.clamp(-1.0, 1.0);
    _settings = _settings.copyWith(balance: clamped);
    await _repository.setBalance(clamped);
    await _playbackController?.setBalance(clamped);
    notifyListeners();
  }

  Future<void> setMono(bool mono) async {
    _settings = _settings.copyWith(mono: mono);
    await _repository.setMono(mono);
    await _playbackController?.setMono(mono);
    notifyListeners();
  }

  Future<void> setCrossfeed(CrossfeedMode mode) async {
    _settings = _settings.copyWith(crossfeedMode: mode);
    await _repository.setCrossfeed(mode);
    await _playbackController?.setCrossfeed(mode);
    notifyListeners();
  }

  Future<void> setSpatializer(double width) async {
    final clamped = width.clamp(0.0, 2.0);
    _settings = _settings.copyWith(spatializerWidth: clamped);
    await _repository.setSpatializer(clamped);
    await _playbackController?.setSpatializer(clamped);
    notifyListeners();
  }

  Future<void> setLimiter(bool limiter) async {
    _settings = _settings.copyWith(limiterEnabled: limiter);
    await _repository.setLimiter(limiter);
    await _playbackController?.setLimiter(limiter);
    notifyListeners();
  }

  Future<void> setReverbEnabled(bool enabled) async {
    if (enabled && (_settings.reverbPreset == 'off' || _settings.reverbPreset == 'Off' || _settings.reverbRoomSize == 0.0)) {
      const preset = 'studio';
      const target = Reverb.studio;
      _settings = _settings.copyWith(
        reverbEnabled: true,
        reverbPreset: preset,
        reverbRoomSize: target.roomSize,
        reverbDamping: target.damping,
        reverbWidth: target.width,
        reverbWet: target.wet,
        reverbDry: target.dry,
      );
      await _repository.setReverbEnabled(true);
      await _repository.setReverbPreset(preset);
      await _repository.setReverbRoomSize(target.roomSize);
      await _repository.setReverbDamping(target.damping);
      await _repository.setReverbWidth(target.width);
      await _repository.setReverbWet(target.wet);
      await _repository.setReverbDry(target.dry);
    } else {
      _settings = _settings.copyWith(reverbEnabled: enabled);
      await _repository.setReverbEnabled(enabled);
    }
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbPreset(String preset) async {
    final Reverb? target;
    switch (preset) {
      case 'off':
        target = Reverb.off;
        break;
      case 'smallRoom':
        target = Reverb.smallRoom;
        break;
      case 'studio':
        target = Reverb.studio;
        break;
      case 'concertHall':
        target = Reverb.concertHall;
        break;
      case 'cathedral':
        target = Reverb.cathedral;
        break;
      case 'plate':
        target = Reverb.plate;
        break;
      case 'ambient':
        target = Reverb.ambient;
        break;
      default:
        target = null;
    }

    if (target != null) {
      final isOff = preset == 'off';
      _settings = _settings.copyWith(
        reverbEnabled: !isOff,
        reverbPreset: preset,
        reverbRoomSize: target.roomSize,
        reverbDamping: target.damping,
        reverbWidth: target.width,
        reverbWet: target.wet,
        reverbDry: target.dry,
      );
      await _repository.setReverbEnabled(!isOff);
      await _repository.setReverbPreset(preset);
      await _repository.setReverbRoomSize(target.roomSize);
      await _repository.setReverbDamping(target.damping);
      await _repository.setReverbWidth(target.width);
      await _repository.setReverbWet(target.wet);
      await _repository.setReverbDry(target.dry);
    } else {
      _settings = _settings.copyWith(reverbPreset: preset);
      await _repository.setReverbPreset(preset);
    }
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbRoomSize(double val) async {
    final clamped = val.clamp(0.0, 1.0);
    _settings = _settings.copyWith(
      reverbEnabled: true,
      reverbRoomSize: clamped,
      reverbPreset: 'custom',
    );
    await _repository.setReverbEnabled(true);
    await _repository.setReverbPreset('custom');
    await _repository.setReverbRoomSize(clamped);
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbDamping(double val) async {
    final clamped = val.clamp(0.0, 1.0);
    _settings = _settings.copyWith(
      reverbEnabled: true,
      reverbDamping: clamped,
      reverbPreset: 'custom',
    );
    await _repository.setReverbEnabled(true);
    await _repository.setReverbPreset('custom');
    await _repository.setReverbDamping(clamped);
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbWidth(double val) async {
    final clamped = val.clamp(0.0, 1.0);
    _settings = _settings.copyWith(
      reverbEnabled: true,
      reverbWidth: clamped,
      reverbPreset: 'custom',
    );
    await _repository.setReverbEnabled(true);
    await _repository.setReverbPreset('custom');
    await _repository.setReverbWidth(clamped);
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbWet(double val) async {
    final clamped = val.clamp(0.0, 2.0);
    _settings = _settings.copyWith(
      reverbEnabled: true,
      reverbWet: clamped,
      reverbPreset: 'custom',
    );
    await _repository.setReverbEnabled(true);
    await _repository.setReverbPreset('custom');
    await _repository.setReverbWet(clamped);
    await _playbackController?.setReverb(_settings.reverbConfig);
    notifyListeners();
  }

  Future<void> setReverbDry(double val) async {
    final clamped = val.clamp(0.0, 2.0);
    _settings = _settings.copyWith(
      reverbEnabled: true,
      reverbDry: clamped,
      reverbPreset: 'custom',
    );
    await _repository.setReverbEnabled(true);
    await _repository.setReverbPreset('custom');
    await _repository.setReverbDry(clamped);
    await _playbackController?.setReverb(_settings.reverbConfig);
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

  Future<void> setAccentColor(int colorValue) async {
    _settings = _settings.copyWith(accentColorValue: colorValue);
    await _repository.setAccentColor(colorValue);
    notifyListeners();
  }

  Future<void> setIsOledMode(bool isOled) async {
    _settings = _settings.copyWith(isOledMode: isOled);
    await _repository.setIsOledMode(isOled);
    notifyListeners();
  }

  Future<bool> setCustomBackground(String? sourceImagePath) async {
    if (sourceImagePath == null) {
      _settings = _settings.copyWith(clearCustomBackground: true);
      await _repository.setCustomBackgroundPath(null);
      notifyListeners();
      return true;
    }

    try {
      final sourceFile = File(sourceImagePath);
      if (!await sourceFile.exists()) return false;

      final supportDir = await getApplicationSupportDirectory();
      final bgDir = Directory('${supportDir.path}/backgrounds');
      if (!await bgDir.exists()) {
        await bgDir.create(recursive: true);
      }

      final ext = sourceImagePath.contains('.')
          ? '.${sourceImagePath.split('.').last}'
          : '.jpg';
      final targetPath = '${bgDir.path}/custom_bg$ext';
      final targetFile = await sourceFile.copy(targetPath);

      _settings = _settings.copyWith(customBackgroundPath: targetFile.path);
      await _repository.setCustomBackgroundPath(targetFile.path);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBackgroundBlurSigma(double sigma) async {
    final clamped = sigma.clamp(0.0, 50.0);
    _settings = _settings.copyWith(backgroundBlurSigma: clamped);
    await _repository.setBackgroundBlurSigma(clamped);
    notifyListeners();
  }

  Future<void> setBackgroundDimOpacity(double opacity) async {
    final clamped = opacity.clamp(0.1, 0.95);
    _settings = _settings.copyWith(backgroundDimOpacity: clamped);
    await _repository.setBackgroundDimOpacity(clamped);
    notifyListeners();
  }

  Future<void> setAppLanguage(String languageCode) async {
    _settings = _settings.copyWith(appLanguage: languageCode);
    await _repository.setAppLanguage(languageCode);
    notifyListeners();
  }

  Future<void> setLyricsTranslationTargetLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationTargetLang: languageCode);
    await _repository.setLyricsTranslationTargetLang(languageCode);
    notifyListeners();
  }

  Future<void> setLyricsTranslationSourceLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationSourceLang: languageCode);
    await _repository.setLyricsTranslationSourceLang(languageCode);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
    await init();
  }
}
