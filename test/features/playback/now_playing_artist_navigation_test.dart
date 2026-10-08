import 'dart:io';
import 'dart:ui';

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
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
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
      RawArtistDto(id: 2, name: 'David Bowie'),
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
      RawTrackDto(
        id: 101,
        filePath: '/music/queen/under_pressure.mp3',
        title: 'Under Pressure',
        durationMs: 240000,
        fileSize: 4000000,
        modifiedAt: 1000,
        albumId: 10,
      ),
    ],
    playlists: [],
    playlistEntries: [],
    trackArtists: [
      TrackArtistPair(trackId: 100, artistId: 1),
      TrackArtistPair(trackId: 101, artistId: 1),
      TrackArtistPair(trackId: 101, artistId: 2),
    ],
    trackGenres: [],
  );
}

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({
    required super.backend,
    required super.settingsRepository,
  });

  Track? _mockTrack;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  void setMockTrack(Track? track) {
    _mockTrack = track;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late AppDatabase db;
  late DirectTachyonBackendClient backend;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late LibraryStore libraryStore;
  late LibraryController libraryController;
  late _TestPlaybackController playbackController;
  late LyricsController lyricsController;
  late PlaylistsController playlistsController;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;

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
    navigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() async {
    settingsController.dispose();
    libraryController.dispose();
    playbackController.dispose();
    lyricsController.dispose();
    playlistsController.dispose();
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
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
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

  group('NowPlayingScreen Clickable Artist Navigation', () {
    testWidgets('Tapping single artist name navigates to ArtistDetailScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

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
      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Queen'), findsWidgets);

      // Find the artist link for Queen under the track title and tap it
      await tester.tap(find.text('Queen').first);
      await tester.pumpAndSettle();

      // ArtistDetailScreen for Queen must be open
      expect(find.byType(ArtistDetailScreen), findsOneWidget);

      // Back navigation via ESC returns to NowPlayingScreen
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsNothing);
      expect(find.byType(NowPlayingScreen), findsOneWidget);
    });

    testWidgets('Track with multiple artists displays both and allows tapping each', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(101)!;
      playbackController.setMockTrack(track);

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
      expect(find.text('Under Pressure'), findsOneWidget);
      expect(find.text('Queen'), findsWidgets);
      expect(find.text('David Bowie'), findsWidgets);

      // Tap David Bowie
      await tester.tap(find.text('David Bowie').first);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);

      // Pop back to NowPlayingScreen
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsNothing);
      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Now tap Queen
      await tester.tap(find.text('Queen').first);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);
    });

    testWidgets('Returning from ArtistDetailScreen resets artist link hover/underline state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const NowPlayingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final queenFinder = find.text('Queen').first;
      expect(queenFinder, findsOneWidget);

      // Verify initial state: not underlined
      Text queenText = tester.widget<Text>(queenFinder);
      expect(queenText.style?.decoration, isNot(TextDecoration.underline));

      // Simulate mouse hovering on Queen
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(queenFinder));
      await tester.pumpAndSettle();

      // When hovered, it should be underlined
      queenText = tester.widget<Text>(queenFinder);
      expect(queenText.style?.decoration, equals(TextDecoration.underline));

      // Click to navigate
      await gesture.down(tester.getCenter(queenFinder));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsOneWidget);

      // Move mouse away to top-left (e.g. where the back button was clicked)
      await gesture.moveTo(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Pop back (e.g. via ESC or back button)
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ArtistDetailScreen), findsNothing);
      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Once back on NowPlayingScreen, the text must NOT remain underlined
      queenText = tester.widget<Text>(find.text('Queen').first);
      expect(queenText.style?.decoration, isNot(TextDecoration.underline));
    });
  });
}
