import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:tachyon/core/backend/services/audio_player_adapter.dart';

/// Helper to generate a valid PCM 16-bit WAV file with a pure sine tone.
File _createTestWavFile(String path, {int durationSeconds = 1}) {
  const sampleRate = 44100;
  const numChannels = 1;
  const bitsPerSample = 16;
  final numSamples = sampleRate * durationSeconds;
  final subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
  final chunkSize = 36 + subChunk2Size;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  const blockAlign = numChannels * (bitsPerSample ~/ 8);

  final byteData = ByteData(44 + subChunk2Size);
  // 'RIFF'
  byteData.setUint8(0, 0x52);
  byteData.setUint8(1, 0x49);
  byteData.setUint8(2, 0x46);
  byteData.setUint8(3, 0x46);
  byteData.setUint32(4, chunkSize, Endian.little);
  // 'WAVE'
  byteData.setUint8(8, 0x57);
  byteData.setUint8(9, 0x41);
  byteData.setUint8(10, 0x56);
  byteData.setUint8(11, 0x45);
  // 'fmt '
  byteData.setUint8(12, 0x66);
  byteData.setUint8(13, 0x6D);
  byteData.setUint8(14, 0x74);
  byteData.setUint8(15, 0x20);
  byteData.setUint32(16, 16, Endian.little);
  byteData.setUint16(20, 1, Endian.little);
  byteData.setUint16(22, numChannels, Endian.little);
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, byteRate, Endian.little);
  byteData.setUint16(32, blockAlign, Endian.little);
  byteData.setUint16(34, bitsPerSample, Endian.little);
  // 'data'
  byteData.setUint8(36, 0x64);
  byteData.setUint8(37, 0x61);
  byteData.setUint8(38, 0x74);
  byteData.setUint8(39, 0x61);
  byteData.setUint32(40, subChunk2Size, Endian.little);

  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sampleVal = (math.sin(2 * math.pi * 440 * t) * 3000).toInt();
    byteData.setInt16(44 + i * 2, sampleVal, Endian.little);
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testWav;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('adapter_test_');
    testWav = _createTestWavFile('${tempDir.path}/test_tone.wav', durationSeconds: 2);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AudioPlayerAdapter with MiniaudioPlayer', () {
    test('ensureInitialized executes without error', () async {
      await expectLater(
        AudioPlayerAdapter.ensureInitialized(logLevel: MiniaudioLogLevel.none),
        completes,
      );
    });

    test('AudioPlayerAdapter lifecycle: open, play, pause, seek, volume, dispose', () async {
      final adapter = AudioPlayerAdapter();
      expect(adapter.isDisposed, isFalse);

      await adapter.open(testWav.path, play: false);
      expect(adapter.duration.inMilliseconds, greaterThan(0));

      await adapter.play();
      expect(adapter.isPlaying, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(adapter.position.inMilliseconds, greaterThanOrEqualTo(0));

      await adapter.pause();
      expect(adapter.isPlaying, isFalse);

      await adapter.seek(const Duration(milliseconds: 500));
      expect(adapter.position.inMilliseconds, closeTo(500, 100));

      // Volume testing: 0..100 scale
      await adapter.setVolume(80.0);
      expect(adapter.volume, closeTo(80.0, 1.0));

      // Rate & pitch testing
      await adapter.setRate(1.2);
      expect(adapter.rate, closeTo(1.2, 0.05));

      await adapter.setPitch(1.1);
      expect(adapter.pitch, closeTo(1.1, 0.05));

      await adapter.stop();
      expect(adapter.isPlaying, isFalse);

      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });

    test('AudioPlayerAdapter supports file:// URI scheme', () async {
      final adapter = AudioPlayerAdapter();
      final fileUri = 'file://${testWav.path}';

      await adapter.open(fileUri, play: false);
      expect(adapter.duration.inMilliseconds, greaterThan(0));

      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });

    test('volumeStream emits values scaled to 0..100', () async {
      final adapter = AudioPlayerAdapter();

      final volumeEvents = <double>[];
      final sub = adapter.volumeStream.listen(volumeEvents.add);

      await adapter.setVolume(50.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await adapter.setVolume(100.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();
      await adapter.dispose();

      expect(volumeEvents, contains(closeTo(50.0, 1.0)));
      expect(volumeEvents, contains(closeTo(100.0, 1.0)));
    });
  });
}
