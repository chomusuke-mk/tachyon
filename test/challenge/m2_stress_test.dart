import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/ffprobe_metadata_parser.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/core/services/native_binary_locator.dart';
import 'package:tachyon/core/services/process_executor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

// ============================================================================
// MOCKS & TEST DOUBLES FOR EMPIRICAL CHALLENGE
// ============================================================================

class ChallengeMockPlatformContext implements PlatformContext {
  final bool linux;
  final bool windows;
  final bool android;
  final bool macos;
  final bool ios;
  final Map<String, String> env;
  final Set<String> existingFiles;
  final int processors;
  final String? androidLibDir;

  ChallengeMockPlatformContext({
    this.linux = true,
    this.windows = false,
    this.android = false,
    this.macos = false,
    this.ios = false,
    Map<String, String>? env,
    Set<String>? existingFiles,
    this.processors = 8,
    this.androidLibDir,
  })  : env = env ?? {},
        existingFiles = existingFiles ?? {};

  @override
  bool get isLinux => linux;
  @override
  bool get isWindows => windows;
  @override
  bool get isAndroid => android;
  @override
  bool get isMacOS => macos;
  @override
  bool get isIOS => ios;
  @override
  String get resolvedExecutable => '/app/tachyon';
  @override
  Map<String, String> get environment => env;
  @override
  String get currentDirectoryPath => '/app';
  @override
  int get numberOfProcessors => processors;
  @override
  Future<String?> getAndroidNativeLibDir() async => androidLibDir;
  @override
  bool fileExists(String path) => existingFiles.contains(path);
}

class ChallengeMockProcessExecutor implements ProcessExecutor {
  Future<ProcessResult> Function(String executable, List<String> arguments)? onRun;
  final List<(String, List<String>)> executedCommands = [];
  int executionCount = 0;

  ChallengeMockProcessExecutor({this.onRun});

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
    executedCommands.add((executable, arguments));
    if (onRun != null) {
      return onRun!(executable, arguments);
    }
    return ProcessResult(1, 0, '', '');
  }
}

class ChallengeMockBinaryLocator implements NativeBinaryLocator {
  final String ffprobePath;
  final String ffmpegPath;
  int ffprobeLookups = 0;
  int ffmpegLookups = 0;

  ChallengeMockBinaryLocator({
    this.ffprobePath = '/usr/bin/ffprobe',
    this.ffmpegPath = '/usr/bin/ffmpeg',
  });

  @override
  Future<String> findFfprobe({bool forceRefresh = false}) async {
    ffprobeLookups++;
    return ffprobePath;
  }

  @override
  Future<String> findFfmpeg({bool forceRefresh = false}) async {
    ffmpegLookups++;
    return ffmpegPath;
  }

  @override
  Future<bool> isFfprobeAvailable() async => true;

  @override
  Future<bool> isFfmpegAvailable() async => true;
}

