import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
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

      // Create a mock/direct backend client with empty database
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final controller = LibraryController(
        backend: backend,
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

      // Sort in RAM without backend call
      await controller.setSortOption(TrackSortOption.title, ascending: true);
      expect(controller.tracks.first.title, equals('Bohemian Rhapsody'));

      controller.dispose();
      await backend.dispose();
      await db.close();
    });

    test('PlaylistsController resolves tracks directly from memory pointers (entry.track)', () async {
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final playlistsController = PlaylistsController(
        backend: backend,
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
      await backend.dispose();
      await db.close();
    });

    test('Reactivity: backend catalogUpdatedStream triggers controller reloading', () async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final store = LibraryStore.fromSnapshot(const CatalogSnapshot.empty());
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      // Insert tracks into database
      db.upsertTracks([
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

      // Emit catalogUpdated event via direct backend method
      await backend.deleteTrack(99999);

      // Wait a tick for event stream dispatch
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notified, isTrue);
      expect(controller.allTracks.length, equals(1));
      expect(controller.allTracks.first.title, equals('Live Track 1'));

      controller.dispose();
      await backend.dispose();
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
      final snapshot = _createSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final playlistsController = PlaylistsController(
        backend: backend,
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
      await backend.dispose();
      await db.close();
    });

    test('Zero-Jank: toggleLike does NOT emit catalogUpdated or trigger LibraryController reload', () async {
      final db = AppDatabase.inMemory();
      db.upsertTracks([
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
      final snapshot = db.getCatalogSnapshot();
      final trackId = snapshot.tracks.first.id;
      final store = LibraryStore.fromSnapshot(snapshot);
      final backend = DirectTachyonBackendClient(database: db);

      final libraryController = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      final playlistsController = PlaylistsController(
        backend: backend,
        store: store,
      );

      var catalogUpdateCount = 0;
      final sub = backend.catalogUpdatedStream.listen((_) {
        catalogUpdateCount++;
      });

      var libraryReloadCount = 0;
      libraryController.addListener(() {
        libraryReloadCount++;
      });

      // Track is not liked initially
      expect(playlistsController.isTrackLiked(trackId), isFalse);

      // 1. Toggle like (add to liked)
      final likedResult = await playlistsController.toggleLike(trackId);
      expect(likedResult, isTrue);
      expect(playlistsController.isTrackLiked(trackId), isTrue);
      expect(store.isTrackLiked(trackId), isTrue);
      expect(db.isTrackLiked(trackId), isTrue);

      // Wait a tick to guarantee any asynchronous stream events would have fired
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert that catalogUpdated was NOT emitted and LibraryController was NOT reloaded
      expect(catalogUpdateCount, equals(0));
      expect(libraryReloadCount, equals(0));

      // 2. Toggle like again (remove from liked)
      final unlikedResult = await playlistsController.toggleLike(trackId);
      expect(unlikedResult, isFalse);
      expect(playlistsController.isTrackLiked(trackId), isFalse);
      expect(store.isTrackLiked(trackId), isFalse);
      expect(db.isTrackLiked(trackId), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(catalogUpdateCount, equals(0));
      expect(libraryReloadCount, equals(0));

      await sub.cancel();
      playlistsController.dispose();
      libraryController.dispose();
      await backend.dispose();
      await db.close();
    });
  });
}
