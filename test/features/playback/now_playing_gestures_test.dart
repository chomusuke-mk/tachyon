import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/now_playing_cover_art.dart';
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

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({
    required super.backend,
    required super.settingsRepository,
  });

  Track? _mockTrack;
  bool mockHasNext = true;
  bool mockHasPrevious = true;
  int nextCallCount = 0;
  int previousCallCount = 0;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  @override
  bool get hasNext => mockHasNext;

  @override
  bool get hasPrevious => mockHasPrevious;

  @override
  Future<void> next() async {
    nextCallCount++;
  }

  @override
  Future<void> previous() async {
    previousCallCount++;
  }

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

  group('NowPlayingScreen Gestures Tests', () {
    testWidgets('Dragging down past threshold dismisses NowPlayingScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Drag down anywhere on NowPlayingScreen past threshold (e.g. 200px)
      await tester.drag(find.byType(NowPlayingScreen), const Offset(0, 200));
      await tester.pumpAndSettle();

      // NowPlayingScreen should be popped
      expect(find.byType(NowPlayingScreen), findsNothing);
    });

    testWidgets('Small drag downwards snaps back and does not dismiss NowPlayingScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Small drag down (15px) without velocity
      final gesture = await tester.startGesture(tester.getCenter(find.byType(NowPlayingScreen)));
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      // Screen remains open
      expect(find.byType(NowPlayingScreen), findsOneWidget);
    });

    testWidgets('Dragging down on top app bar dismisses NowPlayingScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Drag downwards from the minimize icon
      final minimizeIconFinder = find.byIcon(Icons.keyboard_arrow_down_rounded).first;
      await tester.drag(minimizeIconFinder, const Offset(0, 180));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsNothing);
    });

    testWidgets('Swiping left and right on cover art changes track', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingCoverArt), findsOneWidget);
      expect(playbackController.nextCallCount, equals(0));
      expect(playbackController.previousCallCount, equals(0));

      // Swipe left on cover art (forward -> next)
      await tester.drag(find.byType(NowPlayingCoverArt), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(playbackController.nextCallCount, equals(1));

      // Swipe right on cover art (backward -> previous)
      await tester.drag(find.byType(NowPlayingCoverArt), const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(playbackController.previousCallCount, equals(1));
    });

    testWidgets('Empty queue screen can also be dragged down to dismiss', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      playbackController.setMockTrack(null);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      await tester.drag(find.byType(NowPlayingScreen), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsNothing);
    });

    testWidgets('Multi-frame vertical drag dismisses NowPlayingScreen on the very first swipe without getting stuck after crossing touch slop', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final track = libraryStore.getTrackById(100)!;
      playbackController.setMockTrack(track);

      await tester.pumpWidget(buildApp(const TachyonShell()));
      await tester.pumpAndSettle();

      NowPlayingScreen.open(navigatorKey.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Simulate realistic 60fps finger drag where a frame is pumped right after
      // crossing the ~20px (0.5cm) touch slop threshold:
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NowPlayingScreen)),
      );
      await gesture.moveBy(const Offset(0, 22));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      // Must dismiss on the first swipe without getting stuck at ~22px
      expect(find.byType(NowPlayingScreen), findsNothing);
    });
  });
}
