import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
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
  });
}
