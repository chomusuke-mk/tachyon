// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';
import 'package:tachyon/shared/utils/folder_utils.dart';

class _SettingsDomainNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final PlaybackController? _playbackController;

  late AppSettings _settings;
  bool _isDisposed = false;
  bool _inScopedNotify = false;

  // Scoped domain listenables
  final _SettingsDomainNotifier _themeNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _libraryNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _crossfadeNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _enhancementsNotifier =
      _SettingsDomainNotifier();
  final _SettingsDomainNotifier _spatialNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _reverbNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _equalizerNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _lyricsNotifier = _SettingsDomainNotifier();
  final _SettingsDomainNotifier _localeNotifier = _SettingsDomainNotifier();

  // Future-based latest-wins persistence coalescing (no timers)
  final Map<String, Future<void>> _persistInFlight = {};
  final Map<String, Future<void> Function()> _persistPending = {};

  SettingsController({
    required SettingsRepository repository,
    PlaybackController? playbackController,
  }) : _repository = repository,
       _playbackController = playbackController {
    _settings = _repository.getSettings();
  }

  // ---------------------------------------------------------------------------
  // Scoped Listenables & Getters
  // ---------------------------------------------------------------------------
  Listenable get themeListenable => _themeNotifier;
  Listenable get libraryListenable => _libraryNotifier;
  Listenable get crossfadeListenable => _crossfadeNotifier;
  Listenable get enhancementsListenable => _enhancementsNotifier;
  Listenable get spatialListenable => _spatialNotifier;
  Listenable get reverbListenable => _reverbNotifier;
  Listenable get equalizerListenable => _equalizerNotifier;
  Listenable get lyricsListenable => _lyricsNotifier;
  Listenable get localeListenable => _localeNotifier;

  AppSettings get settings => _settings;
  SettingsRepository get repository => _repository;

  List<String> get musicDirectories => _settings.musicDirectories;
  List<String> get musicFiles => _settings.musicFiles;
  int get crossfadeDuration => _settings.crossfadeDuration;
  int get crossfadeManualDuration => _settings.crossfadeManualDuration;
  CrossfadeCurve get crossfadeCurve => _settings.crossfadeCurve;
  double get volume => _settings.volume;
  double get playbackRate => _settings.playbackRate;
  double get playbackPitch => _settings.playbackPitch;
  LoopMode get loopMode => _settings.loopMode;
  bool get shuffle => _settings.shuffle;
  bool get skipSilence => _settings.skipSilence;
  SilenceSkipMode get silenceSkipMode => _settings.silenceSkipMode;
  bool get volumeNormalization => _settings.volumeNormalization;
  double get preampDb => _settings.preampDb;
  double get balance => _settings.balance;
  bool get mono => _settings.mono;
  Crossfeed get crossfeed => _settings.crossfeed;
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
  String get lyricsTranslationTargetLang =>
      _settings.lyricsTranslationTargetLang;
  String get lyricsTranslationSourceLang =>
      _settings.lyricsTranslationSourceLang;
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

  void _emitScoped(List<_SettingsDomainNotifier> domains) {
    if (_isDisposed) return;
    for (final d in domains) {
      d.notify();
    }
    _inScopedNotify = true;
    try {
      super.notifyListeners();
    } finally {
      _inScopedNotify = false;
    }
  }

  Future<void> _coalescePersist(String key, Future<void> Function() task) {
    final existing = _persistInFlight[key];
    if (existing != null) {
      _persistPending[key] = task;
      return existing;
    }
    Future<void> drain() async {
      var current = task;
      while (true) {
        try {
          await current();
        } catch (e) {
          debugPrint('[SettingsController] Persist ($key) error: $e');
        }
        final next = _persistPending.remove(key);
        if (next == null || _isDisposed) break;
        current = next;
      }
    }

    late final Future<void> tracked;
    var syncCompleted = false;
    tracked = drain().whenComplete(() {
      syncCompleted = true;
      if (identical(_persistInFlight[key], tracked)) {
        _persistInFlight.remove(key);
      }
    });
    if (!syncCompleted) {
      _persistInFlight[key] = tracked;
    }
    return tracked;
  }

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
      await pb.setSilenceConfig(_settings.silenceSkipConfig);
      await pb.setReplayGainMode(_settings.replayGainMode);
      await pb.setPreamp(_settings.preampDb);
      await pb.setBalance(_settings.balance);
      await pb.setMono(_settings.mono);
      await pb.setCrossfeed(_settings.crossfeed);
      await pb.setSpatializer(_settings.spatializerWidth);
      await pb.setLimiter(_settings.limiterEnabled);
      await pb.setPauseOnDeviceChange(_settings.pauseOnDeviceChange);
      await pb.setReverb(_settings.reverbConfig);
      await pb.setLoopMode(_settings.loopMode);

      if (_settings.equalizerEnabled) {
        await pb.setEqualizer(Equalizer.fromList(_settings.equalizerGains));
      } else {
        await pb.setEqualizer(Equalizer.off);
      }
    }

    _emitScoped([
      _themeNotifier,
      _libraryNotifier,
      _crossfadeNotifier,
      _enhancementsNotifier,
      _spatialNotifier,
      _reverbNotifier,
      _equalizerNotifier,
      _lyricsNotifier,
      _localeNotifier,
    ]);
  }

  // ---------------------------------------------------------------------------
  // Music Sources Management (Directories & Individual Files / Links)
  // ---------------------------------------------------------------------------
  Future<bool> addMusicDirectory(String directoryPath) async {
    final cleanPath = directoryPath.trim();
    if (cleanPath.isEmpty) return false;

    if (!await PersistentBinaryStorage.directoryExists(cleanPath)) return false;

    if (_settings.musicDirectories.contains(cleanPath)) return true;

    final updated = List<String>.from(_settings.musicDirectories)
      ..add(cleanPath);
    _settings = _settings.copyWith(musicDirectories: updated);
    await _repository.setMusicDirectories(updated);
    _emitScoped([_libraryNotifier]);
    return true;
  }

  Future<void> removeMusicDirectory(String directoryPath) async {
    final updated = List<String>.from(_settings.musicDirectories)
      ..remove(directoryPath);
    _settings = _settings.copyWith(musicDirectories: updated);
    await _repository.setMusicDirectories(updated);
    _emitScoped([_libraryNotifier]);
  }

  /// Validates and registers a single local audio file, OPFS file, or HTTP(S) audio URL.
  Future<bool> addMusicFile(String pathOrUrl) async {
    final clean = pathOrUrl.trim();
    if (clean.isEmpty) return false;

    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final uri = Uri.tryParse(clean);
      if (uri == null || uri.host.isEmpty) return false;
    } else if (!await PersistentBinaryStorage.fileExists(clean)) {
      return false;
    }

    if (_settings.musicFiles.contains(clean)) return true;

    final updated = List<String>.from(_settings.musicFiles)..add(clean);
    _settings = _settings.copyWith(musicFiles: updated);
    await _repository.setMusicFiles(updated);
    _emitScoped([_libraryNotifier]);
    return true;
  }

  /// Validates and registers multiple audio files or URLs in a single batch.
  /// Returns the number of newly added or valid entries.
  Future<int> addMusicFiles(List<String> pathsOrUrls) async {
    if (pathsOrUrls.isEmpty) return 0;
    final updated = List<String>.from(_settings.musicFiles);
    int addedCount = 0;

    for (final raw in pathsOrUrls) {
      final clean = raw.trim();
      if (clean.isEmpty) continue;
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        final uri = Uri.tryParse(clean);
        if (uri == null || uri.host.isEmpty) continue;
      } else if (!await PersistentBinaryStorage.fileExists(clean)) {
        continue;
      }
      if (!updated.contains(clean)) {
        updated.add(clean);
      }
      addedCount++;
    }

    if (addedCount > 0) {
      _settings = _settings.copyWith(musicFiles: updated);
      await _repository.setMusicFiles(updated);
      _emitScoped([_libraryNotifier]);
    }
    return addedCount;
  }

  Future<void> removeMusicFile(String pathOrUrl) async {
    final updated = List<String>.from(_settings.musicFiles)..remove(pathOrUrl);
    _settings = _settings.copyWith(musicFiles: updated);
    await _repository.setMusicFiles(updated);
    if (pathOrUrl.startsWith('opfs://audio/')) {
      await PersistentBinaryStorage.removeWebAudioFile(pathOrUrl);
    }
    _emitScoped([_libraryNotifier]);
  }

  Future<void> clearMusicFiles() async {
    final oldFiles = List<String>.from(_settings.musicFiles);
    _settings = _settings.copyWith(musicFiles: const []);
    await _repository.setMusicFiles(const []);
    for (final pathOrUrl in oldFiles) {
      if (pathOrUrl.startsWith('opfs://audio/')) {
        await PersistentBinaryStorage.removeWebAudioFile(pathOrUrl);
      }
    }
    _emitScoped([_libraryNotifier]);
  }

  /// Adds the platform's default music directory (on Native) or default Web
  /// sample audio catalog (on Web) when music sources have never been configured.
  /// Returns `true` if any default source was added.
  Future<bool> ensureDefaultMusicDirectory() async {
    if (kIsWeb) {
      if (_repository.hasMusicFilesBeenSet) return false;
      final added = await addMusicFiles(AppDefaults.defaultWebSampleAudioUrls);
      return added > 0;
    }
    if (_repository.hasMusicDirectoriesBeenSet) return false;
    final musicDirPath = await FolderUtils.getMusicDirectoryPath();
    if (musicDirPath == null) return false;
    return addMusicDirectory(musicDirPath);
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
    _emitScoped([_crossfadeNotifier]);
    final rpc = _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: clamped),
        manualDuration: Duration(seconds: _settings.crossfadeManualDuration),
        curve: _settings.crossfadeCurve,
      ),
    );
    final persist = _coalescePersist(
      'crossfadeDuration',
      () => _repository.setCrossfadeDuration(clamped),
    );
    await Future.wait([?rpc, persist]);
  }

  Future<void> setCrossfadeManualDuration(int durationSeconds) async {
    _settings = _settings.copyWith(crossfadeManualDuration: durationSeconds);
    _emitScoped([_crossfadeNotifier]);
    final rpc = _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: _settings.crossfadeDuration),
        manualDuration: Duration(seconds: durationSeconds),
        curve: _settings.crossfadeCurve,
      ),
    );
    final persist = _coalescePersist(
      'crossfadeManualDuration',
      () => _repository.setCrossfadeManualDuration(durationSeconds),
    );
    await Future.wait([?rpc, persist]);
  }

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async {
    _settings = _settings.copyWith(crossfadeCurve: curve);
    _emitScoped([_crossfadeNotifier]);
    await _repository.setCrossfadeCurve(curve);
    await _playbackController?.setCrossfadeConfig(
      CrossfadeConfig(
        duration: Duration(seconds: _settings.crossfadeDuration),
        manualDuration: Duration(seconds: _settings.crossfadeManualDuration),
        curve: curve,
      ),
    );
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _settings = _settings.copyWith(equalizerEnabled: enabled);
    _emitScoped([_equalizerNotifier]);
    await _repository.setEqualizerEnabled(enabled);
    if (enabled) {
      await _playbackController?.setEqualizer(
        Equalizer.fromList(_settings.equalizerGains),
      );
    } else {
      await _playbackController?.setEqualizer(Equalizer.off);
    }
  }

  Future<void> setEqualizerGains(List<double> gains) async {
    _settings = _settings.copyWith(
      equalizerGains: gains,
      equalizerEnabled: true,
    );
    _emitScoped([_equalizerNotifier]);
    final rpc = _playbackController?.setEqualizer(Equalizer.fromList(gains));
    final persist = _coalescePersist('equalizerGains', () async {
      await _repository.setEqualizerGains(gains);
      await _repository.setEqualizerEnabled(true);
    });
    await Future.wait([?rpc, persist]);
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
    _settings = _settings.copyWith(
      equalizerPreset: 'custom',
      equalizerGains: newGains,
      equalizerEnabled: true,
    );
    _emitScoped([_equalizerNotifier]);
    final rpc = _playbackController?.setEqualizer(Equalizer.fromList(newGains));
    final persist = _coalescePersist('equalizerBand', () async {
      await _repository.setEqualizerPreset('custom');
      await _repository.setEqualizerGains(newGains);
      await _repository.setEqualizerEnabled(true);
    });
    await Future.wait([?rpc, persist]);
  }

  Future<void> setAudioOutputDeviceId(String? deviceId) async {
    _settings = _settings.copyWith(audioOutputDeviceId: deviceId);
    await _repository.setAudioOutputDeviceId(deviceId);
    _emitScoped([_enhancementsNotifier]);
  }

  Future<void> setPauseOnDeviceChange(bool pause) async {
    _settings = _settings.copyWith(pauseOnDeviceChange: pause);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setPauseOnDeviceChange(pause);
    await _playbackController?.setPauseOnDeviceChange(pause);
  }

  Future<void> setSkipSilence(bool enabled) async {
    _settings = _settings.copyWith(skipSilence: enabled);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setSkipSilence(enabled);
    await _playbackController?.setSilenceConfig(_settings.silenceSkipConfig);
  }

  Future<void> setSilenceSkipMode(SilenceSkipMode mode) async {
    final effectiveMode =
        mode == SilenceSkipMode.disabled ? SilenceSkipMode.all : mode;
    _settings = _settings.copyWith(
      silenceSkipMode: effectiveMode,
      skipSilence: true,
    );
    _emitScoped([_enhancementsNotifier]);
    await _repository.setSilenceSkipMode(effectiveMode);
    await _repository.setSkipSilence(true);
    await _playbackController?.setSilenceConfig(_settings.silenceSkipConfig);
  }

  Future<void> setVolumeNormalization(bool enabled) async {
    _settings = _settings.copyWith(volumeNormalization: enabled);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setVolumeNormalization(enabled);
    await _playbackController?.setReplayGainMode(_settings.replayGainMode);
  }

  Future<void> setPreamp(double preampDb) async {
    final clamped = preampDb.clamp(-12.0, 12.0);
    _settings = _settings.copyWith(preampDb: clamped);
    _emitScoped([_equalizerNotifier]);
    final rpc = _playbackController?.setPreamp(clamped);
    final persist = _coalescePersist(
      'preamp',
      () => _repository.setPreamp(clamped),
    );
    await Future.wait([?rpc, persist]);
  }

  Future<void> setBalance(double balance) async {
    final clamped = balance.clamp(-1.0, 1.0);
    _settings = _settings.copyWith(balance: clamped);
    _emitScoped([_spatialNotifier]);
    final rpc = _playbackController?.setBalance(clamped);
    final persist = _coalescePersist(
      'balance',
      () => _repository.setBalance(clamped),
    );
    await Future.wait([?rpc, persist]);
  }

  Future<void> setMono(bool mono) async {
    _settings = _settings.copyWith(mono: mono);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setMono(mono);
    await _playbackController?.setMono(mono);
  }

  Future<void> setCrossfeed(Crossfeed crossfeed) async {
    _settings = _settings.copyWith(crossfeed: crossfeed);
    _emitScoped([_spatialNotifier]);
    await _repository.setCrossfeed(crossfeed);
    await _playbackController?.setCrossfeed(crossfeed);
  }

  Future<void> setSpatializer(double width) async {
    final clamped = width.clamp(0.0, 2.0);
    _settings = _settings.copyWith(spatializerWidth: clamped);
    _emitScoped([_spatialNotifier]);
    final rpc = _playbackController?.setSpatializer(clamped);
    final persist = _coalescePersist(
      'spatializer',
      () => _repository.setSpatializer(clamped),
    );
    await Future.wait([?rpc, persist]);
  }

  Future<void> setLimiter(bool limiter) async {
    _settings = _settings.copyWith(limiterEnabled: limiter);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setLimiter(limiter);
    await _playbackController?.setLimiter(limiter);
  }

  Future<void> setReverbEnabled(bool enabled) async {
    if (enabled &&
        (_settings.reverbPreset == 'off' ||
            _settings.reverbPreset == 'Off' ||
            _settings.reverbRoomSize == 0.0)) {
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
      _emitScoped([_reverbNotifier]);
      await Future.wait([
        _repository.setReverbEnabled(true),
        _repository.setReverbPreset(preset),
        _repository.setReverbRoomSize(target.roomSize),
        _repository.setReverbDamping(target.damping),
        _repository.setReverbWidth(target.width),
        _repository.setReverbWet(target.wet),
        _repository.setReverbDry(target.dry),
      ]);
    } else {
      _settings = _settings.copyWith(reverbEnabled: enabled);
      _emitScoped([_reverbNotifier]);
      await _repository.setReverbEnabled(enabled);
    }
    await _playbackController?.setReverb(_settings.reverbConfig);
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
      _emitScoped([_reverbNotifier]);
      await Future.wait([
        _repository.setReverbEnabled(!isOff),
        _repository.setReverbPreset(preset),
        _repository.setReverbRoomSize(target.roomSize),
        _repository.setReverbDamping(target.damping),
        _repository.setReverbWidth(target.width),
        _repository.setReverbWet(target.wet),
        _repository.setReverbDry(target.dry),
      ]);
    } else {
      _settings = _settings.copyWith(reverbPreset: preset);
      _emitScoped([_reverbNotifier]);
      await _repository.setReverbPreset(preset);
    }
    await _playbackController?.setReverb(_settings.reverbConfig);
  }

  Future<void> _updateReverbParam({
    required String persistKey,
    required AppSettings Function(AppSettings current) updateSettings,
    required Future<void> Function() persistValue,
  }) async {
    _settings = updateSettings(
      _settings.copyWith(reverbEnabled: true, reverbPreset: 'custom'),
    );
    _emitScoped([_reverbNotifier]);
    final rpc = _playbackController?.setReverb(_settings.reverbConfig);
    final persist = _coalescePersist(persistKey, () async {
      await _repository.setReverbEnabled(true);
      await _repository.setReverbPreset('custom');
      await persistValue();
    });
    await Future.wait([?rpc, persist]);
  }

  Future<void> setReverbRoomSize(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbRoomSize',
      updateSettings: (s) => s.copyWith(reverbRoomSize: clamped),
      persistValue: () => _repository.setReverbRoomSize(clamped),
    );
  }

  Future<void> setReverbDamping(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbDamping',
      updateSettings: (s) => s.copyWith(reverbDamping: clamped),
      persistValue: () => _repository.setReverbDamping(clamped),
    );
  }

  Future<void> setReverbWidth(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbWidth',
      updateSettings: (s) => s.copyWith(reverbWidth: clamped),
      persistValue: () => _repository.setReverbWidth(clamped),
    );
  }

  Future<void> setReverbWet(double val) {
    final clamped = val.clamp(0.0, 2.0);
    return _updateReverbParam(
      persistKey: 'reverbWet',
      updateSettings: (s) => s.copyWith(reverbWet: clamped),
      persistValue: () => _repository.setReverbWet(clamped),
    );
  }

  Future<void> setReverbDry(double val) {
    final clamped = val.clamp(0.0, 2.0);
    return _updateReverbParam(
      persistKey: 'reverbDry',
      updateSettings: (s) => s.copyWith(reverbDry: clamped),
      persistValue: () => _repository.setReverbDry(clamped),
    );
  }

  Future<void> setVolumeBoost(double boost) async {
    final clamped = boost.clamp(
      AppDefaults.volumeBoostMin,
      AppDefaults.volumeBoostMax,
    );
    _settings = _settings.copyWith(volumeBoost: clamped);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setVolumeBoost(clamped);
  }

  // ---------------------------------------------------------------------------
  // Appearance & Localization
  // ---------------------------------------------------------------------------
  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    _emitScoped([_themeNotifier]);
    await _repository.setThemeMode(mode);
  }

  Future<void> setAccentColor(int colorValue) async {
    _settings = _settings.copyWith(accentColorValue: colorValue);
    _emitScoped([_themeNotifier]);
    await _repository.setAccentColor(colorValue);
  }

  Future<void> setIsOledMode(bool isOled) async {
    _settings = _settings.copyWith(isOledMode: isOled);
    _emitScoped([_themeNotifier]);
    await _repository.setIsOledMode(isOled);
  }

  Future<bool> setCustomBackground(String? sourceImagePath) async {
    if (sourceImagePath == null) {
      _settings = _settings.copyWith(clearCustomBackground: true);
      _emitScoped([_themeNotifier]);
      await _repository.setCustomBackgroundPath(null);
      return true;
    }

    try {
      final targetPath = await PersistentBinaryStorage.copyCustomBackgroundFile(
        sourceImagePath,
      );
      if (targetPath == null) return false;

      _settings = _settings.copyWith(customBackgroundPath: targetPath);
      _emitScoped([_themeNotifier]);
      await _repository.setCustomBackgroundPath(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBackgroundBlurSigma(double sigma) async {
    final clamped = sigma.clamp(0.0, 50.0);
    _settings = _settings.copyWith(backgroundBlurSigma: clamped);
    _emitScoped([_themeNotifier]);
    await _coalescePersist(
      'bgBlurSigma',
      () => _repository.setBackgroundBlurSigma(clamped),
    );
  }

  Future<void> setBackgroundDimOpacity(double opacity) async {
    final clamped = opacity.clamp(0.1, 0.95);
    _settings = _settings.copyWith(backgroundDimOpacity: clamped);
    _emitScoped([_themeNotifier]);
    await _coalescePersist(
      'bgDimOpacity',
      () => _repository.setBackgroundDimOpacity(clamped),
    );
  }

  Future<void> setAppLanguage(String languageCode) async {
    _settings = _settings.copyWith(appLanguage: languageCode);
    _emitScoped([_localeNotifier]);
    await _repository.setAppLanguage(languageCode);
  }

  Future<void> setLyricsTranslationTargetLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationTargetLang: languageCode);
    _emitScoped([_lyricsNotifier]);
    await _repository.setLyricsTranslationTargetLang(languageCode);
  }

  Future<void> setLyricsTranslationSourceLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationSourceLang: languageCode);
    _emitScoped([_lyricsNotifier]);
    await _repository.setLyricsTranslationSourceLang(languageCode);
  }

  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
    await init();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    if (!_inScopedNotify) {
      _themeNotifier.notify();
      _libraryNotifier.notify();
      _crossfadeNotifier.notify();
      _enhancementsNotifier.notify();
      _spatialNotifier.notify();
      _reverbNotifier.notify();
      _equalizerNotifier.notify();
      _lyricsNotifier.notify();
      _localeNotifier.notify();
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _themeNotifier.dispose();
    _libraryNotifier.dispose();
    _crossfadeNotifier.dispose();
    _enhancementsNotifier.dispose();
    _spatialNotifier.dispose();
    _reverbNotifier.dispose();
    _equalizerNotifier.dispose();
    _lyricsNotifier.dispose();
    _localeNotifier.dispose();
    super.dispose();
  }
}
