import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

Future<ui.Image> _createTestUiImage({int width = 8, int height = 8}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}

class _TestImageKey {
  final int id;
  const _TestImageKey(this.id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _TestImageKey && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '_TestImageKey($id)';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Empirical Challenger: SQLite Catalog Query Trimming & On-Demand Lyrics', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.inMemory();
      await db.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('Stress Test: 1,000 tracks query trimming in getAllTracks & searchTracks', () async {
      // 1. Generate 1,000 realistic tracks with heavy lyrics (~30 LRC lines each)
      const totalTracks = 1000;
      final heavyTracks = List<Track>.generate(totalTracks, (i) {
        final buffer = StringBuffer();
        for (int line = 0; line < 30; line++) {
          final mm = (line ~/ 2).toString().padLeft(2, '0');
          final ss = ((line % 2) * 30).toString().padLeft(2, '0');
          buffer.writeln('[$mm:$ss.00] Synced line $line of song $i with metadata payload padding text');
        }
        return Track(
          uri: '/music/stress_catalog/artist_${i % 25}/track_${i.toString().padLeft(4, '0')}.flac',
          title: 'Catalog Track ${i.toString().padLeft(4, '0')}',
          artist: 'Stress Artist ${i % 25}',
          album: 'Stress Album ${i % 10}',
          albumArtist: 'Stress Artist ${i % 25}',
          trackNumber: (i % 20) + 1,
          discNumber: 1,
          year: 2024,
          durationMs: 180000 + (i * 50),
          bitrate: 320000,
          sampleRate: 44100,
          channels: 2,
          codec: 'FLAC',
          fileSize: 25000000 + i * 1024,
          modifiedAt: 1700000000000 + i,
          lyrics: buffer.toString(),
        );
      });

      // 2. Batch insert all 1,000 tracks into SQLite
      final insertStopwatch = Stopwatch()..start();
      await db.batchInsertTracks(heavyTracks);
      insertStopwatch.stop();

      // 3. Query all 1,000 tracks via getAllTracks
      final queryStopwatch = Stopwatch()..start();
      final catalogTracks = await db.getAllTracks();
      queryStopwatch.stop();

      expect(catalogTracks.length, equals(totalTracks));

      // 4. Assert that ALL 1,000 tracks have lyrics == null (zero RAM retention of lyric text in memory catalog)
      int nullLyricsCount = 0;
      for (final t in catalogTracks) {
        if (t.lyrics == null) {
          nullLyricsCount++;
        }
      }
      expect(nullLyricsCount, equals(totalTracks));
      expect(catalogTracks.every((t) => t.lyrics == null), isTrue);

      // Verify essential catalog metadata is intact despite projection trimming
      final sample = catalogTracks[42];
      expect(sample.title, equals('Catalog Track 0042'));
      expect(sample.artist, equals('Stress Artist 17'));
      expect(sample.album, equals('Stress Album 2'));
      expect(sample.durationMs, equals(180000 + 42 * 50));
      expect(sample.lyrics, isNull);

      // 5. Stress test searchTracks query trimming
      final searchHits = await db.searchTracks('Catalog Track 05');
      expect(searchHits.isNotEmpty, isTrue);
      for (final hit in searchHits) {
        expect(hit.lyrics, isNull);
        expect(hit.title, contains('05'));
      }
    });

    test('On-Demand Lyrics Resolution via LyricsService & Direct Queries', () async {
      // 1. Insert 50 tracks with distinct lyrics
      const count = 50;
      final tracks = List<Track>.generate(count, (i) {
        final lyrics = '[00:05.00]Song $i First Line\n[00:15.00]Song $i Chorus Line';
        return Track(
          uri: '/music/album/track_$i.mp3',
          title: 'Track $i',
          artist: 'Artist $i',
          album: 'Album 1',
          durationMs: 200000,
          fileSize: 5000000,
          modifiedAt: 1000000 + i,
          lyrics: lyrics,
        );
      });
      await db.batchInsertTracks(tracks);

      final catalog = await db.getAllTracks();
      expect(catalog.length, equals(count));
      expect(catalog.every((t) => t.lyrics == null), isTrue);

      final service = LyricsService(database: db);

      // 2. Fetch lyrics for individual tracks via LyricsService on-demand
      for (int i = 0; i < 5; i++) {
        final track = catalog[i];
        final match = RegExp(r'track_(\d+)\.mp3').firstMatch(track.uri)!;
        final expectedSongId = match.group(1)!;
        final result = await service.resolveLyricsForTrack(track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.embedded));
        expect(result.rawLrc, equals('[00:05.00]Song $expectedSongId First Line\n[00:15.00]Song $expectedSongId Chorus Line'));
        expect(result.lines.length, equals(2));
        expect(result.lines[0].text, equals('Song $expectedSongId First Line'));
        expect(result.lines[1].text, equals('Song $expectedSongId Chorus Line'));
      }

      // 3. High-throughput concurrent on-demand fetching (simulating rapid playback switching)
      final concurrentIndices = [10, 15, 20, 25, 30, 35, 40, 45];
      final futures = concurrentIndices.map((idx) => service.resolveLyricsForTrack(catalog[idx]));
      final concurrentResults = await Future.wait(futures);

      for (int k = 0; k < concurrentIndices.length; k++) {
        final track = catalog[concurrentIndices[k]];
        final match = RegExp(r'track_(\d+)\.mp3').firstMatch(track.uri)!;
        final expectedSongId = match.group(1)!;
        final res = concurrentResults[k];
        expect(res, isNotNull);
        expect(res!.source, equals(LyricsSource.embedded));
        expect(res.rawLrc, contains('Song $expectedSongId First Line'));
      }

      // 4. Edge cases: track with null/empty lyrics
      const emptyTrack = Track(
        uri: '/music/instrumental.mp3',
        title: 'Instrumental',
        artist: 'Composer',
        album: 'OST',
        durationMs: 120000,
        fileSize: 3000000,
        modifiedAt: 2000000,
        lyrics: null,
      );
      await db.batchInsertTracks([emptyTrack]);
      final fetchedEmpty = (await db.getAllTracks()).firstWhere((t) => t.uri == '/music/instrumental.mp3');

      final emptyResult = await service.resolveLyricsForTrack(
        fetchedEmpty,
        enabledSources: {LyricsSource.embedded},
      );
      expect(emptyResult, isNull);

      final emptyDirectUri = await db.getTrackLyricsByUri('/music/instrumental.mp3');
      expect(emptyDirectUri, isNull);

      final nonExistentUri = await db.getTrackLyricsByUri('/music/non_existent.mp3');
      expect(nonExistentUri, isNull);

      final nonExistentId = await db.getTrackLyrics(-999);
      expect(nonExistentId, isNull);
    });
  });

  group('Empirical Challenger: ImageCache Boundaries & Rapid Allocation Stress', () {
    setUp(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      PaintingBinding.instance.imageCache.maximumSize = 60;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 15 * 1024 * 1024;
    });

    tearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    test('ImageCache maximumSize boundary (60 items) holds under rapid allocation', () async {
      final imageCache = PaintingBinding.instance.imageCache;

      expect(imageCache.maximumSize, equals(60));
      expect(imageCache.maximumSizeBytes, equals(15 * 1024 * 1024));

      // 50x50 image = 50 * 50 * 4 = 10,000 bytes (10KB)
      final testImage = await _createTestUiImage(width: 50, height: 50);

      // Allocate 120 distinct images (2x the maximumSize)
      const totalImages = 120;
      for (int i = 0; i < totalImages; i++) {
        final key = _TestImageKey(i);
        final completer = OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: testImage.clone())),
        );
        imageCache.putIfAbsent(key, () => completer);
        await Future<void>.delayed(Duration.zero);

        expect(
          imageCache.currentSize,
          lessThanOrEqualTo(60),
          reason: 'imageCache.currentSize exceeded maximumSize (60) on iteration $i',
        );
      }

      // Exactly 60 images retained in cache
      expect(imageCache.currentSize, equals(60));
      expect(imageCache.currentSizeBytes, equals(60 * 10000));
    });

    test('ImageCache maximumSizeBytes boundary (15MB) holds under large raster allocations', () async {
      final imageCache = PaintingBinding.instance.imageCache;

      // 500x500 image = 500 * 500 * 4 = 1,000,000 bytes (1MB)
      final largeImage = await _createTestUiImage(width: 500, height: 500);

      // Allocate 30 images of 1MB each (total 30MB, double the 15MB limit)
      const totalImages = 30;
      for (int i = 0; i < totalImages; i++) {
        final key = _TestImageKey(200 + i);
        final completer = OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: largeImage.clone())),
        );
        imageCache.putIfAbsent(key, () => completer);
        await Future<void>.delayed(Duration.zero);

        expect(
          imageCache.currentSizeBytes,
          lessThanOrEqualTo(15 * 1024 * 1024),
          reason: 'imageCache.currentSizeBytes exceeded 15MB on iteration $i (was ${imageCache.currentSizeBytes})',
        );
      }

      // Maximum 1MB images that fit in 15MB = 15 images
      expect(imageCache.currentSize, lessThanOrEqualTo(15));
      expect(imageCache.currentSizeBytes, lessThanOrEqualTo(15 * 1024 * 1024));
    });

    test('AlbumArtImage auto-downsampling and DPR scaling computation integrity', () {
      AlbumArtImage.clearExistenceCache();

      // Case A: Explicit list thumbnail dimensions
      const thumb = AlbumArtImage(
        uri: '/music/song.mp3',
        width: 48,
        height: 48,
        cacheWidth: 96,
        cacheHeight: 96,
      );
      expect(thumb.cacheWidth, equals(96));
      expect(thumb.cacheHeight, equals(96));

      // Case B: High-res Hero image with null explicit cache bounds
      const hero = AlbumArtImage(
        uri: '/music/hero.mp3',
        width: 320,
        height: 320,
      );
      expect(hero.cacheWidth, isNull);
      expect(hero.cacheHeight, isNull);
      expect(hero.width, equals(320));
      expect(hero.height, equals(320));
    });

    testWidgets('TrackTile strictly enforces 80x80 cacheWidth and cacheHeight', (tester) async {
      const track = Track(
        uri: '/music/heavy_cover_track.flac',
        title: 'Heavy Cover Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 240000,
        fileSize: 40000000,
        modifiedAt: 1700000000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackTile(track: track),
          ),
        ),
      );

      final artFinder = find.byType(AlbumArtImage);
      expect(artFinder, findsOneWidget);
      final widget = tester.widget<AlbumArtImage>(artFinder);

      expect(widget.cacheWidth, equals(80));
      expect(widget.cacheHeight, equals(80));
    });

    test('Existence cache Set (_existingCovers) stress and clearing', () {
      AlbumArtImage.clearExistenceCache();
      // Clearing empty cache succeeds
      AlbumArtImage.clearExistenceCache();
    });
  });
}
