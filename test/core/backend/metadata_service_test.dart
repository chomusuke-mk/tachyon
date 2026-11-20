import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataService Isolate Pool Tests', () {
    late Directory tempDir;
    late Directory musicDir;
    late AppDatabase database;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('metadata_service_test_');
      musicDir = Directory(p.join(tempDir.path, 'music'))..createSync();
      MetadataUtils.init(
        p.join(tempDir.path, 'thumbnails'),
        p.join(tempDir.path, 'cache'),
      );
      database = AppDatabase.inMemory();
    });

    tearDown(() {
      database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('workerCount defaults to Platform.numberOfProcessors or customWorkerCount', () {
      final defaultService = MetadataService(database: database);
      expect(
        defaultService.workerCount,
        equals(math.max(1, Platform.numberOfProcessors)),
      );

      final customService = MetadataService(
        database: database,
        customWorkerCount: 4,
      );
      expect(customService.workerCount, equals(4));
    });

    test('Isolate pool extracts files in parallel and streams progress to caller', () async {
      // Create 8 dummy audio files
      for (int i = 1; i <= 8; i++) {
        final file = File(p.join(musicDir.path, 'song_$i.mp3'));
        file.writeAsStringSync('ID3 dummy audio content $i');
      }

      final service = MetadataService(
        database: database,
        customWorkerCount: 4,
      );

      final progressEvents = <ScanProgress>[];
      final completer = Completer<void>();

      service.scanDirectories([musicDir.path]).listen(
        (progress) {
          progressEvents.add(progress);
        },
        onDone: completer.complete,
      );

      await completer.future;

      expect(progressEvents.isNotEmpty, isTrue);

      // Verify stages occurred
      final stages = progressEvents.map((e) => e.stage).toList();
      expect(stages, contains(ScanStage.gettingDatabase));
      expect(stages, contains(ScanStage.discovering));
      expect(stages, contains(ScanStage.extracting));
      expect(stages, contains(ScanStage.completed));

      // Verify progress in extracting stage was reported
      final extractingEvents =
          progressEvents.where((e) => e.stage == ScanStage.extracting).toList();
      expect(extractingEvents.isNotEmpty, isTrue);
      expect(extractingEvents.first.progressLabel, equals('0/8'));
      expect(extractingEvents.last.progressValue, equals(1.0));

      service.dispose();
    });

    test('Cancellation immediately stops isolate workers and emits cancelled stage', () async {
      // Create 20 dummy audio files
      for (int i = 1; i <= 20; i++) {
        final file = File(p.join(musicDir.path, 'track_$i.mp3'));
        file.writeAsStringSync('ID3 track content $i');
      }

      final service = MetadataService(
        database: database,
        customWorkerCount: 4,
      );

      final token = CancellationToken();
      final stream = service.scanDirectories(
        [musicDir.path],
        cancellationToken: token,
      );

      final events = <ScanProgress>[];
      final completer = Completer<void>();
      stream.listen(
        (progress) {
          events.add(progress);
          if (progress.stage == ScanStage.extracting && !token.isCancelled) {
            token.cancel();
          }
        },
        onDone: completer.complete,
      );

      await completer.future;
      expect(events.last.stage, equals(ScanStage.cancelled));
      expect(service.isScanning, isFalse);

      service.dispose();
    });

    test('Empty directory scan skips isolate creation and completes', () async {
      final service = MetadataService(
        database: database,
        customWorkerCount: 4,
      );

      final events = await service.scanDirectories([musicDir.path]).toList();
      expect(events.last.stage, equals(ScanStage.completed));

      service.dispose();
    });

    test('MetadataUtils.extractTrackMetadata extracts audio info & waveform natively in single pass without chromaprint', () async {
      await MiniaudioPlayer.ensureInitialized();

      // Build valid 0.25s 16-bit mono PCM WAV at 44100 Hz with a 440 Hz tone
      const sampleRate = 44100;
      const numSamples = sampleRate ~/ 4;
      const dataSize = numSamples * 2;
      final byteData = ByteData(44 + dataSize);
      // "RIFF"
      byteData.setUint8(0, 0x52);
      byteData.setUint8(1, 0x49);
      byteData.setUint8(2, 0x46);
      byteData.setUint8(3, 0x46);
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      // "WAVE"
      byteData.setUint8(8, 0x57);
      byteData.setUint8(9, 0x41);
      byteData.setUint8(10, 0x56);
      byteData.setUint8(11, 0x45);
      // "fmt "
      byteData.setUint8(12, 0x66);
      byteData.setUint8(13, 0x6D);
      byteData.setUint8(14, 0x74);
      byteData.setUint8(15, 0x20);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little); // PCM
      byteData.setUint16(22, 1, Endian.little); // Mono
      byteData.setUint32(24, sampleRate, Endian.little);
      byteData.setUint32(28, sampleRate * 2, Endian.little);
      byteData.setUint16(32, 2, Endian.little);
      byteData.setUint16(34, 16, Endian.little);
      // "data"
      byteData.setUint8(36, 0x64);
      byteData.setUint8(37, 0x61);
      byteData.setUint8(38, 0x74);
      byteData.setUint8(39, 0x61);
      byteData.setUint32(40, dataSize, Endian.little);
      for (int i = 0; i < numSamples; i++) {
        final sample =
            (math.sin(2 * math.pi * 440 * i / sampleRate) * 16000).round();
        byteData.setInt16(44 + i * 2, sample, Endian.little);
      }

      final wavFile = File(p.join(musicDir.path, 'tone_test.wav'));
      wavFile.writeAsBytesSync(byteData.buffer.asUint8List());

      final extracted = await MetadataUtils.extractTrackMetadata(
        filePath: wavFile.path,
      );

      expect(extracted, isNotNull);
      expect(extracted!.title, equals('tone_test'));
      expect(extracted.sampleRate, equals(sampleRate));
      expect(extracted.channels, equals(1));
      expect(extracted.durationMs, closeTo(250, 20));
      expect(extracted.waveformData, isNotNull);
      expect(extracted.waveformData!.isNotEmpty, isTrue);
    });
  });
}
