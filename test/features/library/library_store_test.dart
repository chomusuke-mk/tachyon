import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

CatalogSnapshot _createSampleSnapshot() {
  final artists = [
    const RawArtistDto(id: 1, name: 'The Beatles'),
    const RawArtistDto(id: 2, name: 'Pink Floyd'),
    const RawArtistDto(id: 3, name: 'Queen'),
  ];

  final albums = [
    const RawAlbumDto(id: 10, name: 'Abbey Road', year: 1969, artistId: 1),
    const RawAlbumDto(
      id: 20,
      name: 'The Dark Side of the Moon',
      year: 1973,
      artistId: 2,
    ),
    const RawAlbumDto(
      id: 30,
      name: 'A Night at the Opera',
      year: 1975,
      artistId: 3,
    ),
  ];

  final genres = [
    const RawGenreDto(id: 100, name: 'Rock'),
    const RawGenreDto(id: 200, name: 'Progressive Rock'),
  ];

  final tracks = [
    const RawTrackDto(
      id: 1001,
      filePath: '/music/beatles/come_together.mp3',
      title: 'Come Together',
      trackNumber: 1,
      discNumber: 1,
      year: 1969,
      durationMs: 259000,
      fileSize: 6200000,
      modifiedAt: 1000,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1002,
      filePath: '/music/beatles/something.mp3',
      title: 'Something',
      trackNumber: 2,
      discNumber: 1,
      year: 1969,
      durationMs: 182000,
      fileSize: 4300000,
      modifiedAt: 1010,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1003,
      filePath: '/music/pink_floyd/time.mp3',
      title: 'Time',
      trackNumber: 4,
      discNumber: 1,
      year: 1973,
      durationMs: 425000,
      fileSize: 10200000,
      modifiedAt: 2000,
      albumId: 20,
    ),
    const RawTrackDto(
      id: 1004,
      filePath: '/music/queen/bohemian_rhapsody.mp3',
      title: 'Bohemian Rhapsody',
      trackNumber: 11,
      discNumber: 1,
      year: 1975,
      durationMs: 354000,
      fileSize: 8500000,
      modifiedAt: 3000,
      albumId: 30,
    ),
  ];

  final trackArtists = [
    const TrackArtistPair(trackId: 1001, artistId: 1),
    const TrackArtistPair(trackId: 1002, artistId: 1),
    const TrackArtistPair(trackId: 1003, artistId: 2),
    const TrackArtistPair(trackId: 1004, artistId: 3),
  ];

  final trackGenres = [
    const TrackGenrePair(trackId: 1001, genreId: 100),
    const TrackGenrePair(trackId: 1002, genreId: 100),
    const TrackGenrePair(trackId: 1003, genreId: 100),
    const TrackGenrePair(trackId: 1003, genreId: 200),
    const TrackGenrePair(trackId: 1004, genreId: 100),
  ];

  final playlists = [
    const RawPlaylistDto(
      id: 1,
      name: 'Liked Songs',
      createdAt: 100,
      type: 1,
    ),
    const RawPlaylistDto(
      id: 2,
      name: 'History',
      createdAt: 100,
      type: 2,
    ),
    const RawPlaylistDto(
      id: 50,
      name: 'My Favorites',
      createdAt: 500,
      type: 0,
    ),
  ];

  final playlistEntries = [
    const RawPlaylistEntryDto(
      id: 501,
      playlistId: 1,
      trackId: 1001,
      position: 0,
      addedAt: 200,
    ),
    const RawPlaylistEntryDto(
      id: 502,
      playlistId: 50,
      trackId: 1003,
      position: 0,
      addedAt: 600,
    ),
    const RawPlaylistEntryDto(
      id: 503,
      playlistId: 50,
      trackId: 1004,
      position: 1,
      addedAt: 601,
    ),
  ];

  return CatalogSnapshot(
    tracks: tracks,
    albums: albums,
    artists: artists,
    genres: genres,
    playlists: playlists,
    playlistEntries: playlistEntries,
    trackArtists: trackArtists,
    trackGenres: trackGenres,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryStore In-Memory Graph & Hydration Tests', () {
    test('Hydrating from empty CatalogSnapshot produces valid empty store', () {
      final store = LibraryStore.fromSnapshot(const CatalogSnapshot.empty());

      expect(store.tracks, isEmpty);
      expect(store.albums, isEmpty);
      expect(store.artists, isEmpty);
      expect(store.genres, isEmpty);
      expect(store.playlists, isEmpty);
      expect(store.likedTrackIds, isEmpty);
      expect(store.getTrackById(1), isNull);
      expect(store.getAlbumById(1), isNull);
    });

    test('Single-pass O(N) hydration populates relational entities and indices correctly', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      expect(store.tracks.length, equals(4));
      expect(store.albums.length, equals(3));
      expect(store.artists.length, equals(3));
      expect(store.genres.length, equals(2));
      expect(store.playlists.length, equals(3));

      // Fast O(1) ID lookups
      final track1 = store.getTrackById(1001);
      expect(track1, isNotNull);
      expect(track1!.title, equals('Come Together'));

      final trackByPath = store.getTrackByPath('/music/beatles/come_together.mp3');
      expect(identical(track1, trackByPath), isTrue);

      final album1 = store.getAlbumById(10);
      expect(album1, isNotNull);
      expect(album1!.name, equals('Abbey Road'));

      final artist1 = store.getArtistById(1);
      expect(artist1, isNotNull);
      expect(artist1!.name, equals('The Beatles'));

      final genreRock = store.getGenreById(100);
      expect(genreRock, isNotNull);
      expect(genreRock!.name, equals('Rock'));

      final playlistFav = store.getPlaylistById(50);
      expect(playlistFav, isNotNull);
      expect(playlistFav!.name, equals('My Favorites'));
    });

    test('Guarantees 100% pointer identity (identical() == true) across shared entities', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final track1 = store.getTrackById(1001)!;
      final track2 = store.getTrackById(1002)!;

      // 1. Shared Artist Identity: Both tracks share The Beatles (id: 1)
      expect(identical(track1.artists.first, track2.artists.first), isTrue);
      expect(identical(track1.artists.first, store.getArtistById(1)), isTrue);

      // 2. Shared Album Identity: Both tracks share Abbey Road (id: 10)
      expect(identical(track1.album, track2.album), isTrue);
      expect(identical(track1.album, store.getAlbumById(10)), isTrue);

      // 3. Shared Genre Identity: Both tracks share Rock (id: 100)
      expect(identical(track1.genres.first, track2.genres.first), isTrue);
      expect(identical(track1.genres.first, store.getGenreById(100)), isTrue);

      // 4. Playlist Entries Point to the Exact Same Track Instances
      final playlistFav = store.getPlaylistById(50)!;
      final entry0 = playlistFav.entries[0];
      final entry1 = playlistFav.entries[1];

      expect(identical(entry0.playlist, playlistFav), isTrue);
      expect(identical(entry0.track, store.getTrackById(1003)), isTrue);
      expect(identical(entry1.track, store.getTrackById(1004)), isTrue);
    });

    test('Validates bidirectional navigation and cyclic consistency', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final albumAbbey = store.getAlbumById(10)!;
      final trackComeTogether = store.getTrackById(1001)!;

      // Album -> Tracks contains track, and Track -> Album is album
      expect(albumAbbey.tracks.contains(trackComeTogether), isTrue);
      expect(identical(trackComeTogether.album, albumAbbey), isTrue);
      expect(identical(albumAbbey.tracks.first.album, albumAbbey), isTrue);

      // Artist -> Tracks and Tracks -> Artists
      final artistBeatles = store.getArtistById(1)!;
      expect(artistBeatles.tracks.contains(trackComeTogether), isTrue);
      expect(identical(artistBeatles.tracks.first.artists.first, artistBeatles), isTrue);

      // Artist -> Albums
      expect(artistBeatles.albums.contains(albumAbbey), isTrue);
      expect(identical(albumAbbey.artist, artistBeatles), isTrue);

      // Genre -> Tracks
      final genreRock = store.getGenreById(100)!;
      expect(genreRock.tracks.contains(trackComeTogether), isTrue);
    });

    test('Album tracks are automatically sorted by discNumber and trackNumber in order', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final albumAbbey = store.getAlbumById(10)!;
      expect(albumAbbey.tracks.length, equals(2));
      expect(albumAbbey.tracks[0].trackNumber, equals(1));
      expect(albumAbbey.tracks[1].trackNumber, equals(2));
    });

    test('In-memory like toggling mutates store and Liked Songs playlist reactively', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      // Track 1001 starts as liked in sample snapshot
      expect(store.isTrackLiked(1001), isTrue);
      expect(store.isTrackLiked(1002), isFalse);

      final likedPl = store.likedSongsPlaylist;
      expect(likedPl, isNotNull);
      expect(likedPl!.entries.length, equals(1));
      expect(likedPl.entries.first.track?.id, equals(1001));

      // Like Track 1002
      store.setTrackLiked(1002, true);
      expect(store.isTrackLiked(1002), isTrue);
      expect(likedPl.entries.length, equals(2));
      expect(likedPl.entries.any((e) => e.track?.id == 1002), isTrue);

      // Unlike Track 1001 via toggleTrackLiked
      final nowLiked = store.toggleTrackLiked(1001);
      expect(nowLiked, isFalse);
      expect(store.isTrackLiked(1001), isFalse);
      expect(likedPl.entries.length, equals(1));
      expect(likedPl.entries.first.track?.id, equals(1002));
    });

    test('In-memory playlist mutations: add, remove, and reorder entries', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final playlist = store.getPlaylistById(50)!;
      expect(playlist.entries.length, equals(2));

      // Add Track 1001 to playlist
      store.addTrackToPlaylist(50, 1001);
      expect(playlist.entries.length, equals(3));
      expect(playlist.entries.last.track?.id, equals(1001));
      expect(identical(playlist.entries.last.track, store.getTrackById(1001)), isTrue);

      // Reorder: move last item (index 2) to first (index 0)
      store.reorderPlaylistEntries(50, 2, 0);
      expect(playlist.entries.first.track?.id, equals(1001));
      expect(playlist.entries.first.position, equals(0));

      // Remove Track 1001
      store.removeTrackFromPlaylist(50, 1001);
      expect(playlist.entries.length, equals(2));
      expect(playlist.entries.any((e) => e.track?.id == 1001), isFalse);
    });

    test('In-memory track deletion cleanly updates all graph entities', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final album = store.getAlbumById(10)!;
      final artist = store.getArtistById(1)!;
      final genre = store.getGenreById(100)!;

      expect(album.tracks.any((t) => t.id == 1001), isTrue);
      expect(artist.tracks.any((t) => t.id == 1001), isTrue);
      expect(genre.tracks.any((t) => t.id == 1001), isTrue);

      store.removeTrack(1001);

      expect(store.getTrackById(1001), isNull);
      expect(store.getTrackByPath('/music/beatles/come_together.mp3'), isNull);
      expect(album.tracks.any((t) => t.id == 1001), isFalse);
      expect(artist.tracks.any((t) => t.id == 1001), isFalse);
      expect(genre.tracks.any((t) => t.id == 1001), isFalse);
      expect(store.isTrackLiked(1001), isFalse);
    });

    test('In-memory filtering, sorting, and search without SQL', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      // Filter by Album
      final abbeyTracks = store.filterTracks(album: store.getAlbumById(10));
      expect(abbeyTracks.length, equals(2));
      expect(abbeyTracks.every((t) => t.album?.id == 10), isTrue);

      // Filter by Artist
      final beatlesTracks = store.filterTracks(artist: store.getArtistById(1));
      expect(beatlesTracks.length, equals(2));

      // Search Tracks
      final searchResult = store.searchTracks('rhapsody');
      expect(searchResult.length, equals(1));
      expect(searchResult.first.id, equals(1004));

      // Sort Tracks
      final sortedByTitleDesc = store.sortTracks(
        store.allTracks,
        TrackSortOption.title,
        ascending: false,
      );
      expect(sortedByTitleDesc.first.title, equals('Time'));
    });
  });

  group('Controller Integration Tests with LibraryStore', () {
    late SharedPreferences prefs;
    late SettingsRepository settingsRepository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settingsRepository = SettingsRepository(prefs);
    });

    test('LibraryController connects to LibraryStore and provides fast in-memory operations', () async {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final controller = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      expect(controller.allTracks.length, equals(4));
      expect(controller.albums.length, equals(3));
      expect(controller.artists.length, equals(3));
      expect(controller.genres.length, equals(2));

      // Filter by artist in RAM
      controller.filterByArtist(store.getArtistById(1));
      expect(controller.tracks.length, equals(2));
      expect(controller.tracks.every((t) => t.artists.any((a) => a.id == 1)), isTrue);

      controller.clearFilters();
      expect(controller.tracks.length, equals(4));

      // Sort in RAM without database call
      await controller.setSortOption(TrackSortOption.title, ascending: true);
      expect(controller.tracks.first.title, equals('Bohemian Rhapsody'));

      controller.dispose();
    });

    test('PlaylistsController resolves tracks directly from memory pointers (entry.track)', () async {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final playlistsController = PlaylistsController(
        store: store,
      );

      expect(playlistsController.playlists.length, equals(3));
      expect(playlistsController.isTrackLiked(1001), isTrue);
      expect(playlistsController.isTrackLiked(1003), isFalse);

      // Select playlist and verify direct pointer resolution without SQL RPC
      final playlist50 = store.getPlaylistById(50)!;
      await playlistsController.selectPlaylist(playlist50);

      expect(playlistsController.selectedPlaylistTracks.length, equals(2));
      expect(playlistsController.selectedPlaylistTracks[0].id, equals(1003));
      expect(playlistsController.selectedPlaylistTracks[1].id, equals(1004));

      // Pointer identity check on controller output
      expect(
        identical(
          playlistsController.selectedPlaylistTracks[0],
          store.getTrackById(1003),
        ),
        isTrue,
      );

      playlistsController.dispose();
    });

    test('Reactivity: LibraryStore.reloadFromDatabase triggers controller reloading', () async {
      final db = AppDatabase.inMemory();

      final store = LibraryStore(db);
      await store.reloadFromDatabase();
      final controller = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      // Insert tracks into database
      await db.upsertTracks([
        ExtractedTrackData(
          filePath: '/music/live/track1.mp3',
          title: 'Live Track 1',
          artistNames: ['Live Artist'],
          albumName: 'Live Album',
          genreNames: ['Rock'],
          durationMs: 120000,
          fileSize: 3000000,
          modifiedAt: 1234,
        ),
      ]);

      await store.reloadFromDatabase();

      expect(notified, isTrue);
      expect(controller.allTracks.length, equals(1));
      expect(controller.allTracks.first.title, equals('Live Track 1'));

      controller.dispose();
      await db.close();
    });

    test('LibraryStore renamePlaylist and clearHistory work in-memory', () {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      expect(store.getPlaylistById(50)?.name, equals('My Favorites'));
      store.renamePlaylist(50, 'Classic Rock Hits');
      expect(store.getPlaylistById(50)?.name, equals('Classic Rock Hits'));
      expect(store.playlists.firstWhere((p) => p.id == 50).name, equals('Classic Rock Hits'));

      final historyPl = store.historyPlaylist;
      expect(historyPl, isNotNull);
      store.addTrackToPlaylist(2, 1001);
      expect(historyPl!.entries.length, equals(1));
      store.clearHistory();
      expect(historyPl.entries, isEmpty);
    });

    test('PlaylistsController performs in-memory playlist mutations cleanly', () async {
      final db = AppDatabase.inMemory();
      final store = LibraryStore(db);
      store.hydrateFromSnapshot(_createSampleSnapshot());

      final playlistsController = PlaylistsController(
        store: store,
      );

      // Create playlist
      final newId = await playlistsController.createPlaylist('New In-Memory Playlist');
      expect(newId, isPositive);
      expect(playlistsController.playlists.any((p) => p.name == 'New In-Memory Playlist'), isTrue);
      expect(store.getPlaylistById(newId)?.name, equals('New In-Memory Playlist'));

      // Rename playlist
      await playlistsController.renamePlaylist(newId, 'Renamed Playlist');
      expect(playlistsController.playlists.any((p) => p.name == 'Renamed Playlist'), isTrue);
      expect(store.getPlaylistById(newId)?.name, equals('Renamed Playlist'));

      // Delete playlist
      await playlistsController.deletePlaylist(newId);
      expect(playlistsController.playlists.any((p) => p.id == newId), isFalse);
      expect(store.getPlaylistById(newId), isNull);

      // Clear history
      await playlistsController.clearHistory();
      expect(playlistsController.historyPlaylist?.entries, isEmpty);

      playlistsController.dispose();
      await db.close();
    });

    test('Zero-Jank: toggleLike updates store and DB without triggering full catalog reload', () async {
      final db = AppDatabase.inMemory();
      await db.upsertTracks([
        ExtractedTrackData(
          filePath: '/music/rock/song1.mp3',
          title: 'Song 1',
          artistNames: ['Artist 1'],
          albumName: 'Album 1',
          genreNames: ['Rock'],
          durationMs: 180000,
          fileSize: 4000000,
          modifiedAt: 1000,
        ),
      ]);
      final store = LibraryStore(db);
      await store.reloadFromDatabase();
      final trackId = store.tracks.first.id!;

      final libraryController = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      final playlistsController = PlaylistsController(
        store: store,
      );

      // Track is not liked initially
      expect(playlistsController.isTrackLiked(trackId), isFalse);

      // 1. Toggle like (add to liked)
      final likedResult = await playlistsController.toggleLike(trackId);
      expect(likedResult, isTrue);
      expect(playlistsController.isTrackLiked(trackId), isTrue);
      expect(store.isTrackLiked(trackId), isTrue);

      final snap1 = await db.getCatalogSnapshot();
      expect(
        snap1.playlistEntries.any(
          (e) => e.playlistId == AppDatabase.likedSongsPlaylistId && e.trackId == trackId,
        ),
        isTrue,
      );

      // 2. Toggle like again (remove from liked)
      final unlikedResult = await playlistsController.toggleLike(trackId);
      expect(unlikedResult, isFalse);
      expect(playlistsController.isTrackLiked(trackId), isFalse);
      expect(store.isTrackLiked(trackId), isFalse);

      final snap2 = await db.getCatalogSnapshot();
      expect(
        snap2.playlistEntries.any(
          (e) => e.playlistId == AppDatabase.likedSongsPlaylistId && e.trackId == trackId,
        ),
        isFalse,
      );

      playlistsController.dispose();
      libraryController.dispose();
      await db.close();
    });

    test('Hydrates Track thumbnailHash with fallback to album.thumbnailHash', () {
      final snapshot = CatalogSnapshot(
        albums: const [
          RawAlbumDto(id: 1, name: 'Album With Cover', thumbnailHash: 'album_hash'),
          RawAlbumDto(id: 2, name: 'Album Without Cover', thumbnailHash: null),
        ],
        tracks: const [
          RawTrackDto(
            id: 101,
            filePath: '/t1.mp3',
            title: 'Track With Own Cover',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: 1,
            thumbnailHash: 'own_track_hash',
          ),
          RawTrackDto(
            id: 102,
            filePath: '/t2.mp3',
            title: 'Track Without Cover (Takes Album Cover)',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: 1,
            thumbnailHash: null,
          ),
          RawTrackDto(
            id: 103,
            filePath: '/t3.mp3',
            title: 'Track With Empty Cover (Takes Album Cover)',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: 1,
            thumbnailHash: '',
          ),
          RawTrackDto(
            id: 104,
            filePath: '/t4.mp3',
            title: 'Track Without Any Cover',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: 2,
            thumbnailHash: null,
          ),
        ],
        artists: const [],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      expect(store.getTrackById(101)?.thumbnailHash, equals('own_track_hash'));
      expect(store.getTrackById(102)?.thumbnailHash, equals('album_hash'));
      expect(store.getTrackById(103)?.thumbnailHash, equals('album_hash'));
      expect(store.getTrackById(104)?.thumbnailHash, isNull);
    });

    test('Hydrates Genre coverHash from its tracks and updates upon track removal', () {
      final snapshot = CatalogSnapshot(
        albums: const [],
        artists: const [],
        genres: const [
          RawGenreDto(id: 10, name: 'Rock'),
          RawGenreDto(id: 20, name: 'Jazz'),
        ],
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/rock1.mp3',
            title: 'Rock 1',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            thumbnailHash: null,
          ),
          RawTrackDto(
            id: 2,
            filePath: '/rock2.mp3',
            title: 'Rock 2',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            thumbnailHash: 'rock_cover_hash',
          ),
        ],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [
          TrackGenrePair(trackId: 1, genreId: 10),
          TrackGenrePair(trackId: 2, genreId: 10),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      expect(store.getGenreById(10)?.coverHash, equals('rock_cover_hash'));
      expect(store.getGenreById(20)?.coverHash, isNull);

      // Remove the track that had the cover
      store.removeTrack(2);
      expect(store.getGenreById(10)?.coverHash, isNull);
    });

    test('Hydrates Playlist coverHash and updates on setTrackLiked and mutations', () {
      final snapshot = CatalogSnapshot(
        albums: const [],
        artists: const [],
        genres: const [],
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/t1.mp3',
            title: 'T1',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            thumbnailHash: 'hash_1',
          ),
          RawTrackDto(
            id: 2,
            filePath: '/t2.mp3',
            title: 'T2',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            thumbnailHash: 'hash_2',
          ),
          RawTrackDto(
            id: 3,
            filePath: '/t3.mp3',
            title: 'T3',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            thumbnailHash: null,
          ),
        ],
        playlists: [
          RawPlaylistDto(
            id: AppDatabase.likedSongsPlaylistId,
            name: 'Liked Songs',
            createdAt: 100,
            type: PlaylistType.liked.index,
          ),
          const RawPlaylistDto(
            id: 200,
            name: 'Custom',
            createdAt: 100,
            type: 0,
          ),
        ],
        playlistEntries: [
          RawPlaylistEntryDto(
            id: 1,
            playlistId: AppDatabase.likedSongsPlaylistId,
            trackId: 1,
            position: 0,
            addedAt: 100,
          ),
        ],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final likedPl = store.likedSongsPlaylist!;
      expect(likedPl.coverHash, equals('hash_1'));

      // Like track 2 (more recent timestamp)
      store.setTrackLiked(2, true);
      expect(likedPl.coverHash, equals('hash_2'));

      // Like track 3 (no cover) -> coverHash remains hash_2
      store.setTrackLiked(3, true);
      expect(likedPl.coverHash, equals('hash_2'));

      // Unlike track 2 -> coverHash falls back to hash_1
      store.setTrackLiked(2, false);
      expect(likedPl.coverHash, equals('hash_1'));

      // Unlike track 1 -> coverHash becomes null
      store.setTrackLiked(1, false);
      expect(likedPl.coverHash, isNull);

      // Custom playlist mutations
      final customPl = store.getPlaylistById(200)!;
      expect(customPl.coverHash, isNull);
      store.addTrackToPlaylist(200, 2);
      expect(customPl.coverHash, equals('hash_2'));
      store.removeTrackFromPlaylist(200, 2);
      expect(customPl.coverHash, isNull);
    });

    test('Hydrates Artist thumbnailHash with fallback to album and track thumbnailHash', () {
      final snapshot = CatalogSnapshot(
        artists: const [
          RawArtistDto(id: 1, name: 'Artist With Own Cover', thumbnailHash: 'own_artist_hash'),
          RawArtistDto(id: 2, name: 'Artist With Album Fallback', thumbnailHash: null),
          RawArtistDto(id: 3, name: 'Artist With Track Fallback', thumbnailHash: null),
          RawArtistDto(id: 4, name: 'Artist Without Any Cover', thumbnailHash: null),
        ],
        albums: const [
          RawAlbumDto(id: 10, name: 'Album 1', artistId: 2, thumbnailHash: 'album_10_hash'),
          RawAlbumDto(id: 20, name: 'Album Without Cover', artistId: 3, thumbnailHash: null),
        ],
        tracks: const [
          RawTrackDto(
            id: 100,
            filePath: '/t100.mp3',
            title: 'Track With Cover for Artist 3',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: 20,
            thumbnailHash: 'track_100_hash',
          ),
          RawTrackDto(
            id: 200,
            filePath: '/t200.mp3',
            title: 'Track Without Cover for Artist 4',
            durationMs: 1000,
            fileSize: 100,
            modifiedAt: 100,
            albumId: null,
            thumbnailHash: null,
          ),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [
          TrackArtistPair(trackId: 100, artistId: 3),
          TrackArtistPair(trackId: 200, artistId: 4),
        ],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      expect(store.getArtistById(1)?.thumbnailHash, equals('own_artist_hash'));
      expect(store.getArtistById(2)?.thumbnailHash, equals('album_10_hash'));
      expect(store.getArtistById(3)?.thumbnailHash, equals('track_100_hash'));
      expect(store.getArtistById(4)?.thumbnailHash, isNull);
    });

    test('Ephemeral tracks (id < 0) register, resolve in O(1), and do not pollute catalog', () {
      final store = LibraryStore();

      // Initially empty catalog
      expect(store.tracks, isEmpty);

      // Register external file
      final track = store.registerEphemeralTrack(
        '/external/unindexed_track.flac',
        title: 'External Track',
        artist: 'External Artist',
      );

      expect(track.id, isNotNull);
      expect(track.id!, lessThan(0));
      expect(track.title, equals('External Track'));
      expect(track.artists.first.name, equals('External Artist'));

      // Lookups resolve in O(1)
      expect(store.getTrackById(track.id!), equals(track));
      expect(store.getTrackByPath('/external/unindexed_track.flac'), equals(track));

      // Catalog indexed lists are strictly NOT contaminated
      expect(store.tracks, isEmpty);
      expect(store.allTracks, isEmpty);
      expect(store.artists, isEmpty);

      // Re-registering the same path returns the identical instance
      final sameTrack = store.registerEphemeralTrack('/external/unindexed_track.flac');
      expect(identical(sameTrack, track), isTrue);

      // Updating metadata
      final updated = Track(
        id: track.id,
        filePath: track.filePath,
        title: 'Updated External Track',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 123456,
        artists: track.artists,
      );
      store.updateEphemeralTrack(updated);
      expect(store.getTrackById(track.id!)?.title, equals('Updated External Track'));
      expect(store.getTrackById(track.id!)?.durationMs, equals(180000));

      // Removing ephemeral track
      store.removeEphemeralTrack(track.id!);
      expect(store.getTrackById(track.id!), isNull);
      expect(store.getTrackByPath('/external/unindexed_track.flac'), isNull);
    });
  });
}
