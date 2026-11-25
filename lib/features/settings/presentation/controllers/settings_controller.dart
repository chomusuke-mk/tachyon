// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';
import 'package:tachyon/core/platform/folder_utils.dart';

class _SettingsDomainNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// State management controller coordinating persisted [AppSettings] and live
/// playback engine synchronization.
///
/// Exposes domain-specific [Listenable]s (such as [themeListenable] and
/// [equalizerListenable]) to minimize unnecessary widget rebuilds.
class SettingsController extends ChangeNotifier {
  static const _log = ScopedLogger('Settings');

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

  /// Creates a [SettingsController] backed by [repository] and an optional
  /// [playbackController].
  ///
  /// Loads the initial [AppSettings] snapshot synchronously from [repository].
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

  /// Listenable notified when theme, accent color, or background settings change.
  Listenable get themeListenable => _themeNotifier;

  /// Listenable notified when configured music directories or files change.
  Listenable get libraryListenable => _libraryNotifier;

  /// Listenable notified when crossfade duration or curve settings change.
  Listenable get crossfadeListenable => _crossfadeNotifier;

  /// Listenable notified when playback enhancement or output device settings change.
  Listenable get enhancementsListenable => _enhancementsNotifier;

  /// Listenable notified when balance, crossfeed, or spatializer settings change.
  Listenable get spatialListenable => _spatialNotifier;

  /// Listenable notified when reverb preset or room parameters change.
  Listenable get reverbListenable => _reverbNotifier;

  /// Listenable notified when equalizer state, preset, band gains, or preamp change.
  Listenable get equalizerListenable => _equalizerNotifier;

  /// Listenable notified when lyrics translation language settings change.
  Listenable get lyricsListenable => _lyricsNotifier;

  /// Listenable notified when the application language setting changes.
  Listenable get localeListenable => _localeNotifier;

  /// Current immutable [AppSettings] snapshot.
  AppSettings get settings => _settings;

  /// Underlying [SettingsRepository] used to persist setting changes.
  SettingsRepository get repository => _repository;

  /// Configured local directory paths scanned for audio tracks.
  List<String> get musicDirectories => _settings.musicDirectories;

  /// Configured individual local audio file paths and remote stream URLs.
  List<String> get musicFiles => _settings.musicFiles;

  /// Automatic track-to-track crossfade duration in seconds.
  int get crossfadeDuration => _settings.crossfadeDuration;

  /// Manual track-skip crossfade duration in seconds.
  int get crossfadeManualDuration => _settings.crossfadeManualDuration;

  /// Gain interpolation curve applied during crossfade transitions.
  CrossfadeCurve get crossfadeCurve => _settings.crossfadeCurve;

  /// Playback output volume factor (`0.0` to `1.0`).
  double get volume => _settings.volume;

  /// Playback speed multiplier (`0.5` to `1.5`).
  double get playbackRate => _settings.playbackRate;

  /// Playback pitch multiplier (`0.5` to `1.5`).
  double get playbackPitch => _settings.playbackPitch;

  /// Active queue repeat mode.
  LoopMode get loopMode => _settings.loopMode;

  /// Whether queue playback shuffling is enabled.
  bool get shuffle => _settings.shuffle;

  /// Whether automatic silence skipping is enabled.
  bool get skipSilence => _settings.skipSilence;

  /// Active silence detection mode applied when [skipSilence] is enabled.
  SilenceSkipMode get silenceSkipMode => _settings.silenceSkipMode;

  /// Whether ReplayGain loudness normalization is enabled.
  bool get volumeNormalization => _settings.volumeNormalization;

  /// Pre-amplifier gain offset in decibels (`-12.0` to `+12.0` dB).
  double get preampDb => _settings.preampDb;

  /// Stereo left-to-right pan balance (`-1.0` to `1.0`).
  double get balance => _settings.balance;

  /// Whether stereo audio output is downmixed to mono.
  bool get mono => _settings.mono;

  /// Headphone crossfeed configuration.
  Crossfeed get crossfeed => _settings.crossfeed;

