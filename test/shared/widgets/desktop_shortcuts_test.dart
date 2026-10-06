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
import 'package:tachyon/features/library/presentation/genre_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/widgets/desktop_shortcuts_handler.dart';

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
    genres: [
      RawGenreDto(id: 5, name: 'Rock'),
    ],
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
    trackGenres: [
      TrackGenrePair(trackId: 100, genreId: 5),
    ],
  );
}

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({
    required super.backend,
    required super.settingsRepository,
  });

  Duration? lastSeekPosition;
  Track? _mockTrack;
  Duration _mockDuration = Duration.zero;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  @override
  Duration get duration =>
      _mockDuration > Duration.zero ? _mockDuration : super.duration;

  void setMockTrack(Track? track, {Duration? duration}) {
    _mockTrack = track;
    if (duration != null) _mockDuration = duration;
    notifyListeners();
  }

  int playOrPauseCallCount = 0;
  bool mockIsPlaying = false;

  @override
  bool get isPlaying => mockIsPlaying;

  @override
  Future<void> playOrPause() async {
    playOrPauseCallCount++;
    mockIsPlaying = !mockIsPlaying;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration pos) async {
    lastSeekPosition = pos;
    await super.seek(pos);
  }
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
  late _TestPlaybackController playbackController;
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
    playbackController = _TestPlaybackController(
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
        builder: (context, child) => DesktopShortcutsHandler(
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

  group('DesktopShortcutsHandler - Keyboard ESC Navigation', () {
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

    testWidgets('ESC pops GenreDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final genre = libraryStore.allGenres.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => GenreDetailScreen(genre: genre),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GenreDetailScreen), findsOneWidget);

      // Press ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(GenreDetailScreen), findsNothing);
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

  group('DesktopShortcutsHandler - Mouse Back Button Navigation', () {
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

    testWidgets('Mouse back button pops GenreDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final genre = libraryStore.allGenres.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => GenreDetailScreen(genre: genre),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GenreDetailScreen), findsOneWidget);

      // Click mouse back button
      await clickMouseBackButton(tester);

      expect(find.byType(GenreDetailScreen), findsNothing);
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

  group('DesktopShortcutsHandler - Alt+Left & Folders Navigation', () {
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

    testWidgets('Alt+Left Arrow pops GenreDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final genre = libraryStore.allGenres.first;
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => GenreDetailScreen(genre: genre),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GenreDetailScreen), findsOneWidget);

      // Press Alt+Left
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(find.byType(GenreDetailScreen), findsNothing);
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

  group('DesktopShortcutsHandler - Number Keys 0-9 Seek', () {
    const sampleTrack = Track(
      id: 100,
      filePath: '/music/queen/bohemian.mp3',
      title: 'Bohemian Rhapsody',
      durationMs: 200000,
      fileSize: 1000,
      modifiedAt: 1000,
    );

    testWidgets('Pressing 0-9 seeks to corresponding 0%-90% fraction of track duration', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      final digitKeys = [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];

      for (int i = 0; i <= 9; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.sendKeyEvent(digitKeys[i]);
        await tester.pump();

        final expectedSeconds = (200 * (i / 10.0)).round();
        expect(
          playbackController.lastSeekPosition,
          Duration(seconds: expectedSeconds),
          reason: 'Key $i should seek to $expectedSeconds seconds (fraction ${i / 10.0})',
        );
      }
    });

    testWidgets('Numpad numbers 0-9 seek to corresponding fraction', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.numpad0);
      await tester.pump();
      expect(playbackController.lastSeekPosition, Duration.zero);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad5);
      await tester.pump();
      expect(playbackController.lastSeekPosition, const Duration(seconds: 100));

      await tester.pump(const Duration(milliseconds: 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad9);
      await tester.pump();
      expect(playbackController.lastSeekPosition, const Duration(seconds: 180));
    });

    testWidgets('Pressing 0-9 does nothing when no track is loaded/playing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(null);
      playbackController.lastSeekPosition = null;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      expect(playbackController.lastSeekPosition, isNull);
    });

    testWidgets('Pressing 0-9 does nothing when duration is Duration.zero', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: Duration.zero);
      playbackController.lastSeekPosition = null;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      expect(playbackController.lastSeekPosition, isNull);
    });

    testWidgets('Pressing 0-9 does NOT seek when a text input (TextField) is focused', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));
      playbackController.lastSeekPosition = null;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Open SearchScreen
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Focus TextField
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Press digit 5 while focused
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      // Seek must NOT have been called
      expect(playbackController.lastSeekPosition, isNull);
    });

    testWidgets('Pressing 0-9 with modifiers (Alt, Control, Shift) does NOT seek', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Alt + 5
      playbackController.lastSeekPosition = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(playbackController.lastSeekPosition, isNull);

      // Control + 5
      playbackController.lastSeekPosition = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(playbackController.lastSeekPosition, isNull);

      // Shift + 5 (e.g. typing '%')
      playbackController.lastSeekPosition = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(playbackController.lastSeekPosition, isNull);
    });
  });

  group('DesktopShortcutsHandler - Spacebar Play/Pause', () {
    const sampleTrack = Track(
      id: 100,
      filePath: '/music/queen/bohemian.mp3',
      title: 'Bohemian Rhapsody',
      durationMs: 200000,
      fileSize: 1000,
      modifiedAt: 1000,
    );

    testWidgets('Pressing Spacebar calls playOrPause when track is loaded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));
      playbackController.playOrPauseCallCount = 0;
      playbackController.mockIsPlaying = false;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Press Spacebar -> play
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(playbackController.playOrPauseCallCount, 1);
      expect(playbackController.isPlaying, true);

      // Press Spacebar again -> pause
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(playbackController.playOrPauseCallCount, 2);
      expect(playbackController.isPlaying, false);
    });

    testWidgets('Pressing Spacebar does nothing when no track is loaded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(null);
      playbackController.playOrPauseCallCount = 0;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(playbackController.playOrPauseCallCount, 0);
    });

    testWidgets('Pressing Spacebar does NOT toggle play/pause when a text input is focused', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));
      playbackController.playOrPauseCallCount = 0;

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Open SearchScreen
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Focus TextField
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Press Space while focused
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // playOrPause must NOT have been called
      expect(playbackController.playOrPauseCallCount, 0);
    });

    testWidgets('Pressing Spacebar with modifiers (Alt, Control, Shift) does NOT toggle play/pause', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(sampleTrack, duration: const Duration(seconds: 200));

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      // Alt + Space
      playbackController.playOrPauseCallCount = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(playbackController.playOrPauseCallCount, 0);

      // Control + Space
      playbackController.playOrPauseCallCount = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(playbackController.playOrPauseCallCount, 0);

      // Shift + Space
      playbackController.playOrPauseCallCount = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(playbackController.playOrPauseCallCount, 0);
    });
  });
}

