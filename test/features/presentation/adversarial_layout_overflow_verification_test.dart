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
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/genres_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_screen.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

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

CatalogSnapshot _buildTestSnapshot() {
  return const CatalogSnapshot(
    tracks: [
      RawTrackDto(
        id: 1,
        filePath: '/music/track1.mp3',
        title: 'Track One',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 1000,
        albumId: 10,
      ),
    ],
    albums: [
      RawAlbumDto(id: 10, name: 'Album One', year: 2020, artistId: 1),
    ],
    artists: [
      RawArtistDto(id: 1, name: 'Artist One'),
    ],
    genres: [],
    playlists: [],
    trackArtists: [
      TrackArtistPair(trackId: 1, artistId: 1),
    ],
    trackGenres: [],
    playlistEntries: [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController esLocaleController;
  late LocaleController enLocaleController;
  late SettingsRepository settingsRepository;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(prefs);

    final localeRepo = _FileSystemLocaleRepository();
    esLocaleController = LocaleController(localeRepo, 'es');
    await esLocaleController.whenReady;

    enLocaleController = LocaleController(localeRepo, 'en');
    await enLocaleController.whenReady;
  });

  group('Adversarial Layout Overflow & Stress Harness', () {
    testWidgets('ADV-1: PlaylistDetailScreen action buttons wrap cleanly at 360px & 320px in Spanish', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      const track = Track(
        id: 101,
        filePath: '/music/very_long_named_track_supercalifragilistic.mp3',
        title: 'Supercalifragilisticoespialidoso Canción con Título Extremadamente Largo para Forzar Flex',
        durationMs: 3754000,
        fileSize: 5000000,
        modifiedAt: 1000,
        artists: [Artist(id: 1, name: 'Artista con Nombre Extremadamente Largo de Muestra', tracks: [])],
        album: Album(id: 1, name: 'Álbum con Título Gigantesco', tracks: []),
      );

      final playlist = Playlist(
        id: 1,
        name: 'Mi Lista de Reproducción con Nombre Extraordinariamente Largo para Probar Text Wrapping',
        createdAt: 1000,
        entries: [
          PlaylistEntry(id: 1, position: 0, addedAt: 1000, track: track),
        ],
      );

      for (final width in [360.0, 320.0]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;

        FlutterErrorDetails? caughtOverflowError;
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
            caughtOverflowError = details;
          } else {
            originalOnError?.call(details);
          }
        };

        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
                ChangeNotifierProvider<PlaybackController>.value(value: playbackCtrl),
                ChangeNotifierProvider<PlaylistsController>.value(value: playlistsCtrl),
              ],
              child: MaterialApp(
                home: PlaylistDetailScreen(playlist: playlist),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(caughtOverflowError, isNull,
              reason: 'PlaylistDetailScreen must not trigger RenderFlex overflow at ${width}px in Spanish');
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = originalOnError;
        }
      }

      tester.view.resetPhysicalSize();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await db.close();
    });

    testWidgets('ADV-2: TracksScreen sort popup menu opens without overflow at 360px & 320px in Spanish', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore.fromSnapshot(_buildTestSnapshot());

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      for (final width in [360.0, 320.0]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;

        FlutterErrorDetails? caughtOverflowError;
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
            caughtOverflowError = details;
          } else {
            originalOnError?.call(details);
          }
        };

        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
                ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
                ChangeNotifierProvider<PlaybackController>.value(value: playbackCtrl),
                ChangeNotifierProvider<PlaylistsController>.value(value: playlistsCtrl),
              ],
              child: const MaterialApp(
                home: TracksScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Tap the sort button (IconButton with popup menu)
          final sortButton = find.byType(PopupMenuButton<TrackSortOption>);
          expect(sortButton, findsOneWidget);
          await tester.tap(sortButton);
          await tester.pumpAndSettle();

          expect(caughtOverflowError, isNull,
              reason: 'TracksScreen sort popup menu must not overflow at ${width}px in Spanish');
          expect(tester.takeException(), isNull);

          // Close popup menu
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = originalOnError;
        }
      }

      tester.view.resetPhysicalSize();
      libraryCtrl.dispose();
      playbackCtrl.dispose();
      playlistsCtrl.dispose();
      await db.close();
    });

    testWidgets('ADV-3: PlaylistsScreen options popup menu opens without overflow at 360px in Spanish', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final playlistsCtrl = PlaylistsController(
        backend: backend,
        store: store,
      );

      // Create a playlist
      db.createPlaylist('Playlist Test');
      await playlistsCtrl.loadPlaylists();

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<PlaylistsController>.value(value: playlistsCtrl),
            ],
            child: const MaterialApp(
              home: PlaylistsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final popup = find.byType(PopupMenuButton<String>);
        if (popup.evaluate().isNotEmpty) {
          await tester.tap(popup.first);
          await tester.pumpAndSettle();
        }

        expect(caughtOverflowError, isNull,
            reason: 'PlaylistsScreen popup menu must not overflow at 360px in Spanish');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
        tester.view.resetPhysicalSize();
        playlistsCtrl.dispose();
        await db.close();
      }
    });

    testWidgets('ADV-4: TrackTile with extreme text length (200 chars title, 10 artists, long album) renders and opens popup menu cleanly at 360px & 320px in Spanish & English', (tester) async {
      final manyArtists = List.generate(
        10,
        (i) => Artist(id: i + 1, name: 'Artista Extraordinariamente Largo Número $i', tracks: []),
      );
      final track = Track(
        id: 999,
        filePath: '/music/huge_track.mp3',
        title: 'Título Gigantesco ' * 10,
        durationMs: 9999999,
        fileSize: 10000000,
        modifiedAt: 1000,
        artists: manyArtists,
        album: const Album(id: 1, name: 'Álbum con Nombre Infinito ' '1234567890 ' 'ABCDEFGHIJ ', tracks: []),
      );

      for (final locale in [esLocaleController, enLocaleController]) {
        for (final width in [360.0, 320.0]) {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1.0;

          FlutterErrorDetails? caughtOverflowError;
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
              caughtOverflowError = details;
            } else {
              originalOnError?.call(details);
            }
          };

          try {
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<LocaleController>.value(value: locale),
                ],
                child: MaterialApp(
                  home: Scaffold(
                    body: TrackTile(
                      track: track,
                      onActionSelected: (_) {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(caughtOverflowError, isNull,
                reason: 'TrackTile must not overflow while idle at ${width}px with long text');
            expect(tester.takeException(), isNull);

            // Open popup menu
            final popupFinder = find.byType(PopupMenuButton<TrackAction>);
            expect(popupFinder, findsOneWidget);
            await tester.tap(popupFinder);
            await tester.pumpAndSettle();

            expect(caughtOverflowError, isNull,
                reason: 'TrackTile popup menu must not overflow at ${width}px');
            expect(tester.takeException(), isNull);

            // Dismiss menu
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          } finally {
            FlutterError.onError = originalOnError;
          }
        }
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('ADV-5: AlbumDetailScreen and ArtistDetailScreen at extreme 300px narrow viewport in Spanish', (tester) async {
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      const track = Track(
        id: 1,
        filePath: '/music/t1.mp3',
        title: 'Canción con Título Moderadamente Largo',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
        artists: [],
        album: null,
      );
      final album = Album(id: 1, name: 'Álbum Complejo de Prueba', tracks: [track]);
      final artist = Artist(id: 1, name: 'Artista Complejo de Prueba', tracks: [track]);

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: MaterialApp(
              home: AlbumDetailScreen(album: album),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'AlbumDetailScreen action buttons must wrap cleanly even at 300px width in Spanish');
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: MaterialApp(
              home: ArtistDetailScreen(artist: artist),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'ArtistDetailScreen action buttons must wrap cleanly even at 300px width in Spanish');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
        libraryCtrl.dispose();
        playback.dispose();
        await db.close();
      }
    });

    testWidgets('ADV-6: SearchScreen and GenresScreen render cleanly at 360px viewport in Spanish', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);
      final store = LibraryStore();
      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playback = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );
      final searchCtrl = TachyonSearchController(store: store);

      FlutterErrorDetails? caughtOverflowError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          caughtOverflowError = details;
        } else {
          originalOnError?.call(details);
        }
      };

      try {
        // GenresScreen
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: const MaterialApp(
              home: GenresScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'GenresScreen must render cleanly at 360px width');
        expect(tester.takeException(), isNull);

        // SearchScreen
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleController>.value(value: esLocaleController),
              ChangeNotifierProvider<LibraryController>.value(value: libraryCtrl),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
              ChangeNotifierProvider<TachyonSearchController>.value(value: searchCtrl),
            ],
            child: const MaterialApp(
              home: SearchScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(caughtOverflowError, isNull,
            reason: 'SearchScreen must render cleanly at 360px width');
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = originalOnError;
        searchCtrl.dispose();
        libraryCtrl.dispose();
        playback.dispose();
        await db.close();
      }
    });
  });
}
