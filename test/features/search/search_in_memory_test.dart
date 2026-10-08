import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'dart:async';

import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/shared/widgets/artist_card.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

CatalogSnapshot _createSampleSnapshot() {
  return const CatalogSnapshot(
    artists: [
      RawArtistDto(id: 1, name: 'Queen'),
      RawArtistDto(id: 2, name: 'David Bowie'),
    ],
    albums: [
      RawAlbumDto(id: 1, name: 'A Night at the Opera', year: 1975, artistId: 1),
      RawAlbumDto(id: 2, name: 'The Works', year: 1984, artistId: 1),
      RawAlbumDto(id: 3, name: 'The Rise and Fall of Ziggy Stardust', year: 1972, artistId: 2),
      RawAlbumDto(id: 4, name: 'Hot Space', year: 1982, artistId: 1),
    ],
    genres: [],
    tracks: [
      RawTrackDto(
        id: 1,
        filePath: '/music/queen/bohemian.mp3',
        title: 'Bohemian Rhapsody',
        durationMs: 354000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 1,
      ),
      RawTrackDto(
        id: 2,
        filePath: '/music/queen/radio_gaga.mp3',
        title: 'Radio Ga Ga',
        durationMs: 348000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 2,
      ),
      RawTrackDto(
        id: 3,
        filePath: '/music/bowie/starman.mp3',
        title: 'Starman',
        durationMs: 254000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 3,
      ),
      RawTrackDto(
        id: 4,
        filePath: '/music/queen_bowie/under_pressure.mp3',
        title: 'Under Pressure',
        durationMs: 248000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 4,
      ),
    ],
    playlists: [],
    playlistEntries: [],
    trackArtists: [
      TrackArtistPair(trackId: 1, artistId: 1),
      TrackArtistPair(trackId: 2, artistId: 1),
      TrackArtistPair(trackId: 3, artistId: 2),
      TrackArtistPair(trackId: 4, artistId: 1),
      TrackArtistPair(trackId: 4, artistId: 2),
    ],
    trackGenres: [],
  );
}

class _TestBackendClient extends DirectTachyonBackendClient {
  _TestBackendClient({required super.database, this.storeSupplier});

  final LibraryStore Function()? storeSupplier;
  List<PlaylistEntry>? openedItems;
  int? openedIndex;
  final StreamController<PlaybackState> _stateCtrl =
      StreamController<PlaybackState>.broadcast();

  @override
  Stream<PlaybackState> get playbackStateStream => _stateCtrl.stream;

  @override
  Future<void> open(
    List<int> trackIds, {
    int? index,
    bool play = true,
    bool shuffle = false,
  }) async {
    final tracks = database?.getTracksByIds(trackIds) ?? [];
    final trackMap = {for (final t in tracks) t.id: t};
    final store = storeSupplier?.call();
    int pos = 0;
    final resolvedItems = trackIds.map((id) {
      final t = trackMap[id] ?? store?.getTrackById(id);
      if (t != null) {
        return PlaylistEntry.forQueue(id: pos, position: pos++, track: t);
      }
      return null;
    }).whereType<PlaylistEntry>().toList();

    openedItems = resolvedItems;
    openedIndex = index ?? 0;
    final state = PlaybackState(
      playables: resolvedItems,
      index: index ?? 0,
      playing: true,
    );
    _stateCtrl.add(state);
  }

  @override
  Future<void> playQueue(
    List<int> trackIds, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) async {
    final dbTracks = database?.getTracksByIds(trackIds) ?? [];
    final trackMap = {for (final t in dbTracks) t.id: t};
    final store = storeSupplier?.call();
    int pos = 0;
    final items = trackIds
        .map((id) => trackMap[id] ?? store?.getTrackById(id))
        .whereType<Track>()
        .map((t) => PlaylistEntry.forQueue(id: pos, position: pos++, track: t))
        .toList();
    openedItems = items;
    openedIndex = startIndex ?? 0;
    final state = PlaybackState(
      playables: items,
      index: startIndex ?? 0,
      playing: play,
    );
    _stateCtrl.add(state);
  }

  @override
  Future<void> playTrack(int trackId, {bool play = true}) async {
    await playQueue([trackId], play: play);
  }

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late AppDatabase db;
  late _TestBackendClient backend;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late LibraryStore libraryStore;
  late LibraryController libraryController;
  late PlaybackController playbackController;
  late PlaylistsController playlistsController;
  late TachyonSearchController searchController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;