  /// Stereo spatializer width factor (`0.0` to `2.0`).
  double get spatializerWidth => _settings.spatializerWidth;

  /// Whether the output peak limiter is enabled.
  bool get limiterEnabled => _settings.limiterEnabled;

  /// Additional volume boost multiplier (`1.0` to `2.0`).
  double get volumeBoost => _settings.volumeBoost;

  /// Active application brightness theme mode.
  ThemeMode get themeMode => _settings.themeMode;

  /// ARGB integer value of the selected accent seed color.
  int get accentColorValue => _settings.accentColorValue;

  /// Accent seed [Color] derived from [accentColorValue].
  Color get accentColor => _settings.accentColor;

  /// Whether pure-black OLED surfaces are used in dark theme.
  bool get isOledMode => _settings.isOledMode;

  /// Path or storage key of the custom background image, or `null` if unset.
  String? get customBackgroundPath => _settings.customBackgroundPath;

  /// Gaussian blur sigma applied to the custom background image.
  double get backgroundBlurSigma => _settings.backgroundBlurSigma;

  /// Darkening overlay opacity applied over the custom background image.
  double get backgroundDimOpacity => _settings.backgroundDimOpacity;

  /// Selected UI language code.
  String get appLanguage => _settings.appLanguage;

  /// Target language code for lyrics translation.
  String get lyricsTranslationTargetLang =>
      _settings.lyricsTranslationTargetLang;

  /// Source language code for lyrics translation.
  String get lyricsTranslationSourceLang =>
      _settings.lyricsTranslationSourceLang;

  /// Identifier of the selected audio output device, or `null` for default.
  String? get audioOutputDeviceId => _settings.audioOutputDeviceId;

  /// Whether playback pauses automatically when the audio output device changes.
  bool get pauseOnDeviceChange => _settings.pauseOnDeviceChange;

  /// Whether the 10-band graphic equalizer is enabled.
  bool get equalizerEnabled => _settings.equalizerEnabled;

  /// Identifier of the active equalizer preset.
  String get equalizerPreset => _settings.equalizerPreset;

  /// Gain values in decibels for each of the 10 equalizer bands.
  List<double> get equalizerGains => _settings.equalizerGains;

  /// Whether the audio reverb effect is enabled.
  bool get reverbEnabled => _settings.reverbEnabled;

  /// Identifier of the active reverb preset.
  String get reverbPreset => _settings.reverbPreset;

  /// Reverb virtual room size parameter (`0.0` to `1.0`).
  double get reverbRoomSize => _settings.reverbRoomSize;

  /// Reverb high-frequency damping factor (`0.0` to `1.0`).
  double get reverbDamping => _settings.reverbDamping;

  /// Reverb stereo width factor (`0.0` to `1.0`).
  double get reverbWidth => _settings.reverbWidth;

  /// Reverb wet signal mix level (`0.0` to `2.0`).
  double get reverbWet => _settings.reverbWet;

  /// Reverb dry signal mix level (`0.0` to `2.0`).
  double get reverbDry => _settings.reverbDry;

  /// Effective [Reverb] configuration derived from the current reverb settings.
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
          _log.e('Persist ($key) error', error: e);
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

