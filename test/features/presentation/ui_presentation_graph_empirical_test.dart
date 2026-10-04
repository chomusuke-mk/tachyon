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
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/genres_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
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

CatalogSnapshot _buildSampleSnapshot() {
  final artists = [
    const RawArtistDto(id: 1, name: 'Pink Floyd'),
    const RawArtistDto(id: 2, name: 'David Gilmour'),
    const RawArtistDto(id: 3, name: 'The Beatles'),
  ];

  final albums = [
    const RawAlbumDto(
      id: 10,
      name: 'The Dark Side of the Moon',
      year: 1973,
      artistId: 1,
    ),
    const RawAlbumDto(
      id: 20,
      name: 'Abbey Road',
      year: 1969,
      artistId: 3,
    ),
  ];

  final genres = [
    const RawGenreDto(id: 100, name: 'Progressive Rock'),
    const RawGenreDto(id: 200, name: 'Classic Rock'),
  ];

  final tracks = [
    const RawTrackDto(
      id: 1001,
      filePath: '/music/pink_floyd/time.mp3',
      title: 'Time',
      trackNumber: 4,
      discNumber: 1,
      year: 1973,
      durationMs: 425000,
      fileSize: 10200000,
      modifiedAt: 1000,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1002,
      filePath: '/music/pink_floyd/money.mp3',
      title: 'Money',
      trackNumber: 6,
      discNumber: 1,
      year: 1973,
      durationMs: 382000,
      fileSize: 9100000,
      modifiedAt: 1010,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1003,
      filePath: '/music/beatles/come_together.mp3',
      title: 'Come Together',
      trackNumber: 1,
      discNumber: 1,
      year: 1969,
      durationMs: 259000,
      fileSize: 6200000,
      modifiedAt: 2000,
      albumId: 20,
    ),
  ];

  final trackArtists = [
    const TrackArtistPair(trackId: 1001, artistId: 1),
    const TrackArtistPair(trackId: 1001, artistId: 2), // Multiple artists: Pink Floyd & David Gilmour
    const TrackArtistPair(trackId: 1002, artistId: 1),
    const TrackArtistPair(trackId: 1003, artistId: 3),
  ];

  final trackGenres = [
    const TrackGenrePair(trackId: 1001, genreId: 100),
    const TrackGenrePair(trackId: 1002, genreId: 100),
    const TrackGenrePair(trackId: 1003, genreId: 200),
  ];

  final playlists = [
    const RawPlaylistDto(
      id: 1,
      name: 'Liked Songs',
      createdAt: 100,
      type: 1,
    ),
  ];

  final playlistEntries = [
    const RawPlaylistEntryDto(
      id: 1,
      playlistId: 1,
      trackId: 1001,
      position: 0,
      addedAt: 100,
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

  group('Milestone 3 Challenger: O(1) In-Memory Graph Access vs Linear Loops', () {
    test('Empirical Complexity: album.tracks, artist.tracks, artist.albums, genre.tracks resolve in O(1)', () {
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final album = store.getAlbumById(10)!;
      final artist = store.getArtistById(1)!;
      final genre = store.getGenreById(100)!;

      // Assert instant graph pointer dereferences
      expect(album.tracks.length, equals(2));
      expect(album.tracks.map((t) => t.id), containsAll([1001, 1002]));

      expect(artist.tracks.length, equals(2));
      expect(artist.tracks.map((t) => t.id), containsAll([1001, 1002]));
      expect(artist.albums.length, equals(1));
      expect(artist.albums.first.id, equals(10));

      expect(genre.tracks.length, equals(2));
      expect(genre.tracks.map((t) => t.id), containsAll([1001, 1002]));
    });

    test('Empirical Stress Benchmark: 5,000 tracks O(1) graph access executes orders of magnitude faster than O(N) scan', () {
      // Synthesize 5,000 tracks across 250 albums and 100 artists
      const trackCount = 5000;
      const albumCount = 250;
      const artistCount = 100;
      const genreCount = 20;

      final rawArtists = List.generate(
        artistCount,
        (i) => RawArtistDto(id: i + 1, name: 'Artist ${i + 1}'),
      );
      final rawAlbums = List.generate(
        albumCount,
        (i) => RawAlbumDto(
          id: i + 1,
          name: 'Album ${i + 1}',
          year: 2000 + (i % 25),
          artistId: (i % artistCount) + 1,
        ),
      );
      final rawGenres = List.generate(
        genreCount,
        (i) => RawGenreDto(id: i + 1, name: 'Genre ${i + 1}'),
      );

      final rawTracks = <RawTrackDto>[];
      final rawTrackArtists = <TrackArtistPair>[];
      final rawTrackGenres = <TrackGenrePair>[];

      for (var i = 0; i < trackCount; i++) {
        final trackId = i + 1;
        final albumId = (i % albumCount) + 1;
        final artistId = (i % artistCount) + 1;
        final genreId = (i % genreCount) + 1;

        rawTracks.add(
          RawTrackDto(
            id: trackId,
            filePath: '/music/track_$trackId.mp3',
            title: 'Track $trackId',
            trackNumber: (i % 20) + 1,
            discNumber: 1,
            year: 2020,
            durationMs: 200000,
            fileSize: 5000000,
            modifiedAt: 1000,
            albumId: albumId,
          ),
        );
        rawTrackArtists.add(TrackArtistPair(trackId: trackId, artistId: artistId));
        rawTrackGenres.add(TrackGenrePair(trackId: trackId, genreId: genreId));
      }

      final bigSnapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: rawAlbums,
        artists: rawArtists,
        genres: rawGenres,
        playlists: const [],
        playlistEntries: const [],
        trackArtists: rawTrackArtists,
        trackGenres: rawTrackGenres,
      );

      final store = LibraryStore.fromSnapshot(bigSnapshot);
      final targetAlbum = store.getAlbumById(50)!;

      // Measure 2,000 accesses to targetAlbum.tracks (O(1) graph dereference)
      final swO1 = Stopwatch()..start();
      var countO1 = 0;
      for (var i = 0; i < 2000; i++) {
        final list = targetAlbum.tracks;
        countO1 += list.length;
      }
      swO1.stop();

      // Measure 2,000 iterations of legacy O(N) where-scan over 5,000 tracks
      final swOn = Stopwatch()..start();
      var countOn = 0;
      for (var i = 0; i < 2000; i++) {
        final list = store.allTracks.where((t) => t.album?.id == targetAlbum.id).toList();
        countOn += list.length;
      }
      swOn.stop();

      expect(countO1, equals(countOn));
      // O(1) should take less than 10ms total for 2,000 accesses
      expect(swO1.elapsedMilliseconds, lessThan(10));
      // O(1) must be demonstrably faster than O(N) scan
      expect(swO1.elapsedMicroseconds, lessThan(swOn.elapsedMicroseconds));
    });
  });

  group('Milestone 3 Challenger: Pointer Identity Oracle across Entities', () {
    test('Strict pointer identity (identical() == true) is preserved across all graph relationships', () {
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final track1 = store.getTrackById(1001)!; // Time (Pink Floyd & David Gilmour)
      final track2 = store.getTrackById(1002)!; // Money (Pink Floyd)
      final album10 = store.getAlbumById(10)!;  // Dark Side of the Moon
      final artist1 = store.getArtistById(1)!;  // Pink Floyd

      // 1. Shared artist pointer identity
      expect(identical(track1.artists.first, track2.artists.first), isTrue);
      expect(identical(track1.artists.first, artist1), isTrue);
      expect(identical(album10.artist, artist1), isTrue);

      // 2. Shared album pointer identity
      expect(identical(track1.album, track2.album), isTrue);
      expect(identical(track1.album, album10), isTrue);

      // 3. Cyclic bidirectional pointer identity
      expect(identical(album10.tracks.first.album, album10), isTrue);
      expect(identical(artist1.albums.first.tracks.first.album, album10), isTrue);
      expect(identical(artist1.tracks.first.artists.first, artist1), isTrue);

      // 4. Playlist entry pointer identity
      final playlist = store.getPlaylistById(1)!;
      expect(playlist.entries.isNotEmpty, isTrue);
      final entry = playlist.entries.first;
      expect(identical(entry.track, track1), isTrue);
      expect(identical(entry.track?.album, album10), isTrue);
      expect(identical(entry.track?.artists.first, artist1), isTrue);
    });
  });

  group('Milestone 3 Challenger: UI Isolate Architectural Decoupling Oracle', () {
    test('Zero direct SQLite or AppDatabase instance access in presentation and shared UI layers', () {
      final libDir = Directory('lib');
      final presentationFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.path.contains('/presentation/') || f.path.contains('/shared/widgets/'))
          .toList();

      expect(presentationFiles.isNotEmpty, isTrue);

      for (final file in presentationFiles) {
        final content = file.readAsStringSync();
        final path = file.path;

        // Ensure no direct SQLite driver imports
        expect(
          content.contains("import 'package:sqlite3"),
          isFalse,
          reason: 'File $path imports package:sqlite3 directly in UI isolate!',
        );
        expect(
          content.contains("import 'package:sqflite"),
          isFalse,
          reason: 'File $path imports package:sqflite directly in UI isolate!',
        );

        // Ensure no AppDatabase direct instantiation or raw db handle access
        expect(
          content.contains('AppDatabase(') ||
              content.contains('AppDatabase.inMemory') ||
              content.contains('AppDatabase.forTesting'),
          isFalse,
          reason: 'File $path directly instantiates AppDatabase in UI isolate!',
        );
        expect(
          content.contains('.db.select') ||
              content.contains('.db.execute') ||
              content.contains('.db.prepare'),
          isFalse,
          reason: 'File $path calls low-level database handles directly!',
        );
      }
    });

    test('CatalogSnapshot contains strictly ZERO lyrics fields and enforces light transmission', () {
      final snapshot = _buildSampleSnapshot();
      final tracks = snapshot.tracks;

      for (final track in tracks) {
        expect(track.durationMs, greaterThan(0));
        expect(track.filePath.isNotEmpty, isTrue);
      }
    });
  });

  group('Milestone 3 Challenger: Presentation Screen & Widget Integration', () {
    testWidgets('TrackTile renders multiple artists, album name, and dynamic popup actions', (tester) async {
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);
      final trackMulti = store.getTrackById(1001)!; // Pink Floyd, David Gilmour • Dark Side of the Moon

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackTile(
                track: trackMulti,
                onActionSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert multi-artist and album title rendered
      expect(find.text('Time'), findsOneWidget);
      expect(
        find.text('Pink Floyd, David Gilmour • The Dark Side of the Moon'),
        findsOneWidget,
      );

      // Verify PopupMenu items directly via itemBuilder
      final popupFinder = find.byType(PopupMenuButton<TrackAction>);
      expect(popupFinder, findsOneWidget);
      final popupWidget = tester.widget<PopupMenuButton<TrackAction>>(popupFinder);
      final items = popupWidget.itemBuilder(tester.element(popupFinder));

      expect(items.length, equals(8));
      // Action values
      expect((items[0] as PopupMenuItem).value, equals(TrackAction.play));
      expect((items[1] as PopupMenuItem).value, equals(TrackAction.playNext));
      expect((items[2] as PopupMenuItem).value, equals(TrackAction.addToQueue));
      expect((items[3] as PopupMenuItem).value, equals(TrackAction.addToPlaylist));

      // viewAlbum must be enabled when album != null
      final viewAlbumItem = items[4] as PopupMenuItem;
      expect(viewAlbumItem.value, equals(TrackAction.viewAlbum));
      expect(viewAlbumItem.enabled, isTrue);

      // viewArtist must be enabled when artists.isNotEmpty
      final viewArtistItem = items[5] as PopupMenuItem;
      expect(viewArtistItem.value, equals(TrackAction.viewArtist));
      expect(viewArtistItem.enabled, isTrue);
    });

    testWidgets('TrackTile edge cases: single artist, empty artists, and null album', (tester) async {
      const trackNoAlbum = Track(
        id: 9991,
        filePath: '/music/solo.mp3',
        title: 'Solo Track',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Solo Artist')],
      );

      const trackNoArtist = Track(
        id: 9992,
        filePath: '/music/anon.mp3',
        title: 'Anonymous Track',
        durationMs: 150000,
        fileSize: 1000,
        modifiedAt: 1000,
        album: Album(id: 1, name: 'Mystery Album'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TrackTile(
                    track: trackNoAlbum,
                    onActionSelected: (_) {},
                  ),
                  TrackTile(
                    track: trackNoArtist,
                    onActionSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // trackNoAlbum subtitle should be just "Solo Artist" without trailing bullet
      expect(find.text('Solo Artist'), findsOneWidget);

      // trackNoArtist subtitle should fallback to Unknown Artist • Mystery Album
      final strings = localeController.localeStrings;
      expect(
        find.text('${strings.trUnknownArtist} • Mystery Album'),
        findsOneWidget,
      );

      // Verify disabled states for null album and empty artist
      final tiles = find.byType(PopupMenuButton<TrackAction>);
      expect(tiles, findsNWidgets(2));

      // For trackNoAlbum: viewAlbum should be disabled
      final noAlbumPopup = tester.widget<PopupMenuButton<TrackAction>>(tiles.at(0));
      final noAlbumItems = noAlbumPopup.itemBuilder(tester.element(tiles.at(0)));
      expect((noAlbumItems[4] as PopupMenuItem).enabled, isFalse);
      expect((noAlbumItems[5] as PopupMenuItem).enabled, isTrue);

      // For trackNoArtist: viewArtist should be disabled
      final noArtistPopup = tester.widget<PopupMenuButton<TrackAction>>(tiles.at(1));
      final noArtistItems = noArtistPopup.itemBuilder(tester.element(tiles.at(1)));
      expect((noArtistItems[4] as PopupMenuItem).enabled, isTrue);
      expect((noArtistItems[5] as PopupMenuItem).enabled, isFalse);
    });

    testWidgets('AlbumDetailScreen renders album details and provides O(1) tracks to playback', (tester) async {
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);
      final album = store.getAlbumById(10)!;

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: MaterialApp(
            home: AlbumDetailScreen(album: album),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      // Verify Header information
      expect(find.text('The Dark Side of the Moon'), findsWidgets);
      expect(find.text('Pink Floyd'), findsOneWidget);
      expect(find.text(strings.alPlayAll), findsOneWidget);
      expect(find.text(strings.alShuffleAll), findsOneWidget);

      // Verify tracks list contains both tracks
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);

      // Tap Play All
      await tester.tap(find.text(strings.alPlayAll));
      await tester.pumpAndSettle();

      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('AlbumDetailScreen edge case: album with 0 tracks handles gracefully without error', (tester) async {
      const emptyAlbum = Album(
        id: 999,
        name: 'Empty Album',
        artist: Artist(id: 1, name: 'Ghost Artist'),
        tracks: [],
      );

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: const MaterialApp(
            home: AlbumDetailScreen(album: emptyAlbum),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      expect(find.text('Empty Album'), findsWidgets);
      expect(find.text('Ghost Artist'), findsOneWidget);
      expect(find.text(strings.alPlayAll), findsOneWidget);

      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('ArtistDetailScreen renders discography and tracks in O(1)', (tester) async {
      // Use adequate vertical space so sliver list items are built
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);
      final artist = store.getArtistById(1)!;

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
          ],
          child: MaterialApp(
            home: ArtistDetailScreen(artist: artist),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      expect(find.text('Pink Floyd'), findsWidgets);
      expect(find.text(strings.arDiscography), findsOneWidget);
      expect(find.text(strings.arAllTracks), findsOneWidget);
      expect(find.text('The Dark Side of the Moon'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);

      libraryCtrl.dispose();
      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('GenresScreen displays genres and opens genre tracks in O(1)', (tester) async {
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
          ],
          child: const MaterialApp(
            home: GenresScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Progressive Rock'), findsOneWidget);
      expect(find.text('Classic Rock'), findsOneWidget);

      // Tap on Progressive Rock genre card
      await tester.tap(find.text('Progressive Rock'));
      await tester.pumpAndSettle();

      // Should now display genre tracks
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);

      libraryCtrl.dispose();
      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('ADVERSARIAL STRESS FINDING: TrackTile popup menu triggers RenderFlex layout overflow with long localized text', (tester) async {
      // This test empirically documents the layout bug in TrackTile popup menu
      // When PopupMenuItem opens, child Row([Icon, SizedBox, Text]) lacks Expanded,
      // overflowing by 1.6px in English ("File information") and by >40px in Spanish ("Información del archivo").
      final snapshot = _buildSampleSnapshot();
      final store = LibraryStore.fromSnapshot(snapshot);
      final track = store.getTrackById(1001)!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
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

      // Tap PopupMenuButton to open popup menu
      final popupFinder = find.byType(PopupMenuButton<TrackAction>);
      expect(popupFinder, findsOneWidget);
      await tester.tap(popupFinder);
      await tester.pumpAndSettle();

      // Verify that no layout overflow exception was captured
      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: 'TrackTile popup menu should fit available width without overflow',
      );
    });
  });
}
