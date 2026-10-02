import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/features/library/domain/track.dart';

File createTestWavFile(String path) {
  const sampleRate = 44100;
  const numChannels = 1;
  const bitsPerSample = 16;
  const numSamples = sampleRate ~/ 10; // 100ms
  final subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
  final chunkSize = 36 + subChunk2Size;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  const blockAlign = numChannels * (bitsPerSample ~/ 8);

  final byteData = ByteData(44 + subChunk2Size);
  byteData.setUint8(0, 0x52);
  byteData.setUint8(1, 0x49);
  byteData.setUint8(2, 0x46);
  byteData.setUint8(3, 0x46);
  byteData.setUint32(4, chunkSize, Endian.little);
  byteData.setUint8(8, 0x57);
  byteData.setUint8(9, 0x41);
  byteData.setUint8(10, 0x56);
  byteData.setUint8(11, 0x45);
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
  byteData.setUint8(36, 0x64);
  byteData.setUint8(37, 0x61);
  byteData.setUint8(38, 0x74);
  byteData.setUint8(39, 0x61);
  byteData.setUint32(40, subChunk2Size, Endian.little);

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempCacheDir;
  late Directory tempMusicDir;
  late AppDatabase db;
  late CoverCacheService coverCache;
  late MetadataService metadataService;

  setUp(() async {
    tempCacheDir = await Directory.systemTemp.createTemp('metadata_cache_test_');
    tempMusicDir = await Directory.systemTemp.createTemp('metadata_music_test_');
    db = AppDatabase.inMemory();
    await db.init();

    coverCache = CoverCacheService(cacheDirectory: tempCacheDir);
    await coverCache.init();

    metadataService = MetadataService(
      database: db,
      coverCacheService: coverCache,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempCacheDir.exists()) {
      await tempCacheDir.delete(recursive: true);
    }
    if (await tempMusicDir.exists()) {
      await tempMusicDir.delete(recursive: true);
    }
  });

  group('MetadataService: Cache-First and Worker Isolate Orchestration', () {
    test('getMetadata returns cached track from SQLite without invoking worker', () async {
      final trackPath = p.join(tempMusicDir.path, 'cached_track.mp3');
      final cachedTrack = Track(
        filePath: trackPath,
        title: 'Cached Song',
        artist: 'Cached Artist',
        album: 'Cached Album',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 123456789,
      );

      // 1. Insert directly into SQLite DB
      await db.insertTrack(cachedTrack);

      // 2. Request through MetadataService
      final result = await metadataService.getMetadata(cachedTrack.filePath);

      expect(result, isNotNull);
      expect(result!.title, equals('Cached Song'));
      expect(result.artist, equals('Cached Artist'));
      expect(result.album, equals('Cached Album'));
    });

    test('getThumbnail returns disk path immediately when already cached on disk', () async {
      final trackPath = p.join(tempMusicDir.path, 'pre_cached_art.mp3');
      final hash = coverCache.computeHash(trackPath);

      // Manually create the LQ and HQ cover files in cache directory
      final coversDir = Directory(p.join(tempCacheDir.path, 'covers'));
      await coversDir.create(recursive: true);

      final lqFile = File(p.join(coversDir.path, '${hash}_lq.jpg'));
      final hqFile = File(p.join(coversDir.path, '${hash}_hq.jpg'));
      await lqFile.writeAsString('dummy_lq_bytes');
      await hqFile.writeAsString('dummy_hq_bytes');

      // Request LQ thumbnail
      final lqPath = await metadataService.getThumbnail(trackPath, isHighQuality: false);
      expect(lqPath, equals(lqFile.path));

      // Request HQ thumbnail
      final hqPath = await metadataService.getThumbnail(trackPath, isHighQuality: true);
      expect(hqPath, equals(hqFile.path));
    });

    test('getThumbnail delegates to worker isolate, performs square center-crop, saves to disk and returns string path', () async {
      final trackPath = p.join(tempMusicDir.path, 'test_song.mp3');
      final dummyAudioFile = File(trackPath);
      await dummyAudioFile.writeAsString('ID3_DUMMY_CONTENT');

      // Create a rectangular folder cover (600x300) in the music directory
      final rectangularImage = img.Image(width: 600, height: 300);
      img.fill(rectangularImage, color: img.ColorRgb8(0, 128, 255));
      final jpgBytes = img.encodeJpg(rectangularImage);

      final folderCover = File(p.join(tempMusicDir.path, 'cover.jpg'));
      await folderCover.writeAsBytes(jpgBytes);

      // Ensure cache is initially empty
      expect(coverCache.hasCachedCover(trackPath), isFalse);

      // Invoke getThumbnail (triggers Isolate.run)
      final generatedLqPath = await metadataService.getThumbnail(trackPath, isHighQuality: false);

      expect(generatedLqPath, isNotNull);
      expect(generatedLqPath, isA<String>()); // Returns ONLY String paths, NO bytes!
      expect(File(generatedLqPath!).existsSync(), isTrue);

      // Verify the generated LQ image on disk is exactly 80x80 square
      final lqDecoded = img.decodeImage(await File(generatedLqPath).readAsBytes());
      expect(lqDecoded, isNotNull);
      expect(lqDecoded!.width, equals(80));
      expect(lqDecoded.height, equals(80));

      // Request HQ thumbnail
      final generatedHqPath = await metadataService.getThumbnail(trackPath, isHighQuality: true);
      expect(generatedHqPath, isNotNull);
      expect(File(generatedHqPath!).existsSync(), isTrue);

      // Original minDim was 300 (min(600, 300) = 300 <= 500), so HQ is 300x300 square without distortion
      final hqDecoded = img.decodeImage(await File(generatedHqPath).readAsBytes());
      expect(hqDecoded, isNotNull);
      expect(hqDecoded!.width, equals(300));
      expect(hqDecoded.height, equals(300));
    });

    test('MetadataExtractor typedef is fully interchangeable with MetadataService', () {
      expect(metadataService, isA<MetadataExtractor>());
      final MetadataExtractor alias = metadataService;
      expect(alias.workerCount, isPositive);
    });

    test('extractMetadata runs in worker isolate via Isolate.run and returns Track', () async {
      final audioPath = p.join(tempMusicDir.path, 'song_extract.wav');
      createTestWavFile(audioPath);

      final track = await metadataService.extractMetadata(audioPath);
      expect(track, isNotNull);
      expect(track!.filePath, equals(audioPath));
      expect(track.title, equals('song_extract')); // Falls back to basename without extension
      expect(track.fileSize, isPositive);

      // Verify extractMetadata does NOT automatically insert into DB (pure extraction)
      final inDb = await db.getTrackByFilePath(audioPath);
      expect(inDb, isNull);
    });

    test('getMetadata on cache miss runs worker isolate via Isolate.run and persists to SQLite', () async {
      final audioPath = p.join(tempMusicDir.path, 'song_cache_miss.wav');
      createTestWavFile(audioPath);

      // Verify not yet in DB
      expect(await db.getTrackByFilePath(audioPath), isNull);

      final track = await metadataService.getMetadata(audioPath);
      expect(track, isNotNull);
      expect(track!.filePath, equals(audioPath));
      expect(track.title, equals('song_cache_miss'));

      // Verify now persisted in DB
      final inDb = await db.getTrackByFilePath(audioPath);
      expect(inDb, isNotNull);
      expect(inDb!.filePath, equals(audioPath));
      expect(inDb.title, equals('song_cache_miss'));
    });

    test('scanDirectories spawns scan isolate via Isolate.spawn and reports progress', () async {
      final audioPath = p.join(tempMusicDir.path, 'song_in_dir.wav');
      createTestWavFile(audioPath);

      final progressEvents = await metadataService
          .scanDirectories([tempMusicDir.path])
          .toList();

      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last.phase.name, equals('completed'));
    });
  });
}
