import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

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

  late AppDatabase db;
  late DirectTachyonBackendClient backend;
  late SettingsRepository settingsRepo;
  late _FileSystemLocaleRepository localeRepo;
  late LocaleController localeControllerEn;
  late LocaleController localeControllerEs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabase.inMemory();
    backend = DirectTachyonBackendClient(database: db);

    localeRepo = _FileSystemLocaleRepository();
    localeControllerEn = LocaleController(localeRepo, 'en');
    await localeControllerEn.whenReady;

    localeControllerEs = LocaleController(localeRepo, 'es');
    await localeControllerEs.whenReady;
  });

  tearDown(() async {
    backend.dispose();
    await db.close();
  });

  group('LibraryController Loading State', () {
    test('initializes isLoading to true when no store is provided', () {
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      expect(controller.isLoading, isTrue);
      expect(controller.tracks, isEmpty);

      controller.dispose();
    });

    test('initializes isLoading to false when store is provided', () {
      final store = LibraryStore();
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );

      expect(controller.isLoading, isFalse);
      expect(controller.tracks, isEmpty);

      controller.dispose();
    });

    test('loadLibrary transitions isLoading true -> false on completion', () async {
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      expect(controller.isLoading, isTrue);

      await controller.loadLibrary();

      expect(controller.isLoading, isFalse);

      controller.dispose();
    });
  });

  group('TracksScreen Loading UI Presentation', () {
    Widget buildTestScreen({
      required LibraryController libraryCtrl,
      required LocaleController localeCtrl,
    }) {
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepo,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: libraryCtrl.store,
      );

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
          ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
          ChangeNotifierProvider<PlaybackController>.value(value: playbackCtrl),
          ChangeNotifierProvider<PlaylistsController>.value(value: playlistsCtrl),
        ],
        child: const MaterialApp(
          home: TracksScreen(),
        ),
      );
    }

    testWidgets('displays centered loading text and horizontal loader while loading with empty tracks', (tester) async {
      // Create controller with store == null so isLoading is true
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEn,
        ),
      );

      // Verify the loading message is rendered
      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsOneWidget);
      expect(find.text('Loading tracks...'), findsOneWidget);

      // Verify horizontal loader is present
      expect(find.byKey(const Key('tracks_loading_indicator')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Verify empty state is NOT displayed while loading
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsNothing);
      expect(find.byIcon(Icons.music_off_rounded), findsNothing);

      libraryCtrl.dispose();
    });

    testWidgets('displays Spanish localized message "Cargando canciones..." when in Spanish locale', (tester) async {
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEs,
        ),
      );

      // Verify Spanish translation
      expect(find.text(localeControllerEs.localeStrings.trLoadingTracks), findsOneWidget);
      expect(find.text('Cargando canciones...'), findsOneWidget);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsOneWidget);

      libraryCtrl.dispose();
    });

    testWidgets('displays empty state when loading is finished and library has no tracks', (tester) async {
      // Store provided, isLoading == false
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: LibraryStore(),
      );

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEn,
        ),
      );

      // Loading indicator should NOT be shown
      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsNothing);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsNothing);

      // Empty state should be shown
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsOneWidget);
      expect(find.byIcon(Icons.music_off_rounded), findsOneWidget);

      libraryCtrl.dispose();
    });

    testWidgets('displays track list when tracks are present', (tester) async {
      const snapshot = CatalogSnapshot(
        tracks: [
          RawTrackDto(
            id: 1,
            filePath: '/music/song1.mp3',
            title: 'Sample Track',
            durationMs: 180000,
            fileSize: 4000000,
            modifiedAt: 123456,
          ),
        ],
        albums: [],
        artists: [],
        genres: [],
        playlists: [],
        playlistEntries: [],
        trackArtists: [],
        trackGenres: [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEn,
        ),
      );

      // Neither loading nor empty state should be shown
      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsNothing);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsNothing);
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsNothing);

      // The track item should be rendered
      expect(find.text('Sample Track'), findsOneWidget);

      libraryCtrl.dispose();
    });

    testWidgets(
        'displays centered loading indicator when metadata scan is running and tracks are empty',
        (tester) async {
      final store = LibraryStore();
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );

      // Verify initial state: not loading, no tracks, not scanning
      expect(libraryCtrl.isLoading, isFalse);
      expect(libraryCtrl.tracks, isEmpty);
      expect(libraryCtrl.isScanning, isFalse);

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEn,
        ),
      );

      // Initially shows empty state because not loading and not scanning
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsOneWidget);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsNothing);

      // Start scan -> isScanning becomes true
      await libraryCtrl.startScan([]);
      expect(libraryCtrl.isScanning, isTrue);
      await tester.pump();

      // Now it should show the loader and hide the empty state
      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsOneWidget);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsOneWidget);
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsNothing);

      // Cancel scan -> returns to empty state
      libraryCtrl.cancelScan();
      expect(libraryCtrl.isScanning, isFalse);
      await tester.pump();

      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsNothing);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsNothing);
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsOneWidget);

      libraryCtrl.dispose();
    });

    testWidgets(
        'displays tracks and NOT loading indicator when metadata scan is running but tracks are already present',
        (tester) async {
      const snapshot = CatalogSnapshot(
        tracks: [
          RawTrackDto(
            id: 1,
            filePath: '/music/song1.mp3',
            title: 'Sample Track',
            durationMs: 180000,
            fileSize: 4000000,
            modifiedAt: 123456,
          ),
        ],
        albums: [],
        artists: [],
        genres: [],
        playlists: [],
        playlistEntries: [],
        trackArtists: [],
        trackGenres: [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );

      await tester.pumpWidget(
        buildTestScreen(
          libraryCtrl: libraryCtrl,
          localeCtrl: localeControllerEn,
        ),
      );

      // Start scan
      await libraryCtrl.startScan([]);
      expect(libraryCtrl.isScanning, isTrue);
      expect(libraryCtrl.tracks.isNotEmpty, isTrue);
      await tester.pump();

      // With tracks present, loader should NOT show, empty state should NOT show, tracks should show
      expect(find.text(localeControllerEn.localeStrings.trLoadingTracks), findsNothing);
      expect(find.byKey(const Key('tracks_loading_indicator')), findsNothing);
      expect(find.text(localeControllerEn.localeStrings.trNoTracks), findsNothing);
      expect(find.text('Sample Track'), findsOneWidget);

      libraryCtrl.dispose();
    });
  });
}
