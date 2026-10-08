import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/presentation/folders_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

class _FileSystemLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

RawTrackDto _createTrackDto({
  required int id,
  required String filePath,
  required String title,
  int? trackNumber,
  int? discNumber,
  int durationMs = 180000,
  int fileSize = 1024,
  int modifiedAt = 1000,
}) {
  return RawTrackDto(
    id: id,
    filePath: filePath,
    title: title,
    trackNumber: trackNumber,
    discNumber: discNumber,
    durationMs: durationMs,
    fileSize: fileSize,
    modifiedAt: modifiedAt,
  );
}

CatalogSnapshot _createSnapshot({List<RawTrackDto> tracks = const []}) {
  return CatalogSnapshot(
    tracks: tracks,
    albums: const [],
    artists: const [],
    genres: const [],
    playlists: const [],
    playlistEntries: const [],
    trackArtists: const [],
    trackGenres: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DirectTachyonBackendClient backend;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late _FileSystemLocaleRepository localeRepo;
  late LocaleController localeController;
  late PlaybackController playbackController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabase.inMemory();
    backend = DirectTachyonBackendClient(database: db);

    settingsController = SettingsController(
      repository: settingsRepo,
      backend: backend,
    );

    localeRepo = _FileSystemLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;

    playbackController = PlaybackController(
      backend: backend,
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    settingsController.dispose();
    backend.dispose();
    await db.close();
  });

  Widget buildFoldersApp(LibraryController libraryController) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ],
      child: const MaterialApp(
        home: FoldersScreen(),
      ),
    );
  }

  group('LibraryStore Directory Indexing', () {
    test('indexes and retrieves tracks by directory in O(1)', () {
      final snapshot = _createSnapshot(
        tracks: [
          _createTrackDto(
            id: 1,
            filePath: '/music/rock/queen/song1.mp3',
            title: 'Song 1',
            trackNumber: 1,
            discNumber: 1,
          ),
          _createTrackDto(
            id: 2,
            filePath: '/music/rock/queen/song2.mp3',
            title: 'Song 2',
            trackNumber: 2,
            discNumber: 1,
          ),
          _createTrackDto(
            id: 3,
            filePath: '/music/pop/abba/dancing.mp3',
            title: 'Dancing Queen',
            trackNumber: 1,
            discNumber: 1,
          ),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);

      final queenTracks = store.getTracksInDirectory('/music/rock/queen');
      expect(queenTracks.length, 2);
      expect(queenTracks.map((t) => t.title), containsAll(['Song 1', 'Song 2']));

      final abbaTracks = store.getTracksInDirectory('/music/pop/abba');
      expect(abbaTracks.length, 1);
      expect(abbaTracks.first.title, 'Dancing Queen');

      final emptyTracks = store.getTracksInDirectory('/music/jazz');
      expect(emptyTracks, isEmpty);
    });
  });

  group('LibraryController Navigation Stack', () {
    test('handles push, pop, breadcrumbs, and edge cases', () async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_folders_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final musicRoot = Directory(p.join(tempDir.path, 'Music'))..createSync();
      final rockDir = Directory(p.join(musicRoot.path, 'Rock'))..createSync();
      final queenDir = Directory(p.join(rockDir.path, 'Queen'))..createSync();

      await settingsController.addMusicDirectory(musicRoot.path);

      final store = LibraryStore.fromSnapshot(
        _createSnapshot(
          tracks: [
            _createTrackDto(
              id: 1,
              filePath: p.join(queenDir.path, 'bohemian.mp3'),
              title: 'Bohemian Rhapsody',
              trackNumber: 1,
              discNumber: 1,
            ),
          ],
        ),
      );

      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );
      addTearDown(controller.dispose);

      expect(controller.isAtFolderRoot, isTrue);
      expect(controller.currentFolderPath, isNull);

      // Navigate to Music root
      await controller.navigateToFolder(musicRoot.path);
      expect(controller.isAtFolderRoot, isFalse);
      expect(controller.currentFolderPath, p.normalize(musicRoot.path));
      expect(controller.currentFolderSubdirectories, [p.normalize(rockDir.path)]);
      expect(controller.currentFolderTracks, isEmpty);

      // Push into Rock
      await controller.navigateToFolder(rockDir.path);
      expect(controller.currentFolderPath, p.normalize(rockDir.path));
      expect(controller.currentFolderSubdirectories, [p.normalize(queenDir.path)]);

      // Push into Queen
      await controller.navigateToFolder(queenDir.path);
      expect(controller.currentFolderPath, p.normalize(queenDir.path));
      expect(controller.currentFolderSubdirectories, isEmpty);
      expect(controller.currentFolderTracks.length, 1);
      expect(controller.currentFolderTracks.first.title, 'Bohemian Rhapsody');

      // Check breadcrumbs stack
      expect(controller.folderBreadcrumbs.length, 3);

      // Pop back to Rock
      await controller.navigateUpFolder();
      expect(controller.currentFolderPath, p.normalize(rockDir.path));

      // Pop back to Music
      await controller.navigateUpFolder();
      expect(controller.currentFolderPath, p.normalize(musicRoot.path));

      // Pop back to Settings root
      await controller.navigateUpFolder();
      expect(controller.isAtFolderRoot, isTrue);
      expect(controller.currentFolderPath, isNull);

      // Cannot pop higher than root
      await controller.navigateUpFolder();
      expect(controller.isAtFolderRoot, isTrue);
      expect(controller.currentFolderPath, isNull);
    });

    test('navigateToBreadcrumbIndex jumps to target ancestor', () async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_bc_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dirA = Directory(p.join(tempDir.path, 'A'))..createSync();
      final dirB = Directory(p.join(dirA.path, 'B'))..createSync();
      final dirC = Directory(p.join(dirB.path, 'C'))..createSync();

      await settingsController.addMusicDirectory(dirA.path);

      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: LibraryStore(),
      );
      addTearDown(controller.dispose);

      await controller.navigateToFolder(dirA.path);
      await controller.navigateToFolder(dirB.path);
      await controller.navigateToFolder(dirC.path);
      expect(controller.folderBreadcrumbs.length, 3);

      // Jump back to index 0 (dirA)
      await controller.navigateToBreadcrumbIndex(0);
      expect(controller.currentFolderPath, p.normalize(dirA.path));
      expect(controller.folderBreadcrumbs.length, 1);

      // Reset to root
      await controller.resetFolderNavigation();
      expect(controller.isAtFolderRoot, isTrue);
      expect(controller.currentFolderPath, isNull);
    });
  });

  group('FoldersScreen Widget Tests', () {
    testWidgets('shows empty state when no music directories are configured', (tester) async {
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: LibraryStore(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildFoldersApp(controller));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_off_rounded), findsOneWidget);
      expect(find.text(localeController.localeStrings.sAddFolder), findsOneWidget);
    });

    testWidgets('renders music directories and toggles between list and grid view', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_view_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final myMusic = Directory(p.join(tempDir.path, 'MyMusic'))..createSync();
      await settingsRepo.setMusicDirectories([myMusic.path]);
      await settingsController.init();

      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: LibraryStore(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildFoldersApp(controller));
      await tester.pumpAndSettle();

      // In default list mode
      expect(find.text('MyMusic'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);

      // Toggle to grid mode
      final toggleBtn = find.byTooltip(localeController.localeStrings.fViewAsGrid);
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(controller.isFolderGridView, isTrue);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('MyMusic'), findsOneWidget);

      // Toggle back to list mode
      final listToggleBtn = find.byTooltip(localeController.localeStrings.fViewAsList);
      expect(listToggleBtn, findsOneWidget);
      await tester.tap(listToggleBtn);
      await tester.pumpAndSettle();

      expect(controller.isFolderGridView, isFalse);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('navigates inside folder, shows breadcrumbs and tracks', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_ui_nav_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final rootDir = Directory(p.join(tempDir.path, 'Music'))..createSync();
      final jazzDir = Directory(p.join(rootDir.path, 'Jazz'))..createSync();
      await settingsRepo.setMusicDirectories([rootDir.path]);
      await settingsController.init();

      final trackPath = p.join(jazzDir.path, 'autumn_leaves.mp3');
      final store = LibraryStore.fromSnapshot(
        _createSnapshot(
          tracks: [
            _createTrackDto(
              id: 10,
              filePath: trackPath,
              title: 'Autumn Leaves',
              durationMs: 240000,
            ),
          ],
        ),
      );

      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: store,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildFoldersApp(controller));
      await tester.pumpAndSettle();

      // Navigate to Music folder via controller
      await controller.navigateToFolder(rootDir.path);
      await tester.pumpAndSettle();

      // Inside Music: breadcrumb should show Root and Music
      expect(find.text(localeController.localeStrings.fBreadcrumbRoot), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);

      // Navigate to Jazz subfolder
      await controller.navigateToFolder(jazzDir.path);
      await tester.pumpAndSettle();

      // Inside Jazz: shows track tile for Autumn Leaves
      expect(find.text('Autumn Leaves'), findsOneWidget);
      expect(find.byType(TrackTile), findsOneWidget);

      // Tap breadcrumb root icon to return to root
      final rootIcon = find.byIcon(Icons.home_rounded);
      await tester.tap(rootIcon);
      await tester.pumpAndSettle();

      // Back at root view
      expect(controller.isAtFolderRoot, isTrue);
      expect(find.text('Music'), findsOneWidget);
    });

    testWidgets('rescan button in AppBar triggers scanDirectories with localized tooltip', (tester) async {
      final controller = LibraryController(
        backend: backend,
        settingsRepository: settingsRepo,
        store: LibraryStore(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildFoldersApp(controller));
      await tester.pumpAndSettle();

      final rescanBtn = find.byTooltip(localeController.localeStrings.fRescanAll);
      expect(rescanBtn, findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

      await tester.tap(rescanBtn);
      await tester.pump();

      expect(controller.isScanning, isTrue);
    });
  });
}
