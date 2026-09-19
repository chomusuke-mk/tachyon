import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late LyricsServiceImpl service;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabaseImpl.inMemory();
    await db.init();
    service = LyricsServiceImpl(database: db);
    tempDir = await Directory.systemTemp.createTemp('tachyon_lyrics_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LyricsService 3-Tier Resolution', () {
    test('Tier 1: Embedded lyrics take priority and are cached into SQLite', () async {
      const track = Track(
        id: 1,
        uri: '/music/song.mp3',
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 1600000000,
        lyrics: '[00:01.00]Embedded Lyric Line',
      );

      final result = await service.getLyricsForTrack(track);

      expect(result, isNotNull);
      expect(result!.lines.length, equals(1));
      expect(result.lines.first.text, equals('Embedded Lyric Line'));

      // Verify Tier 3 cache was populated
      final keyHash = LyricsServiceImpl.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final cachedLrc = await db.getLyrics(keyHash);
      expect(cachedLrc, equals(track.lyrics));
    });

    test('Tier 2: External .lrc file in directory is discovered when embedded is null', () async {
      final audioFile = File(p.join(tempDir.path, 'track_audio.mp3'));
      await audioFile.writeAsString('dummy mp3 content');

      final lrcFile = File(p.join(tempDir.path, 'track_audio.lrc'));
      await lrcFile.writeAsString('[00:05.00]External Directory Lyric');

      final track = Track(
        id: 2,
        uri: audioFile.path,
        title: 'Track Audio',
        artist: 'Band',
        durationMs: 200000,
        fileSize: 4000000,
        modifiedAt: 1600000001,
        lyrics: null, // No embedded lyrics
      );

      final result = await service.getLyricsForTrack(track);

      expect(result, isNotNull);
      expect(result!.lines.length, equals(1));
      expect(result.lines.first.text, equals('External Directory Lyric'));

      // Verify cached in database
      final keyHash = LyricsServiceImpl.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final cachedLrc = await db.getLyrics(keyHash);
      expect(cachedLrc, contains('External Directory Lyric'));
    });

    test('Tier 3: Local SQLite database cache is utilized when embedded and file are absent', () async {
      const track = Track(
        id: 3,
        uri: '/remote/streaming_song.mp3',
        title: 'Cached Song',
        artist: 'Singer',
        durationMs: 150000,
        fileSize: 3000000,
        modifiedAt: 1600000002,
        lyrics: null,
      );

      final keyHash = LyricsServiceImpl.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );

      // Pre-populate SQLite database cache
      await db.saveLyrics(keyHash, '[00:10.00]Cached from SQLite', 'db_seed');

      final result = await service.getLyricsForTrack(track);

      expect(result, isNotNull);
      expect(result!.lines.length, equals(1));
      expect(result.lines.first.text, equals('Cached from SQLite'));
    });

    test('in-memory LRU cache returns result without querying database on repeated call', () async {
      const track = Track(
        id: 5,
        uri: '/music/memory_cached.mp3',
        title: 'Memory Song',
        artist: 'Memory Artist',
        durationMs: 120000,
        fileSize: 1000000,
        modifiedAt: 1600000005,
        lyrics: '[00:02.00]Memory Lyric',
      );

      // First fetch caches in memory
      final res1 = await service.getLyricsForTrack(track);
      expect(res1, isNotNull);

      // Second fetch returns from memory
      final res2 = await service.getLyricsForTrack(track);
      expect(identical(res1, res2), isTrue);

      // Clearing memory cache forces re-parse
      service.clearMemoryCache();
      final res3 = await service.getLyricsForTrack(track);
      expect(res3, isNotNull);
    });

    test('QueueItem resolution works identically via getLyricsForQueueItem', () async {
      final item = QueueItem(
        id: 'item_1',
        uri: '/music/queue_song.mp3',
        title: 'Queue Song',
        artist: 'Queue Artist',
        album: 'Queue Album',
        duration: const Duration(seconds: 180),
        extras: {'lyrics': '[00:03.00]Queue Lyric'},
      );

      final result = await service.getLyricsForQueueItem(item);
      expect(result, isNotNull);
      expect(result!.lines.first.text, equals('Queue Lyric'));
    });

    test('returns null gracefully when lyrics are absent in all 3 tiers', () async {
      const track = Track(
        id: 4,
        uri: '/non/existent/path/instrumental.mp3',
        title: 'Instrumental',
        artist: 'Composer',
        durationMs: 300000,
        fileSize: 8000000,
        modifiedAt: 1600000003,
      );

      final result = await service.getLyricsForTrack(track);
      expect(result, isNull);
    });
  });
}
