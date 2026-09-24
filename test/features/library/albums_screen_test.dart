import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
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
  late MetadataExtractor extractor;
  late LibraryController libraryController;
  late LocaleController localeController;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_albums_test_');
    db = AppDatabase.inMemory();
    coverCacheService = CoverCacheService(cacheDirectory: tempDir);
    await coverCacheService.init();

    extractor = MetadataExtractor(
      database: db,
      coverCacheService: coverCacheService,
    );
    libraryController = LibraryController(
      database: db,
      metadataExtractor: extractor,
      coverCacheService: coverCacheService,
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

  testWidgets('AlbumsScreen selects track with cached cover over track without cover', (tester) async {
    // Two tracks for "Greatest Hits" album:
    // Track 1 does NOT have a cached cover
    // Track 2 DOES have a cached cover
    const track1 = Track(
      uri: '/media/album1/01-intro.mp3',
      title: 'Intro',
      album: 'Greatest Hits',
      artist: 'Best Band',
      durationMs: 60000,
      fileSize: 100000,
      modifiedAt: 1000,
    );
    const track2 = Track(
      uri: '/media/album1/02-hit.mp3',
      title: 'Hit Song',
      album: 'Greatest Hits',
      artist: 'Best Band',
      durationMs: 200000,
      fileSize: 500000,
      modifiedAt: 1000,
    );

    await db.batchInsertTracks([track1, track2]);
    await libraryController.loadLibrary();

    // Create a dummy cached cover image file for track2 only
    final track2Cover = coverCacheService.getCoverFile(track2.uri);
    final transparentPng = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    track2Cover.parent.createSync(recursive: true);
    track2Cover.writeAsBytesSync(transparentPng);

    expect(coverCacheService.hasCachedCover(track1.uri), isFalse);
    expect(coverCacheService.hasCachedCover(track2.uri), isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: localeController),
          ChangeNotifierProvider.value(value: libraryController),
          Provider<CoverCacheService>.value(value: coverCacheService),
          Provider<CoverCacheService?>.value(value: coverCacheService),
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

    // Verify AlbumArtImage received the URI of track2 (the one with the cached cover)
    final albumArtFinder = find.byType(AlbumArtImage);
    expect(albumArtFinder, findsOneWidget);
    final albumArtWidget = tester.widget<AlbumArtImage>(albumArtFinder);
    expect(albumArtWidget.uri, equals(track2.uri));
  });
}