  /// Reloads settings from [repository], synchronizes the audio engine, and
  /// notifies all scoped listenables.
  Future<void> init() async {
    _settings = _repository.getSettings();
    _log.d(
      'init themeMode=${_settings.themeMode.name} oled=${_settings.isOledMode} '
      'dirs=${_settings.musicDirectories.length} files=${_settings.musicFiles.length} '
      'customBg=${_settings.customBackgroundPath?.isNotEmpty ?? false}',
    );

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

  /// Validates and registers [directoryPath] as a library music source.
  ///
  /// Returns `true` if [directoryPath] exists and is present in the configured
  /// directory list, or `false` if it is empty or does not exist.
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

  /// Removes [directoryPath] from the configured music directories and persists
  /// the update.
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

  /// Validates and registers multiple audio files or URLs ([pathsOrUrls]) in a single batch.
  ///
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

  /// Removes [pathOrUrl] from the configured music files and deletes any
  /// managed Web audio asset associated with it.
  Future<void> removeMusicFile(String pathOrUrl) async {
    final updated = List<String>.from(_settings.musicFiles)..remove(pathOrUrl);
    _settings = _settings.copyWith(musicFiles: updated);
    await _repository.setMusicFiles(updated);
    if (PersistentBinaryStorage.isManagedWebAudioPath(pathOrUrl)) {
      await PersistentBinaryStorage.removeWebAudioFile(pathOrUrl);
    }
    _emitScoped([_libraryNotifier]);
  }

  /// Clears all configured individual music files and deletes any managed Web
  /// audio assets associated with them.
  Future<void> clearMusicFiles() async {
    final oldFiles = List<String>.from(_settings.musicFiles);
    _settings = _settings.copyWith(musicFiles: const []);
    await _repository.setMusicFiles(const []);
    for (final pathOrUrl in oldFiles) {
      if (PersistentBinaryStorage.isManagedWebAudioPath(pathOrUrl)) {
        await PersistentBinaryStorage.removeWebAudioFile(pathOrUrl);
      }
    }
    _emitScoped([_libraryNotifier]);
  }

  /// Adds the platform's default music directory (on Native) or default Web
  /// sample audio catalog (on Web) when music sources have never been configured.
  ///
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

  /// Updates the automatic crossfade duration to [seconds], clamped to the
  /// supported bounds, and syncs the playback engine.
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

  /// Updates the manual track-skip crossfade duration to [durationSeconds]
  /// and syncs the playback engine.
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

  /// Updates the crossfade interpolation [curve], persists it, and syncs the
  /// playback engine.
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

  /// Enables or disables the graphic equalizer according to [enabled] and
  /// syncs the playback engine.
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

  /// Applies and persists custom 10-band equalizer [gains] while enabling the
  /// equalizer.
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

  /// Applies the named equalizer [preset] and persists its corresponding band
  /// gains.
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

  /// Updates the equalizer [gain] for [bandIndex] (`0`–`9`), switches the
  /// preset to `'custom'`, and syncs the playback engine.
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

  /// Updates and persists the preferred audio output [deviceId], or resets to
  /// the system default when `null`.
  Future<void> setAudioOutputDeviceId(String? deviceId) async {
    _settings = _settings.copyWith(audioOutputDeviceId: deviceId);
    await _repository.setAudioOutputDeviceId(deviceId);
    _emitScoped([_enhancementsNotifier]);
  }

  /// Updates whether playback pauses on audio output device changes ([pause])
  /// and syncs the playback engine.
  Future<void> setPauseOnDeviceChange(bool pause) async {
    _settings = _settings.copyWith(pauseOnDeviceChange: pause);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setPauseOnDeviceChange(pause);
    await _playbackController?.setPauseOnDeviceChange(pause);
  }

  /// Enables or disables automatic silence skipping according to [enabled] and
  /// syncs the playback engine.
  Future<void> setSkipSilence(bool enabled) async {
    _settings = _settings.copyWith(skipSilence: enabled);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setSkipSilence(enabled);
    await _playbackController?.setSilenceConfig(_settings.silenceSkipConfig);
  }

  /// Updates the silence detection [mode], enables silence skipping, and syncs
  /// the playback engine.
  ///
  /// Maps [SilenceSkipMode.disabled] to [SilenceSkipMode.all].
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

  /// Enables or disables ReplayGain volume normalization according to [enabled]
  /// and syncs the playback engine.
  Future<void> setVolumeNormalization(bool enabled) async {
    _settings = _settings.copyWith(volumeNormalization: enabled);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setVolumeNormalization(enabled);
    await _playbackController?.setReplayGainMode(_settings.replayGainMode);
  }

  /// Updates the pre-amplifier gain to [preampDb] dB (clamped to `-12.0`–`12.0`)
  /// and syncs the playback engine.
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

  /// Updates the stereo [balance] (clamped to `-1.0`–`1.0`) and syncs the
  /// playback engine.
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

  /// Enables or disables [mono] audio downmixing and syncs the playback engine.
  Future<void> setMono(bool mono) async {
    _settings = _settings.copyWith(mono: mono);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setMono(mono);
    await _playbackController?.setMono(mono);
  }

  /// Updates the headphone [crossfeed] configuration, persists it, and syncs
  /// the playback engine.
  Future<void> setCrossfeed(Crossfeed crossfeed) async {
    _settings = _settings.copyWith(crossfeed: crossfeed);
    _emitScoped([_spatialNotifier]);
    await _repository.setCrossfeed(crossfeed);
    await _playbackController?.setCrossfeed(crossfeed);
  }

  /// Updates the stereo spatializer [width] (clamped to `0.0`–`2.0`) and syncs
  /// the playback engine.
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

  /// Enables or disables the output peak [limiter] and syncs the playback
  /// engine.
  Future<void> setLimiter(bool limiter) async {
    _settings = _settings.copyWith(limiterEnabled: limiter);
    _emitScoped([_enhancementsNotifier]);
    await _repository.setLimiter(limiter);
    await _playbackController?.setLimiter(limiter);
  }

  /// Enables or disables audio reverb according to [enabled] and syncs the
  /// playback engine.
  ///
  /// Activates the `'studio'` preset automatically when enabling reverb from an
  /// `'off'` or zero-room-size state.
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

  /// Applies the named reverb [preset], persists its parameters, and syncs the
  /// playback engine.
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

  /// Updates the reverb room size to [val] (clamped to `0.0`–`1.0`), sets the
  /// preset to `'custom'`, and syncs the playback engine.
  Future<void> setReverbRoomSize(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbRoomSize',
      updateSettings: (s) => s.copyWith(reverbRoomSize: clamped),
      persistValue: () => _repository.setReverbRoomSize(clamped),
    );
  }

