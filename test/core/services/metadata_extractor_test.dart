import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/core/services/native_binary_locator.dart';
import 'package:tachyon/core/services/process_executor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

class MockBinaryLocator implements NativeBinaryLocator {
  final String ffprobePath;
  final String ffmpegPath;

  MockBinaryLocator({
    this.ffprobePath = '/usr/bin/ffprobe',
    this.ffmpegPath = '/usr/bin/ffmpeg',
  });

  @override
  Future<String> findFfprobe({bool forceRefresh = false}) async => ffprobePath;

  @override
  Future<String> findFfmpeg({bool forceRefresh = false}) async => ffmpegPath;

  @override
  Future<bool> isFfprobeAvailable() async => true;

  @override
  Future<bool> isFfmpegAvailable() async => true;
}

class MockProcessExecutor implements ProcessExecutor {
  final Future<ProcessResult> Function(String executable, List<String> arguments)? onRun;
  int executionCount = 0;

  MockProcessExecutor({this.onRun});

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    executionCount++;
    if (onRun != null) {
      return onRun!(executable, arguments);
    }

    final filePath = arguments.last;
    final title = p.basenameWithoutExtension(filePath);

    final mockJson = json.encode({
      'streams': [
        {
          'codec_type': 'audio',
          'codec_name': 'mp3',
          'sample_rate': '44100',
          'channels': 2,
          'bit_rate': '320000',
        }
      ],
      'format': {
        'duration': '180.0',
        'size': '7200000',
        'tags': {
          'TITLE': title,
          'ARTIST': 'Test Artist',
          'ALBUM': 'Test Album',
          'DATE': '2024',
          'TRACK': '1',
        }
      }
    });

