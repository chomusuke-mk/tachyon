import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/widgets/desktop_back_navigation_handler.dart';

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
    ],
    albums: [
      RawAlbumDto(id: 10, name: 'A Night at the Opera', year: 1975, artistId: 1),
    ],
    genres: [],
    tracks: [
      RawTrackDto(
        id: 100,
        filePath: '/music/queen/bohemian.mp3',
        title: 'Bohemian Rhapsody',
        durationMs: 354000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 10,
      ),
    ],
    playlists: [],
    playlistEntries: [],
    trackArtists: [
      TrackArtistPair(trackId: 100, artistId: 1),
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
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late LibraryStore libraryStore;
  late LibraryController libraryController;
  late PlaybackController playbackController;
  late LyricsController lyricsController;
  late PlaylistsController playlistsController;
  late TachyonSearchController searchController;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
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
    lyricsController = LyricsController(
      backendClient: backend,
      playbackController: playbackController,
      settingsRepository: settingsRepo,
    );
    playlistsController = PlaylistsController(
      backend: backend,
    );
    searchController = TachyonSearchController(
      storeSupplier: () => libraryController.store,
    );
    navigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() async {
    settingsController.dispose();
    libraryController.dispose();
    playbackController.dispose();
    lyricsController.dispose();
    playlistsController.dispose();
    searchController.dispose();
    await backend.dispose();
    await db.close();
  });

  Widget buildApp(Widget child, {LocaleController? locale}) {
    return MultiProvider(
      providers: [
        Provider<TachyonBackendClient>.value(value: backend),
        Provider<SettingsRepository>.value(value: settingsRepo),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<LocaleController>.value(value: locale ?? localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
        ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => DesktopBackNavigationHandler(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: child,
      ),
    );
  }

  Future<void> clickMouseBackButton(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('DesktopBackNavigationHandler - Keyboard ESC Navigation', () {
    testWidgets('ESC pops SearchScreen even with focused TextField', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Open SearchScreen
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const SearchScreen(initialCategory: SearchFilterCategory.tracks),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);

      // TextField is focused
      await tester.enterText(find.byType(TextField), 'Bohemian');
      await tester.pumpAndSettle();

      // Press ESC key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // SearchScreen must have been popped
      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('ESC pops AlbumDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final album = libraryStore.allAlbums.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumDetailScreen(album: album),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlbumDetailScreen), findsOneWidget);

      // Press ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(AlbumDetailScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('ESC pops ArtistDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final artist = libraryStore.allArtists.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistDetailScreen(artist: artist),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);

      // Press ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('ESC minimizes NowPlayingScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Open NowPlayingScreen
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const NowPlayingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Press ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // NowPlayingScreen popped (minimized)
      expect(find.byType(NowPlayingScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('ESC does not pop root or throw when at root', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      expect(find.byType(TachyonShell), findsOneWidget);

      // Press ESC at root
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TachyonShell), findsOneWidget);
    });
  });

  group('DesktopBackNavigationHandler - Mouse Back Button Navigation', () {
    testWidgets('Mouse back button pops SearchScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);

      // Click mouse back button
      await clickMouseBackButton(tester);

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('Mouse back button pops AlbumDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final album = libraryStore.allAlbums.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumDetailScreen(album: album),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlbumDetailScreen), findsOneWidget);

      // Click mouse back button
      await clickMouseBackButton(tester);

      expect(find.byType(AlbumDetailScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('Mouse back button pops ArtistDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final artist = libraryStore.allArtists.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistDetailScreen(artist: artist),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);

      // Click mouse back button
      await clickMouseBackButton(tester);

      expect(find.byType(ArtistDetailScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('Mouse back button minimizes NowPlayingScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const NowPlayingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Click mouse back button
      await clickMouseBackButton(tester);

      expect(find.byType(NowPlayingScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });
  });

  group('DesktopBackNavigationHandler - Alt+Left & Folders Navigation', () {
    testWidgets('Alt+Left Arrow pops active route', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);

      // Press Alt+Left
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TachyonShell), findsOneWidget);
    });

    testWidgets('ESC navigates up folder when in subfolder at root', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = Directory.systemTemp.createTempSync('tachyon_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final parentDir = Directory('${tempDir.path}/rock')..createSync(recursive: true);
      final subDir = Directory('${parentDir.path}/queen')..createSync(recursive: true);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Navigate to a folder in LibraryController
      await libraryController.navigateToFolder(subDir.path);
      expect(libraryController.currentFolderPath, subDir.path);

      // Press ESC at root
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Navigated up one level to parentDir
      expect(libraryController.currentFolderPath, parentDir.path);
    });
  });

  group('NowPlayingScreen minimize button localized tooltip', () {
    testWidgets('displays localized tooltip in English ("Minimize")', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const NowPlayingScreen(), locale: localeController));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Minimize'), findsOneWidget);
    });

    testWidgets('displays localized tooltip in Spanish ("Minimizar")', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const NowPlayingScreen(), locale: esLocaleController));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Minimizar'), findsOneWidget);
    });
  });
}
