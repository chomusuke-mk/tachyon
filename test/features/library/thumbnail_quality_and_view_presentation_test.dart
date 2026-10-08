import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
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

  group('CoverUtils Triple-Quality JPEG Caching', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('cover_cache_test_');
      CoverUtils.init(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('File path resolution follows _lq.jpg, _mq.jpg, _hq.jpg naming', () {
      const testHash = 'a1b2c3d4e5f6';

      final lqFile = CoverUtils.getCoverFile(
        testHash,
        quality: ThumbnailQuality.low,
      );
      final mqFile = CoverUtils.getCoverFile(
        testHash,
        quality: ThumbnailQuality.medium,
      );
      final hqFile = CoverUtils.getCoverFile(
        testHash,
        quality: ThumbnailQuality.high,
      );

      expect(lqFile.path.endsWith('_lq.jpg'), isTrue);
      expect(mqFile.path.endsWith('_mq.jpg'), isTrue);
      expect(hqFile.path.endsWith('_hq.jpg'), isTrue);
    });

    test('Artist cover file path resolution follows triple quality naming', () {
      const artistHash = 'b2c3d4e5f6a1';

      final lqFile = CoverUtils.getArtistCoverFile(
        artistHash,
        quality: ThumbnailQuality.low,
      );
      final mqFile = CoverUtils.getArtistCoverFile(
        artistHash,
        quality: ThumbnailQuality.medium,
      );
      final hqFile = CoverUtils.getArtistCoverFile(
        artistHash,
        quality: ThumbnailQuality.high,
      );

      expect(lqFile.path.endsWith('_lq.jpg'), isTrue);
      expect(mqFile.path.endsWith('_mq.jpg'), isTrue);
      expect(hqFile.path.endsWith('_hq.jpg'), isTrue);
    });

    test('Album cover file path resolution follows triple quality naming', () {
      const albumHash = 'c3d4e5f6a1b2';

      final lqFile = CoverUtils.getAlbumCoverFile(
        albumHash,
        quality: ThumbnailQuality.low,
      );
      final mqFile = CoverUtils.getAlbumCoverFile(
        albumHash,
        quality: ThumbnailQuality.medium,
      );
      final hqFile = CoverUtils.getAlbumCoverFile(
        albumHash,
        quality: ThumbnailQuality.high,
      );

      expect(lqFile.path.endsWith('_lq.jpg'), isTrue);
      expect(mqFile.path.endsWith('_mq.jpg'), isTrue);
      expect(hqFile.path.endsWith('_hq.jpg'), isTrue);
    });

    test('writeTripleQualityImages generates and saves all 3 qualities in JPEG format', () async {
      // Create a 1000x1000 test image
      final testImg = img.Image(width: 1000, height: 1000);
      img.fill(testImg, color: img.ColorRgb8(255, 0, 0));
      final rawJpegBytes = img.encodeJpg(testImg);
      final hash = CoverUtils.computeBytesHash(rawJpegBytes);

      final lqFile = CoverUtils.getCoverFile(hash, quality: ThumbnailQuality.low);
      final mqFile = CoverUtils.getCoverFile(
        hash,
        quality: ThumbnailQuality.medium,
      );
      final hqFile = CoverUtils.getCoverFile(hash, quality: ThumbnailQuality.high);

      await CoverUtils.writeTripleQualityImages(
        rawJpegBytes,
        [hqFile],
        [mqFile],
        [lqFile],
      );

      // Verify that all 3 files exist on disk
      expect(lqFile.existsSync(), isTrue);
      expect(mqFile.existsSync(), isTrue);
      expect(hqFile.existsSync(), isTrue);
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.low),
        isTrue,
      );
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.medium),
        isTrue,
      );
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.high),
        isTrue,
      );

      // Decode generated images to verify dimensions
      final lqDecoded = img.decodeImage(lqFile.readAsBytesSync())!;
      expect(lqDecoded.width, AppDefaults.lowQualityResolution);
      expect(lqDecoded.height, AppDefaults.lowQualityResolution);

      final mqDecoded = img.decodeImage(mqFile.readAsBytesSync())!;
      expect(mqDecoded.width, AppDefaults.mediumQualityResolution);
      expect(mqDecoded.height, AppDefaults.mediumQualityResolution);

      final hqDecoded = img.decodeImage(hqFile.readAsBytesSync())!;
      expect(hqDecoded.width, AppDefaults.highQualityResolution);
      expect(hqDecoded.height, AppDefaults.highQualityResolution);
    });

    test('writeTripleQualityImages writes to multiple target files in a single pass', () async {
      final testImg = img.Image(width: 800, height: 800);
      img.fill(testImg, color: img.ColorRgb8(0, 0, 255));
      final rawJpegBytes = img.encodeJpg(testImg);

      final files1 = CoverUtils.getTrackFiles('/test/song1.mp3');
      final files2 = CoverUtils.getTrackFiles('/test/song2.mp3');

      await CoverUtils.writeTripleQualityImages(
        rawJpegBytes,
        [files1.hq, files2.hq],
        [files1.mq, files2.mq],
        [files1.lq, files2.lq],
      );

      expect(files1.existsAllSync(), isTrue);
      expect(files2.existsAllSync(), isTrue);
    });

    test('parseArtistNames splits comma-separated artists cleanly', () {
      expect(MetadataService.parseArtistNames('Queen, David Bowie'), [
        'Queen',
        'David Bowie',
      ]);
      expect(
        MetadataService.parseArtistNames('Queen,David Bowie, Freddie Mercury'),
        ['Queen', 'David Bowie', 'Freddie Mercury'],
      );
      expect(MetadataService.parseArtistNames('Cher'), ['Cher']);
      expect(MetadataService.parseArtistNames(''), isEmpty);
      expect(MetadataService.parseArtistNames(null), isEmpty);
    });

    test('Standardized hash methods produce deterministic SHA-256 hashes', () {
      final trackHash = CoverUtils.hashTrack('/music/song.flac');
      final albumHash = CoverUtils.hashAlbum('A Night at the Opera');
      final artistHash = CoverUtils.hashArtist('Queen');

      expect(trackHash, isNotEmpty);
      expect(albumHash, CoverUtils.hashAlbum('  a night at the opera  '));
      expect(artistHash, CoverUtils.hashArtist('QUEEN '));
    });

    test('extractHashFromCoverPath extracts content hash from cover filenames', () {
      expect(
        CoverUtils.extractHashFromCoverPath('/path/to/covers/a1b2c3d4_lq.jpg'),
        'a1b2c3d4',
      );
      expect(
        CoverUtils.extractHashFromCoverPath('/path/to/covers/a1b2c3d4_mq.jpg'),
        'a1b2c3d4',
      );
      expect(
        CoverUtils.extractHashFromCoverPath('/path/to/covers/a1b2c3d4_hq.jpg'),
        'a1b2c3d4',
      );
      expect(
        CoverUtils.extractHashFromCoverPath('a1b2c3d4_hq.jpg'),
        'a1b2c3d4',
      );
      expect(
        CoverUtils.extractHashFromCoverPath('/path/to/covers/a1b2c3d4.jpg'),
        'a1b2c3d4',
      );
    });

    test('CoverFileSet provides unified access across qualities and existence checks', () {
      final files = CoverUtils.getTrackFiles('/music/song.mp3');
      expect(files.lq.path.endsWith('_lq.jpg'), isTrue);
      expect(files.mq.path.endsWith('_mq.jpg'), isTrue);
      expect(files.hq.path.endsWith('_hq.jpg'), isTrue);
      expect(files.getByQuality(ThumbnailQuality.low), files.lq);
      expect(files.getByQuality(ThumbnailQuality.medium), files.mq);
      expect(files.getByQuality(ThumbnailQuality.high), files.hq);
      expect(files.existsAllSync(), isFalse);
    });

    test('saveThumbnailBytes saves and caches image by content hash', () async {
      final testImg = img.Image(width: 800, height: 800);
      img.fill(testImg, color: img.ColorRgb8(0, 255, 0));
      final testJpg = img.encodeJpg(testImg);
      final hash = CoverUtils.computeBytesHash(testJpg);

      await CoverUtils.saveThumbnailBytes(hash, testJpg);

      expect(CoverUtils.hasCachedCover(hash), isTrue);
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.high),
        isTrue,
      );
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.medium),
        isTrue,
      );
      expect(
        CoverUtils.hasCachedCover(hash, quality: ThumbnailQuality.low),
        isTrue,
      );
    });

    test(
      'saveThumbnailBytes is safe when processing identical bytes concurrently',
      () async {
        final testImg = img.Image(width: 800, height: 800);
        img.fill(testImg, color: img.ColorRgb8(120, 40, 200));
        final testJpg = img.encodeJpg(testImg);
        final hash = CoverUtils.computeBytesHash(testJpg);

        // Concurrently save identical thumbnail bytes
        await Future.wait<File?>([
          CoverUtils.saveThumbnailBytes(hash, testJpg, force: true),
          CoverUtils.saveThumbnailBytes(hash, testJpg, force: true),
        ]);

        final hqFile = CoverUtils.getCoverFile(
          hash,
          quality: ThumbnailQuality.high,
        );
        final mqFile = CoverUtils.getCoverFile(
          hash,
          quality: ThumbnailQuality.medium,
        );
        final lqFile = CoverUtils.getCoverFile(
          hash,
          quality: ThumbnailQuality.low,
        );

        expect(hqFile.existsSync(), isTrue);
        expect(mqFile.existsSync(), isTrue);
        expect(lqFile.existsSync(), isTrue);

        final decodedHq = img.decodeImage(hqFile.readAsBytesSync());
        expect(decodedHq, isNotNull);
        expect(decodedHq!.width, AppDefaults.highQualityResolution);
      },
    );

    test(
      'clearTemp removes temporary files without touching saved covers',
      () async {
        final testImg = img.Image(width: 400, height: 400);
        final testJpg = img.encodeJpg(testImg);
        final hash = CoverUtils.computeBytesHash(testJpg);

        await CoverUtils.saveThumbnailBytes(hash, testJpg);
        expect(CoverUtils.hasCachedCover(hash), isTrue);

        // Create a dummy leftover temporary file in tempDir
        final tempFile = File('${CoverUtils.tempDir.path}/leftover_worker.tmp')
          ..writeAsStringSync('stale temp content');
        expect(tempFile.existsSync(), isTrue);

        await CoverUtils.clearTemp();

        expect(tempFile.existsSync(), isFalse);
        expect(CoverUtils.hasCachedCover(hash), isTrue);
      },
    );
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
