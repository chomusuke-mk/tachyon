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
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';

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
      RawArtistDto(id: 1, name: 'Radiohead'),
    ],
    albums: [
      RawAlbumDto(id: 10, name: 'OK Computer', year: 1997, artistId: 1),
    ],
    genres: [],
    tracks: [
      RawTrackDto(
        id: 101,
        filePath: '/music/radiohead/paranoid_android.mp3',
        title: 'Paranoid Android',
        durationMs: 387000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 10,
      ),
    ],
    playlists: [],
    playlistEntries: [],
    trackArtists: [
      TrackArtistPair(trackId: 101, artistId: 1),
    ],
    trackGenres: [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late LocaleController esLocaleController;
  late AppDatabase db;
  late DirectTachyonBackendClient backend;
  late LibraryStore libraryStore;
  late LibraryController libraryController;
  late PlaybackController playbackController;
  late PlaylistsController playlistsController;
  late TachyonSearchController searchController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;

    esLocaleController = LocaleController(_TestLocaleRepo(), 'es');
    await esLocaleController.whenReady;

    db = AppDatabase.inMemory();
    backend = DirectTachyonBackendClient(database: db);
    libraryStore = LibraryStore.fromSnapshot(_createSampleSnapshot());

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
    );
    playlistsController = PlaylistsController(
      backend: backend,
    );
    searchController = TachyonSearchController(
      storeSupplier: () => libraryController.store,
    );
  });

  tearDownAll(() async {
    settingsController.dispose();
    libraryController.dispose();
    playbackController.dispose();
    playlistsController.dispose();
    searchController.dispose();
    await backend.dispose();
    await db.close();
  });

  Widget buildApp(Widget child, {LocaleController? controller, Size? mediaSize}) {
    final effectiveController = controller ?? localeController;
    Widget app = MultiProvider(
      providers: [
        Provider<TachyonBackendClient>.value(value: backend),
        Provider<SettingsRepository>.value(value: settingsRepo),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<LocaleController>.value(value: effectiveController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
        ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
      ],
      child: MaterialApp(
        home: child,
      ),
    );

    if (mediaSize != null) {
      app = MediaQuery(
        data: MediaQueryData(size: mediaSize),
        child: app,
      );
    }
    return app;
  }

  group('TachyonShell navigation menu - Search removed', () {
    testWidgets('Desktop NavigationRail has NO search destination', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // NavigationRail should be present
      expect(find.byType(NavigationRail), findsOneWidget);

      // Search destination should NOT be in NavigationRail
      final navRail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(navRail.destinations.length, 6); // Tracks, Albums, Artists, Playlists, Genres, Folders

      // Search icon should not exist in destinations
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.search_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('Mobile NavigationBar and popup menu have NO search destination', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Bottom NavigationBar has 4 main destinations: Tracks, Albums, Artists, Playlists
      expect(find.byType(NavigationBar), findsOneWidget);
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5); // 4 NavigationDestination + 1 PopupMenuButton

      // Open the popup menu in NavigationBar
      final moreButtonFinder = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.more_vert_rounded),
      );
      expect(moreButtonFinder, findsOneWidget);
      await tester.tap(moreButtonFinder);
      await tester.pumpAndSettle();

      // Search should NOT be in the popup menu items
      expect(find.text(localeController.localeStrings.srTitle), findsNothing);
    });
  });

  group('TracksScreen search button navigation', () {
    testWidgets('shows magnifying glass and navigates to SearchScreen with tracks selected',
        (tester) async {
      await tester.pumpWidget(buildApp(const TracksScreen()));
      await tester.pumpAndSettle();

      final searchBtnFinder = find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchBtnFinder, findsOneWidget);

      final btn = tester.widget<IconButton>(searchBtnFinder);
      expect(btn.tooltip, localeController.localeStrings.srTitle);

      // Tap search button
      await tester.tap(searchBtnFinder);
      await tester.pumpAndSettle();

      // Should have navigated to SearchScreen
      expect(find.byType(SearchScreen), findsOneWidget);

      // SearchScreen should have tracks category selected
      expect(searchController.category, SearchFilterCategory.tracks);

      // SearchScreen AppBar should have back arrow
      final backBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      expect(backBtnFinder, findsOneWidget);
      expect(
        tester.widget<IconButton>(backBtnFinder).tooltip,
        localeController.localeStrings.commonBack,
      );

      // Tapping back arrow returns to TracksScreen
      await tester.tap(backBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TracksScreen), findsOneWidget);
    });
  });

  group('AlbumsScreen search button navigation', () {
    testWidgets('shows magnifying glass and navigates to SearchScreen with albums selected',
        (tester) async {
      await tester.pumpWidget(buildApp(const AlbumsScreen()));
      await tester.pumpAndSettle();

      final searchBtnFinder = find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchBtnFinder, findsOneWidget);

      final btn = tester.widget<IconButton>(searchBtnFinder);
      expect(btn.tooltip, localeController.localeStrings.srTitle);

      // Tap search button
      await tester.tap(searchBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      expect(searchController.category, SearchFilterCategory.albums);

      // Back button pops back to AlbumsScreen
      final backBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      expect(backBtnFinder, findsOneWidget);

      await tester.tap(backBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(AlbumsScreen), findsOneWidget);
    });
  });

  group('ArtistsScreen search button navigation', () {
    testWidgets('shows magnifying glass and navigates to SearchScreen with artists selected',
        (tester) async {
      await tester.pumpWidget(buildApp(const ArtistsScreen()));
      await tester.pumpAndSettle();

      final searchBtnFinder = find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchBtnFinder, findsOneWidget);

      final btn = tester.widget<IconButton>(searchBtnFinder);
      expect(btn.tooltip, localeController.localeStrings.srTitle);

      // Tap search button
      await tester.tap(searchBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      expect(searchController.category, SearchFilterCategory.artists);

      // Back button pops back to ArtistsScreen
      final backBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      expect(backBtnFinder, findsOneWidget);

      await tester.tap(backBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(ArtistsScreen), findsOneWidget);
    });
  });

  group('Spanish localization for SearchScreen back button', () {
    testWidgets('back button has localized tooltip in Spanish ("Atrás")', (tester) async {
      expect(esLocaleController.localeStrings.commonBack, 'Atrás');

      await tester.pumpWidget(
        buildApp(
          const SearchScreen(),
          controller: esLocaleController,
        ),
      );
      await tester.pumpAndSettle();

      final backBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      expect(backBtnFinder, findsOneWidget);
      expect(
        tester.widget<IconButton>(backBtnFinder).tooltip,
        'Atrás',
      );
    });
  });
}
