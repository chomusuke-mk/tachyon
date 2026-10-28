import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

CatalogSnapshot _createSortingTestSnapshot() {
  final artists = [
    const RawArtistDto(id: 1, name: 'The Beatles'),
    const RawArtistDto(id: 2, name: 'Pink Floyd'),
    const RawArtistDto(id: 3, name: 'Queen'),
    const RawArtistDto(id: 4, name: 'ABBA'),
  ];

  final albums = [
    // 2 tracks, year 1969, artist The Beatles
    const RawAlbumDto(id: 10, name: 'Abbey Road', year: 1969, artistId: 1),
    // 1 track, year 1973, artist Pink Floyd
    const RawAlbumDto(
      id: 20,
      name: 'The Dark Side of the Moon',
      year: 1973,
      artistId: 2,
    ),
    // 3 tracks, year 1975, artist Queen
    const RawAlbumDto(
      id: 30,
      name: 'A Night at the Opera',
      year: 1975,
      artistId: 3,
    ),
    // 0 tracks, year null, artist null
    const RawAlbumDto(id: 40, name: 'Unknown Compilation', year: null, artistId: null),
  ];

  final tracks = [
    const RawTrackDto(
      id: 1001,
      filePath: '/music/beatles/come_together.mp3',
      title: 'Come Together',
      trackNumber: 1,
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
      durationMs: 182000,
      fileSize: 4300000,
      modifiedAt: 1010,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1003,
      filePath: '/music/pink_floyd/time.mp3',
      title: 'Time',
      trackNumber: 1,
      durationMs: 425000,
      fileSize: 10200000,
      modifiedAt: 2000,
      albumId: 20,
    ),
    const RawTrackDto(
      id: 1004,
      filePath: '/music/queen/bohemian_rhapsody.mp3',
      title: 'Bohemian Rhapsody',
      trackNumber: 1,
      durationMs: 354000,
      fileSize: 8500000,
      modifiedAt: 3000,
      albumId: 30,
    ),
    const RawTrackDto(
      id: 1005,
      filePath: '/music/queen/love_of_my_life.mp3',
      title: 'Love of My Life',
      trackNumber: 2,
      durationMs: 219000,
      fileSize: 5200000,
      modifiedAt: 3010,
      albumId: 30,
    ),
    const RawTrackDto(
      id: 1006,
      filePath: '/music/queen/youre_my_best_friend.mp3',
      title: 'You\'re My Best Friend',
      trackNumber: 3,
      durationMs: 172000,
      fileSize: 4100000,
      modifiedAt: 3020,
      albumId: 30,
    ),
  ];

  final trackArtists = [
    const TrackArtistPair(trackId: 1001, artistId: 1),
    const TrackArtistPair(trackId: 1002, artistId: 1),
    const TrackArtistPair(trackId: 1003, artistId: 2),
    const TrackArtistPair(trackId: 1004, artistId: 3),
    const TrackArtistPair(trackId: 1005, artistId: 3),
    const TrackArtistPair(trackId: 1006, artistId: 3),
  ];

  return CatalogSnapshot(
    artists: artists,
    albums: albums,
    tracks: tracks,
    genres: const [],
    playlists: const [],
    playlistEntries: const [],
    trackArtists: trackArtists,
    trackGenres: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryStore Album Sorting', () {
    late LibraryStore store;

    setUp(() {
      store = LibraryStore.fromSnapshot(_createSortingTestSnapshot());
    });

    test('sortAlbums by title (ascending & descending)', () {
      final asc = store.sortAlbums(store.albums, AlbumSortOption.title, ascending: true);
      expect(asc.map((a) => a.name).toList(), [
        'A Night at the Opera',
        'Abbey Road',
        'The Dark Side of the Moon',
        'Unknown Compilation',
      ]);

      final desc = store.sortAlbums(store.albums, AlbumSortOption.title, ascending: false);
      expect(desc.map((a) => a.name).toList(), [
        'Unknown Compilation',
        'The Dark Side of the Moon',
        'Abbey Road',
        'A Night at the Opera',
      ]);
    });

    test('sortAlbums by artist (ascending & descending)', () {
      final asc = store.sortAlbums(store.albums, AlbumSortOption.artist, ascending: true);
      // Pink Floyd, Queen, The Beatles, Unknown (empty artist sorts first or last depending on string)
      expect(asc[0].artist?.name ?? '', equals(''));
      expect(asc[1].artist?.name, equals('Pink Floyd'));
      expect(asc[2].artist?.name, equals('Queen'));
      expect(asc[3].artist?.name, equals('The Beatles'));

      final desc = store.sortAlbums(store.albums, AlbumSortOption.artist, ascending: false);
      expect(desc[0].artist?.name, equals('The Beatles'));
      expect(desc[1].artist?.name, equals('Queen'));
      expect(desc[2].artist?.name, equals('Pink Floyd'));
      expect(desc[3].artist?.name ?? '', equals(''));
    });

    test('sortAlbums by year (ascending & descending)', () {
      final asc = store.sortAlbums(store.albums, AlbumSortOption.year, ascending: true);
      // 0 (unknown) -> 1969 -> 1973 -> 1975
      expect(asc.map((a) => a.year).toList(), [null, 1969, 1973, 1975]);

      final desc = store.sortAlbums(store.albums, AlbumSortOption.year, ascending: false);
      expect(desc.map((a) => a.year).toList(), [1975, 1973, 1969, null]);
    });

    test('sortAlbums by trackCount (ascending & descending)', () {
      final asc = store.sortAlbums(store.albums, AlbumSortOption.trackCount, ascending: true);
      // 0 -> 1 -> 2 -> 3
      expect(asc.map((a) => a.trackCount).toList(), [0, 1, 2, 3]);

      final desc = store.sortAlbums(store.albums, AlbumSortOption.trackCount, ascending: false);
      expect(desc.map((a) => a.trackCount).toList(), [3, 2, 1, 0]);
    });
  });

  group('LibraryStore Artist Sorting', () {
    late LibraryStore store;

    setUp(() {
      store = LibraryStore.fromSnapshot(_createSortingTestSnapshot());
    });

    test('sortArtists by name (ascending & descending)', () {
      final asc = store.sortArtists(store.artists, ArtistSortOption.name, ascending: true);
      expect(asc.map((a) => a.name).toList(), [
        'ABBA',
        'Pink Floyd',
        'Queen',
        'The Beatles',
      ]);

      final desc = store.sortArtists(store.artists, ArtistSortOption.name, ascending: false);
      expect(desc.map((a) => a.name).toList(), [
        'The Beatles',
        'Queen',
        'Pink Floyd',
        'ABBA',
      ]);
    });

    test('sortArtists by albumCount (ascending & descending)', () {
      // ABBA has 0 albums, Pink Floyd has 1, Queen has 1, Beatles has 1
      final asc = store.sortArtists(store.artists, ArtistSortOption.albums, ascending: true);
      expect(asc[0].name, equals('ABBA'));
      expect(asc[0].albumCount, equals(0));

      final desc = store.sortArtists(store.artists, ArtistSortOption.albums, ascending: false);
      expect(desc.last.name, equals('ABBA'));
      expect(desc.last.albumCount, equals(0));
    });

    test('sortArtists by trackCount (ascending & descending)', () {
      // ABBA: 0 tracks, Pink Floyd: 1 track, Beatles: 2 tracks, Queen: 3 tracks
      final asc = store.sortArtists(store.artists, ArtistSortOption.tracks, ascending: true);
      expect(asc.map((a) => a.name).toList(), [
        'ABBA',
        'Pink Floyd',
        'The Beatles',
        'Queen',
      ]);

      final desc = store.sortArtists(store.artists, ArtistSortOption.tracks, ascending: false);
      expect(desc.map((a) => a.name).toList(), [
        'Queen',
        'The Beatles',
        'Pink Floyd',
        'ABBA',
      ]);
    });
  });

  group('SettingsRepository Sort Persistence', () {
    test('Persists and loads AlbumSortOption and ArtistSortOption correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(prefs);

      // Default values
      expect(repo.getAlbumSortOption(), equals(AlbumSortOption.title));
      expect(repo.getAlbumSortAscending(), isTrue);
      expect(repo.getArtistSortOption(), equals(ArtistSortOption.name));
      expect(repo.getArtistSortAscending(), isTrue);

      // Set album sorting
      await repo.setAlbumSortOption(AlbumSortOption.year);
      await repo.setAlbumSortAscending(false);
      expect(repo.getAlbumSortOption(), equals(AlbumSortOption.year));
      expect(repo.getAlbumSortAscending(), isFalse);

      // Set artist sorting
      await repo.setArtistSortOption(ArtistSortOption.tracks);
      await repo.setArtistSortAscending(false);
      expect(repo.getArtistSortOption(), equals(ArtistSortOption.tracks));
      expect(repo.getArtistSortAscending(), isFalse);

      // Verify app settings model integration
      final settings = repo.getSettings();
      expect(settings.albumSortOption, equals(AlbumSortOption.year));
      expect(settings.albumSortAscending, isFalse);
      expect(settings.artistSortOption, equals(ArtistSortOption.tracks));
      expect(settings.artistSortAscending, isFalse);
    });
  });

  group('LibraryController Sorting & Persistence Integration', () {
    late SharedPreferences prefs;
    late SettingsRepository settingsRepository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settingsRepository = SettingsRepository(prefs);
    });

    test('Controller initializes sorted lists from store and preserves graph pointers', () async {
      final store = LibraryStore.fromSnapshot(_createSortingTestSnapshot());
      final controller = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      // Default sorting: albums by title asc, artists by name asc
      expect(controller.albumSortOption, equals(AlbumSortOption.title));
      expect(controller.albumSortAscending, isTrue);
      expect(controller.artistSortOption, equals(ArtistSortOption.name));
      expect(controller.artistSortAscending, isTrue);

      expect(controller.albums.first.name, equals('A Night at the Opera'));
      expect(controller.artists.first.name, equals('ABBA'));

      // 100% Direct Pointer Identity Guarantee
      expect(
        identical(controller.albums.first, store.getAlbumById(30)),
        isTrue,
      );
      expect(
        identical(controller.artists.first, store.getArtistById(4)),
        isTrue,
      );

      controller.dispose();
    });

    test('Changing album sort option updates state, notifies listeners and persists', () async {
      final store = LibraryStore.fromSnapshot(_createSortingTestSnapshot());
      final controller = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Change option to year
      await controller.setAlbumSortOption(AlbumSortOption.year);
      expect(controller.albumSortOption, equals(AlbumSortOption.year));
      expect(controller.albumSortAscending, isTrue);
      expect(controller.albums.last.name, equals('A Night at the Opera'));
      expect(notifyCount, equals(1));
      expect(settingsRepository.getAlbumSortOption(), equals(AlbumSortOption.year));
      expect(settingsRepository.getAlbumSortAscending(), isTrue);

      // Toggle ascending by passing the same option
      await controller.setAlbumSortOption(AlbumSortOption.year);
      expect(controller.albumSortAscending, isFalse);
      expect(controller.albums.first.name, equals('A Night at the Opera'));
      expect(notifyCount, equals(2));
      expect(settingsRepository.getAlbumSortAscending(), isFalse);

      controller.dispose();
    });

    test('Changing artist sort option updates state, notifies listeners and persists', () async {
      final store = LibraryStore.fromSnapshot(_createSortingTestSnapshot());
      final controller = LibraryController(
        settingsRepository: settingsRepository,
        store: store,
      );

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Change option to tracks
      await controller.setArtistSortOption(ArtistSortOption.tracks);
      expect(controller.artistSortOption, equals(ArtistSortOption.tracks));
      expect(controller.artistSortAscending, isTrue);
      expect(controller.artists.first.name, equals('ABBA'));
      expect(controller.artists.last.name, equals('Queen'));
      expect(notifyCount, equals(1));
      expect(settingsRepository.getArtistSortOption(), equals(ArtistSortOption.tracks));

      // Toggle direction by selecting tracks again
      await controller.setArtistSortOption(ArtistSortOption.tracks);
      expect(controller.artistSortAscending, isFalse);
      expect(controller.artists.first.name, equals('Queen'));
      expect(controller.artists.last.name, equals('ABBA'));
      expect(notifyCount, equals(2));
      expect(settingsRepository.getArtistSortAscending(), isFalse);

      controller.dispose();
    });
  });
}
