import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = SettingsRepository(prefs);
  });

  group('SettingsRepository Defaults & Persistence', () {
    test('returns default settings when preferences store is empty', () {
      final settings = repository.getSettings();

      expect(settings.musicDirectories, isEmpty);
      expect(settings.crossfadeEnabled, isTrue);
      expect(settings.crossfadeDuration, equals(5));
      expect(settings.crossfadeCurve, equals('equal_power'));
      expect(settings.volume, equals(100.0));
      expect(settings.playbackRate, equals(1.0));
      expect(settings.playbackPitch, equals(1.0));
      expect(settings.loopMode, equals(Loop.off));
      expect(settings.shuffle, isFalse);
      expect(settings.replayGain, equals(ReplayGainMode.off));
      expect(settings.replayGainPreamp, equals(0.0));
      expect(settings.volumeBoost, equals(100.0));
      expect(settings.exclusiveAudio, isFalse);
      expect(settings.themeMode, equals(ThemeMode.dark));
      expect(settings.appLanguage, equals('defaultOption'));
      expect(settings.lastPlayedUri, isNull);
      expect(settings.lastPlayedPositionMs, equals(0));
      expect(settings.equalizerEnabled, isFalse);
      expect(settings.equalizerGains.length, equals(10));
    });

    test('saveSettings persists full settings state accurately', () async {
      const custom = AppSettings(
        musicDirectories: ['/home/user/Music', '/mnt/audio'],
        crossfadeEnabled: false,
        crossfadeDuration: 8,
        crossfadeCurve: 'linear',
        volume: 75.0,
        playbackRate: 1.25,
        playbackPitch: 1.1,
        loopMode: Loop.all,
        shuffle: true,
        replayGain: ReplayGainMode.track,
        replayGainPreamp: 2.5,
        volumeBoost: 120.0,
        exclusiveAudio: true,
        themeMode: ThemeMode.light,
        appLanguage: 'es',
        lastPlayedUri: 'file:///music/song.flac',
        lastPlayedPositionMs: 45000,
        equalizerEnabled: true,
        equalizerGains: [1.0, 2.0, 0.0, -1.0, -2.0, 0.5, 1.5, -0.5, 0.0, 3.0],
      );

      await repository.saveSettings(custom);
      final loaded = repository.getSettings();

      expect(loaded.musicDirectories, equals(custom.musicDirectories));
      expect(loaded.crossfadeEnabled, isFalse);
      expect(loaded.crossfadeDuration, equals(8));
      expect(loaded.crossfadeCurve, equals('linear'));
      expect(loaded.volume, equals(75.0));
      expect(loaded.playbackRate, equals(1.25));
      expect(loaded.playbackPitch, equals(1.1));
      expect(loaded.loopMode, equals(Loop.all));
      expect(loaded.shuffle, isTrue);
      expect(loaded.replayGain, equals(ReplayGainMode.track));
      expect(loaded.replayGainPreamp, equals(2.5));
      expect(loaded.volumeBoost, equals(120.0));
      expect(loaded.exclusiveAudio, isTrue);
      expect(loaded.themeMode, equals(ThemeMode.light));
      expect(loaded.appLanguage, equals('es'));
      expect(loaded.lastPlayedUri, equals('file:///music/song.flac'));
      expect(loaded.lastPlayedPositionMs, equals(45000));
      expect(loaded.equalizerEnabled, isTrue);
      expect(loaded.equalizerGains, equals(custom.equalizerGains));
    });
  });

  group('Individual Modifiers & Bounds Clamping', () {
    test('setCrossfadeDuration clamps to [1, 12]', () async {
      await repository.setCrossfadeDuration(0);
      expect(repository.getSettings().crossfadeDuration, equals(1));

      await repository.setCrossfadeDuration(25);
      expect(repository.getSettings().crossfadeDuration, equals(12));

      await repository.setCrossfadeDuration(6);
      expect(repository.getSettings().crossfadeDuration, equals(6));
    });

    test('setVolume clamps to [0.0, 100.0]', () async {
      await repository.setVolume(-10.0);
      expect(repository.getSettings().volume, equals(0.0));

      await repository.setVolume(150.0);
      expect(repository.getSettings().volume, equals(100.0));

      await repository.setVolume(60.0);
      expect(repository.getSettings().volume, equals(60.0));
    });

    test('setPlaybackRate and setPlaybackPitch clamp to [0.5, 1.5]', () async {
      await repository.setPlaybackRate(0.1);
      expect(repository.getSettings().playbackRate, equals(0.5));

      await repository.setPlaybackRate(2.0);
      expect(repository.getSettings().playbackRate, equals(1.5));

      await repository.setPlaybackPitch(0.2);
      expect(repository.getSettings().playbackPitch, equals(0.5));

      await repository.setPlaybackPitch(3.0);
      expect(repository.getSettings().playbackPitch, equals(1.5));
    });

    test('setReplayGainPreamp clamps to [-15.0, 15.0]', () async {
      await repository.setReplayGainPreamp(-25.0);
      expect(repository.getSettings().replayGainPreamp, equals(-15.0));

      await repository.setReplayGainPreamp(30.0);
      expect(repository.getSettings().replayGainPreamp, equals(15.0));
    });

    test('setVolumeBoost clamps to [100.0, 200.0]', () async {
      await repository.setVolumeBoost(80.0);
      expect(repository.getSettings().volumeBoost, equals(100.0));

      await repository.setVolumeBoost(250.0);
      expect(repository.getSettings().volumeBoost, equals(200.0));
    });

    test('setLastPlayed persists and clears uri/position', () async {
      await repository.setLastPlayed(uri: 'file:///song.mp3', positionMs: 32000);
      expect(repository.getSettings().lastPlayedUri, equals('file:///song.mp3'));
      expect(repository.getSettings().lastPlayedPositionMs, equals(32000));
    });

    test('resetToDefaults clears all preferences', () async {
      await repository.setVolume(45.0);
      await repository.setAppLanguage('es');
      expect(repository.getSettings().volume, equals(45.0));

      await repository.resetToDefaults();
      expect(repository.getSettings().volume, equals(100.0));
      expect(repository.getSettings().appLanguage, equals('defaultOption'));
    });
  });
}
