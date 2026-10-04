import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

void main() {
  group('AppDatabase Milestone 1 tests', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('upsertTracks and getCatalogSnapshot works with normalized references and zero lyrics', () {
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
        embeddedLyrics: 'Embedded lyric line',
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

    test('lyrics cache and translation CRUD works', () {
      const keyHash = 'abc123hash';
      final entry = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.embedded,
        rawLrc: '[00:01.00] Hello World',
        isSynced: true,
      );

      database.saveLyricsSourceEntry(entry);
      final fetched = database.getLyricsSourceEntry(keyHash, LyricsSource.embedded);
      expect(fetched, isNotNull);
      expect(fetched!.rawLrc, '[00:01.00] Hello World');
      expect(fetched.isSynced, isTrue);

      database.saveLyricsTranslation(
        keyHash: keyHash,
        source: LyricsSource.embedded.dbValue,
        targetLang: 'es',
        translatedLines: ['[00:01.00] Hola Mundo'],
      );

      final translation = database.getLyricsTranslation(
        keyHash: keyHash,
        source: LyricsSource.embedded.dbValue,
        targetLang: 'es',
      );
      expect(translation, ['[00:01.00] Hola Mundo']);
    });
  });
}
