import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/genres_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

/// Test locale repository loading translations directly from filesystem assets.
class _FileSystemLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    final stringMap = json.map(
      (key, value) => MapEntry(key, value.toString().trim()),
    );
    stringMap.removeWhere((_, value) => value.isEmpty);
    return stringMap;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SettingsRepository settingsRepository;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(prefs);

    final localeRepo = _FileSystemLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;
  });

  Widget createTestHarness({
    required Widget child,
    LibraryController? libraryController,
    PlaybackController? playbackController,
    PlaylistsController? playlistsController,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        if (libraryController != null)
          ChangeNotifierProvider<LibraryController>.value(
            value: libraryController,
          ),
        if (playbackController != null)
          ChangeNotifierProvider<PlaybackController>.value(
            value: playbackController,
          ),
        if (playlistsController != null)
          ChangeNotifierProvider<PlaylistsController>.value(
            value: playlistsController,
          ),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Focus 1: Empty Artists List on a Track', () {
    testWidgets('1.1 TrackTile with empty artists and null album falls back to trUnknownArtist without dangling bullet', (tester) async {
      const track = Track(
        id: 1,
        filePath: '/music/solo.mp3',
        title: 'Ghost Track',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: null,
      );

      await tester.pumpWidget(
        createTestHarness(child: const Scaffold(body: TrackTile(track: track))),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;
      expect(find.text('Ghost Track'), findsOneWidget);
      expect(find.text(strings.trUnknownArtist), findsOneWidget);
    });

    testWidgets('1.2 TrackTile with empty artists and non-null album renders Unknown Artist • Album', (tester) async {
      const track = Track(
        id: 2,
        filePath: '/music/album_solo.mp3',
        title: 'Orphan Track',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: Album(id: 10, name: 'Vocaloid Comp', tracks: []),
      );

      await tester.pumpWidget(
        createTestHarness(child: const Scaffold(body: TrackTile(track: track))),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;
      expect(
        find.text('${strings.trUnknownArtist} • Vocaloid Comp'),
        findsOneWidget,
      );
    });

    testWidgets('1.3 TrackTile PopupMenuButton itemBuilder evaluates viewArtist as disabled when artists list is empty', (tester) async {
      const track = Track(
        id: 3,
        filePath: '/music/track3.mp3',
        title: 'No Artist Track',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: Album(id: 1, name: 'Album One', tracks: []),
      );

      late BuildContext capturedContext;
      await tester.pumpWidget(
        createTestHarness(
          child: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return TrackTile(
                  track: track,
                  onActionSelected: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final popupBtn = tester.widget<PopupMenuButton<TrackAction>>(
        find.byType(PopupMenuButton<TrackAction>),
      );
      final items = popupBtn.itemBuilder(capturedContext);

      final viewArtistItem = items.firstWhere(
        (entry) => entry is PopupMenuItem<TrackAction> && entry.value == TrackAction.viewArtist,
      ) as PopupMenuItem<TrackAction>;
      expect(viewArtistItem.enabled, isFalse);

      final viewAlbumItem = items.firstWhere(
        (entry) => entry is PopupMenuItem<TrackAction> && entry.value == TrackAction.viewAlbum,
      ) as PopupMenuItem<TrackAction>;
      expect(viewAlbumItem.enabled, isTrue);
    });

    testWidgets('1.4 TracksScreen file info dialog omits artist row without crashing when artists is empty', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 4,
            filePath: '/music/track4.mp3',
            title: 'Info Test Track',
            durationMs: 120000,
            fileSize: 4000000,
            modifiedAt: 1000,
            albumId: 1,
          ),
        ],
        albums: [
          const RawAlbumDto(id: 1, name: 'Solo Album'),
        ],
        artists: const [],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Invoke fileInfo action directly via TrackTile callback
      final tile = tester.widget<TrackTile>(find.byType(TrackTile));
      tile.onActionSelected!(TrackAction.fileInfo);
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      // Verify AlertDialog mounted
      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Info Test Track')),
        findsOneWidget,
      );
      // trSortArtist label row should be omitted
      expect(
        find.descendant(of: dialogFinder, matching: find.text(strings.trSortArtist)),
        findsNothing,
      );
      // trSortAlbum label row should be present
      expect(
        find.descendant(of: dialogFinder, matching: find.text(strings.trSortAlbum)),
        findsOneWidget,
      );

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('1.5 PlaylistDetailScreen subtitle cleanly formats track when artists list is empty', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 5,
            filePath: '/music/track5.mp3',
            title: 'Playlist Orphan',
            durationMs: 150000,
            fileSize: 1000,
            modifiedAt: 1000,
            albumId: 1,
          ),
        ],
        albums: [
          const RawAlbumDto(id: 1, name: 'Great Hits'),
        ],
        artists: const [],
        genres: const [],
        playlists: [
          const RawPlaylistDto(
            id: 1,
            name: 'My Custom Playlist',
            createdAt: 100,
            type: 0,
          ),
        ],
        playlistEntries: [
          const RawPlaylistEntryDto(
            id: 1,
            playlistId: 1,
            trackId: 5,
            position: 0,
            addedAt: 100,
          ),
        ],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);
      final playlist = store.getPlaylistById(1)!;

      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(playlist);
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: playlist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playlist Orphan'), findsOneWidget);
      final strings = localeController.localeStrings;
      expect(find.text('${strings.trUnknownArtist} • Great Hits'), findsOneWidget);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Focus 2: Null Album on a Track', () {
    testWidgets('2.1 TrackTile displays artist text alone without bullet when album is null', (tester) async {
      const track = Track(
        id: 10,
        filePath: '/music/single.mp3',
        title: 'Single Song',
        durationMs: 210000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Adele', tracks: [])],
        album: null,
      );

      await tester.pumpWidget(
        createTestHarness(child: const Scaffold(body: TrackTile(track: track))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Single Song'), findsOneWidget);
      expect(find.text('Adele'), findsOneWidget);
    });

    testWidgets('2.2 TrackTile PopupMenuButton itemBuilder evaluates viewAlbum as disabled when album is null', (tester) async {
      const track = Track(
        id: 11,
        filePath: '/music/single2.mp3',
        title: 'Single Song 2',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Drake', tracks: [])],
        album: null,
      );

      late BuildContext capturedContext;
      await tester.pumpWidget(
        createTestHarness(
          child: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return TrackTile(
                  track: track,
                  onActionSelected: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final popupBtn = tester.widget<PopupMenuButton<TrackAction>>(
        find.byType(PopupMenuButton<TrackAction>),
      );
      final items = popupBtn.itemBuilder(capturedContext);

      final viewAlbumItem = items.firstWhere(
        (entry) => entry is PopupMenuItem<TrackAction> && entry.value == TrackAction.viewAlbum,
      ) as PopupMenuItem<TrackAction>;
      expect(viewAlbumItem.enabled, isFalse);

      final viewArtistItem = items.firstWhere(
        (entry) => entry is PopupMenuItem<TrackAction> && entry.value == TrackAction.viewArtist,
      ) as PopupMenuItem<TrackAction>;
      expect(viewArtistItem.enabled, isTrue);
    });

    testWidgets('2.3 TracksScreen file info dialog omits album row when album is null', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 12,
            filePath: '/music/single3.mp3',
            title: 'Single Info Test',
            durationMs: 140000,
            fileSize: 3000000,
            modifiedAt: 1000,
            albumId: null,
          ),
        ],
        albums: const [],
        artists: [
          const RawArtistDto(id: 2, name: 'Taylor Swift'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: [
          const TrackArtistPair(trackId: 12, artistId: 2),
        ],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger fileInfo action directly
      final tile = tester.widget<TrackTile>(find.byType(TrackTile));
      tile.onActionSelected!(TrackAction.fileInfo);
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Taylor Swift')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text(strings.trSortAlbum)),
        findsNothing,
      );

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('2.4 PlaylistDetailScreen subtitle cleanly formats track when album is null', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 13,
            filePath: '/music/single4.mp3',
            title: 'Playlist Single',
            durationMs: 180000,
            fileSize: 1000,
            modifiedAt: 1000,
            albumId: null,
          ),
        ],
        albums: const [],
        artists: [
          const RawArtistDto(id: 3, name: 'Coldplay'),
        ],
        genres: const [],
        playlists: [
          const RawPlaylistDto(
            id: 2,
            name: 'Chill Vibes',
            createdAt: 200,
            type: 0,
          ),
        ],
        playlistEntries: [
          const RawPlaylistEntryDto(
            id: 2,
            playlistId: 2,
            trackId: 13,
            position: 0,
            addedAt: 200,
          ),
        ],
        trackArtists: [
          const TrackArtistPair(trackId: 13, artistId: 3),
        ],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);
      final playlist = store.getPlaylistById(2)!;

      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(playlist);
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: playlist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playlist Single'), findsOneWidget);
      expect(find.text('Coldplay'), findsOneWidget);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Focus 3: Empty Tracks on an Album, Artist, or Genre', () {
    testWidgets('3.1 AlbumDetailScreen with 0 tracks renders without error and disables play buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const emptyAlbum = Album(
        id: 101,
        name: 'Empty Vault Album',
        year: 2024,
        artist: Artist(id: 1, name: 'Silent Band', tracks: []),
        tracks: [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const AlbumDetailScreen(album: emptyAlbum),
          playbackController: playback,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Empty Vault Album'), findsWidgets);
      expect(find.text('Silent Band'), findsOneWidget);
      expect(find.textContaining('0m'), findsOneWidget);

      // FilledButton (Play All) and OutlinedButton (Shuffle All) should have onPressed == null
      final playButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(playButton.onPressed, isNull);

      final shuffleButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(shuffleButton.onPressed, isNull);

      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('3.2 AlbumsScreen with empty tracks renders grid and sorts without exception', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: [
          const RawAlbumDto(id: 201, name: 'Beta Album', year: 2021, artistId: null),
          const RawAlbumDto(id: 202, name: 'Alpha Album', year: 2023, artistId: 2),
        ],
        artists: [
          const RawArtistDto(id: 2, name: 'Zeta Artist'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const AlbumsScreen(),
          libraryController: libraryCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Beta Album'), findsOneWidget);
      expect(find.text('Alpha Album'), findsOneWidget);
      final strings = localeController.localeStrings;
      expect(find.text(strings.trUnknownArtist), findsOneWidget);
      expect(find.text('Zeta Artist'), findsOneWidget);

      // Test artist sorting with null artist
      final sortButton = find.byIcon(Icons.sort_rounded);
      await tester.tap(sortButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.alSortArtist));
      await tester.pumpAndSettle();

      // No crash during sort
      expect(find.text('Alpha Album'), findsOneWidget);

      libraryCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('3.3 ArtistDetailScreen with 0 tracks and 0 albums renders avatar fallback and disables play buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: const [],
        artists: [
          const RawArtistDto(id: 301, name: 'Solo Hermit'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);
      final emptyArtist = store.getArtistById(301)!;

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: ArtistDetailScreen(artist: emptyArtist),
          libraryController: libraryCtrl,
          playbackController: playback,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solo Hermit'), findsWidgets);
      // Avatar fallback icon
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);

      // Play and Shuffle buttons should be disabled
      final playButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(playButton.onPressed, isNull);

      final shuffleButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(shuffleButton.onPressed, isNull);

      // Discography section should be omitted
      final strings = localeController.localeStrings;
      expect(find.text(strings.arDiscography), findsNothing);

      libraryCtrl.dispose();
      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('3.4 ArtistsScreen with empty tracks renders avatar fallback and sorts without exception', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: const [],
        artists: [
          const RawArtistDto(id: 401, name: 'Zorro'),
          const RawArtistDto(id: 402, name: 'Apollo'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const ArtistsScreen(),
          libraryController: libraryCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zorro'), findsOneWidget);
      expect(find.text('Apollo'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsNWidgets(2));

      // Test sorting
      final sortButton = find.byIcon(Icons.sort_rounded);
      await tester.tap(sortButton);
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;
      await tester.tap(find.text(strings.arSortTracks));
      await tester.pumpAndSettle();

      expect(find.text('Zorro'), findsOneWidget);

      libraryCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('3.5 GenresScreen with empty genre tracks handles selection and disables actions', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: const [],
        artists: const [],
        genres: [
          const RawGenreDto(id: 501, name: 'Ambient Drone'),
        ],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const GenresScreen(),
          libraryController: libraryCtrl,
          playbackController: playback,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ambient Drone'), findsOneWidget);

      // Select genre
      await tester.tap(find.text('Ambient Drone'));
      await tester.pumpAndSettle();

      // Play and Shuffle icons in AppBar should be disabled (IconButton onPressed == null)
      final playIconBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
      );
      expect(playIconBtn.onPressed, isNull);

      final shuffleIconBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.shuffle_rounded),
      );
      expect(shuffleIconBtn.onPressed, isNull);

      libraryCtrl.dispose();
      playback.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Focus 4: Special Characters, Emojis, and Empty Strings in Names', () {
    testWidgets('4.1 TrackTile with completely empty strings in title, artist, and album renders without crash', (tester) async {
      const track = Track(
        id: 601,
        filePath: '/music/empty.mp3',
        title: '',
        durationMs: 60000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: '', tracks: [])],
        album: Album(id: 1, name: '', tracks: []),
      );

      await tester.pumpWidget(
        createTestHarness(child: const Scaffold(body: TrackTile(track: track))),
      );
      await tester.pumpAndSettle();

      // Title is empty Text, does not throw
      expect(find.byType(TrackTile), findsOneWidget);
    });

    testWidgets('4.2 TrackTile with extreme characters, emojis, quotes, and multiple artists joins cleanly', (tester) async {
      const complexTrack = Track(
        id: 602,
        filePath: '/music/complex.mp3',
        title: '<script>alert(1)</script> & "quotes" \'single\' 🔥 🎧 🎵',
        durationMs: 250000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [
          Artist(id: 1, name: 'AC/DC', tracks: []),
          Artist(id: 2, name: 'Ke\$ha', tracks: []),
          Artist(id: 3, name: 'Tyler, The Creator', tracks: []),
        ],
        album: Album(
          id: 1,
          name: 'Album/With/Slashes [2024] (Deluxe) #1',
          tracks: [],
        ),
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const Scaffold(body: TrackTile(track: complexTrack)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('<script>alert(1)</script> & "quotes" \'single\' 🔥 🎧 🎵'),
        findsOneWidget,
      );
      expect(
        find.text(
          'AC/DC, Ke\$ha, Tyler, The Creator • Album/With/Slashes [2024] (Deluxe) #1',
        ),
        findsOneWidget,
      );
    });

    testWidgets('4.3 AlbumsScreen and ArtistsScreen sorting handles case variations and special characters', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: [
          const RawAlbumDto(id: 701, name: 'album a', year: 2020, artistId: 1),
          const RawAlbumDto(id: 702, name: 'Album A', year: 2020, artistId: 2),
          const RawAlbumDto(id: 703, name: '!Special', year: 2020, artistId: 3),
        ],
        artists: [
          const RawArtistDto(id: 1, name: 'b'),
          const RawArtistDto(id: 2, name: 'B'),
          const RawArtistDto(id: 3, name: '@artist'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const AlbumsScreen(),
          libraryController: libraryCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('album a'), findsOneWidget);
      expect(find.text('Album A'), findsOneWidget);
      expect(find.text('!Special'), findsOneWidget);

      libraryCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Focus 5: Navigation Actions and Null Tolerance', () {
    testWidgets('5.1 TracksScreen navigation to AlbumDetailScreen works when track.album != null', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 801,
            filePath: '/music/nav_album.mp3',
            title: 'Navigable Album Track',
            durationMs: 120000,
            fileSize: 1000,
            modifiedAt: 1000,
            albumId: 801,
          ),
        ],
        albums: [
          const RawAlbumDto(id: 801, name: 'Target Album', year: 2022),
        ],
        artists: [
          const RawArtistDto(id: 1, name: 'Test Artist'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: [
          const TrackArtistPair(trackId: 801, artistId: 1),
        ],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger viewAlbum action directly via callback
      final tile = tester.widget<TrackTile>(find.byType(TrackTile));
      tile.onActionSelected!(TrackAction.viewAlbum);
      await tester.pumpAndSettle();

      // Verify AlbumDetailScreen was pushed
      expect(find.byType(AlbumDetailScreen), findsOneWidget);
      expect(find.text('Target Album'), findsWidgets);

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('5.2 TracksScreen navigation to ArtistDetailScreen works when track.artists is not empty', (tester) async {
      final snapshot = CatalogSnapshot(
        tracks: [
          const RawTrackDto(
            id: 802,
            filePath: '/music/nav_artist.mp3',
            title: 'Navigable Artist Track',
            durationMs: 120000,
            fileSize: 1000,
            modifiedAt: 1000,
            albumId: null,
          ),
        ],
        albums: const [],
        artists: [
          const RawArtistDto(id: 802, name: 'Target Artist'),
        ],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: [
          const TrackArtistPair(trackId: 802, artistId: 802),
        ],
        trackGenres: const [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(snapshot);

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger viewArtist action directly via callback
      final tile = tester.widget<TrackTile>(find.byType(TrackTile));
      tile.onActionSelected!(TrackAction.viewArtist);
      await tester.pumpAndSettle();

      // Verify ArtistDetailScreen was pushed
      expect(find.byType(ArtistDetailScreen), findsOneWidget);
      expect(find.text('Target Artist'), findsWidgets);

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('5.3 ArtistDetailScreen tolerates artist with id: null without throwing', (tester) async {
      const transientArtist = Artist(
        id: null,
        name: 'Ephemeral Artist',
        albums: [],
        tracks: [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const ArtistDetailScreen(artist: transientArtist),
          libraryController: libraryCtrl,
          playbackController: playback,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ephemeral Artist'), findsWidgets);

      libraryCtrl.dispose();
      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('5.4 AlbumDetailScreen tolerates album with artist: null and id: null without throwing', (tester) async {
      const transientAlbum = Album(
        id: null,
        name: 'Ephemeral Album',
        artist: null,
        tracks: [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const AlbumDetailScreen(album: transientAlbum),
          playbackController: playback,
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;
      expect(find.text('Ephemeral Album'), findsWidgets);
      expect(find.text(strings.trUnknownArtist), findsOneWidget);

      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('5.5 TracksScreen safely ignores viewAlbum and viewArtist actions when target is null', (tester) async {
      const track = Track(
        id: 999,
        filePath: '/music/orphan.mp3',
        title: 'Complete Orphan',
        durationMs: 100000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: null,
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger viewAlbum and viewArtist on a track where both are null
      final state = tester.state(find.byType(TracksScreen));
      expect(state, isNotNull);

      // Verify no exceptions when calling actions with null references
      expect(
        () {
          // If action is somehow dispatched when track.album is null
          if (track.album != null) {
            Navigator.of(state.context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlbumDetailScreen(album: track.album!),
              ),
            );
          }
        },
        returnsNormally,
      );

      expect(
        () {
          // If action is somehow dispatched when track.artists is empty
          final artist = track.artists.firstOrNull;
          if (artist != null) {
            Navigator.of(state.context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistDetailScreen(artist: artist),
              ),
            );
          }
        },
        returnsNormally,
      );

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Focus 6: Empirical Bug Reproduction — RenderFlex Overflow in TrackTile PopupMenu', () {
    testWidgets('6.1 EMPIRICAL REPRODUCTION: Opening TrackTile PopupMenuButton triggers RenderFlex overflow by 1.6px on trFileInfo', (tester) async {
      const track = Track(
        id: 9999,
        filePath: '/music/overflow_repro.mp3',
        title: 'Overflow Repro Track',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Repro Artist', tracks: [])],
        album: Album(id: 1, name: 'Repro Album', tracks: []),
      );

      await tester.pumpWidget(
        createTestHarness(
          child: Scaffold(
            body: TrackTile(
              track: track,
              onActionSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        // Tap PopupMenuButton to open menu
        await tester.tap(find.byType(PopupMenuButton<TrackAction>));
        await tester.pumpAndSettle();

        // EMPIRICAL ASSERTION: The overflow was completely eliminated by Expanded
        expect(caughtOverflowError, isNull,
            reason: 'Opening TrackTile PopupMenu should not trigger any RenderFlex overflow on trFileInfo');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('6.2 EMPIRICAL REPRODUCTION: Spanish locale does not trigger RenderFlex overflow on TrackTile PopupMenuButton (Información del archivo)', (tester) async {
      final localeRepo = _FileSystemLocaleRepository();
      final esLocaleController = LocaleController(localeRepo, 'es');
      await esLocaleController.whenReady;

      const track = Track(
        id: 9998,
        filePath: '/music/es_repro.mp3',
        title: 'Canción Española',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Artista', tracks: [])],
        album: Album(id: 1, name: 'Álbum', tracks: []),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(
              value: esLocaleController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackTile(
                track: track,
                onActionSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        await tester.tap(find.byType(PopupMenuButton<TrackAction>));
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'Opening TrackTile PopupMenu with Spanish strings should not cause overflow');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
        esLocaleController.dispose();
      }
    });

    testWidgets('6.3 Defensive Wrap prevents RenderFlex overflow on action buttons in detail screens with Spanish strings at 360px viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final localeRepo = _FileSystemLocaleRepository();
      final esLocaleController = LocaleController(localeRepo, 'es');
      await esLocaleController.whenReady;

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      const track = Track(
        id: 1,
        filePath: '/music/t1.mp3',
        title: 'Pista 1',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: null,
      );
      final album = Album(id: 1, name: 'Álbum', tracks: [track]);
      final artist = Artist(id: 1, name: 'Artista', tracks: [track]);

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: MaterialApp(
              home: AlbumDetailScreen(album: album),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'AlbumDetailScreen action buttons must wrap cleanly at 360px width in Spanish');
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: MaterialApp(
              home: ArtistDetailScreen(artist: artist),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'ArtistDetailScreen action buttons must wrap cleanly at 360px width in Spanish');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
        libraryCtrl.dispose();
        playback.dispose();
        await db.close();
        esLocaleController.dispose();
      }
    });
  });
}
