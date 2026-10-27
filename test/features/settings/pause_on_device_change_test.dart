import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository repository;
  late PlaybackController playbackController;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = SettingsRepository(prefs);
    playbackController = PlaybackController(settingsRepository: repository);
    settingsController = SettingsController(
      repository: repository,
      playbackController: playbackController,
    );
  });

  tearDown(() {
    settingsController.dispose();
    playbackController.dispose();
  });

  group('pauseOnDeviceChange configuration and persistence', () {
    test('default value is true', () {
      expect(repository.getPauseOnDeviceChange(), isTrue);
      expect(repository.getSettings().pauseOnDeviceChange, isTrue);
      expect(settingsController.pauseOnDeviceChange, isTrue);
      expect(playbackController.pauseOnDeviceChange, isTrue);
    });

    test('SettingsRepository persists pauseOnDeviceChange', () async {
      await repository.setPauseOnDeviceChange(false);
      expect(repository.getPauseOnDeviceChange(), isFalse);
      expect(repository.getSettings().pauseOnDeviceChange, isFalse);

      await repository.setPauseOnDeviceChange(true);
      expect(repository.getPauseOnDeviceChange(), isTrue);
      expect(repository.getSettings().pauseOnDeviceChange, isTrue);
    });

    test('SettingsRepository saveSettings saves pauseOnDeviceChange', () async {
      final settings = repository.getSettings().copyWith(pauseOnDeviceChange: false);
      await repository.saveSettings(settings);
      expect(repository.getPauseOnDeviceChange(), isFalse);
    });

    test('SettingsController updates setting, notifies, and syncs with PlaybackController', () async {
      int notifyCount = 0;
      settingsController.addListener(() {
        notifyCount++;
      });

      await settingsController.setPauseOnDeviceChange(false);
      expect(settingsController.pauseOnDeviceChange, isFalse);
      expect(repository.getPauseOnDeviceChange(), isFalse);
      expect(playbackController.pauseOnDeviceChange, isFalse);
      expect(notifyCount, equals(1));

      await settingsController.setPauseOnDeviceChange(true);
      expect(settingsController.pauseOnDeviceChange, isTrue);
      expect(repository.getPauseOnDeviceChange(), isTrue);
      expect(playbackController.pauseOnDeviceChange, isTrue);
      expect(notifyCount, equals(2));
    });

    test('AppSettings equality and hashCode includes pauseOnDeviceChange', () {
      const s1 = AppSettings(lastPlayedFilePath: null, pauseOnDeviceChange: true);
      const s2 = AppSettings(lastPlayedFilePath: null, pauseOnDeviceChange: true);
      const s3 = AppSettings(lastPlayedFilePath: null, pauseOnDeviceChange: false);

      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });
  });
}
