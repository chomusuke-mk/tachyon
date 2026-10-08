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
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

class _TestLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

class _TrackingBackendClient extends DirectTachyonBackendClient {
  final List<int> insertNextTrackIds = [];
  final List<List<int>> appendTrackIds = [];

  _TrackingBackendClient({super.database});

  @override
  Future<void> insertNext(int trackId) async {
    insertNextTrackIds.add(trackId);
    await super.insertNext(trackId);
  }

  @override
  Future<void> append(List<int> trackIds) async {
    appendTrackIds.add(trackIds);
    await super.append(trackIds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _TrackingBackendClient backend;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late _TestLocaleRepository localeRepo;
  late LocaleController localeController;
  late PlaybackController playbackController;
  late LibraryStore store;
  late LibraryController libraryController;
  late PlaylistsController playlistsController;

  final trackA = Track(
    id: 1,
    filePath: '/music/track_a.mp3',
    title: 'Song Alpha',
    durationMs: 180000,
    fileSize: 1024,
    modifiedAt: 1000,
    artists: [],
  );

  final trackB = Track(
    id: 2,
    filePath: '/music/track_b.mp3',
    title: 'Song Beta',
    durationMs: 240000,
    fileSize: 2048,
    modifiedAt: 2000,
    artists: [],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabase.inMemory();
    db.db.execute(
      'INSERT INTO tracks (id, file_path, title, duration_ms, file_size, modified_at) VALUES (?, ?, ?, ?, ?, ?)',
      [trackA.id, trackA.filePath, trackA.title, trackA.durationMs, trackA.fileSize, trackA.modifiedAt],
    );
    db.db.execute(
      'INSERT INTO tracks (id, file_path, title, duration_ms, file_size, modified_at) VALUES (?, ?, ?, ?, ?, ?)',
      [trackB.id, trackB.filePath, trackB.title, trackB.durationMs, trackB.fileSize, trackB.modifiedAt],
    );
    db.db.execute(
      'INSERT INTO playlists (id, name, created_at, type) VALUES (10, ?, 1000, ?)',
      ['My Mix', PlaylistType.user.index],
    );

    backend = _TrackingBackendClient(database: db);

    settingsController = SettingsController(
      repository: settingsRepo,
      backend: backend,
    );

    localeRepo = _TestLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;

    playbackController = PlaybackController(
      backend: backend,
      settingsRepository: settingsRepo,
    );

    final snapshot = CatalogSnapshot(
      tracks: [
        RawTrackDto(
          id: 1,
          filePath: trackA.filePath,
          title: trackA.title,
          durationMs: trackA.durationMs,
          fileSize: trackA.fileSize,
          modifiedAt: trackA.modifiedAt,
        ),
        RawTrackDto(
          id: 2,
          filePath: trackB.filePath,
          title: trackB.title,
          durationMs: trackB.durationMs,
          fileSize: trackB.fileSize,
          modifiedAt: trackB.modifiedAt,
        ),
      ],
      albums: const [],
      artists: const [],
      genres: const [],
      playlists: [
        RawPlaylistDto(id: 1, name: 'Favorites', type: PlaylistType.liked.index, createdAt: 100),
        RawPlaylistDto(id: 2, name: 'History', type: PlaylistType.history.index, createdAt: 200),
        RawPlaylistDto(id: 10, name: 'My Mix', type: PlaylistType.user.index, createdAt: 1000),
      ],
      playlistEntries: const [],
      trackArtists: const [],
      trackGenres: const [],
    );

    store = LibraryStore.fromSnapshot(snapshot);

    libraryController = LibraryController(
      backend: backend,
      settingsRepository: settingsRepo,
      store: store,
    );

    playlistsController = PlaylistsController(
      backend: backend,
      store: store,
    );
  });

  tearDown(() async {
    playlistsController.dispose();
    libraryController.dispose();
    playbackController.dispose();
    settingsController.dispose();
    backend.dispose();
    await db.close();
  });

  Widget buildApp(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('TrackTile has transparent Material wrapper for hover illumination', (tester) async {
    await tester.pumpWidget(
      buildApp(
        TrackTile(track: trackA),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Material with transparency exists enclosing ListTile
    final materialFinder = find.descendant(
      of: find.byType(TrackTile),
      matching: find.byWidgetPredicate((w) => w is Material && w.type == MaterialType.transparency),
    );
    expect(materialFinder, findsOneWidget);

    // Verify ListTile exists inside the Material
    final listTileFinder = find.descendant(
      of: materialFinder,
      matching: find.byType(ListTile),
    );
    expect(listTileFinder, findsOneWidget);
  });

  testWidgets('TrackTile shows popup menu and handles playNext and addToQueue', (tester) async {
    await tester.pumpWidget(
      buildApp(
        TrackTile(track: trackA),
      ),
    );
    await tester.pumpAndSettle();

    // Find the 3-dot popup menu button
    final menuButton = find.descendant(
      of: find.byType(TrackTile),
      matching: find.byType(PopupMenuButton<TrackAction>),
    );
    expect(menuButton, findsOneWidget);

    // Tap menu button
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Verify actions exist in menu
    expect(find.text(localeController.localeStrings.trPlayNext), findsOneWidget);
    expect(find.text(localeController.localeStrings.trAddQueue), findsOneWidget);
    expect(find.text(localeController.localeStrings.trAddPlaylist), findsOneWidget);

    // Tap "Play Next"
    await tester.tap(find.text(localeController.localeStrings.trPlayNext));
    await tester.pumpAndSettle();

    // Verify backend received insertNext
    expect(backend.insertNextTrackIds, contains(trackA.id));

    // Tap menu button again
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Tap "Add to queue"
    await tester.tap(find.text(localeController.localeStrings.trAddQueue));
    await tester.pumpAndSettle();

    // Verify backend received append
    expect(backend.appendTrackIds.any((ids) => ids.contains(trackA.id)), isTrue);
  });

  testWidgets('TrackTile shows Add to Playlist dialog when selected', (tester) async {
    await tester.pumpWidget(
      buildApp(
        TrackTile(track: trackA),
      ),
    );
    await tester.pumpAndSettle();

    final menuButton = find.descendant(
      of: find.byType(TrackTile),
      matching: find.byType(PopupMenuButton<TrackAction>),
    );
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Tap "Add to playlist"
    await tester.tap(find.text(localeController.localeStrings.trAddPlaylist));
    await tester.pumpAndSettle();

    // Dialog should appear with user playlist "My Mix"
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('My Mix'), findsOneWidget);

    // Tap the playlist in dialog
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('PlaylistDetailScreen for user playlist uses unified TrackTile with additionalActions (remove and reorder handle)', (tester) async {
    final userPlaylist = store.playlists.firstWhere((p) => p.type == PlaylistType.user);
    // Add trackA to the user playlist
    store.addTrackToPlaylist(userPlaylist.id!, trackA.id!);

    await tester.pumpWidget(
      buildApp(
        PlaylistDetailScreen(playlist: userPlaylist),
      ),
    );
    await tester.pumpAndSettle();

    // Verify TrackTile is used directly
    expect(find.byType(TrackTile), findsOneWidget);

    // Find the track item
    expect(find.text('Song Alpha'), findsOneWidget);

    // Verify Material with transparency exists for hover illumination
    final materialFinders = find.byWidgetPredicate(
      (w) => w is Material && w.type == MaterialType.transparency && find.descendant(of: find.byWidget(w), matching: find.text('Song Alpha')).evaluate().isNotEmpty,
    );
    expect(materialFinders, findsOneWidget);

    // Verify remove button exists
    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);

    // Verify reorder drag handle exists
    expect(find.byIcon(Icons.drag_handle_rounded), findsOneWidget);

    // Verify actions popup menu exists
    final menuButton = find.byType(PopupMenuButton<TrackAction>);
    expect(menuButton, findsOneWidget);

    // Tap menu button and check play next, add to queue, add to playlist
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(find.text(localeController.localeStrings.trPlayNext), findsOneWidget);
    expect(find.text(localeController.localeStrings.trAddQueue), findsOneWidget);
    expect(find.text(localeController.localeStrings.trAddPlaylist), findsOneWidget);
  });

  testWidgets('PlaylistDetailScreen for liked playlist uses TrackTile with hover Material and actions', (tester) async {
    final likedPlaylist = store.playlists.firstWhere((p) => p.type == PlaylistType.liked);
    store.addTrackToPlaylist(likedPlaylist.id!, trackB.id!);

    await tester.pumpWidget(
      buildApp(
        PlaylistDetailScreen(playlist: likedPlaylist),
      ),
    );
    await tester.pumpAndSettle();

    // Should render TrackTile
    expect(find.byType(TrackTile), findsOneWidget);
    expect(find.text('Song Beta'), findsOneWidget);

    // Verify hover Material exists
    final materialFinder = find.descendant(
      of: find.byType(TrackTile),
      matching: find.byWidgetPredicate((w) => w is Material && w.type == MaterialType.transparency),
    );
    expect(materialFinder, findsOneWidget);

    // Verify actions popup menu exists
    final menuButton = find.descendant(
      of: find.byType(TrackTile),
      matching: find.byType(PopupMenuButton<TrackAction>),
    );
    expect(menuButton, findsOneWidget);
  });
}
