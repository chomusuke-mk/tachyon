import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SettingsRepository settingsRepo;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;
  });

  testWidgets('AmbientBackdrop renders blur filter and gradient overlay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientBackdrop(
            thumbnailHash: 'test_hash_123',
          ),
        ),
      ),
    );

    expect(find.byType(AmbientBackdrop), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('AmbientBackdrop without image renders only gradient overlay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientBackdrop(thumbnailHash: null),
        ),
      ),
    );

    expect(find.byType(AmbientBackdrop), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('AlbumDetailScreen renders AmbientBackdrop with thumbnailHash', (tester) async {
    final track = Track(
      id: 1,
      filePath: '/music/album_track.mp3',
      title: 'Album Track',
      durationMs: 180000,
      fileSize: 1000,
      modifiedAt: 0,
      artists: const [Artist(id: 1, name: 'The Band')],
    );
    final album = Album(
      id: 10,
      name: 'Greatest Hits',
      artist: const Artist(id: 1, name: 'The Band'),
      tracks: [track],
      thumbnailHash: 'album_hash_123',
    );

    final db = AppDatabase.inMemory();
    final backend = DirectTachyonBackendClient(database: db);
    final playback = PlaybackController(backend: backend, settingsRepository: settingsRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: localeController),
          ChangeNotifierProvider.value(value: playback),
        ],
        child: MaterialApp(
          home: AlbumDetailScreen(album: album),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backdropFinder = find.byType(AmbientBackdrop);
    expect(backdropFinder, findsOneWidget);
    final backdrop = tester.widget<AmbientBackdrop>(backdropFinder);
    expect(backdrop.thumbnailHash, equals('album_hash_123'));

    playback.dispose();
    await backend.dispose();
    await db.close();
  });

  testWidgets('ArtistDetailScreen renders AmbientBackdrop with thumbnailHash', (tester) async {
    final track = Track(
      id: 2,
      filePath: '/music/artist_track.mp3',
      title: 'Artist Song',
      durationMs: 200000,
      fileSize: 1000,
      modifiedAt: 0,
    );
    final artist = Artist(
      id: 5,
      name: 'Legendary Artist',
      tracks: [track],
      thumbnailHash: 'artist_hash_456',
    );

    final db = AppDatabase.inMemory();
    final backend = DirectTachyonBackendClient(database: db);
    final snapshot = CatalogSnapshot(
      tracks: [
        const RawTrackDto(
          id: 2,
          filePath: '/music/artist_track.mp3',
          title: 'Artist Song',
          durationMs: 200000,
          fileSize: 1000,
          modifiedAt: 0,
        ),
      ],
      albums: const [],
      artists: [const RawArtistDto(id: 5, name: 'Legendary Artist', thumbnailHash: 'artist_hash_456')],
      genres: const [],
      playlists: const [],
      playlistEntries: const [],
      trackArtists: [const TrackArtistPair(trackId: 2, artistId: 5)],
      trackGenres: const [],
    );
    final store = LibraryStore.fromSnapshot(snapshot);
    final library = LibraryController(backend: backend, settingsRepository: settingsRepo, store: store);
    final playback = PlaybackController(backend: backend, settingsRepository: settingsRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: localeController),
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: playback),
        ],
        child: MaterialApp(
          home: ArtistDetailScreen(artist: artist),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backdropFinder = find.byType(AmbientBackdrop);
    expect(backdropFinder, findsOneWidget);
    final backdrop = tester.widget<AmbientBackdrop>(backdropFinder);
    expect(backdrop.thumbnailHash, equals('artist_hash_456'));

    library.dispose();
    playback.dispose();
    await backend.dispose();
    await db.close();
  });
}
