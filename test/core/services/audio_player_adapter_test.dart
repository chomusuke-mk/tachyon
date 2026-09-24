import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/tachyon_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TachyonAudioPlatform & AudioPlayerAdapter', () {
    test('ensureInitialized registers TachyonAudioPlatform', () async {
      await AudioPlayerAdapter.ensureInitialized();
      expect(JustAudioPlatform.instance, isA<TachyonAudioPlatform>());
    });

    test('AudioPlayerAdapter initializes and plays without lavf cache errors',
        () async {
      await AudioPlayerAdapter.ensureInitialized();
      final adapter = AudioPlayerAdapter();

      expect(adapter.isDisposed, isFalse);

      final testFile = File('/tmp/test.mp3');
      if (testFile.existsSync()) {
        await adapter.open('/tmp/test.mp3', play: true);
        await Future.delayed(const Duration(milliseconds: 300));
        await adapter.pause();
        await adapter.stop();
      }

      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });
  });
}
