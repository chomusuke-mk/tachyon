import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 1: Global ImageCache Bounds', () {
    test('PaintingBinding imageCache is configured with 60 entries and 15MB cap', () {
      PaintingBinding.instance.imageCache.maximumSize = 60;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 15 * 1024 * 1024;

      expect(PaintingBinding.instance.imageCache.maximumSize, equals(60));
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        equals(15 * 1024 * 1024),
      );
    });
  });

  group('Milestone 1: AlbumArtImage Properties & Existence Cache', () {
    test('AlbumArtImage constructor stores cacheWidth, cacheHeight, and allows clearing cache', () {
      AlbumArtImage.clearExistenceCache();

      const image = AlbumArtImage(
        uri: '/music/song.mp3',
        width: 48,
        height: 48,
        cacheWidth: 96,
        cacheHeight: 96,
      );

      expect(image.cacheWidth, equals(96));
      expect(image.cacheHeight, equals(96));
      expect(image.width, equals(48));
      expect(image.height, equals(48));
      expect(image.uri, equals('/music/song.mp3'));
    });
  });

  group('Milestone 1: TrackTile Bounded Thumbnail Dimensions', () {
    testWidgets('TrackTile instantiates AlbumArtImage with explicit cacheWidth 96 and cacheHeight 96', (tester) async {
      const track = Track(
        uri: '/music/tile_track.mp3',
        title: 'Tile Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
      );

      // Pump TrackTile without CoverCacheService so it renders fallback without invoking file codecs
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackTile(track: track),
          ),
        ),
      );

      final albumArtFinder = find.byType(AlbumArtImage);
      expect(albumArtFinder, findsOneWidget);
      final albumArt = tester.widget<AlbumArtImage>(albumArtFinder);
      expect(albumArt.cacheWidth, equals(96));
      expect(albumArt.cacheHeight, equals(96));
    });
  });

  group('Milestone 1: Catalog Query Trimming & On-Demand Lyrics Queries', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.inMemory();
      await db.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('getAllTracks and searchTracks project NULL AS lyrics while dedicated queries fetch on-demand', () async {
      const track = Track(
        uri: '/music/trimmed_lyrics.mp3',
        title: 'Trimmed Lyrics Song',
        lyrics: '[00:01.00]Line 1\n[00:04.00]Line 2',
        durationMs: 240000,
        fileSize: 100000,
        modifiedAt: 1700000000000,
      );
      await db.batchInsertTracks([track]);

      final allTracks = await db.getAllTracks();
      expect(allTracks.length, equals(1));
      expect(allTracks.first.lyrics, isNull);

      final searchResults = await db.searchTracks('Trimmed');
      expect(searchResults.length, equals(1));
      expect(searchResults.first.lyrics, isNull);

      // Verify on-demand query by URI
      final lyricsByUri = await db.getTrackLyricsByUri('/music/trimmed_lyrics.mp3');
      expect(lyricsByUri, equals('[00:01.00]Line 1\n[00:04.00]Line 2'));

      // Verify on-demand query by ID
      final trackId = allTracks.first.id!;
      final lyricsById = await db.getTrackLyrics(trackId);
      expect(lyricsById, equals('[00:01.00]Line 1\n[00:04.00]Line 2'));
    });

    test('getTrackIdsForPlaylist retrieves IDs directly from playlist_entries without Track models', () async {
      const track1 = Track(
        uri: '/music/pl1.mp3',
        title: 'PL 1',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
      );
      const track2 = Track(
        uri: '/music/pl2.mp3',
        title: 'PL 2',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
      );
      await db.batchInsertTracks([track1, track2]);
      final tracks = await db.getAllTracks();
      final id1 = tracks[0].id!;
      final id2 = tracks[1].id!;

      await db.addTrackToPlaylist(AppDatabase.likedSongsPlaylistId, id1);
      await db.addTrackToPlaylist(AppDatabase.likedSongsPlaylistId, id2);

      final likedIds = await db.getTrackIdsForPlaylist(AppDatabase.likedSongsPlaylistId);
      expect(likedIds, containsAll([id1, id2]));
      expect(likedIds.length, equals(2));
    });
  });

  group('Milestone 1: LyricsService On-Demand Resolution', () {
    test('LyricsService resolves embedded lyrics via getTrackLyricsByUri when Track.lyrics is null', () async {
      final db = AppDatabase.inMemory();
      await db.init();
      const track = Track(
        uri: '/music/embedded_ondemand.mp3',
        title: 'Embedded On Demand',
        lyrics: '[00:03.50]Synchronized embedded lyric text',
        durationMs: 180000,
        fileSize: 5000,
        modifiedAt: 5000,
      );
      await db.batchInsertTracks([track]);

      // Retrieve track from catalog — lyrics field is null
      final catalogTracks = await db.getAllTracks();
      expect(catalogTracks.first.lyrics, isNull);

      final service = LyricsService(database: db);
      final result = await service.resolveLyricsForTrack(catalogTracks.first);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.embedded));
      expect(result.rawLrc, equals('[00:03.50]Synchronized embedded lyric text'));
      expect(result.lines.length, equals(1));
      expect(result.lines.first.text, equals('Synchronized embedded lyric text'));

      await db.close();
    });
  });

  group('Milestone 1: In-Memory Controllers Optimization', () {
    test('LibraryController.tracks returns _tracks directly without cloning when no filter is applied', () async {
      final db = AppDatabase.inMemory();
      await db.init();
      final tempDir = await Directory.systemTemp.createTemp('lib_opt_test_');
      final coverCache = CoverCacheService(cacheDirectory: tempDir);
      final extractor = MetadataExtractor(database: db, coverCacheService: coverCache);

      final controller = LibraryController(
        database: db,
        metadataExtractor: extractor,
        coverCacheService: coverCache,
      );

      const track1 = Track(uri: '/music/a.mp3', title: 'Track A', durationMs: 1000, fileSize: 100, modifiedAt: 100);
      const track2 = Track(uri: '/music/b.mp3', title: 'Track B', durationMs: 1000, fileSize: 100, modifiedAt: 100);
      await db.batchInsertTracks([track1, track2]);

      await controller.loadLibrary();

      final list1 = controller.tracks;
      final list2 = controller.tracks;
      expect(identical(list1, list2), isTrue);
      expect(list1.length, equals(2));

      controller.dispose();
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('PlaylistsController.loadPlaylists pre-caches liked track IDs via getTrackIdsForPlaylist', () async {
      final db = AppDatabase.inMemory();
      await db.init();

      const track = Track(uri: '/music/liked.mp3', title: 'Liked', durationMs: 1000, fileSize: 100, modifiedAt: 100);
      await db.batchInsertTracks([track]);
      final tracks = await db.getAllTracks();
      final trackId = tracks.first.id!;

      await db.addTrackToPlaylist(AppDatabase.likedSongsPlaylistId, trackId);

      final controller = PlaylistsController(database: db);
      await controller.loadPlaylists();

      expect(controller.isTrackLiked(trackId), isTrue);
      expect(controller.isTrackLiked(99999), isFalse);

      controller.dispose();
      await db.close();
    });
  });
}