    db = AppDatabase.inMemory();
    libraryStore = LibraryStore.fromSnapshot(_createSampleSnapshot());
    backend = _TestBackendClient(
      database: db,
      storeSupplier: () => libraryStore,
    );

    settingsController = SettingsController(
      repository: settingsRepo,
      backend: backend,
    );
    libraryController = LibraryController(
      backend: backend,
      settingsRepository: settingsRepo,
      store: libraryStore,
    );
    playbackController = PlaybackController(
      backend: backend,
      settingsRepository: settingsRepo,
      libraryStoreSupplier: () => libraryStore,
    );
    playlistsController = PlaylistsController(
      backend: backend,
    );
    searchController = TachyonSearchController(
      storeSupplier: () => libraryController.store,
    );
  });

  tearDown(() async {
    settingsController.dispose();
    libraryController.dispose();
    playbackController.dispose();
    playlistsController.dispose();
    searchController.dispose();
    await backend.dispose();
    await db.close();
  });

  Widget buildApp(Widget child) {
    return MultiProvider(
      providers: [
        Provider<TachyonBackendClient>.value(value: backend),
        Provider<SettingsRepository>.value(value: settingsRepo),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
        ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('TachyonSearchController in-memory tests', () {
    test('searches tracks, albums, artists synchronously from LibraryStore in RAM', () {
      expect(searchController.isEmptyQuery, isTrue);
      expect(searchController.hasResults, isFalse);

      // Search for Queen
      searchController.onQueryChanged('Queen', debounce: false);

      expect(searchController.query, 'Queen');
      expect(searchController.isEmptyQuery, isFalse);
      expect(searchController.hasResults, isTrue);
      expect(searchController.matchedTracks.length, 3); // Bohemian Rhapsody, Radio Ga Ga, Under Pressure
      expect(searchController.matchedAlbums.length, 3); // A Night at the Opera, The Works, Hot Space
      expect(searchController.matchedArtists.length, 1); // Queen
      expect(searchController.matchedArtists.first.name, 'Queen');
    });

    test('searches by song title', () {
      searchController.onQueryChanged('Starman', debounce: false);

      expect(searchController.matchedTracks.length, 1);
      expect(searchController.matchedTracks.first.title, 'Starman');
      expect(searchController.matchedAlbums.isEmpty, isTrue);
      expect(searchController.matchedArtists.isEmpty, isTrue);
    });

    test('searches by album name', () {
      searchController.onQueryChanged('Ziggy', debounce: false);

      expect(searchController.matchedTracks.length, 1); // Starman is on Ziggy Stardust album
      expect(searchController.matchedAlbums.length, 1);
      expect(searchController.matchedAlbums.first.name, 'The Rise and Fall of Ziggy Stardust');
    });

    test('category filtering properly adjusts hasResults', () {
      searchController.onQueryChanged('Starman', debounce: false);

      // In "all", hasResults is true because tracks matched
      searchController.setCategory(SearchFilterCategory.all);
      expect(searchController.hasResults, isTrue);

      // In "tracks", hasResults is true
      searchController.setCategory(SearchFilterCategory.tracks);
      expect(searchController.hasResults, isTrue);

      // In "albums", hasResults is false because no album is named "Starman"
      searchController.setCategory(SearchFilterCategory.albums);
      expect(searchController.hasResults, isFalse);

      // In "artists", hasResults is false because no artist is named "Starman"
      searchController.setCategory(SearchFilterCategory.artists);
      expect(searchController.hasResults, isFalse);
    });

    test('clear resets query and results', () {
      searchController.onQueryChanged('Queen', debounce: false);
      expect(searchController.hasResults, isTrue);

      searchController.clear();
      expect(searchController.query, '');
      expect(searchController.isEmptyQuery, isTrue);
      expect(searchController.hasResults, isFalse);
      expect(searchController.matchedTracks.isEmpty, isTrue);
      expect(searchController.matchedAlbums.isEmpty, isTrue);
      expect(searchController.matchedArtists.isEmpty, isTrue);
    });

    test('storeSupplier dynamically reflects library updates in RAM', () {
      searchController.onQueryChanged('Radio', debounce: false);
      expect(searchController.matchedTracks.length, 1);

      // Update the library store with a new snapshot that doesn't have Radio Ga Ga
      const newSnapshot = CatalogSnapshot(
        tracks: [
          RawTrackDto(
            id: 1,
            title: 'Bohemian Rhapsody',
            filePath: '/music/queen/bohemian.mp3',
            durationMs: 354000,
            fileSize: 5000000,
            modifiedAt: 1000,
            albumId: 1,
          ),
        ],
        albums: [RawAlbumDto(id: 1, name: 'A Night at the Opera', artistId: 1)],
        artists: [RawArtistDto(id: 1, name: 'Queen')],
        genres: [],
        playlists: [],
        playlistEntries: [],
        trackArtists: [TrackArtistPair(trackId: 1, artistId: 1)],
        trackGenres: [],
      );

      libraryController.store.hydrateFromSnapshot(newSnapshot);

      // Searching again gets results from updated RAM store
      searchController.onQueryChanged('Radio', debounce: false);
      expect(searchController.matchedTracks.isEmpty, isTrue);

      searchController.onQueryChanged('Bohemian', debounce: false);
      expect(searchController.matchedTracks.length, 1);
      expect(searchController.matchedTracks.first.title, 'Bohemian Rhapsody');
    });
  });

  group('SearchScreen widget interaction tests', () {
    testWidgets('shows empty state initially, typing displays in-memory results', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      // Initially search hint / placeholder is shown
      expect(find.text('Search by track, artist, album, genre...'), findsWidgets);
      expect(find.byType(TrackTile), findsNothing);

      // Type "Queen" in search TextField
      await tester.enterText(find.byType(TextField), 'Queen');
      // Wait for debounce timer (150ms)
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Results for Queen should appear
      expect(find.byType(TrackTile), findsNWidgets(3));
      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Radio Ga Ga'), findsOneWidget);
      expect(find.text('Under Pressure'), findsOneWidget);

      // Albums should appear
      expect(find.byType(AlbumCard), findsNWidgets(3));
      expect(find.text('A Night at the Opera'), findsOneWidget);

      // Artists should appear
      expect(find.byType(ArtistCard), findsOneWidget);
    });

    testWidgets('category filter chips filter results and show no results when appropriate', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Starman');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Starman track is found in "All"
      expect(find.widgetWithText(TrackTile, 'Starman'), findsOneWidget);
      expect(find.byType(TrackTile), findsOneWidget);
      expect(find.byType(AlbumCard), findsNothing);
      expect(find.byType(ArtistCard), findsNothing);

      // Tap "Tracks" chip
      await tester.tap(find.widgetWithText(FilterChip, 'Tracks'));
      await tester.pumpAndSettle();

      expect(find.byType(TrackTile), findsOneWidget);
      expect(find.widgetWithText(TrackTile, 'Starman'), findsOneWidget);

      // Tap "Albums" chip - no albums named Starman exist
      await tester.tap(find.widgetWithText(FilterChip, 'Albums'));
      await tester.pumpAndSettle();

      expect(find.byType(TrackTile), findsNothing);
      expect(find.byType(AlbumCard), findsNothing);
      expect(find.text('No results found'), findsOneWidget);

      // Tap "All" chip again - results return
      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();

      expect(find.byType(TrackTile), findsOneWidget);
      expect(find.widgetWithText(TrackTile, 'Starman'), findsOneWidget);
    });

    testWidgets('clear button clears search text and results', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Queen');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(TrackTile), findsNWidgets(3));

      // Clear button should be visible
      final clearButton = find.byIcon(Icons.clear_rounded);
      expect(clearButton, findsOneWidget);

      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      // Results should be cleared and search placeholder restored
      expect(find.byType(TrackTile), findsNothing);
      expect(find.byType(AlbumCard), findsNothing);
      expect(find.byType(ArtistCard), findsNothing);
      expect(find.text('Search by track, artist, album, genre...'), findsWidgets);
    });

    testWidgets('tapping track tile triggers playback with context', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ga Ga');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Radio Ga Ga'), findsOneWidget);

      await tester.tap(find.text('Radio Ga Ga'));
      await tester.pumpAndSettle();

      expect(backend.openedItems?.firstOrNull?.track?.title, 'Radio Ga Ga');
      expect(playbackController.currentTrack?.title, 'Radio Ga Ga');
    });

    testWidgets('tapping album card navigates to AlbumDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Night at the');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(AlbumCard), findsOneWidget);

      await tester.tap(find.byType(AlbumCard));
      await tester.pumpAndSettle();

      expect(find.byType(AlbumDetailScreen), findsOneWidget);
      expect(find.text('A Night at the Opera'), findsWidgets);
    });

    testWidgets('tapping artist card navigates to ArtistDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Bowie');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistCard), findsOneWidget);

      await tester.tap(find.byType(ArtistCard));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);
      expect(find.text('David Bowie'), findsWidgets);
    });
  });
}