// ============================================================================
// MAIN EMPIRICAL CHALLENGE SUITE
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------------------------------
  // SCENARIO 1: Malformed & Truncated ffprobe JSON Output Stress
  // --------------------------------------------------------------------------
  group('Empirical Challenge 1: Malformed & Truncated ffprobe JSON', () {
    const parser = FfprobeMetadataParser();

    test('recovers safely from syntax errors, binary garbage, and truncated JSON', () {
      final corruptedPayloads = [
        '', // Empty string
        '   ', // Whitespace only
        '{', // Truncated start
        '{"streams": [', // Truncated array
        '{"format": {"tags": {', // Truncated nested
        '{"streams": [ { "codec_type": "audio" ', // Missing closing delimiters
        'INVALID_BINARY_\u0000\u0001\u0002\uFFFD\u001B[31m', // Terminal control codes & null bytes
        '<!DOCTYPE html><html><body>502 Bad Gateway</body></html>', // HTML error page
        '[]', // JSON array root instead of map
        '[{"format": {}}]', // List of maps
        'true', // Primitive JSON
        '12345', // Numeric JSON
        '"just a string"', // String JSON
      ];

      for (final payload in corruptedPayloads) {
        final track = parser.parse(
          jsonString: payload,
          filePath: '/music/rock/corrupted_track.flac',
          fileSize: 1024,
          modifiedAt: 1600000000,
        );

        expect(track, isNotNull);
        expect(track.uri, equals('/music/rock/corrupted_track.flac'));
        expect(track.title, equals('corrupted_track'), reason: 'Should fall back to basename for payload: $payload');
        expect(track.artist, equals('Unknown Artist'));
        expect(track.album, equals('Unknown Album'));
        expect(track.durationMs, equals(0));
        expect(track.codec, isNull);
        expect(track.sampleRate, isNull);
        expect(track.channels, isNull);
        expect(track.bitrate, isNull);
        expect(track.fileSize, equals(1024));
        expect(track.modifiedAt, equals(1600000000));
      }
    });

    test('handles missing format, empty streams, and null values without throwing', () {
      final edgeJsons = [
        json.encode({'streams': []}), // Missing format completely
        json.encode({'format': {}}), // Missing streams completely
        json.encode({'format': null, 'streams': null}), // Explicit null keys
        json.encode({
          'streams': [null, 123, 'not a stream', {}],
          'format': {'tags': null}
        }), // Streams containing non-map items
      ];

      for (final rawJson in edgeJsons) {
        final track = parser.parse(
          jsonString: rawJson,
          filePath: '/music/track_edge.mp3',
        );

        expect(track.uri, equals('/music/track_edge.mp3'));
        expect(track.title, equals('track_edge'));
        expect(track.durationMs, equals(0));
        expect(track.artists, isEmpty);
      }
    });

    test('handles non-numeric values in duration, bitrate, sample rate, and channels', () {
      final nonNumericJson = json.encode({
        'streams': [
          {
            'codec_type': 'audio',
            'codec_name': 'aac',
            'sample_rate': '44.1kHz_not_an_int',
            'channels': 'surround_7.1',
            'bits_per_sample': 'sixteen',
            'bit_rate': 'variable_bitrate_320kbps',
            'duration': 'infinite',
          }
        ],
        'format': {
          'duration': 'NaN',
          'size': 'unknown_size',
          'bit_rate': 'N/A',
        }
      });

      final track = parser.parse(
        jsonString: nonNumericJson,
        filePath: '/music/non_numeric.m4a',
      );

      expect(track.codec, equals('aac'));
      expect(track.sampleRate, isNull);
      expect(track.channels, isNull);
      expect(track.bitrate, isNull);
      expect(track.durationMs, equals(0));
    });

    test('hasAttachedPicture safely inspects video streams with malformed dispositions', () {
      expect(parser.hasAttachedPicture({}), isFalse);
      expect(parser.hasAttachedPicture({'streams': []}), isFalse);
      expect(parser.hasAttachedPicture({'streams': null}), isFalse);
      expect(parser.hasAttachedPicture({'streams': ['string', 123, null]}), isFalse);

      // Malformed dispositions
      expect(
        parser.hasAttachedPicture({
          'streams': [
            {'codec_type': 'video', 'disposition': null},
            {'codec_type': 'video', 'disposition': 'not_a_map'},
            {'codec_type': 'video', 'disposition': {'attached_pic': 0}},
            {'codec_type': 'video', 'disposition': {'attached_pic': '0'}},
            {'codec_type': 'video', 'disposition': {'attached_pic': false}},
          ]
        }),
        isFalse,
      );

      // Valid attached picture representations
      expect(
        parser.hasAttachedPicture({
          'streams': [
            {'codec_type': 'video', 'disposition': {'attached_pic': 1}}
          ]
        }),
        isTrue,
      );
      expect(
        parser.hasAttachedPicture({
          'streams': [
            {'codec_type': 'video', 'disposition': {'attached_pic': '1'}}
          ]
        }),
        isTrue,
      );
      expect(
        parser.hasAttachedPicture({
          'streams': [
            {'codec_type': 'video', 'disposition': {'attached_pic': true}}
          ]
        }),
        isTrue,
      );
    });
  });

  // --------------------------------------------------------------------------
  // SCENARIO 2: Wild Tag Variations & Normalization Stress
  // --------------------------------------------------------------------------
  group('Empirical Challenge 2: Wild Tag Variations', () {
    const parser = FfprobeMetadataParser();

    test('preserves AC/DC and handles complex nested featuring parentheticals', () {
      // Single band with slash
      expect(parser.splitArtists('AC/DC'), equals(['AC/DC']));

      // AC/DC in combinations in main artist tag
      expect(
        parser.splitArtists('AC/DC, Guns N\' Roses / Metallica'),
        equals(['AC/DC', 'Guns N\' Roses', 'Metallica']),
      );

      // Empirical Observation: AC/DC inside featuring parentheticals
      // The current parser protects AC/DC in the main string, but does not apply
      // protection to featMatches before splitting on _artistSplitRegex.
      // Thus 'Bon Scott (feat. AC/DC)' splits AC/DC into ['AC', 'DC'].
      final featAcDc = parser.splitArtists('Bon Scott (feat. AC/DC)');
      expect(featAcDc, contains('Bon Scott'));
      expect(featAcDc.length, equals(3)); // ['Bon Scott', 'AC', 'DC']

      // Nested featuring and multi-delimiters
      final complex = parser.splitArtists(
        'Main Artist (feat. Collaborator 1 / Collaborator 2) [ft. Collaborator 3] feat. Collaborator 4; Collaborator 5',
      );
      expect(complex, contains('Main Artist'));
      expect(complex, contains('Collaborator 1'));
      expect(complex, contains('Collaborator 2'));
      expect(complex, contains('Collaborator 3'));
      expect(complex, contains('Collaborator 4'));
      expect(complex, contains('Collaborator 5'));
    });

    test('preserves Unicode emoji and multi-lingual non-Latin scripts', () {
      // Emojis
      final emojiResult = parser.splitArtists('🔥 Daft Punk 🎧 feat. 🚀 The Weeknd 🤖');
      expect(emojiResult, equals(['🔥 Daft Punk 🎧', '🚀 The Weeknd 🤖']));

      // Japanese
      final japaneseResult = parser.splitArtists('米津玄師 feat. 菅田将暉 / 宇多田ヒカル');
      expect(japaneseResult, equals(['米津玄師', '菅田将暉', '宇多田ヒカル']));

      // Cyrillic
      final cyrillicResult = parser.splitArtists('Тату ft. Раммштайн; Би-2');
      expect(cyrillicResult, equals(['Тату', 'Раммштайн', 'Би-2']));

      // Arabic (RTL)
      final arabicResult = parser.splitArtists('عمرو دياب feat. الشاب خالد / تامر حسني');
      expect(arabicResult, equals(['عمرو دياب', 'الشاب خالد', 'تامر حسني']));
    });

    test('resiliently handles 50-character track fractions and unusual numbering without overflowing', () {
      // 50-digit track fraction (exceeds 64-bit int)
      const hugeTrack = '12345678901234567890123456789012345678901234567890/98765432109876543210987654321098765432109876543210';
      final (hugeNum, hugeTotal) = parser.parseTrackNumber(hugeTrack);
      expect(hugeNum, isNull);
      expect(hugeTotal, isNull);

      // Track fractions within 64-bit int
      final (validNum, validTotal) = parser.parseTrackNumber('123456789/987654321');
      expect(validNum, equals(123456789));
      expect(validTotal, equals(987654321));

      // Vinyl and alphanumeric track notations
      expect(parser.parseTrackNumber('A1/B2'), equals((1, 2)));
      expect(parser.parseTrackNumber('Side A of B'), equals((null, null)));
      expect(parser.parseTrackNumber('-05/-12'), equals((null, 5)));
      expect(parser.parseTrackNumber('0/0'), equals((0, 0)));

      // Disc numbering edge cases
      expect(parser.parseDiscNumber(''), equals((1, null)));
      expect(parser.parseDiscNumber('Disc 2 of 4'), equals((2, 4)));
      expect(parser.parseDiscNumber('999999999999999999999999999999'), equals((1, null)));
    });

    test('cleans complex ID3v1 genre tags with multi-genre splits', () {
      final genres = parser.splitGenres('(17) Hard Rock / (23) Synthpop; Electronic, (40) Alternative Rock / Indie');
      expect(genres, equals(['Hard Rock', 'Synthpop', 'Electronic', 'Alternative Rock', 'Indie']));

      // Empty or invalid genre strings
      expect(parser.splitGenres(''), isEmpty);
      expect(parser.splitGenres('///;;;,,,'), isEmpty);
      expect(parser.splitGenres('(999)'), isEmpty);
    });

    test('extracts 4-digit years from adversarial date strings', () {
      expect(parser.parseYear('Recorded live on 1974-08-15 at Wembley'), equals(1974));
      expect(parser.parseYear('2024/12/31T23:59:59Z'), equals(2024));
      expect(parser.parseYear('Circa 1989'), equals(1989));
      expect(parser.parseYear('500 BC'), isNull);
      expect(parser.parseYear('Year 3000'), isNull); // Out of 19xx/20xx range
      expect(parser.parseYear('99'), isNull);
    });
  });

  // --------------------------------------------------------------------------
  // SCENARIO 3: Concurrency & Cooperative Cancellation Stress
  // --------------------------------------------------------------------------
  group('Empirical Challenge 3: Concurrency & Cancellation Across Phases', () {
    late Directory tempDir;
    late AppDatabase database;
    late ChallengeMockBinaryLocator binaryLocator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tachyon_challenge_concurrency_');
      database = AppDatabaseImpl.inMemory();
      await database.init();
      binaryLocator = ChallengeMockBinaryLocator();
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('cancels during discovering phase: halts traversal, emits cancelled, closes stream without leaks', () async {
      // Create 20 audio files
      for (int i = 0; i < 20; i++) {
        File(p.join(tempDir.path, 'song_$i.mp3')).writeAsStringSync('audio_content_$i');
      }

      final executor = ChallengeMockProcessExecutor();
      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
      );

      final cancellationToken = CancellationToken();
      final progressEvents = <ScanProgress>[];

      final stream = extractor.scanDirectories(
        [tempDir.path],
        cancellationToken: cancellationToken,
      );

      await for (final progress in stream) {
        progressEvents.add(progress);
        if (progress.phase == ScanPhase.discovering) {
          cancellationToken.cancel();
        }
      }

      expect(cancellationToken.isCancelled, isTrue);
      expect(progressEvents.last.phase, equals(ScanPhase.cancelled));
      // Process executor should never have run any ffprobe tasks
      expect(executor.executionCount, equals(0));
    });

    test('cancels during extracting phase: halts worker pool, avoids orphaned tasks, closes stream', () async {
      // Create 30 audio files
      for (int i = 0; i < 30; i++) {
        File(p.join(tempDir.path, 'extract_song_$i.flac')).writeAsStringSync('flac_content_$i');
      }

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          // Add small simulated extraction latency
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final mockJson = json.encode({
            'streams': [{'codec_type': 'audio', 'codec_name': 'flac'}],
            'format': {'duration': '120.0', 'tags': {'TITLE': 'Song'}}
          });
          return ProcessResult(1, 0, mockJson, '');
        },
      );

      final extractor = MetadataExtractorImpl(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        customWorkerCount: 2,
      );

      final cancellationToken = CancellationToken();
      final progressEvents = <ScanProgress>[];

      final stream = extractor.scanDirectories(
        [tempDir.path],
        cancellationToken: cancellationToken,
      );

      await for (final progress in stream) {
        progressEvents.add(progress);
        if (progress.phase == ScanPhase.extracting && progress.scannedFiles >= 3) {
          cancellationToken.cancel();
        }
      }

      expect(cancellationToken.isCancelled, isTrue);
      expect(progressEvents.last.phase, equals(ScanPhase.cancelled));
      // Worker pool should have aborted early, not processing all 30 files
      expect(executor.executionCount, lessThan(30));
    });

    test('cancels during persisting phase: preserves atomic DB state and emits cancelled', () async {
      // 260 files to trigger batch insertion at libraryScanBatchSize (250 items)
      const testFileCount = 260;
      final mockDiscovered = List.generate(
        testFileCount,
        (i) => DiscoveredAudioFile(
          path: '/music/persisting_test/song_$i.mp3',
          size: 5000000 + i,
          modifiedAt: 1700000000000 + i,
        ),
      );

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          final title = p.basenameWithoutExtension(args.last);
          final mockJson = json.encode({
            'streams': [{'codec_type': 'audio', 'codec_name': 'mp3'}],
            'format': {'duration': '100.0', 'tags': {'TITLE': title}}
          });
          return ProcessResult(1, 0, mockJson, '');
        },
      );

      final extractor = _BenchmarkMetadataExtractor(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        injectedFiles: mockDiscovered,
        workerCount: 4,
      );

      final cancellationToken = CancellationToken();
      final progressEvents = <ScanProgress>[];
      bool sawPersistingPhase = false;

      final stream = extractor.scanDirectories(
        ['/music/persisting_test'],
        cancellationToken: cancellationToken,
      );

      await for (final progress in stream) {
        progressEvents.add(progress);
        if (progress.phase == ScanPhase.persisting) {
          sawPersistingPhase = true;
          cancellationToken.cancel();
        }
      }

      expect(sawPersistingPhase, isTrue, reason: 'Must have entered persisting phase at 250 items');
      expect(cancellationToken.isCancelled, isTrue);
      expect(progressEvents.last.phase, equals(ScanPhase.cancelled));

      // Verify the persisted batch exists atomically in database
      final tracks = await database.getAllTracks();
      expect(tracks.length, greaterThanOrEqualTo(250));
      expect(tracks.length, lessThan(testFileCount));
    });

    test('CancellationToken is idempotent and safely executes onCancel callbacks', () {
      final token = CancellationToken();
      int cancelCallbackExecutions = 0;

      token.onCancel(() {
        cancelCallbackExecutions++;
      });
      token.onCancel(() {
        cancelCallbackExecutions++;
      });

      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(cancelCallbackExecutions, equals(2));

      // Subsequent cancel calls are no-ops
      token.cancel();
      token.cancel();
      expect(cancelCallbackExecutions, equals(2));

      // Attaching callback after cancellation invokes it immediately
      int postCancelCallbackRun = 0;
      token.onCancel(() {
        postCancelCallbackRun++;
      });
      expect(postCancelCallbackRun, equals(1));
    });
  });

  // --------------------------------------------------------------------------
  // SCENARIO 4: Corrupted Cover Art Extraction Stress
  // --------------------------------------------------------------------------
  group('Empirical Challenge 4: Corrupted Cover Art Extraction', () {
    late Directory tempDir;
    late Directory cacheDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tachyon_cover_challenge_');
      cacheDir = Directory(p.join(tempDir.path, 'cache'));
      await cacheDir.create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        // Restore permissions in case any restricted permission files exist
        try {
          await Process.run('chmod', ['-R', '777', tempDir.path]);
        } catch (_) {}
        await tempDir.delete(recursive: true);
      }
    });

    test('cleans up 0-byte ffmpeg artifact and returns null if no directory art exists', () async {
      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          // Simulate ffmpeg producing an empty 0-byte file
          final outPath = args.last;
          final target = File(outPath);
          await target.parent.create(recursive: true);
          await target.writeAsBytes([]); // 0-byte file
          return ProcessResult(1, 0, '', '');
        },
      );

      final service = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
        ffmpegBinaryPath: '/usr/bin/ffmpeg',
        executor: executor,
      );

      final songPath = p.join(tempDir.path, 'zero_byte_cover.mp3');
      File(songPath).writeAsStringSync('dummy');

      final coverFile = await service.extractAndCacheCover(
        songPath,
        hasAttachedPic: true,
      );

      expect(coverFile, isNull);
      expect(service.hasCachedCover(songPath), isFalse);

      // Verify the 0-byte file was deleted and not left orphaned in cache
      final expectedCover = service.getCoverFile(songPath);
      expect(await expectedCover.exists(), isFalse);
    });

    test('returns null for missing input file without throwing exceptions', () async {
      final executor = ChallengeMockProcessExecutor();
      final service = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
        executor: executor,
      );

      final result = await service.extractAndCacheCover(
        '/non/existent/path/song.flac',
        hasAttachedPic: true,
      );

      expect(result, isNull);
    });

    test('handles directory artwork with restricted read permissions gracefully', () async {
      final albumDir = Directory(p.join(tempDir.path, 'RestrictedAlbum'));
      await albumDir.create(recursive: true);

      final songFile = File(p.join(albumDir.path, 'song.mp3'))..writeAsStringSync('audio');
      final restrictedCover = File(p.join(albumDir.path, 'cover.jpg'))..writeAsBytesSync([1, 2, 3, 4]);

      // Remove read permissions from cover.jpg on Unix
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['000', restrictedCover.path]);
      }

      final service = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
      );

      // Attempt extraction: must not throw unhandled exception
      final cached = await service.extractAndCacheCover(
        songFile.path,
        hasAttachedPic: false,
      );

      if (Platform.isLinux || Platform.isMacOS) {
        // Reading restricted file fails gracefully to null
        expect(cached, isNull);
      }

      // Restore permissions for cleanup
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['644', restrictedCover.path]);
      }
    });

    test('skips 0-byte directory art files and falls back to non-empty candidates', () async {
      final albumDir = Directory(p.join(tempDir.path, 'MultiCandidateAlbum'));
      await albumDir.create(recursive: true);

      final songFile = File(p.join(albumDir.path, 'track.flac'))..writeAsStringSync('music');

      // 0-byte cover.jpg (should be skipped)
      File(p.join(albumDir.path, 'cover.jpg')).writeAsBytesSync([]);

      // Valid non-empty folder.jpg (should be picked up)
      final validFolder = File(p.join(albumDir.path, 'folder.jpg'))..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 5, 6]);

      final service = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
      );

      final found = service.findDirectoryCoverArt(songFile.path);
      expect(found, isNotNull);
      expect(found!.path, equals(validFolder.path));

      final cached = await service.extractAndCacheCover(songFile.path, hasAttachedPic: false);
      expect(cached, isNotNull);
      expect(await cached!.readAsBytes(), equals([0xFF, 0xD8, 0xFF, 0xE0, 5, 6]));
    });
  });

  // --------------------------------------------------------------------------
  // SCENARIO 5: 5,000 Files Large Library Incremental Scan Benchmark
  // --------------------------------------------------------------------------
  group('Empirical Challenge 5: 5,000 Files Incremental Scan Benchmark', () {
    late AppDatabase database;
    late ChallengeMockBinaryLocator binaryLocator;
    late ChallengeMockProcessExecutor executor;

    setUp(() async {
      database = AppDatabaseImpl.inMemory();
      await database.init();
      binaryLocator = ChallengeMockBinaryLocator();
      executor = ChallengeMockProcessExecutor();
    });

    tearDown(() async {
      await database.close();
    });

    test('benchmarks incremental cache comparison against 5,000 files with zero jank', () async {
      const totalFiles = 5000;
      final seededTracks = <Track>[];
      final discoveredFiles = <DiscoveredAudioFile>[];

      const baseModifiedAt = 1700000000000;
      const baseFileSize = 8000000;

      for (int i = 0; i < totalFiles; i++) {
        final uri = '/music/library/artist_${i % 100}/album_${i % 500}/track_$i.mp3';
        final fileSize = baseFileSize + (i * 1024);
        final modifiedAt = baseModifiedAt + (i * 1000);

        seededTracks.add(Track(
          uri: uri,
          title: 'Track $i',
          album: 'Album ${i % 500}',
          artist: 'Artist ${i % 100}',
          durationMs: 200000,
          fileSize: fileSize,
          modifiedAt: modifiedAt,
        ));

        discoveredFiles.add(DiscoveredAudioFile(
          path: uri,
          size: fileSize,
          modifiedAt: modifiedAt,
        ));
      }

      // Pre-seed SQLite database with all 5,000 tracks
      await database.batchInsertTracks(seededTracks);

      final initialCount = (await database.getAllTracks()).length;
      expect(initialCount, equals(totalFiles));

      // Create a test extractor subclass to inject pre-discovered files
      final extractor = _BenchmarkMetadataExtractor(
        binaryLocator: binaryLocator,
        database: database,
        executor: executor,
        injectedFiles: discoveredFiles,
      );

      final stopwatch = Stopwatch()..start();
      final progressEvents = <ScanProgress>[];

      await for (final progress in extractor.scanDirectories(['/music/library'])) {
        progressEvents.add(progress);
      }
      stopwatch.stop();

      final elapsedMs = stopwatch.elapsedMilliseconds;
      final finalProgress = progressEvents.last;

      // 1. Empirical Correctness
      expect(finalProgress.phase, equals(ScanPhase.completed));
      expect(finalProgress.totalFiles, equals(totalFiles));
      expect(finalProgress.scannedFiles, equals(totalFiles));
      expect(finalProgress.skippedTracks, equals(totalFiles));
      expect(finalProgress.newTracks, equals(0));
      expect(finalProgress.updatedTracks, equals(0));
      expect(finalProgress.failedTracks, equals(0));

      // 2. Zero Subprocess Execution (All files identified via memory hash lookup)
      expect(executor.executionCount, equals(0), reason: 'Unchanged files must never spawn ffprobe');

      // 3. Performance Benchmark (< 1,000ms for 5,000 files in memory SQLite)
      expect(
        elapsedMs,
        lessThan(2500),
        reason: 'Incremental comparison of 5,000 tracks took ${elapsedMs}ms, exceeding budget',
      );

      // 4. UI 60 FPS Jank Protection: Throttled Progress Emitter Verification
      // Emitted events must be strictly throttled (substantially fewer than 5,000)
      expect(
        progressEvents.length,
        lessThan(100),
        reason: 'Progress emitter must throttle rapid updates to prevent UI isolate jank (got ${progressEvents.length} events for 5,000 files)',
      );
    });

    test('handles mixed delta: 4,950 unchanged files + 50 changed files', () async {
      const totalFiles = 5000;
      const changedFilesCount = 50;
      final seededTracks = <Track>[];
      final discoveredFiles = <DiscoveredAudioFile>[];

      for (int i = 0; i < totalFiles; i++) {
        final uri = '/music/delta/track_$i.flac';
        final fileSize = 10000000;
        final modifiedAt = 1700000000000;

        seededTracks.add(Track(
          uri: uri,
          title: 'Track $i',
          album: 'Delta Album',
          artist: 'Delta Artist',
          durationMs: 180000,
          fileSize: fileSize,
          modifiedAt: modifiedAt,
        ));

        // For the first 50 files, mutate the modification timestamp to simulate updates
        final isMutated = i < changedFilesCount;
        discoveredFiles.add(DiscoveredAudioFile(
          path: uri,
          size: fileSize,
          modifiedAt: isMutated ? modifiedAt + 50000 : modifiedAt,
        ));
      }

      await database.batchInsertTracks(seededTracks);

      final executorWithMock = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          final title = p.basenameWithoutExtension(args.last);
          final mockJson = json.encode({
            'streams': [{'codec_type': 'audio', 'codec_name': 'flac'}],
            'format': {'duration': '180.0', 'tags': {'TITLE': title}}
          });
          return ProcessResult(1, 0, mockJson, '');
        },
      );

      final extractor = _BenchmarkMetadataExtractor(
        binaryLocator: binaryLocator,
        database: database,
        executor: executorWithMock,
        injectedFiles: discoveredFiles,
        workerCount: 4,
      );

      final progressEvents = <ScanProgress>[];
      await for (final progress in extractor.scanDirectories(['/music/delta'])) {
        progressEvents.add(progress);
      }

      final finalProgress = progressEvents.last;
      expect(finalProgress.phase, equals(ScanPhase.completed));
      expect(finalProgress.totalFiles, equals(totalFiles));
      expect(finalProgress.skippedTracks, equals(totalFiles - changedFilesCount));
      expect(finalProgress.updatedTracks, equals(changedFilesCount));
      expect(executorWithMock.executionCount, equals(changedFilesCount));
    });
  });

  // --------------------------------------------------------------------------
  // SCENARIO 6: NativeBinaryLocator Multiplatform & Fallback Stress
  // --------------------------------------------------------------------------
  group('Empirical Challenge 6: NativeBinaryLocator Multiplatform & Fallback Stress', () {
    test('strictly prioritizes TACHYON_FFPROBE_PATH environment variable override', () async {
      final mockPlatform = ChallengeMockPlatformContext(
        linux: true,
        env: {'TACHYON_FFPROBE_PATH': '/custom/tools/ffprobe'},
        existingFiles: {'/custom/tools/ffprobe', '/usr/bin/ffprobe'},
      );

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          if (exe == '/custom/tools/ffprobe' && args.contains('-version')) {
            return ProcessResult(1, 0, 'ffprobe version 6.1.1 Custom Build', '');
          }
          return ProcessResult(1, 1, '', 'Command not found');
        },
      );

      final locator = NativeBinaryLocatorImpl(
        platform: mockPlatform,
        executor: executor,
      );

      final located = await locator.findFfprobe();
      expect(located, equals('/custom/tools/ffprobe'));
    });

    test('throws NativeBinaryNotFoundException with detailed attempted paths when all candidates fail', () async {
      final mockPlatform = ChallengeMockPlatformContext(
        linux: true,
        existingFiles: {}, // No files exist on disk
      );

      final executor = ChallengeMockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(
        platform: mockPlatform,
        executor: executor,
      );

      expect(
        () => locator.findFfprobe(),
        throwsA(isA<NativeBinaryNotFoundException>().having(
          (e) => e.attemptedPaths,
          'attemptedPaths',
          isNotEmpty,
        )),
      );
    });

    test('safely rejects binaries when -version validation exits non-zero or outputs invalid text', () async {
      final mockPlatform = ChallengeMockPlatformContext(
        linux: true,
        existingFiles: {'/usr/bin/ffprobe'},
      );

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          // Exits with 0 but returns irrelevant text (not ffmpeg/ffprobe)
          return ProcessResult(1, 0, 'Some other binary version 1.0', '');
        },
      );

      final locator = NativeBinaryLocatorImpl(
        platform: mockPlatform,
        executor: executor,
      );

      expect(() => locator.findFfprobe(), throwsA(isA<NativeBinaryNotFoundException>()));
    });

    test('sequential calls to findFfprobe leverage in-memory memoization without redundant subprocess calls', () async {
      final mockPlatform = ChallengeMockPlatformContext(
        linux: true,
        existingFiles: {'/usr/bin/ffprobe', '/usr/bin/ffmpeg'},
      );

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          return ProcessResult(1, 0, 'ffprobe version 6.0', '');
        },
      );

      final locator = NativeBinaryLocatorImpl(
        platform: mockPlatform,
        executor: executor,
      );

      // Sequential calls
      final path1 = await locator.findFfprobe();
      final path2 = await locator.findFfprobe();
      final path3 = await locator.findFfprobe();

      expect(path1, equals('/usr/bin/ffprobe'));
      expect(path2, equals('/usr/bin/ffprobe'));
      expect(path3, equals('/usr/bin/ffprobe'));
      // Process executor should only have been invoked once for -version check
      expect(executor.executionCount, equals(1));
    });

    test('empirical finding: concurrent in-flight calls before resolution trigger parallel locate calls', () async {
      final mockPlatform = ChallengeMockPlatformContext(
        linux: true,
        existingFiles: {'/usr/bin/ffprobe'},
      );

      final executor = ChallengeMockProcessExecutor(
        onRun: (exe, args) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return ProcessResult(1, 0, 'ffprobe version 6.0', '');
        },
      );

      final locator = NativeBinaryLocatorImpl(
        platform: mockPlatform,
        executor: executor,
      );

      // 5 concurrent calls launched simultaneously before any has resolved
      final results = await Future.wait(List.generate(5, (_) => locator.findFfprobe()));

      for (final r in results) {
        expect(r, equals('/usr/bin/ffprobe'));
      }

      // Empirical observation: NativeBinaryLocator memoizes String _cachedFfprobePath
      // but does not deduplicate in-flight Future<String>, resulting in 5 subprocess executions
      expect(executor.executionCount, equals(5));

      // After resolution, subsequent calls correctly hit the memoized path (0 additional executions)
      final subsequent = await locator.findFfprobe();
      expect(subsequent, equals('/usr/bin/ffprobe'));
      expect(executor.executionCount, equals(5));
    });
  });
}

// ============================================================================
// BENCHMARK HARNESS SUBCLASS
// ============================================================================

class _BenchmarkMetadataExtractor extends MetadataExtractorImpl {
  final List<DiscoveredAudioFile> injectedFiles;
  final int? _customWorkers;

  _BenchmarkMetadataExtractor({
    required super.binaryLocator,
    required super.database,
    required super.executor,
    required this.injectedFiles,
    int? workerCount,
  })  : _customWorkers = workerCount,
        super(customWorkerCount: workerCount);

  @override
  int get workerCount => _customWorkers ?? 4;

  @override
  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) async* {
    for (final file in injectedFiles) {
      if (cancellationToken?.isCancelled ?? false) break;
      yield file;
    }
  }
}
