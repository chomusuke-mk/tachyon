import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
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

CatalogSnapshot _createSampleSnapshot() {
  final artists = [
    const RawArtistDto(id: 1, name: 'The Beatles'),
    const RawArtistDto(id: 2, name: 'Pink Floyd'),
  ];

  final albums = [
    const RawAlbumDto(id: 10, name: 'Abbey Road', year: 1969, artistId: 1),
    const RawAlbumDto(
      id: 20,
      name: 'The Dark Side of the Moon',
      year: 1973,
      artistId: 2,
    ),
  ];

  final genres = [
    const RawGenreDto(id: 100, name: 'Rock'),
  ];

  final tracks = [
    const RawTrackDto(
      id: 1001,
      filePath: '/music/beatles/come_together.mp3',
      title: 'Come Together',
      trackNumber: 1,
      discNumber: 1,
      year: 1969,
      durationMs: 259000,
      fileSize: 6200000,
      modifiedAt: 1000,
      albumId: 10,
    ),
    const RawTrackDto(
      id: 1002,
      filePath: '/music/beatles/something.mp3',
      title: 'Something',
      trackNumber: 2,
      discNumber: 1,
      year: 1969,
      durationMs: 182000,
      fileSize: 4500000,
      modifiedAt: 1000,
      albumId: 10,
    ),
  ];

  final trackArtists = [
    const TrackArtistPair(trackId: 1001, artistId: 1),
    const TrackArtistPair(trackId: 1002, artistId: 1),
  ];

  final trackGenres = [
    const TrackGenrePair(trackId: 1001, genreId: 100),
    const TrackGenrePair(trackId: 1002, genreId: 100),
  ];

  return CatalogSnapshot(
    tracks: tracks,
    albums: albums,
    artists: artists,
    genres: genres,
    playlists: const [],
    playlistEntries: const [],
    trackArtists: trackArtists,
    trackGenres: trackGenres,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailQuality and AppDefaults Constants', () {
    test('ThumbnailQuality has low, medium, and high values', () {
      expect(ThumbnailQuality.values, [
        ThumbnailQuality.low,
        ThumbnailQuality.medium,
        ThumbnailQuality.high,
      ]);
    });

    test('AppDefaults thumbnail resolutions match specification', () {
      expect(AppDefaults.lowQualityResolution, 50);
      expect(AppDefaults.mediumQualityResolution, 250);
      expect(AppDefaults.highQualityResolution, 800);
    });
  });

  group('MetadataUtils Triple-Quality PNG Caching', () {
    late Directory tempDir;
    late Directory thumbnailsDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('metadata_temp_test_');
      thumbnailsDir = Directory.systemTemp.createTempSync('metadata_thumb_test_');
      MetadataUtils.init(thumbnailsDir.path, tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      if (thumbnailsDir.existsSync()) {
        thumbnailsDir.deleteSync(recursive: true);
      }
    });

    test('File path resolution follows _low.png, _medium.png, _high.png naming', () {
      const testHash = 'a1b2c3d4e5f6';

      final lqPath = MetadataUtils.getThumbnailFilePath(
        testHash,
        quality: ThumbnailQuality.low,
      );
      final mqPath = MetadataUtils.getThumbnailFilePath(
        testHash,
        quality: ThumbnailQuality.medium,
      );
      final hqPath = MetadataUtils.getThumbnailFilePath(
        testHash,
        quality: ThumbnailQuality.high,
      );

      expect(lqPath.endsWith('_low.png'), isTrue);
      expect(mqPath.endsWith('_medium.png'), isTrue);
      expect(hqPath.endsWith('_high.png'), isTrue);
    });

    test('extractHashFromThumbnailPath extracts content hash from thumbnail filenames', () {
      expect(
        MetadataUtils.extractHashFromThumbnailPath('/path/to/covers/a1b2c3d4_low.png'),
        'a1b2c3d4',
      );
      expect(
        MetadataUtils.extractHashFromThumbnailPath('/path/to/covers/a1b2c3d4_medium.png'),
        'a1b2c3d4',
      );
      expect(
        MetadataUtils.extractHashFromThumbnailPath('/path/to/covers/a1b2c3d4_high.png'),
        'a1b2c3d4',
      );
      expect(
        MetadataUtils.extractHashFromThumbnailPath('a1b2c3d4_high.png'),
        'a1b2c3d4',
      );
    });

    test('Standardized hash methods produce deterministic SHA-256 hashes', () {
      final bytesHash = ParserUtils.computeBytesHash(Uint8List.fromList([1, 2, 3, 4]));
      final strHash = ParserUtils.computeStringHash('Queen');

      expect(bytesHash, isNotEmpty);
      expect(strHash, ParserUtils.computeStringHash('Queen'));
    });

    test('hasCachedThumbnail and listCachedThumbnails track saved files', () {
      const hash = 'a1b2c3d4e5f6';
      expect(MetadataUtils.hasCachedThumbnail(hash), isFalse);

      final lqFile = File(
        MetadataUtils.getThumbnailFilePath(hash, quality: ThumbnailQuality.low),
      );
      lqFile.writeAsStringSync('dummy_thumbnail_content');

      expect(
        MetadataUtils.hasCachedThumbnail(hash, quality: ThumbnailQuality.low),
        isTrue,
      );
      expect(
        MetadataUtils.hasCachedThumbnail(hash, quality: ThumbnailQuality.high),
        isFalse,
      );
      expect(MetadataUtils.listCachedThumbnails().length, 1);
    });

    test('clearTempDirectory removes temporary files without touching saved covers', () async {
      const hash = 'saved_hash_123';
      final savedFile = File(
        MetadataUtils.getThumbnailFilePath(hash, quality: ThumbnailQuality.low),
      );
      savedFile.writeAsStringSync('saved cover content');
      expect(savedFile.existsSync(), isTrue);

      final tempFile = File('${MetadataUtils.tempDirectory!.path}/leftover_worker.tmp')
        ..writeAsStringSync('stale temp content');
      expect(tempFile.existsSync(), isTrue);

      await MetadataUtils.clearTempDirectory();

      expect(tempFile.existsSync(), isFalse);
      expect(savedFile.existsSync(), isTrue);
    });
  });

  group('Presentation View Modes (List vs Cards) UI Integration', () {
    late AppDatabase db;
    late DirectTachyonBackendClient backendClient;
    late SettingsRepository settings;
    late PlaylistsController playlists;
    late PlaybackController playback;
    late LibraryStore libraryStore;
    late LibraryController libraryController;
    late LocaleController localeController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.inMemory();
      backendClient = DirectTachyonBackendClient(database: db);
      settings = SettingsRepository(prefs);
      playlists = PlaylistsController(
        backend: backendClient,
      );
      playback = PlaybackController(
        backend: backendClient,
        settingsRepository: settings,
      );
      libraryStore = LibraryStore.fromSnapshot(_createSampleSnapshot());
      libraryController = LibraryController(
        backend: backendClient,
        settingsRepository: settings,
        store: libraryStore,
      );

      final localeRepo = _FileSystemLocaleRepository();
      localeController = LocaleController(localeRepo, 'en');
      await localeController.whenReady;
    });

    tearDown(() async {
      libraryController.dispose();
      playback.dispose();
      playlists.dispose();
      await backendClient.dispose();
      await db.close();
    });

    Widget createTestWidget(Widget child) {
      return MultiProvider(
        providers: [
          Provider<TachyonBackendClient>.value(value: backendClient),
          Provider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider<PlaylistsController>.value(value: playlists),
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LibraryController>.value(value: libraryController),
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('TracksScreen defaults to List view and toggles to Cards view', (tester) async {
      await tester.pumpWidget(createTestWidget(const TracksScreen()));
      await tester.pumpAndSettle();

      // Default: List view with ListView and grid toggle icon (4 squares)
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);

      // Tap toggle button to switch to Cards view
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      // In Cards view: GridView is active and list toggle icon is displayed
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

      // Tap again to switch back to List view
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    });

    testWidgets('AlbumsScreen defaults to Cards view and toggles to List view', (tester) async {
      await tester.pumpWidget(createTestWidget(const AlbumsScreen()));
      await tester.pumpAndSettle();

      // Default: Cards view with GridView and list toggle icon
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

      // Tap toggle button to switch to List view
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      // In List view: ListView is active and grid toggle icon is displayed
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);

      // Tap again to switch back to Cards view
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    });

    testWidgets('ArtistsScreen defaults to Cards view and toggles to List view', (tester) async {
      await tester.pumpWidget(createTestWidget(const ArtistsScreen()));
      await tester.pumpAndSettle();

      // Default: Cards view with GridView and list toggle icon
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

      // Tap toggle button to switch to List view
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      // In List view: ListView is active and grid toggle icon is displayed
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);

      // Tap again to switch back to Cards view
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    });
  });

  group('Localization Keys', () {
    test('common_view_as_cards and common_view_as_list exist in all keys', () {
      final keys = AppStringKey().allKeys;
      expect(keys.contains('common_view_as_cards'), isTrue);
      expect(keys.contains('common_view_as_list'), isTrue);
      expect(keys.contains('scan_stage_idle'), isTrue);
      expect(keys.contains('scan_stage_extracting'), isTrue);
      expect(keys.contains('scan_cancel_tooltip'), isTrue);
      expect(keys.contains('tr_shuffle_all'), isTrue);
    });
  });
}
