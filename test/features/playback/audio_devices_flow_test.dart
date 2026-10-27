import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class _FakeAudioDevicesProvider {
  final StreamController<List<AudioDevice>> _devController =
      StreamController<List<AudioDevice>>.broadcast();

  Stream<List<AudioDevice>> get devicesStream => _devController.stream;

  Future<List<AudioDevice>> getAudioDevices() async => const [];

  void emitAudioDevices(List<AudioDevice> devices) {
    _devController.add(devices);
  }

  Future<void> dispose() async {
    await _devController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioDevice reactive flow and miniaudio_player 3.0.1 integration', () {
    late SettingsRepository settingsRepo;
    late _FakeAudioDevicesProvider audioEngine;
    late PlaybackController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      audioEngine = _FakeAudioDevicesProvider();
      controller = PlaybackController(
        devicesStream: audioEngine.devicesStream,
        settingsRepository: settingsRepo,
      );
    });

    tearDown(() async {
      controller.dispose();
      await audioEngine.dispose();
    });

    test('AudioDevice properties and displayName', () {
      const autoDevice = AudioDevice(
        id: '',
        name: 'SYSTEM DEFAULT',
        resolvedName: 'Realtek Audio',
        isAuto: true,
      );
      expect(autoDevice.isAuto, isTrue);
      expect(autoDevice.resolvedName, equals('Realtek Audio'));
      expect(autoDevice.displayName, contains('Realtek Audio'));

      const hardwareDevice = AudioDevice(
        id: 'dac_123',
        name: 'FiiO USB DAC',
        isAuto: false,
      );
      expect(hardwareDevice.isAuto, isFalse);
      expect(hardwareDevice.displayName, equals('FiiO USB DAC'));
    });

    test('PlaybackController updates audioDevices when backend emits device list', () async {
      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      expect(controller.audioDevices, isEmpty);

      final devices = [
        const AudioDevice(
          id: '',
          name: 'SYSTEM DEFAULT',
          resolvedName: 'Speakers',
          isAuto: true,
        ),
        const AudioDevice(
          id: 'headphone_1',
          name: 'Sony WH-1000XM4',
        ),
      ];

      audioEngine.emitAudioDevices(devices);
      await Future<void>.delayed(Duration.zero);

      expect(controller.audioDevices.length, equals(2));
      expect(controller.audioDevices[0].isAuto, isTrue);
      expect(controller.audioDevices[1].name, equals('Sony WH-1000XM4'));
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('PlaybackController restores saved audio device from settings repository', () async {
      await settingsRepo.setAudioOutputDeviceId('headphone_1');

      final devices = [
        const AudioDevice(
          id: '',
          name: 'SYSTEM DEFAULT',
          isAuto: true,
        ),
        const AudioDevice(
          id: 'headphone_1',
          name: 'Sony WH-1000XM4',
        ),
      ];

      audioEngine.emitAudioDevices(devices);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentDevice?.id, equals('headphone_1'));
      expect(controller.currentDevice?.name, equals('Sony WH-1000XM4'));
    });
  });
}
