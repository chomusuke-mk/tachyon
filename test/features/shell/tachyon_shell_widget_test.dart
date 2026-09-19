import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

class StubMetadataExtractor implements MetadataExtractor {
  @override
  Future<Track?> extractMetadata(String filePath) async => null;

  @override
  Stream<ScanProgress> scanDirectories(List<String> directories, {CancellationToken? cancellationToken}) =>
      const Stream.empty();

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async => null;
}

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late AudioEngineServiceImpl engine;
  late SettingsRepository settingsRepo;
  late LocaleController localeController;
  late LibraryController libraryController;
  late PlaylistsController playlistsController;
  late TachyonSearchController searchController;
  late PlaybackController playbackController;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();

    final playerA = MockAudioPlayerAdapter(id: 'A');
    final playerB = MockAudioPlayerAdapter(id: 'B');
    engine = AudioEngineServiceImpl(playerA: playerA, playerB: playerB, queueManager: QueueManager());

    localeController = LocaleController(StubLocaleRepository(), 'en');
    libraryController = LibraryController(database: db, metadataExtractor: StubMetadataExtractor());
    playlistsController = PlaylistsController(database: db);
    searchController = TachyonSearchController(database: db);
    playbackController = PlaybackController(
      audioEngineService: engine,
      database: db,
      settingsRepository: settingsRepo,
    );
    settingsController = SettingsController(
      settingsRepository: settingsRepo,
      audioEngineService: engine,
      localeController: localeController,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    libraryController.dispose();
    playlistsController.dispose();
    searchController.dispose();
    settingsController.dispose();
    await engine.dispose();
    await db.close();
  });

  Widget buildTestApp({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
        ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
      ],
      child: MaterialApp(
        theme: TachyonTheme.darkTheme,
        home: child,
      ),
    );
  }

  testWidgets('renders NavigationBar and MiniPlayerBar on mobile screen (< 720dp)', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(child: const TachyonShell()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(MiniPlayerBar), findsOneWidget);
  });

  testWidgets('renders NavigationRail on desktop screen (>= 720dp)', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(child: const TachyonShell()));
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(MiniPlayerBar), findsOneWidget);
  });

  testWidgets('navigation switches indexed view state', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(child: const TachyonShell()));
    await tester.pump();

    // Verify initial view index is 0 (Tracks)
    final indexedStackFinder = find.byType(IndexedStack);
    expect(indexedStackFinder, findsOneWidget);
    IndexedStack stack = tester.widget(indexedStackFinder);
    expect(stack.index, equals(0));

    // Tap on Albums rail destination (index 1)
    final albumsDest = find.byIcon(Icons.album_outlined);
    expect(albumsDest, findsOneWidget);
    await tester.tap(albumsDest);
    await tester.pump();

    stack = tester.widget(indexedStackFinder);
    expect(stack.index, equals(1));
  });
}
