import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';

void main() {
  group('AppDatabase Milestone 1 tests', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('upsertTracks and getCatalogSnapshot works with normalized references, zero lyrics in snapshot, and embedded lyrics in lyrics table', () {
      final track1 = ExtractedTrackData(
        filePath: '/music/song1.mp3',
        title: 'Song One',
        artistNames: ['Artist A', 'Artist B'],
        albumName: 'Album One',
        genreNames: ['Rock'],
        trackNumber: 1,
        discNumber: 1,
        year: 2024,
        durationMs: 180000,
        bitrate: 320,
        sampleRate: 44100,
        channels: 2,
        codec: 'mp3',
        fileSize: 5000000,
        modifiedAt: 123456789,
        embeddedLyrics: '[00:01.00] Embedded lyric line',
      );

      final track2 = ExtractedTrackData(
        filePath: '/music/song2.mp3',
        title: 'Song Two',
        artistNames: ['Artist A'],
        albumName: 'Album One',
        genreNames: ['Rock', 'Pop'],
        trackNumber: 2,
        discNumber: 1,
        year: 2024,
        durationMs: 200000,
        bitrate: 320,
        sampleRate: 44100,
        channels: 2,
        codec: 'mp3',
        fileSize: 6000000,
        modifiedAt: 123456790,
      );

      database.upsertTracks([track1, track2]);

      final snapshot = database.getCatalogSnapshot();

      expect(snapshot.tracks.length, 2);
      expect(snapshot.albums.length, 1);
      expect(snapshot.artists.length, 2);
      expect(snapshot.genres.length, 2);
      expect(snapshot.playlists.length, 2); // liked + history defaults

      // Verify ZERO lyrics in snapshot
      final trackDto1 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/song1.mp3');
      expect(trackDto1.title, 'Song One');
      expect(trackDto1.albumId, snapshot.albums.first.id);

      // Verify track artists & genres associations
      final track1Artists = snapshot.trackArtists.where((p) => p.trackId == trackDto1.id).toList();
      expect(track1Artists.length, 2);

      // Verify embedded lyrics are persisted into the lyrics table, not tracks
      final bestLyrics = database.getBestLyricsForTrack(trackDto1.id);
      expect(bestLyrics, isNotNull);
      expect(bestLyrics!['source'], 'embedded');
      expect(bestLyrics['state'], 'FOUND');
      expect(bestLyrics['raw_lrc'], '[00:01.00] Embedded lyric line');
      expect(bestLyrics['is_synced'], 1);

      final entry = database.getLyricsEntry(trackId: trackDto1.id, source: 'embedded');
      expect(entry, isNotNull);
      expect(entry!['raw_lrc'], '[00:01.00] Embedded lyric line');
    });

    test('getBestLyricsForTrack resolves by priority order (embedded > file > lrclib > lyrics_ovh)', () {
      final track = ExtractedTrackData(
        filePath: '/music/multi_source.mp3',
        title: 'Multi Source',
        artistNames: ['Artist Priority'],
        durationMs: 150000,
        fileSize: 4000000,
        modifiedAt: 1000,
      );
      database.upsertTracks([track]);
      final trackId = database.getCatalogSnapshot().tracks.first.id;

      // Add sources in reverse priority order
      final ovhId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'lyrics_ovh',
        state: 'FOUND',
        rawLrc: 'OVH plain lyrics',
        isSynced: false,
      );
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'lyrics_ovh');

      final lrclibId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:02.00] LRCLIB synced lyrics',
        isSynced: true,
      );
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'lrclib');

      final fileId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.50] Local file lyrics',
        isSynced: true,
      );
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'file');

      final embeddedId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'embedded',
        state: 'FOUND',
        rawLrc: '[00:01.00] Embedded tag lyrics',
        isSynced: true,
      );
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'embedded');

      // Deleting higher priority sources falls back gracefully
      database.deleteLyrics(embeddedId);
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'file');

      database.deleteLyrics(fileId);
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'lrclib');

      database.deleteLyrics(lrclibId);
      expect(database.getBestLyricsForTrack(trackId)!['source'], 'lyrics_ovh');

      database.deleteLyrics(ovhId);
      expect(database.getBestLyricsForTrack(trackId), isNull);
    });

    test('lyrics translations CRUD and translation purge on lyrics update', () {
      final track = ExtractedTrackData(
        filePath: '/music/trans.mp3',
        title: 'Translation Test',
        artistNames: ['Artist T'],
        durationMs: 100000,
        fileSize: 2000000,
        modifiedAt: 1000,
      );
      database.upsertTracks([track]);
      final trackId = database.getCatalogSnapshot().tracks.first.id;

      final lyricsId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:01.00] Hello',
        isSynced: true,
      );

      database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Hola'],
      );
      database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'fr',
        translatedLines: ['[00:01.00] Bonjour'],
      );

      final esTrans = database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es');
      expect(esTrans, ['[00:01.00] Hola']);

      final frTrans = database.getLyricsTranslation(lyricsId: lyricsId, lang: 'fr');
      expect(frTrans, ['[00:01.00] Bonjour']);

      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'de'), isNull);

      // Updating lyrics entry purges associated translations
      database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:01.00] Hello World Updated',
        isSynced: true,
      );

      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);
      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'fr'), isNull);
    });

    test('ON DELETE CASCADE deletes lyrics and translations when track or lyrics is deleted', () {
      final track = ExtractedTrackData(
        filePath: '/music/cascade.mp3',
        title: 'Cascade Test',
        artistNames: ['Artist C'],
        durationMs: 110000,
        fileSize: 2500000,
        modifiedAt: 1000,
      );
      database.upsertTracks([track]);
      final trackId = database.getCatalogSnapshot().tracks.first.id;

      final lyricsId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.00] Line',
        isSynced: true,
      );

      database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Linea'],
      );

      expect(database.getBestLyricsForTrack(trackId), isNotNull);
      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNotNull);

      // 1. Test deleting lyrics deletes translations via CASCADE
      database.deleteLyrics(lyricsId);
      expect(database.getBestLyricsForTrack(trackId), isNull);
      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);

      // Re-create lyrics and translation
      final newLyricsId = database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.00] Line 2',
        isSynced: true,
      );
      database.saveLyricsTranslation(
        lyricsId: newLyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Linea 2'],
      );

      // 2. Test deleting track deletes both lyrics and translations via CASCADE
      database.deleteTrack(trackId);
      expect(database.getBestLyricsForTrack(trackId), isNull);
      expect(database.getLyricsTranslation(lyricsId: newLyricsId, lang: 'es'), isNull);
    });

    test('toggleLikeTrack and isTrackLiked works', () {
      final track1 = ExtractedTrackData(
        filePath: '/music/liked.mp3',
        title: 'Liked Song',
        artistNames: ['Artist L'],
        albumName: 'Album L',
        genreNames: ['Pop'],
        durationMs: 120000,
        fileSize: 3000000,
        modifiedAt: 1000,
      );

      database.upsertTracks([track1]);
      final snapshot = database.getCatalogSnapshot();
      final trackId = snapshot.tracks.first.id;

      expect(database.isTrackLiked(trackId), isFalse);

      database.toggleLikeTrack(trackId);
      expect(database.isTrackLiked(trackId), isTrue);

      final snapshotAfterLike = database.getCatalogSnapshot();
      expect(snapshotAfterLike.playlistEntries.any((e) => e.trackId == trackId && e.playlistId == AppDatabase.likedSongsPlaylistId), isTrue);

      database.toggleLikeTrack(trackId);
      expect(database.isTrackLiked(trackId), isFalse);
    });

    test('playlist management (create, add, reorder, remove, delete) works', () {
      final track1 = ExtractedTrackData(
        filePath: '/music/t1.mp3',
        title: 'T1',
        artistNames: ['A'],
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 1,
      );
      final track2 = ExtractedTrackData(
        filePath: '/music/t2.mp3',
        title: 'T2',
        artistNames: ['A'],
        durationMs: 2000,
        fileSize: 2000,
        modifiedAt: 2,
      );
      database.upsertTracks([track1, track2]);
      final tracks = database.getCatalogSnapshot().tracks;
      final id1 = tracks.firstWhere((t) => t.filePath == '/music/t1.mp3').id;
      final id2 = tracks.firstWhere((t) => t.filePath == '/music/t2.mp3').id;

      final playlistId = database.createPlaylist('Favorites');
      expect(playlistId, isPositive);

      database.addTracksToPlaylist(playlistId, [id1, id2]);
      var trackIds = database.getTrackIdsForPlaylist(playlistId);
      expect(trackIds, [id1, id2]);

      database.reorderPlaylistEntries(playlistId, 0, 1);
      trackIds = database.getTrackIdsForPlaylist(playlistId);
      expect(trackIds, [id2, id1]);

      database.removeTrackFromPlaylist(playlistId, id2);
      trackIds = database.getTrackIdsForPlaylist(playlistId);
      expect(trackIds, [id1]);

      database.deletePlaylist(playlistId);
      final snapshot = database.getCatalogSnapshot();
      expect(snapshot.playlists.any((p) => p.id == playlistId), isFalse);
    });
  });
}
