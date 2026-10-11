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

  testWidgets(
      'showAddToPlaylistDialog displays playlists with icon, count, and add button, and updates reactively when new playlist created',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () =>
                  TrackActionHelper.showAddToPlaylistDialog(context, trackA),
              child: const Text('Open Dialog'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsOneWidget,
    );

    // Verify existing user playlist "My Mix"
    expect(find.text('My Mix'), findsOneWidget);
    // Track count should be "0 tracks"
    expect(
      find.text(localeController.localeStrings.plTracksCountFormatted(0)),
      findsOneWidget,
    );
    // Trailing add icon button exists
    expect(find.byIcon(Icons.add_rounded), findsWidgets);

    // Tap "Create playlist" button in actions
    await tester.tap(find.text(localeController.localeStrings.plCreateNew));
    await tester.pumpAndSettle();

    // Enter new playlist name
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Workout Beats');
    await tester.pumpAndSettle();

    // Tap "Create" button
    await tester.tap(find.text(localeController.localeStrings.plCreateButton));
    await tester.pumpAndSettle();

    // The add-to-playlist dialog is STILL OPEN and now shows the new playlist!
    expect(find.text('Workout Beats'), findsOneWidget);
    expect(find.text('My Mix'), findsOneWidget);
    // "Workout Beats" also has "0 tracks"
    expect(
      find.text(localeController.localeStrings.plTracksCountFormatted(0)),
      findsNWidgets(2),
    );
  });

  testWidgets(
      'showAddToPlaylistDialog shows duplicate warning when track is already in playlist',
      (tester) async {
    // Add trackA to "My Mix" first
    final userPl = store.playlists.firstWhere((p) => p.name == 'My Mix');
    store.addTrackToPlaylist(userPl.id!, trackA.id!);
    playlistsController.updateStore(store);

    await tester.pumpWidget(
      buildApp(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () =>
                  TrackActionHelper.showAddToPlaylistDialog(context, trackA),
              child: const Text('Open Dialog'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify track count reflects 1 track
    expect(
      find.text(localeController.localeStrings.plTracksCountFormatted(1)),
      findsOneWidget,
    );

    // Tap "My Mix" playlist tile to add trackA again
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Warning dialog should appear
    expect(
      find.text(localeController.localeStrings.plDuplicateTitle),
      findsOneWidget,
    );
    expect(
      find.text(
        localeController.localeStrings.plDuplicateConfirmFormatted('My Mix'),
      ),
      findsOneWidget,
    );
    final warningDialogFinder = find.byWidgetPredicate(
      (w) =>
          w is AlertDialog &&
          find
              .descendant(
                of: find.byWidget(w),
                matching:
                    find.text(localeController.localeStrings.plDuplicateTitle),
              )
              .evaluate()
              .isNotEmpty,
    );
    expect(warningDialogFinder, findsOneWidget);

    final warningCancelButton = find.descendant(
      of: warningDialogFinder,
      matching: find.text(localeController.localeStrings.plCancelButton),
    );
    expect(warningCancelButton, findsOneWidget);
    expect(
      find.text(localeController.localeStrings.plAddAnyway),
      findsOneWidget,
    );

    // Test Cancel first
    await tester.tap(warningCancelButton);
    await tester.pumpAndSettle();

    // Warning dialog dismissed, parent dialog still open
    expect(
      find.text(localeController.localeStrings.plDuplicateTitle),
      findsNothing,
    );
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsOneWidget,
    );
    // Count remains 1
    expect(userPl.entries.length, 1);

    // Tap "My Mix" again
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Tap "Add anyway"
    await tester.tap(find.text(localeController.localeStrings.plAddAnyway));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsNothing,
    );
    // Track count should now be 2
    expect(userPl.entries.length, 2);
  });

  testWidgets(
      'showAddQueueToPlaylistDialog adds entire queue when no duplicates',
      (tester) async {
    final userPl = store.playlists.firstWhere((p) => p.name == 'My Mix');
    expect(userPl.entries.isEmpty, isTrue);

    final queue = [
      PlaylistEntry.forQueue(id: 1, position: 0, track: trackA),
      PlaylistEntry.forQueue(id: 2, position: 1, track: trackB),
    ];

    await tester.pumpWidget(
      buildApp(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () =>
                  TrackActionHelper.showAddQueueToPlaylistDialog(context, queue),
              child: const Text('Open Queue Dialog'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Queue Dialog'));
    await tester.pumpAndSettle();

    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsOneWidget,
    );
    expect(find.text('My Mix'), findsOneWidget);

    // Tap "My Mix"
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Dialog dismissed immediately since no duplicates
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsNothing,
    );
    // userPl now has 2 entries (trackA and trackB)
    expect(userPl.entries.length, 2);
    expect(userPl.entries[0].track?.id, trackA.id);
    expect(userPl.entries[1].track?.id, trackB.id);
  });

  testWidgets(
      'showAddQueueToPlaylistDialog with duplicates presents 3 options and handles each',
      (tester) async {
    final userPl = store.playlists.firstWhere((p) => p.name == 'My Mix');
    store.addTrackToPlaylist(userPl.id!, trackA.id!);
    playlistsController.updateStore(store);

    expect(userPl.entries.length, 1);

    final queue = [
      PlaylistEntry.forQueue(id: 1, position: 0, track: trackA),
      PlaylistEntry.forQueue(id: 2, position: 1, track: trackB),
    ];

    await tester.pumpWidget(
      buildApp(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () =>
                  TrackActionHelper.showAddQueueToPlaylistDialog(context, queue),
              child: const Text('Open Queue Dialog'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Queue Dialog'));
    await tester.pumpAndSettle();

    // Tap "My Mix" to trigger duplicate warning
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Verify warning dialog title and message
    expect(
      find.text(localeController.localeStrings.plDuplicateQueueTitle),
      findsOneWidget,
    );
    expect(
      find.text(
        localeController.localeStrings.plDuplicateQueueConfirmFormatted('My Mix'),
      ),
      findsOneWidget,
    );

    final warningDialogFinder = find.byWidgetPredicate(
      (w) =>
          w is AlertDialog &&
          find
              .descendant(
                of: find.byWidget(w),
                matching:
                    find.text(localeController.localeStrings.plDuplicateQueueTitle),
              )
              .evaluate()
              .isNotEmpty,
    );
    expect(warningDialogFinder, findsOneWidget);

    // Verify 3 options:
    // 1. Cancel
    final cancelBtn = find.descendant(
      of: warningDialogFinder,
      matching: find.text(localeController.localeStrings.plCancelButton),
    );
    expect(cancelBtn, findsOneWidget);

    // 2. Add anyway
    final addAnywayBtn = find.descendant(
      of: warningDialogFinder,
      matching: find.text(localeController.localeStrings.plAddAnyway),
    );
    expect(addAnywayBtn, findsOneWidget);

    // 3. Insert only new (1)
    final onlyNewBtn = find.descendant(
      of: warningDialogFinder,
      matching: find.text(
        localeController.localeStrings.plInsertOnlyNewFormatted(1),
      ),
    );
    expect(onlyNewBtn, findsOneWidget);

    // Test Option 1: Cancel
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();

    // Warning closed, parent dialog still open, count still 1
    expect(
      find.text(localeController.localeStrings.plDuplicateQueueTitle),
      findsNothing,
    );
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsOneWidget,
    );
    expect(userPl.entries.length, 1);

    // Tap "My Mix" again
    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Test Option 3: Insert only new (1)
    await tester.tap(
      find.text(localeController.localeStrings.plInsertOnlyNewFormatted(1)),
    );
    await tester.pumpAndSettle();

    // Dialog closed, only trackB was inserted (total 2)
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsNothing,
    );
    expect(userPl.entries.length, 2);
    expect(userPl.entries[0].track?.id, trackA.id);
    expect(userPl.entries[1].track?.id, trackB.id);

    // Now test Option 2: Add anyway when duplicates exist
    await tester.tap(find.text('Open Queue Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Mix'));
    await tester.pumpAndSettle();

    // Now both trackA and trackB are duplicates! New count is 0.
    final onlyNewZero = find.text(
      localeController.localeStrings.plInsertOnlyNewFormatted(0),
    );
    expect(onlyNewZero, findsOneWidget);
    // Button should be disabled
    final filledBtnWidget = tester.widget<FilledButton>(
      find.ancestor(of: onlyNewZero, matching: find.byType(FilledButton)),
    );
    expect(filledBtnWidget.onPressed, isNull);

    // Tap Add anyway
    await tester.tap(find.text(localeController.localeStrings.plAddAnyway));
    await tester.pumpAndSettle();

    // Dialog dismissed, both tracks added anyway (total 4)
    expect(
      find.text(localeController.localeStrings.trAddPlaylist),
      findsNothing,
    );
    expect(userPl.entries.length, 4);
  });
}