    return ProcessResult(1, 0, mockJson, '');
  }
}

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late MockBinaryLocator binaryLocator;
  late MockProcessExecutor executor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_extractor_test_');
    database = AppDatabaseImpl.inMemory();
    await database.init();
    binaryLocator = MockBinaryLocator();
    executor = MockProcessExecutor();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ConcurrencyLimiter', () {
    test('strictly bounds concurrent executions to maxConcurrent', () async {
      const maxConcurrent = 3;
      final limiter = ConcurrencyLimiter(maxConcurrent);

      int active = 0;
      int peak = 0;
      final completers = List.generate(10, (_) => Completer<void>());

      final futures = completers.map((c) => limiter.run(() async {
            active++;
            if (active > peak) peak = active;
            await c.future;
            active--;
          })).toList();

      await Future.delayed(const Duration(milliseconds: 20));
      expect(peak, equals(maxConcurrent));
      expect(limiter.activeCount, equals(maxConcurrent));

      // Complete them all
      for (final c in completers) {
        c.complete();
      }
      await Future.wait(futures);
      expect(active, equals(0));
    });
  });

  group('ThrottledProgressEmitter', () {
    test('throttles rapid progress updates to at most 20 Hz unless forced', () async {
      final controller = StreamController<ScanProgress>();
      final emitted = <ScanProgress>[];
      controller.stream.listen(emitted.add);

      final emitter = ThrottledProgressEmitter(controller);

      // Rapidly emit 50 events without force
      for (int i = 0; i < 50; i++) {
        emitter.emit(ScanProgress(
          phase: ScanPhase.extracting,
          scannedFiles: i,
          totalFiles: 50,
        ));
      }

      await Future.delayed(const Duration(milliseconds: 10));
      // Even though 50 calls occurred in <10ms, only 1 should be emitted due to 50ms throttle
      expect(emitted.length, equals(1));

      // Force emissions are immediate (phase transitions)
      emitter.emit(
        const ScanProgress(phase: ScanPhase.completed),
        force: true,
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(emitted.length, equals(2));
      expect(emitted.last.phase, equals(ScanPhase.completed));

      emitter.close();
      await controller.close();
    });
  });

  group('MetadataExtractor - Directory Discovery', () {
    test('discovers only supported audio extensions and skips hidden/empty files', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        customWorkerCount: 2,
      );

      // Create folder structure
      final subDir = Directory(p.join(tempDir.path, 'nested'));
      await subDir.create(recursive: true);

      // Valid audio files
      final f1 = File(p.join(tempDir.path, 'song1.mp3'))..writeAsStringSync('valid mp3 data');
      final f2 = File(p.join(subDir.path, 'song2.flac'))..writeAsStringSync('valid flac data');
      final f3 = File(p.join(subDir.path, 'song3.wav'))..writeAsStringSync('valid wav data');

      // Invalid / ignored files
      File(p.join(tempDir.path, 'cover.jpg')).writeAsStringSync('image data');
      File(p.join(tempDir.path, '.hidden_song.mp3')).writeAsStringSync('hidden mp3');
      File(p.join(tempDir.path, 'empty.mp3')).writeAsStringSync(''); // 0-byte file
      File(p.join(tempDir.path, 'readme.txt')).writeAsStringSync('text');

      final discovered = await extractor.discoverFiles([tempDir.path]).toList();
      final discoveredPaths = discovered.map((d) => d.path).toSet();

      expect(discovered.length, equals(3));
      expect(discoveredPaths.contains(f1.path), isTrue);
      expect(discoveredPaths.contains(f2.path), isTrue);
      expect(discoveredPaths.contains(f3.path), isTrue);
    });
  });

  group('MetadataExtractor - extractMetadata Single File', () {
    test('extracts metadata and constructs Track entity', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
      );

      final songFile = File(p.join(tempDir.path, 'single_test.mp3'))..writeAsStringSync('dummy audio');

      final track = await extractor.extractMetadata(songFile.path);

      expect(track, isNotNull);
      expect(track!.title, equals('single_test'));
      expect(track.artist, equals('Test Artist'));
      expect(track.album, equals('Test Album'));
      expect(track.durationMs, equals(180000));
      expect(executor.executionCount, equals(1));
    });

    test('returns null when file does not exist', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
      );

      final track = await extractor.extractMetadata('/non_existent/song.mp3');
      expect(track, isNull);
      expect(executor.executionCount, equals(0));
    });
  });

  group('MetadataExtractor - Incremental Scanning Pipeline', () {
    test('skips unchanged files based on uri, file_size, and modified_at', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        customWorkerCount: 2,
      );

      final file1 = File(p.join(tempDir.path, 'track1.mp3'))..writeAsStringSync('audio 1 content');
      final stat1 = await file1.stat();

      // Seed database with track1 already scanned
      await database.insertOrUpdateTrack(Track(
        uri: file1.path,
        title: 'track1',
        album: 'Test Album',
        artist: 'Test Artist',
        durationMs: 180000,
        fileSize: stat1.size,
        modifiedAt: stat1.modified.millisecondsSinceEpoch,
      ));

      // Add track2 which is brand new
      File(p.join(tempDir.path, 'track2.mp3')).writeAsStringSync('audio 2 content');

      final progressEvents = <ScanProgress>[];
      await for (final progress in extractor.scanDirectories([tempDir.path])) {
        progressEvents.add(progress);
      }

      final finalProgress = progressEvents.last;
      expect(finalProgress.phase, equals(ScanPhase.completed));
      expect(finalProgress.totalFiles, equals(2));
      expect(finalProgress.skippedTracks, equals(1));
      expect(finalProgress.newTracks, equals(1));

      // Only track2 should have required ffprobe execution
      expect(executor.executionCount, equals(1));

      // Both tracks now exist in database
      final allTracks = await database.getAllTracks();
      expect(allTracks.length, equals(2));
    });

    test('updates existing track when file modification timestamp changes', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        customWorkerCount: 2,
      );

      final file = File(p.join(tempDir.path, 'modified_track.flac'))..writeAsStringSync('initial version');
      final stat = await file.stat();

      await database.insertOrUpdateTrack(Track(
        uri: file.path,
        title: 'modified_track',
        album: 'Old Album',
        artist: 'Old Artist',
        durationMs: 100000,
        fileSize: stat.size,
        modifiedAt: stat.modified.millisecondsSinceEpoch - 10000, // older timestamp in DB
      ));

      final progressEvents = <ScanProgress>[];
      await for (final progress in extractor.scanDirectories([tempDir.path])) {
        progressEvents.add(progress);
      }

      final finalProgress = progressEvents.last;
      expect(finalProgress.phase, equals(ScanPhase.completed));
      expect(finalProgress.skippedTracks, equals(0));
      expect(finalProgress.updatedTracks, equals(1));
      expect(executor.executionCount, equals(1));
    });
  });

  group('MetadataExtractor - Cancellation & Error Handling', () {
    test('aborts gracefully when CancellationToken is triggered', () async {
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        customWorkerCount: 1,
      );

      // Create multiple files
      for (int i = 0; i < 5; i++) {
        File(p.join(tempDir.path, 'song_$i.mp3')).writeAsStringSync('audio $i');
      }

      final cancellationToken = CancellationToken();
      final progressEvents = <ScanProgress>[];

      final scanStream = extractor.scanDirectories(
        [tempDir.path],
        cancellationToken: cancellationToken,
      );

      await for (final progress in scanStream) {
        progressEvents.add(progress);
        if (progress.phase == ScanPhase.extracting) {
          cancellationToken.cancel();
        }
      }

      expect(progressEvents.last.phase, equals(ScanPhase.cancelled));
      expect(cancellationToken.isCancelled, isTrue);
    });
  });
}
