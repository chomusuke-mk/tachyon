import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;

  setUp(() async {
    db = AppDatabaseImpl.inMemory();
    await db.init();
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase Schema & Initialization', () {
    test('enables foreign keys pragma on initialization', () async {
      final res = await db.database.rawQuery('PRAGMA foreign_keys;');
      expect(res.first.values.first, equals(1));
    });

    test('seeds special system playlists (Liked Songs and History)', () async {
      final playlists = await db.getAllPlaylists();
      expect(playlists.length, equals(2));

      final liked = playlists.firstWhere((p) => p.id == AppConstants.likedSongsPlaylistId);
      expect(liked.name, equals(AppConstants.likedSongsPlaylistName));
      expect(liked.isSpecial, equals(1));

      final history = playlists.firstWhere((p) => p.id == AppConstants.historyPlaylistId);
      expect(history.name, equals(AppConstants.historyPlaylistName));
      expect(history.isSpecial, equals(2));
    });
  });

  group('Track Insertion & Aggregation', () {
    test('insertOrUpdateTrack inserts track, automatically creating artist and album', () async {
      const track = Track(
        uri: 'file:///music/metallica/master.flac',
        title: 'Master of Puppets',
        artist: 'Metallica',
        album: 'Master of Puppets',
        year: 1986,
        durationMs: 515000,
        fileSize: 45000000,
        modifiedAt: 1600000000,
        genres: ['Thrash Metal', 'Heavy Metal'],
      );

      await db.insertOrUpdateTrack(track);

      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(1));
      expect(tracks.first.title, equals('Master of Puppets'));
      expect(tracks.first.artist, equals('Metallica'));
      expect(tracks.first.album, equals('Master of Puppets'));

      final artists = await db.getAllArtists();
      expect(artists.length, equals(1));
      expect(artists.first.name, equals('Metallica'));
      expect(artists.first.trackCount, equals(1));

      final albums = await db.getAllAlbums();
      expect(albums.length, equals(1));
      expect(albums.first.name, equals('Master of Puppets'));
      expect(albums.first.trackCount, equals(1));

      final genres = await db.getAllGenres();
      expect(genres.length, equals(2));
      expect(genres.map((g) => g.name).toSet(), equals({'Thrash Metal', 'Heavy Metal'}));
    });

    test('insertOrUpdateTrack updates track upon matching URI without duplicate records', () async {
      const track1 = Track(
        uri: 'file:///music/song.mp3',
        title: 'Initial Title',
        artist: 'Artist A',
        album: 'Album A',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 1000,
      );
      await db.insertOrUpdateTrack(track1);

      const track2 = Track(
        uri: 'file:///music/song.mp3',
        title: 'Corrected Title',
        artist: 'Artist A',
        album: 'Album A',
        durationMs: 185000,
        fileSize: 5100000,
        modifiedAt: 2000,
      );
      await db.insertOrUpdateTrack(track2);

      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(1));
      expect(tracks.first.title, equals('Corrected Title'));
      expect(tracks.first.durationMs, equals(185000));
    });

    test('batchInsertTracks ingests multiple tracks and recalculates counters', () async {
      final batchTracks = List.generate(
        10,
        (i) => Track(
          uri: 'file:///music/track_$i.mp3',
          title: 'Track $i',
          artist: i < 5 ? 'Artist 1' : 'Artist 2',
          album: i < 5 ? 'Album 1' : 'Album 2',
          durationMs: 200000 + i * 1000,
          fileSize: 4000000,
          modifiedAt: 1000 + i,
        ),
      );

      await db.batchInsertTracks(batchTracks);

      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(10));

      final artists = await db.getAllArtists();
      expect(artists.length, equals(2));
      expect(artists.firstWhere((a) => a.name == 'Artist 1').trackCount, equals(5));
      expect(artists.firstWhere((a) => a.name == 'Artist 2').trackCount, equals(5));

      final albums = await db.getAllAlbums();
      expect(albums.length, equals(2));
      expect(albums.firstWhere((a) => a.name == 'Album 1').trackCount, equals(5));
      expect(albums.firstWhere((a) => a.name == 'Album 2').trackCount, equals(5));
    });

    test('batchInsertTracks populates track_genres and getAllGenres returns correct track counts', () async {
      final batchTracks = [
        const Track(
          uri: 'file:///music/rock1.mp3',
          title: 'Rock Song 1',
          genres: ['Rock', 'Classic Rock'],
          durationMs: 200000,
          fileSize: 4000000,
          modifiedAt: 1000,
        ),
        const Track(
          uri: 'file:///music/rock2.mp3',
          title: 'Rock Song 2',
          genres: ['Rock', 'Metal'],
          durationMs: 210000,
          fileSize: 4100000,
          modifiedAt: 1001,
        ),
        const Track(
          uri: 'file:///music/jazz1.mp3',
          title: 'Jazz Song 1',
          genres: ['Jazz'],
          durationMs: 220000,
          fileSize: 4200000,
          modifiedAt: 1002,
        ),
      ];

      await db.batchInsertTracks(batchTracks);

      final genres = await db.getAllGenres();
      expect(genres.length, equals(4));

      final rock = genres.firstWhere((g) => g.name == 'Rock');
      expect(rock.trackCount, equals(2));

      final classicRock = genres.firstWhere((g) => g.name == 'Classic Rock');
      expect(classicRock.trackCount, equals(1));

      final metal = genres.firstWhere((g) => g.name == 'Metal');
      expect(metal.trackCount, equals(1));

      final jazz = genres.firstWhere((g) => g.name == 'Jazz');
      expect(jazz.trackCount, equals(1));
    });
  });

  group('Sorting & Querying', () {
    setUp(() async {
      await db.insertOrUpdateTrack(const Track(
        uri: 'file:///1.mp3',
        title: 'Zebra',
        artist: 'Pink Floyd',
        album: 'B Album',
        year: 1973,
        durationMs: 300000,
        fileSize: 1000,
        modifiedAt: 100,
      ));
      await db.insertOrUpdateTrack(const Track(
        uri: 'file:///2.mp3',
        title: 'Apple',
        artist: 'Beatles',
        album: 'A Album',
        year: 1969,
        durationMs: 150000,
        fileSize: 1000,
        modifiedAt: 200,
      ));
    });

    test('getAllTracks sorts by title, artist, album, year, duration ascending and descending', () async {
      final byTitleAsc = await db.getAllTracks(sortBy: 'title', ascending: true);
      expect(byTitleAsc.first.title, equals('Apple'));

      final byTitleDesc = await db.getAllTracks(sortBy: 'title', ascending: false);
      expect(byTitleDesc.first.title, equals('Zebra'));

      final byYearAsc = await db.getAllTracks(sortBy: 'year', ascending: true);
      expect(byYearAsc.first.year, equals(1969));

      final byDurationDesc = await db.getAllTracks(sortBy: 'duration', ascending: false);
      expect(byDurationDesc.first.durationMs, equals(300000));
    });

    test('searchTracks returns prefix prioritized results across title, artist, and album', () async {
      final results = await db.searchTracks('Beat');
      expect(results.length, equals(1));
      expect(results.first.artist, equals('Beatles'));

      final resultsZ = await db.searchTracks('Zeb');
      expect(resultsZ.length, equals(1));
      expect(resultsZ.first.title, equals('Zebra'));

      final empty = await db.searchTracks('   ');
      expect(empty, isEmpty);
    });
  });

  group('Playlists CRUD & Reordering', () {
    test('creates custom playlist and prevents deleting special playlists', () async {
      final id = await db.createPlaylist('Gym Workout');
      expect(id, greaterThan(2));

      var playlists = await db.getAllPlaylists();
      expect(playlists.length, equals(3));

      // Attempt to delete Liked Songs (special)
      await db.deletePlaylist(AppConstants.likedSongsPlaylistId);
      playlists = await db.getAllPlaylists();
      expect(playlists.any((p) => p.id == AppConstants.likedSongsPlaylistId), isTrue);

      // Delete custom playlist
      await db.deletePlaylist(id);
      playlists = await db.getAllPlaylists();
      expect(playlists.length, equals(2));
    });

    test('addTrackToPlaylist, reorderPlaylistEntries, and removeTrackFromPlaylist', () async {
      await db.insertOrUpdateTrack(const Track(
        id: 1,
        uri: 'file:///track1.mp3',
        title: 'Track 1',
        durationMs: 100000,
        fileSize: 1000,
        modifiedAt: 100,
      ));
      await db.insertOrUpdateTrack(const Track(
        id: 2,
        uri: 'file:///track2.mp3',
        title: 'Track 2',
        durationMs: 100000,
        fileSize: 1000,
        modifiedAt: 100,
      ));
      await db.insertOrUpdateTrack(const Track(
        id: 3,
        uri: 'file:///track3.mp3',
        title: 'Track 3',
        durationMs: 100000,
        fileSize: 1000,
        modifiedAt: 100,
      ));

      final plId = await db.createPlaylist('Party');
      await db.addTrackToPlaylist(plId, 1);
      await db.addTrackToPlaylist(plId, 2);
      await db.addTrackToPlaylist(plId, 3);

      var tracks = await db.getTracksForPlaylist(plId);
      expect(tracks.length, equals(3));
      expect(tracks.map((t) => t.title).toList(), equals(['Track 1', 'Track 2', 'Track 3']));

      // Reorder track 0 to position 2: [Track 2, Track 3, Track 1]
      await db.reorderPlaylistEntries(plId, 0, 2);
      tracks = await db.getTracksForPlaylist(plId);
      expect(tracks.map((t) => t.title).toList(), equals(['Track 2, Track 3, Track 1'.split(', ')[0], 'Track 3', 'Track 1']));

      // Remove Track 2
      await db.removeTrackFromPlaylist(plId, 2);
      tracks = await db.getTracksForPlaylist(plId);
      expect(tracks.length, equals(2));
      expect(tracks.map((t) => t.title).toList(), equals(['Track 3', 'Track 1']));
    });

    test('toggleLikeTrack and isTrackLiked operate on special playlist 1', () async {
      await db.insertOrUpdateTrack(const Track(
        uri: 'file:///liked.mp3',
        title: 'Favorite Song',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 100,
      ));

      final track = (await db.getAllTracks()).firstWhere((t) => t.uri == 'file:///liked.mp3');
      final trackId = track.id!;

      expect(await db.isTrackLiked(trackId), isFalse);

      await db.toggleLikeTrack(trackId, track.uri);
      expect(await db.isTrackLiked(trackId), isTrue);

      await db.toggleLikeTrack(trackId, track.uri);
      expect(await db.isTrackLiked(trackId), isFalse);
    });

    test('clearHistory clears entries in playlist 2', () async {
      await db.insertOrUpdateTrack(const Track(
        uri: 'file:///hist.mp3',
        title: 'History Song',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 100,
      ));

      final track = (await db.getAllTracks()).firstWhere((t) => t.uri == 'file:///hist.mp3');
      final trackId = track.id!;

      await db.addTrackToPlaylist(AppConstants.historyPlaylistId, trackId);
      var historyTracks = await db.getTracksForPlaylist(AppConstants.historyPlaylistId);
      expect(historyTracks.length, equals(1));

      await db.clearHistory();
      historyTracks = await db.getTracksForPlaylist(AppConstants.historyPlaylistId);
      expect(historyTracks, isEmpty);
    });

    test('adding track to playlist followed by insertOrUpdateTrack and batchInsertTracks preserves playlist entry', () async {
      // 1. Insert initial track
      const initialTrack = Track(
        uri: 'file:///music/fav_song.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 200000,
        fileSize: 3000000,
        modifiedAt: 1000,
      );
      await db.insertOrUpdateTrack(initialTrack);
      final tracks = await db.getAllTracks();
      final trackId = tracks.first.id!;

      // 2. Add track to custom playlist and to Liked Songs
      final customPlId = await db.createPlaylist('Favorites');
      await db.addTrackToPlaylist(customPlId, trackId);
      await db.addTrackToPlaylist(AppConstants.likedSongsPlaylistId, trackId);

      var plTracks = await db.getTracksForPlaylist(customPlId);
      var likedTracks = await db.getTracksForPlaylist(AppConstants.likedSongsPlaylistId);
      expect(plTracks.length, equals(1));
      expect(likedTracks.length, equals(1));

      // 3. Update track metadata via insertOrUpdateTrack
      const updatedTrack = Track(
        uri: 'file:///music/fav_song.mp3',
        title: 'Updated Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 205000,
        fileSize: 3100000,
        modifiedAt: 2000,
      );
      await db.insertOrUpdateTrack(updatedTrack);

      // Verify playlist entries are PRESERVED and reflect updated title
      plTracks = await db.getTracksForPlaylist(customPlId);
      likedTracks = await db.getTracksForPlaylist(AppConstants.likedSongsPlaylistId);
      expect(plTracks.length, equals(1), reason: 'Playlist entry must not be cascaded on insertOrUpdateTrack');
      expect(plTracks.first.title, equals('Updated Title'));
      expect(likedTracks.length, equals(1), reason: 'Liked songs entry must not be cascaded on insertOrUpdateTrack');
      expect(likedTracks.first.title, equals('Updated Title'));

      // 4. Update track metadata via batchInsertTracks (rescan simulation)
      const rescanTrack = Track(
        uri: 'file:///music/fav_song.mp3',
        title: 'Rescanned Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 206000,
        fileSize: 3200000,
        modifiedAt: 3000,
      );
      await db.batchInsertTracks([rescanTrack]);

      // Verify playlist entries are STILL PRESERVED and reflect rescanned title
      plTracks = await db.getTracksForPlaylist(customPlId);
      likedTracks = await db.getTracksForPlaylist(AppConstants.likedSongsPlaylistId);
      expect(plTracks.length, equals(1), reason: 'Playlist entry must not be cascaded on batchInsertTracks');
      expect(plTracks.first.title, equals('Rescanned Title'));
      expect(likedTracks.length, equals(1), reason: 'Liked songs entry must not be cascaded on batchInsertTracks');
      expect(likedTracks.first.title, equals('Rescanned Title'));
    });
  });

  group('Lyrics Cache Storage', () {
    test('saves and retrieves cached lyrics by hash key', () async {
      const keyHash = 'abc123hash';
      const rawLrc = '[00:01.00]Hello world';

      expect(await db.getLyrics(keyHash), isNull);

      await db.saveLyrics(keyHash, rawLrc, 'embedded');
      final fetched = await db.getLyrics(keyHash);
      expect(fetched, equals(rawLrc));

      // Overwrite/update
      await db.saveLyrics(keyHash, '[00:01.00]Updated lyric', 'file');
      final updated = await db.getLyrics(keyHash);
      expect(updated, equals('[00:01.00]Updated lyric'));
    });
  });
}
