import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

class _FakeLocaleRepository implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return {
      'al_title': 'Albums',
      'al_no_albums': 'No Albums Found',
      'al_no_albums_desc': 'Your albums will appear here',
      'al_tracks_count': '{count} tracks',
      'al_sort': 'Sort',
      'al_sort_title': 'Title',
      'al_sort_artist': 'Artist',
      'al_sort_year': 'Year',
      'al_sort_track_count': 'Track Count',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CoverCacheService coverCacheService;
  late MetadataService metadataService;
  late DirectTachyonBackendClient backend;
  late LibraryController libraryController;
  late LocaleController localeController;
  late SettingsRepository settingsRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_albums_test_');
    db = AppDatabase.inMemory();
    coverCacheService = CoverCacheService(cacheDirectory: tempDir);
    await coverCacheService.init();

    metadataService = MetadataService(
      database: db,
      coverCacheService: coverCacheService,
    );
    backend = DirectTachyonBackendClient(
      database: db,
      metadataService: metadataService,
      coverCacheService: coverCacheService,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(prefs);
    libraryController = LibraryController(
      backend: backend,
      settingsRepository: settingsRepository,
    );
    localeController = LocaleController(_FakeLocaleRepository(), 'en');
    await localeController.whenReady;
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('AlbumsScreen renders albums and passes album track uri to AlbumArtImage', (tester) async {
    const track1 = Track(
      filePath: '/media/album1/01-intro.mp3',
      title: 'Intro',
      album: 'Greatest Hits',
      artist: 'Best Band',
      durationMs: 60000,
      fileSize: 100000,
      modifiedAt: 1000,
    );
    const track2 = Track(
      filePath: '/media/album1/02-hit.mp3',
      title: 'Hit Song',
      album: 'Greatest Hits',
      artist: 'Best Band',
      durationMs: 200000,
      fileSize: 500000,
      modifiedAt: 1000,
    );

    await db.batchInsertTracks([track1, track2]);
    await libraryController.loadLibrary();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: localeController),
          ChangeNotifierProvider.value(value: libraryController),
          Provider<TachyonBackendClient>.value(value: backend),
        ],
        child: const MaterialApp(
          home: AlbumsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify album title is rendered
    expect(find.text('Greatest Hits'), findsOneWidget);

    // Verify AlbumArtImage received the URI of the first album track sorted by title (Hit Song)
    final albumArtFinder = find.byType(AlbumArtImage);
    expect(albumArtFinder, findsOneWidget);
    final albumArtWidget = tester.widget<AlbumArtImage>(albumArtFinder);
    expect(albumArtWidget.filePath, equals(track2.filePath));
  });
}