  /// Updates the reverb damping factor to [val] (clamped to `0.0`–`1.0`), sets
  /// the preset to `'custom'`, and syncs the playback engine.
  Future<void> setReverbDamping(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbDamping',
      updateSettings: (s) => s.copyWith(reverbDamping: clamped),
      persistValue: () => _repository.setReverbDamping(clamped),
    );
  }

  /// Updates the reverb stereo width to [val] (clamped to `0.0`–`1.0`), sets
  /// the preset to `'custom'`, and syncs the playback engine.
  Future<void> setReverbWidth(double val) {
    final clamped = val.clamp(0.0, 1.0);
    return _updateReverbParam(
      persistKey: 'reverbWidth',
      updateSettings: (s) => s.copyWith(reverbWidth: clamped),
      persistValue: () => _repository.setReverbWidth(clamped),
    );
  }

  /// Updates the reverb wet mix level to [val] (clamped to `0.0`–`2.0`), sets
  /// the preset to `'custom'`, and syncs the playback engine.
  Future<void> setReverbWet(double val) {
    final clamped = val.clamp(0.0, 2.0);
    return _updateReverbParam(
      persistKey: 'reverbWet',
      updateSettings: (s) => s.copyWith(reverbWet: clamped),
      persistValue: () => _repository.setReverbWet(clamped),
    );
  }

  /// Updates the reverb dry mix level to [val] (clamped to `0.0`–`2.0`), sets
  /// the preset to `'custom'`, and syncs the playback engine.
  Future<void> setReverbDry(double val) {
    final clamped = val.clamp(0.0, 2.0);
    return _updateReverbParam(
      persistKey: 'reverbDry',
      updateSettings: (s) => s.copyWith(reverbDry: clamped),
      persistValue: () => _repository.setReverbDry(clamped),
    );
  }

  /// Updates and persists the volume [boost] factor, clamped to the supported
  /// bounds.
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

  /// Updates and persists the application brightness theme [mode].
  Future<void> setThemeMode(ThemeMode mode) async {
    _log.d('setThemeMode(${mode.name})');
    _settings = _settings.copyWith(themeMode: mode);
    _emitScoped([_themeNotifier]);
    await _repository.setThemeMode(mode);
  }

  /// Updates and persists the accent seed color ARGB [colorValue].
  Future<void> setAccentColor(int colorValue) async {
    _settings = _settings.copyWith(accentColorValue: colorValue);
    _emitScoped([_themeNotifier]);
    await _repository.setAccentColor(colorValue);
  }

  /// Updates and persists whether pure-black OLED mode ([isOled]) is enabled.
  Future<void> setIsOledMode(bool isOled) async {
    _log.d('setIsOledMode($isOled)');
    _settings = _settings.copyWith(isOledMode: isOled);
    _emitScoped([_themeNotifier]);
    await _repository.setIsOledMode(isOled);
  }

  /// Sets or clears the custom background image from [sourceImagePath].
  ///
  /// Copies the image into managed storage when [sourceImagePath] is non-null,
  /// or clears the custom background when `null`. Returns `true` on success.
  Future<bool> setCustomBackground(String? sourceImagePath) async {
    if (sourceImagePath == null) {
      _log.d('Clearing custom background');
      _settings = _settings.copyWith(clearCustomBackground: true);
      _emitScoped([_themeNotifier]);
      await _repository.setCustomBackgroundPath(null);
      return true;
    }

    try {
      final targetPath = await PersistentBinaryStorage.copyCustomBackgroundFile(
        sourceImagePath,
      );
      if (targetPath == null) {
        _log.w('setCustomBackground failed: copy returned null for $sourceImagePath');
        return false;
      }

      _log.d('Custom background updated -> $targetPath');
      _settings = _settings.copyWith(customBackgroundPath: targetPath);
      _emitScoped([_themeNotifier]);
      await _repository.setCustomBackgroundPath(targetPath);
      return true;
    } catch (e) {
      _log.w('setCustomBackground error for $sourceImagePath: $e');
      return false;
    }
  }

  /// Updates and persists the background Gaussian blur [sigma], clamped to
  /// `0.0`–`50.0`.
  Future<void> setBackgroundBlurSigma(double sigma) async {
    final clamped = sigma.clamp(0.0, 50.0);
    _settings = _settings.copyWith(backgroundBlurSigma: clamped);
    _emitScoped([_themeNotifier]);
    await _coalescePersist(
      'bgBlurSigma',
      () => _repository.setBackgroundBlurSigma(clamped),
    );
  }

  /// Updates and persists the background dim overlay [opacity], clamped to
  /// `0.1`–`0.95`.
  Future<void> setBackgroundDimOpacity(double opacity) async {
    final clamped = opacity.clamp(0.1, 0.95);
    _settings = _settings.copyWith(backgroundDimOpacity: clamped);
    _emitScoped([_themeNotifier]);
    await _coalescePersist(
      'bgDimOpacity',
      () => _repository.setBackgroundDimOpacity(clamped),
    );
  }

  /// Updates and persists the application UI [languageCode].
  Future<void> setAppLanguage(String languageCode) async {
    _settings = _settings.copyWith(appLanguage: languageCode);
    _emitScoped([_localeNotifier]);
    await _repository.setAppLanguage(languageCode);
  }

  /// Updates and persists the lyrics translation target [languageCode].
  Future<void> setLyricsTranslationTargetLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationTargetLang: languageCode);
    _emitScoped([_lyricsNotifier]);
    await _repository.setLyricsTranslationTargetLang(languageCode);
  }

  /// Updates and persists the lyrics translation source [languageCode].
  Future<void> setLyricsTranslationSourceLang(String languageCode) async {
    _settings = _settings.copyWith(lyricsTranslationSourceLang: languageCode);
    _emitScoped([_lyricsNotifier]);
    await _repository.setLyricsTranslationSourceLang(languageCode);
  }

  /// Resets all persisted settings to defaults and re-initializes the controller.
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
