import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/process_executor.dart';

class MockProcessExecutor implements ProcessExecutor {
  final Future<ProcessResult> Function(String executable, List<String> arguments)? onRun;
  final List<(String, List<String>)> calls = [];

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
    calls.add((executable, arguments));
    if (onRun != null) {
      return onRun!(executable, arguments);
    }
    return ProcessResult(1, 0, '', '');
  }
}

void main() {
  late Directory tempDir;
  late Directory cacheDir;
  late CoverCacheServiceImpl service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_cover_test_');
    cacheDir = Directory(p.join(tempDir.path, 'cache'));
    await cacheDir.create(recursive: true);
    service = CoverCacheServiceImpl(cacheDirectory: cacheDir);
    await service.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CoverCacheService - Hashing & Paths', () {
    test('computes deterministic SHA-256 hash', () {
      const path1 = '/home/user/music/song.mp3';
      final expectedHash = sha256.convert(utf8.encode(path1)).toString();

      expect(service.computeHash(path1), equals(expectedHash));
      expect(service.computeHash(path1).length, equals(64));
      expect(
        service.getCoverFile(path1).path,
        equals(p.join(cacheDir.path, 'covers', '$expectedHash.jpg')),
      );
    });

    test('detects cached cover existence', () async {
      const songPath = '/music/album/track01.flac';
      expect(service.hasCachedCover(songPath), isFalse);

      final coverFile = service.getCoverFile(songPath);
      await coverFile.parent.create(recursive: true);
      await coverFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG magic bytes

      expect(service.hasCachedCover(songPath), isTrue);
    });
  });

  group('CoverCacheService - Directory Artwork Fallback', () {
    test('finds directory cover art case-insensitively', () async {
      final albumDir = Directory(p.join(tempDir.path, 'MyAlbum'));
      await albumDir.create(recursive: true);

      final songFile = File(p.join(albumDir.path, 'song.mp3'));
      await songFile.writeAsString('dummy audio');

      // 1. No art initially
      expect(service.findDirectoryCoverArt(songFile.path), isNull);

      // 2. Add Cover.JPG (mixed case)
      final artFile = File(p.join(albumDir.path, 'Cover.JPG'));
      await artFile.writeAsBytes([1, 2, 3, 4]);

      final found = service.findDirectoryCoverArt(songFile.path);
      expect(found, isNotNull);
      expect(found!.path, equals(artFile.path));
    });

    test('extractAndCacheCover copies directory art to cache when attached_pic is false', () async {
      final albumDir = Directory(p.join(tempDir.path, 'ArtistAlbum'));
      await albumDir.create(recursive: true);

      final songFile = File(p.join(albumDir.path, '01.flac'));
      await songFile.writeAsString('dummy flac');

      final folderImg = File(p.join(albumDir.path, 'folder.jpg'));
      await folderImg.writeAsBytes([10, 20, 30, 40]);

      final cached = await service.extractAndCacheCover(
        songFile.path,
        hasAttachedPic: false,
      );

      expect(cached, isNotNull);
      expect(await cached!.exists(), isTrue);
      expect(await cached.readAsBytes(), equals([10, 20, 30, 40]));
      expect(service.hasCachedCover(songFile.path), isTrue);
    });
  });

  group('CoverCacheService - Process Execution & Attached Pic Extraction', () {
    test('invokes ffmpeg with -an -vcodec copy for attached pic', () async {
      final executor = MockProcessExecutor(
        onRun: (exe, args) async {
          // Simulate writing the output file
          final outPath = args.last;
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
          return ProcessResult(1, 0, '', '');
        },
      );

      final customService = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
        ffmpegBinaryPath: '/usr/bin/ffmpeg',
        executor: executor,
      );

      final songPath = p.join(tempDir.path, 'song_with_pic.mp3');
      final resultFile = await customService.extractAndCacheCover(
        songPath,
        hasAttachedPic: true,
      );

      expect(resultFile, isNotNull);
      expect(await resultFile!.exists(), isTrue);
      expect(executor.calls.length, equals(1));
      expect(executor.calls.first.$1, equals('/usr/bin/ffmpeg'));
      expect(executor.calls.first.$2, contains('-vcodec'));
      expect(executor.calls.first.$2, contains('copy'));
    });

    test('cleans up failed/empty output and falls back to directory art', () async {
      final albumDir = Directory(p.join(tempDir.path, 'FailedExtractionAlbum'));
      await albumDir.create(recursive: true);

      final songFile = File(p.join(albumDir.path, 'broken_stream.mp3'));
      await songFile.writeAsString('audio');

      final fallbackCover = File(p.join(albumDir.path, 'front.png'));
      await fallbackCover.writeAsBytes([9, 8, 7]);

      final executor = MockProcessExecutor(
        onRun: (exe, args) async {
          // Create empty 0-byte file and fail with non-zero exitCode
          final outPath = args.last;
          final outFile = File(outPath);
          await outFile.writeAsBytes([]);
          return ProcessResult(1, 1, '', 'Demux error');
        },
      );

      final customService = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
        executor: executor,
      );

      final cached = await customService.extractAndCacheCover(
        songFile.path,
        hasAttachedPic: true,
      );

      // Should fall back to front.png
      expect(cached, isNotNull);
      expect(await cached!.readAsBytes(), equals([9, 8, 7]));
    });

    test('cache hit returns immediately without invoking executor', () async {
      final executor = MockProcessExecutor();
      final customService = CoverCacheServiceImpl(
        cacheDirectory: cacheDir,
        executor: executor,
      );

      final songPath = '/music/fast_cache_hit.mp3';
      final coverFile = customService.getCoverFile(songPath);
      await coverFile.parent.create(recursive: true);
      await coverFile.writeAsBytes([1, 2, 3]);

      final res = await customService.extractAndCacheCover(songPath, hasAttachedPic: true);
      expect(res, isNotNull);
      expect(executor.calls, isEmpty);
    });
  });

  group('CoverCacheService - Database Status Synchronization & Cache Cleanup', () {
    test('updates has_cover column in SQLite database', () async {
      final db = AppDatabaseImpl.inMemory();
      await db.init();

      // Insert dummy track
      await db.database.insert('tracks', {
        'uri': '/music/track.mp3',
        'title': 'Test Title',
        'duration_ms': 120000,
        'file_size': 1000,
        'modified_at': 1000,
        'has_cover': 0,
      });

      var rows = await db.database.query('tracks', where: 'uri = ?', whereArgs: ['/music/track.mp3']);
      expect(rows.first['has_cover'], equals(0));

      // Update via service
      await service.updateTrackCoverStatus(db, '/music/track.mp3', true);

      rows = await db.database.query('tracks', where: 'uri = ?', whereArgs: ['/music/track.mp3']);
      expect(rows.first['has_cover'], equals(1));

      await db.close();
    });

    test('clearCache removes all cached covers', () async {
      final f1 = service.getCoverFile('/song1.mp3');
      final f2 = service.getCoverFile('/song2.mp3');
      await f1.parent.create(recursive: true);
      await f1.writeAsBytes([1]);
      await f2.writeAsBytes([2]);

      expect(await f1.exists(), isTrue);
      expect(await f2.exists(), isTrue);

      await service.clearCache();

      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isFalse);
      expect(await service.getCoverFile('/any.mp3').parent.exists(), isTrue);
    });
  });
}
