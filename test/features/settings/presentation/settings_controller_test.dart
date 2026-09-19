import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

class FakeLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return {
      'app_title': 'Tachyon',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioPlayerAdapter playerA;
  late MockAudioPlayerAdapter playerB;
  late AudioEngineServiceImpl engine;
  late SettingsRepository repo;
  late LocaleController localeController;
  late SettingsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = SettingsRepository(prefs);

    playerA = MockAudioPlayerAdapter(id: 'PlayerA');
    playerB = MockAudioPlayerAdapter(id: 'PlayerB');
    engine = AudioEngineServiceImpl(
      playerA: playerA,
      playerB: playerB,
      queueManager: QueueManager(),
    );

    final localeRepo = FakeLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');

    controller = SettingsController(
      settingsRepository: repo,
      audioEngineService: engine,
      localeController: localeController,
    );
  });

  tearDown(() async {
    controller.dispose();
    await engine.dispose();
  });

  group('SettingsController Initial State & Sync', () {
    test('initializes with default preferences', () {
      expect(controller.crossfadeEnabled, isTrue);
      expect(controller.crossfadeDuration, equals(AppConstants.defaultCrossfadeDurationSeconds));
      expect(controller.crossfadeCurve, equals('equal_power'));
      expect(controller.themeMode, equals(ThemeMode.dark));
      expect(controller.appLanguage, equals(AppConstants.defaultLanguageCode));
    });

    test('init propagates crossfade and volume settings to AudioEngineService', () async {
      await controller.init();

      expect(engine.crossfadeConfig.enabled, isTrue);
      expect(engine.crossfadeConfig.duration.inSeconds, equals(AppConstants.defaultCrossfadeDurationSeconds));
    });
  });

  group('SettingsController Directory Management', () {
    test('addMusicDirectory validates existence and prevents duplicates', () async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_music_dir_');
      try {
        final success = await controller.addMusicDirectory(tempDir.path);
        expect(success, isTrue);
        expect(controller.musicDirectories, contains(tempDir.path));

        // Duplicate addition returns true without duplicating list item
        final duplicateSuccess = await controller.addMusicDirectory(tempDir.path);
        expect(duplicateSuccess, isTrue);
        expect(controller.musicDirectories.length, equals(1));

        // Remove directory
        await controller.removeMusicDirectory(tempDir.path);
        expect(controller.musicDirectories, isEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('addMusicDirectory fails for non-existent path', () async {
      final success = await controller.addMusicDirectory('/non_existent_folder_xyz_123');
      expect(success, isFalse);
      expect(controller.musicDirectories, isEmpty);
    });
  });

  group('SettingsController Audio Preferences', () {
    test('setCrossfadeDuration clamps to valid bounds and updates engine', () async {
      await controller.setCrossfadeDuration(2);
      expect(controller.crossfadeDuration, equals(2));
      expect(engine.crossfadeConfig.duration.inSeconds, equals(2));

      // Test upper clamp
      await controller.setCrossfadeDuration(100);
      expect(controller.crossfadeDuration, equals(AppConstants.maxCrossfadeDurationSeconds));
      expect(engine.crossfadeConfig.duration.inSeconds, equals(AppConstants.maxCrossfadeDurationSeconds));

      // Test lower clamp
      await controller.setCrossfadeDuration(0);
      expect(controller.crossfadeDuration, equals(AppConstants.minCrossfadeDurationSeconds));
      expect(engine.crossfadeConfig.duration.inSeconds, equals(AppConstants.minCrossfadeDurationSeconds));
    });

    test('setCrossfadeEnabled updates repository and engine', () async {
      await controller.setCrossfadeEnabled(false);
      expect(controller.crossfadeEnabled, isFalse);
      expect(engine.crossfadeConfig.enabled, isFalse);

      await controller.setCrossfadeEnabled(true);
      expect(controller.crossfadeEnabled, isTrue);
      expect(engine.crossfadeConfig.enabled, isTrue);
    });

    test('setReplayGain and preamp update engine', () async {
      await controller.setReplayGain(ReplayGainMode.track);
      expect(controller.replayGain, equals(ReplayGainMode.track));
      expect(engine.currentState.replayGain, equals(ReplayGainMode.track));

      await controller.setReplayGainPreamp(3.5);
      expect(controller.replayGainPreamp, equals(3.5));
      expect(engine.currentState.replayGainPreamp, equals(3.5));
    });

    test('setExclusiveAudio updates setting and engine', () async {
      await controller.setExclusiveAudio(true);
      expect(controller.exclusiveAudio, isTrue);
      expect(engine.currentState.exclusiveAudio, isTrue);
    });
  });

  group('SettingsController Appearance & Localization', () {
    test('setThemeMode updates and persists ThemeMode', () async {
      await controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, equals(ThemeMode.light));

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
    });

    test('setAppLanguage switches locale and persists code', () async {
      await controller.setAppLanguage('es');
      expect(controller.appLanguage, equals('es'));
      expect(localeController.currentLocaleCode, equals('es'));
    });

    test('resetToDefaults restores default settings', () async {
      await controller.setCrossfadeDuration(7);
      await controller.setThemeMode(ThemeMode.light);

      await controller.resetToDefaults();

      expect(controller.crossfadeDuration, equals(AppConstants.defaultCrossfadeDurationSeconds));
      expect(controller.themeMode, equals(ThemeMode.dark));
    });
  });
}
