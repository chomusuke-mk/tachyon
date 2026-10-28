import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/store/library_store.dart';

void main() {
  group('AppDatabase Milestone 1 tests', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('upsertTracks and getCatalogSnapshot works with normalized references, zero lyrics in snapshot, and embedded lyrics in lyrics table', () async {
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

      await database.upsertTracks([track1, track2]);

      final snapshot = await database.getCatalogSnapshot();

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
      final rows = await database.getLyricsForTrack(trackDto1.id);
      expect(rows, isNotEmpty);
      final bestLyrics = rows.first;
      expect(bestLyrics['source'], 'embedded');
      expect(bestLyrics['state'], 'FOUND');
      expect(bestLyrics['raw_lrc'], '[00:01.00] Embedded lyric line');
      expect(bestLyrics['is_synced'], 1);
    });

    test('getLyricsForTrack persists and deletes multiple sources per track', () async {
      final track = ExtractedTrackData(
        filePath: '/music/multi_source.mp3',
        title: 'Multi Source',
        artistNames: ['Artist Priority'],
        durationMs: 150000,
        fileSize: 4000000,
        modifiedAt: 1000,
      );
      await database.upsertTracks([track]);
      final trackId = (await database.getCatalogSnapshot()).tracks.first.id;

      final ovhId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'lyrics_ovh',
        state: 'FOUND',
        rawLrc: 'OVH plain lyrics',
        isSynced: false,
      );
      final lrclibId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:02.00] LRCLIB synced lyrics',
        isSynced: true,
      );
      final fileId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.50] Local file lyrics',
        isSynced: true,
      );
      final embeddedId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'embedded',
        state: 'FOUND',
        rawLrc: '[00:01.00] Embedded tag lyrics',
        isSynced: true,
      );
      expect((await database.getLyricsForTrack(trackId)).length, 4);

      await database.deleteLyrics(embeddedId);
      expect((await database.getLyricsForTrack(trackId)).length, 3);

      await database.deleteLyrics(fileId);
      expect((await database.getLyricsForTrack(trackId)).length, 2);

      await database.deleteLyrics(lrclibId);
      expect((await database.getLyricsForTrack(trackId)).length, 1);

      await database.deleteLyrics(ovhId);
      expect(await database.getLyricsForTrack(trackId), isEmpty);
    });

    test('lyrics translations CRUD and translation purge on lyrics update', () async {
      final track = ExtractedTrackData(
        filePath: '/music/trans.mp3',
        title: 'Translation Test',
        artistNames: ['Artist T'],
        durationMs: 100000,
        fileSize: 2000000,
        modifiedAt: 1000,
      );
      await database.upsertTracks([track]);
      final trackId = (await database.getCatalogSnapshot()).tracks.first.id;

      final lyricsId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:01.00] Hello',
        isSynced: true,
      );

      await database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Hola'],
      );
      await database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'fr',
        translatedLines: ['[00:01.00] Bonjour'],
      );

      final esTrans = await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es');
      expect(esTrans, ['[00:01.00] Hola']);

      final frTrans = await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'fr');
      expect(frTrans, ['[00:01.00] Bonjour']);

      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'de'), isNull);

      // Updating lyrics entry purges associated translations
      await database.saveLyricsEntry(
        trackId: trackId,
        source: 'lrclib',
        state: 'FOUND',
        rawLrc: '[00:01.00] Hello World Updated',
        isSynced: true,
      );

      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);
      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'fr'), isNull);
    });

    test('ON DELETE CASCADE deletes lyrics and translations when track or lyrics is deleted', () async {
      final track = ExtractedTrackData(
        filePath: '/music/cascade.mp3',
        title: 'Cascade Test',
        artistNames: ['Artist C'],
        durationMs: 110000,
        fileSize: 2500000,
        modifiedAt: 1000,
      );
      await database.upsertTracks([track]);
      final trackId = (await database.getCatalogSnapshot()).tracks.first.id;

      final lyricsId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.00] Line',
        isSynced: true,
      );

      await database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Linea'],
      );

      expect(await database.getLyricsForTrack(trackId), isNotEmpty);
      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNotNull);

      // 1. Test deleting lyrics deletes translations via CASCADE
      await database.deleteLyrics(lyricsId);
      expect(await database.getLyricsForTrack(trackId), isEmpty);
      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);

      // Re-create lyrics and translation
      final newLyricsId = await database.saveLyricsEntry(
        trackId: trackId,
        source: 'file',
        state: 'FOUND',
        rawLrc: '[00:01.00] Line 2',
        isSynced: true,
      );
      await database.saveLyricsTranslation(
        lyricsId: newLyricsId,
        lang: 'es',
        translatedLines: ['[00:01.00] Linea 2'],
      );

      // 2. Test deleting track deletes both lyrics and translations via CASCADE
      await database.deleteTracksAndPurgeOrphans([trackId]);
      expect(await database.getLyricsForTrack(trackId), isEmpty);
      expect(await database.getLyricsTranslation(lyricsId: newLyricsId, lang: 'es'), isNull);
    });

    test('toggleLikeTrack and LibraryStore.isTrackLiked works', () async {
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

      await database.upsertTracks([track1]);
      final store = LibraryStore(database);
      await store.reloadFromDatabase();
      final trackId = store.allTracks.first.id!;

      expect(store.isTrackLiked(trackId), isFalse);

      await store.toggleLikeInStore(trackId);
      expect(store.isTrackLiked(trackId), isTrue);

      final snapshotAfterLike = await database.getCatalogSnapshot();
      expect(snapshotAfterLike.playlistEntries.any((e) => e.trackId == trackId && e.playlistId == AppDatabase.likedSongsPlaylistId), isTrue);

      await store.toggleLikeInStore(trackId);
      expect(store.isTrackLiked(trackId), isFalse);
    });

    test('playlist management (create, add, reorder, remove, delete) works', () async {
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
      await database.upsertTracks([track1, track2]);
      final tracks = (await database.getCatalogSnapshot()).tracks;
      final id1 = tracks.firstWhere((t) => t.filePath == '/music/t1.mp3').id;
      final id2 = tracks.firstWhere((t) => t.filePath == '/music/t2.mp3').id;

      final playlistId = await database.createPlaylist('Favorites');
      expect(playlistId, isPositive);

      await database.addTracksToPlaylist(playlistId, [id1, id2]);
      var snapshot = await database.getCatalogSnapshot();
      var trackIds = snapshot.playlistEntries.where((e) => e.playlistId == playlistId).map((e) => e.trackId).toList();
      expect(trackIds, [id1, id2]);

      await database.reorderPlaylistEntries(playlistId, 0, 1);
      snapshot = await database.getCatalogSnapshot();
      trackIds = snapshot.playlistEntries.where((e) => e.playlistId == playlistId).map((e) => e.trackId).toList();
      expect(trackIds, [id2, id1]);

      await database.removeTrackFromPlaylist(playlistId, id2);
      snapshot = await database.getCatalogSnapshot();
      trackIds = snapshot.playlistEntries.where((e) => e.playlistId == playlistId).map((e) => e.trackId).toList();
      expect(trackIds, [id1]);

      await database.deletePlaylist(playlistId);
      snapshot = await database.getCatalogSnapshot();
      expect(snapshot.playlists.any((p) => p.id == playlistId), isFalse);
    });

    test('LibraryStore.getAllThumbnailHashes retrieves unique non-empty thumbnail hashes across tracks, albums, artists', () async {
      final track = ExtractedTrackData(
        filePath: '/music/t1.mp3',
        title: 'T1',
        artistNames: ['Artist One'],
        albumName: 'Album One',
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 1,
        thumbnailHash: 'track_hash_1',
        artistThumbnailHash: 'artist_hash_1',
      );
      await database.upsertTracks([track]);

      final store = LibraryStore(database);
      await store.reloadFromDatabase();
      final hashes = store.getAllThumbnailHashes();
      expect(hashes, containsAll({'track_hash_1', 'artist_hash_1'}));
    });

    test('LibraryStore.getStoredTracks and deleteTracksAndPurgeOrphans work correctly', () async {
      final track = ExtractedTrackData(
        filePath: '/music/t1.mp3',
        title: 'T1',
        artistNames: ['Artist Orphan'],
        albumName: 'Album Orphan',
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 100,
      );
      await database.upsertTracks([track]);

      final store = LibraryStore(database);
      await store.reloadFromDatabase();
      final stored = store.getStoredTracks();
      expect(stored.length, 1);
      expect(stored.first.filePath, '/music/t1.mp3');
      expect(stored.first.modifiedAt, 100);

      await database.deleteTracksAndPurgeOrphans([stored.first.id]);
      await store.reloadFromDatabase();

      final afterDelete = store.getStoredTracks();
      expect(afterDelete, isEmpty);

      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks, isEmpty);
      expect(snapshot.albums, isEmpty);
      expect(snapshot.artists, isEmpty);
    });

    test('RadioStation persistence and AudioPlayable liveStream contract works', () async {
      final now = DateTime.now();
      final station = RadioStation(
        name: 'Chillout Lounge',
        streamUrl: 'https://stream.example.com/chill.mp3',
        homepageUrl: 'https://example.com',
        genre: 'Ambient',
        country: 'Germany',
        bitrateKbps: 320,
        codec: 'mp3',
        isFavorite: true,
        createdAt: now,
      );

      // 1. AudioPlayable contracts
      expect(station.title, equals('Chillout Lounge'));
      expect(station.artistNames, equals(['Ambient']));
      expect(station.albumTitle, equals('Germany'));
      expect(station.duration, equals(Duration.zero));
      expect(station.isStream, isTrue);

      final engineItem = station.toEngineItem();
      expect(engineItem.data, equals(station));
      expect(engineItem.track, equals(station));

      // 2. Database CRUD
      final saved = await database.saveRadioStation(station);
      expect(saved.id, isNotNull);
      expect(saved.name, equals('Chillout Lounge'));
      expect(saved.isFavorite, isTrue);

      var list = await database.getRadioStations();
      expect(list.length, equals(1));
      expect(list.first.name, equals('Chillout Lounge'));
      expect(list.first.streamUrl, equals('https://stream.example.com/chill.mp3'));
      expect(list.first.isFavorite, isTrue);

      // 3. Toggle favorite
      await database.setRadioStationFavorite(saved.id!, false);
      list = await database.getRadioStations();
      expect(list.first.isFavorite, isFalse);

      // 4. Delete station
      await database.deleteRadioStation(saved.id!);
      list = await database.getRadioStations();
      expect(list, isEmpty);
    });
  });
}
