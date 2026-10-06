import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/genre.dart';
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
import 'package:tachyon/features/playlists/presentation/playlist_cover_helper.dart';
import 'package:tachyon/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_screen.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
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

class _PlaybackTestBackendClient extends DirectTachyonBackendClient {
  final StreamController<PlaybackState> _stateCtrl =
      StreamController<PlaybackState>.broadcast();
  PlaybackState currentState = const PlaybackState.initial();

  _PlaybackTestBackendClient({super.database});

  @override
  Stream<PlaybackState> get playbackStateStream => _stateCtrl.stream;

  @override
  Future<PlaybackState> getPlaybackState() async => currentState;

  void emitState(PlaybackState state) {
    currentState = state;
    _stateCtrl.add(state);
  }

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SettingsRepository settingsRepository;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(prefs);

    final localeRepo = _FileSystemLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;
  });

  Widget createTestHarness({
    required Widget child,
    LibraryController? libraryController,
    PlaybackController? playbackController,
    PlaylistsController? playlistsController,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        if (libraryController != null)
          ChangeNotifierProvider<LibraryController>.value(
            value: libraryController,
          ),
        if (playbackController != null)
          ChangeNotifierProvider<PlaybackController>.value(
            value: playbackController,
          ),
        if (playlistsController != null)
          ChangeNotifierProvider<PlaylistsController>.value(
            value: playlistsController,
          ),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Virtualized Builder Screens', () {
    testWidgets('PlaylistDetailScreen virtualizes large playlist using SliverReorderableList without full eager layout', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      // Create 500 tracks
      final tracks = List.generate(
        500,
        (i) => Track(
          id: i + 1,
          filePath: '/music/track_${i + 1}.mp3',
          title: 'Track Title ${i + 1}',
          durationMs: 180000,
          fileSize: 1000,
          modifiedAt: 1000,
          artists: [Artist(id: (i % 10) + 1, name: 'Artist ${(i % 10) + 1}', tracks: [])],
          album: Album(id: (i % 20) + 1, name: 'Album ${(i % 20) + 1}', tracks: []),
        ),
      );

      final playlist = Playlist(
        id: 1,
        name: 'Massive Workout Mix',
        createdAt: 1000,
        type: PlaylistType.user,
        entries: List.generate(
          500,
          (i) => PlaylistEntry(
            id: i + 1,
            position: i,
            addedAt: 1000,
            track: tracks[i],
          ),
        ),
      );

      final store = LibraryStore();
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(playlist);

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: playlist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Verify SliverReorderableList is rendered
      expect(find.byType(SliverReorderableList), findsOneWidget);

      // Verify only a small visible subset of tracks is instantiated in the widget tree (virtualization!)
      expect(find.text('Track Title 1'), findsOneWidget);
      expect(find.text('Track Title 499'), findsNothing);

      // Scroll down
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      // Items that were far down should now be built, earlier ones recycled
      expect(find.text('Track Title 1'), findsNothing);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('PlaylistDetailScreen for liked songs renders virtualized SliverList.builder', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final tracks = List.generate(
        100,
        (i) => Track(
          id: i + 1,
          filePath: '/music/fav_${i + 1}.mp3',
          title: 'Favorite Track ${i + 1}',
          durationMs: 200000,
          fileSize: 1000,
          modifiedAt: 1000,
          artists: [],
          album: null,
        ),
      );

      final likedPlaylist = Playlist(
        id: AppDatabase.likedSongsPlaylistId,
        name: 'Liked Songs',
        createdAt: 1000,
        type: PlaylistType.liked,
        entries: List.generate(
          100,
          (i) => PlaylistEntry(
            id: i + 1,
            position: i,
            addedAt: 1000,
            track: tracks[i],
          ),
        ),
      );

      final store = LibraryStore();
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(likedPlaylist);

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: likedPlaylist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Non-user playlist uses SliverList, not SliverReorderableList
      expect(find.byType(SliverReorderableList), findsNothing);
      expect(find.text('Favorite Track 1'), findsOneWidget);
      expect(find.text('Favorite Track 99'), findsNothing);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('PlaylistsScreen renders user playlists via virtualized SliverList.builder', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final rawPlaylists = [
        const RawPlaylistDto(id: 1, name: 'Liked Songs', createdAt: 100, type: 1),
        const RawPlaylistDto(id: 2, name: 'History', createdAt: 100, type: 2),
        ...List.generate(
          50,
          (i) => RawPlaylistDto(
            id: i + 10,
            name: 'User Playlist ${i + 1}',
            createdAt: 100 + i,
            type: 0,
          ),
        ),
      ];

      final snapshot = CatalogSnapshot(
        tracks: const [],
        albums: const [],
        artists: const [],
        genres: const [],
        playlists: rawPlaylists,
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);

      await tester.pumpWidget(
        createTestHarness(
          child: const PlaylistsScreen(),
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      // Special playlists exist
      expect(find.text(strings.plLikedSongs), findsOneWidget);
      expect(find.text(strings.plHistory), findsOneWidget);

      // Section title with count
      expect(find.text('${strings.plTitle} (50)'), findsOneWidget);

      // First few user playlists visible, but not the last ones (virtualized!)
      expect(find.text('User Playlist 1'), findsOneWidget);
      expect(find.text('User Playlist 50'), findsNothing);

      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('ArtistDetailScreen uses SliverGrid.builder for albums and SliverList.builder for tracks', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final rawAlbums = List.generate(
        12,
        (i) => RawAlbumDto(
          id: i + 1,
          name: 'Studio Album ${i + 1}',
          year: 2010 + i,
          artistId: 1,
        ),
      );

      final rawTracks = List.generate(
        30,
        (i) => RawTrackDto(
          id: i + 1,
          filePath: '/music/track_${i + 1}.mp3',
          title: 'Artist Song ${i + 1}',
          durationMs: 210000,
          fileSize: 1000,
          modifiedAt: 1000,
          albumId: (i % 12) + 1,
        ),
      );

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: rawAlbums,
        artists: [const RawArtistDto(id: 1, name: 'Prolific Rocker')],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: List.generate(
          30,
          (i) => TrackArtistPair(trackId: i + 1, artistId: 1),
        ),
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final artist = store.getArtistById(1)!;

      final libraryCtrl = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: store,
      );
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: ArtistDetailScreen(artist: artist),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      final strings = localeController.localeStrings;

      // Discography and All Tracks headers
      expect(find.text(strings.arDiscography), findsOneWidget);
      expect(find.text(strings.arAllTracks), findsOneWidget);

      // Grid items: AlbumCard widgets present
      expect(find.byType(AlbumCard), findsWidgets);

      // List items: TrackTile widgets present
      expect(find.byType(TrackTile), findsWidgets);

      libraryCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('AlbumDetailScreen uses SliverList.builder for album tracks', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final rawTracks = List.generate(
        20,
        (i) => RawTrackDto(
          id: i + 1,
          filePath: '/music/album_track_${i + 1}.mp3',
          title: 'Album Cut ${i + 1}',
          durationMs: 195000,
          fileSize: 1000,
          modifiedAt: 1000,
          albumId: 1,
        ),
      );

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: [
          const RawAlbumDto(
            id: 1,
            name: 'Double Gatefold Epic',
            year: 1978,
            artistId: 1,
          ),
        ],
        artists: [const RawArtistDto(id: 1, name: 'Progressive Giants')],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: List.generate(
          20,
          (i) => TrackArtistPair(trackId: i + 1, artistId: 1),
        ),
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final album = store.getAlbumById(1)!;

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: AlbumDetailScreen(album: album),
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Double Gatefold Epic'), findsWidgets);
      expect(find.text('Progressive Giants'), findsOneWidget);
      expect(find.byType(TrackTile), findsWidgets);
      expect(find.text('Album Cut 1'), findsOneWidget);

      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });

  group('Playlist Cover and Artwork Presentation', () {
    test('findPlaylistCoverHash searches reverse added order until finding valid cover hash', () {
      final track1 = const Track(
        id: 1,
        filePath: '/music/t1.mp3',
        title: 'T1',
        durationMs: 1000,
        fileSize: 100,
        modifiedAt: 100,
        thumbnailHash: 'hash_old',
      );
      final track2 = const Track(
        id: 2,
        filePath: '/music/t2.mp3',
        title: 'T2',
        durationMs: 1000,
        fileSize: 100,
        modifiedAt: 100,
        thumbnailHash: null,
      );
      final track3 = const Track(
        id: 3,
        filePath: '/music/t3.mp3',
        title: 'T3',
        durationMs: 1000,
        fileSize: 100,
        modifiedAt: 100,
        thumbnailHash: 'hash_latest',
      );
      final track4 = const Track(
        id: 4,
        filePath: '/music/t4.mp3',
        title: 'T4',
        durationMs: 1000,
        fileSize: 100,
        modifiedAt: 100,
        thumbnailHash: null, // added most recently, but has no hash
      );

      final playlist = Playlist(
        id: 1,
        name: 'Cover Test Playlist',
        createdAt: 100,
        entries: [
          PlaylistEntry(id: 1, position: 0, addedAt: 100, track: track1),
          PlaylistEntry(id: 2, position: 1, addedAt: 200, track: track2),
          PlaylistEntry(id: 3, position: 2, addedAt: 300, track: track3),
          PlaylistEntry(id: 4, position: 3, addedAt: 400, track: track4),
        ],
      );

      // Should skip track 4 (addedAt 400, null hash) and pick track 3 (addedAt 300, 'hash_latest')
      final resolvedHash = findPlaylistCoverHash(playlist);
      expect(resolvedHash, equals('hash_latest'));
    });

    testWidgets('PlaylistsScreen renders cover with heart overlay for liked songs and clock for history', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final snapshot = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 10,
            filePath: '/music/cover.mp3',
            title: 'Cover Track',
            durationMs: 180000,
            fileSize: 1000,
            modifiedAt: 1000,
            thumbnailHash: 'liked_track_hash',
          ),
        ],
        albums: const [],
        artists: const [],
        genres: const [],
        playlists: [
          RawPlaylistDto(
            id: AppDatabase.likedSongsPlaylistId,
            name: 'Liked Songs',
            createdAt: 100,
            type: PlaylistType.liked.index,
          ),
          RawPlaylistDto(
            id: AppDatabase.historyPlaylistId,
            name: 'History',
            createdAt: 100,
            type: PlaylistType.history.index,
          ),
          const RawPlaylistDto(
            id: 50,
            name: 'My Mix',
            createdAt: 100,
            type: 0,
          ),
        ],
        playlistEntries: [
          RawPlaylistEntryDto(
            id: 1,
            playlistId: AppDatabase.likedSongsPlaylistId,
            trackId: 10,
            position: 0,
            addedAt: 500,
          ),
          RawPlaylistEntryDto(
            id: 2,
            playlistId: AppDatabase.historyPlaylistId,
            trackId: 10,
            position: 0,
            addedAt: 600,
          ),
          const RawPlaylistEntryDto(
            id: 3,
            playlistId: 50,
            trackId: 10,
            position: 0,
            addedAt: 700,
          ),
        ],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);

      await tester.pumpWidget(
        createTestHarness(
          child: const PlaylistsScreen(),
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // AlbumArtImage should be rendered in AlbumArtImage with ThumbnailQuality.low
      final albumArtImages = tester.widgetList<AlbumArtImage>(find.byType(AlbumArtImage));
      expect(albumArtImages, isNotEmpty);
      for (final img in albumArtImages) {
        expect(img.quality, equals(ThumbnailQuality.low));
      }

      // Check overlay badges
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

      playlistsCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('PlaylistDetailScreen renders AmbientBackdrop and HQ cover of the latest added track with cover hash', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final trackWithCover = const Track(
        id: 25,
        filePath: '/music/with_art.mp3',
        title: 'Song With Art',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 1000,
        thumbnailHash: 'playlist_top_hash',
      );

      final playlist = Playlist(
        id: 1,
        name: 'Art Showcase',
        createdAt: 1000,
        type: PlaylistType.user,
        entries: [
          PlaylistEntry(id: 1, position: 0, addedAt: 1000, track: trackWithCover),
        ],
      );

      final store = LibraryStore();
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(playlist);

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: playlist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Verify AmbientBackdrop has the resolved cover hash
      final backdropFinder = find.byType(AmbientBackdrop);
      expect(backdropFinder, findsOneWidget);
      final backdrop = tester.widget<AmbientBackdrop>(backdropFinder);
      expect(backdrop.thumbnailHash, equals('playlist_top_hash'));

      // Verify that the header artwork uses ThumbnailQuality.high
      final hqImages = tester.widgetList<AlbumArtImage>(find.byType(AlbumArtImage)).where(
        (img) => img.quality == ThumbnailQuality.high,
      );
      expect(hqImages, hasLength(1));
      expect(hqImages.first.thumbnailHash, equals('playlist_top_hash'));

      // Verify that track item in the list uses ThumbnailQuality.low
      final trackArtFinder = find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(AlbumArtImage),
      );
      expect(trackArtFinder, findsOneWidget);
      final trackArt = tester.widget<AlbumArtImage>(trackArtFinder);
      expect(trackArt.quality, equals(ThumbnailQuality.low));
      expect(trackArt.thumbnailHash, equals('playlist_top_hash'));

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('PlaylistDetailScreen highlights and marks currently playing track with equalizer and primary color', (tester) async {
      final db = AppDatabase.inMemory();
      final backend = _PlaybackTestBackendClient(database: db);

      final playingTrack = const Track(
        id: 77,
        filePath: '/music/now_playing.mp3',
        title: 'Active Jam',
        durationMs: 240000,
        fileSize: 1000,
        modifiedAt: 1000,
        thumbnailHash: 'active_jam_hash',
      );

      final otherTrack = const Track(
        id: 78,
        filePath: '/music/other.mp3',
        title: 'Other Song',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
      );

      final playlist = Playlist(
        id: 1,
        name: 'Party Playlist',
        createdAt: 1000,
        type: PlaylistType.user,
        entries: [
          PlaylistEntry(id: 1, position: 0, addedAt: 1000, track: playingTrack),
          PlaylistEntry(id: 2, position: 1, addedAt: 1001, track: otherTrack),
        ],
      );

      final store = LibraryStore();
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      playlistsCtrl.selectPlaylist(playlist);

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      backend.emitState(
        PlaybackState(
          playing: true,
          playables: [
            PlaylistEntry.forQueue(id: 1, position: 0, track: playingTrack),
            PlaylistEntry.forQueue(id: 2, position: 1, track: otherTrack),
          ],
          index: 0,
        ),
      );

      await tester.pumpWidget(
        createTestHarness(
          child: PlaylistDetailScreen(playlist: playlist),
          playlistsController: playlistsCtrl,
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Equalizer icon should be displayed on the active playing track
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);

      // The title of the playing track should have primary color
      final textWidget = tester.widget<Text>(find.text('Active Jam'));
      expect(textWidget.style?.color, isNotNull);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('AlbumDetailScreen highlights and marks currently playing track with equalizer and primary color', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = _PlaybackTestBackendClient(database: db);

      final playingTrack = const Track(
        id: 101,
        filePath: '/music/album_track_1.mp3',
        title: 'Playing Album Song',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 1000,
        thumbnailHash: 'album_track_hash',
      );

      final rawTracks = [
        const RawTrackDto(
          id: 101,
          filePath: '/music/album_track_1.mp3',
          title: 'Playing Album Song',
          durationMs: 200000,
          fileSize: 1000,
          modifiedAt: 1000,
          thumbnailHash: 'album_track_hash',
          albumId: 10,
        ),
        const RawTrackDto(
          id: 102,
          filePath: '/music/album_track_2.mp3',
          title: 'Other Album Song',
          durationMs: 180000,
          fileSize: 1000,
          modifiedAt: 1000,
          albumId: 10,
        ),
      ];

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: [
          const RawAlbumDto(
            id: 10,
            name: 'Featured Album',
            year: 2024,
            artistId: 1,
          ),
        ],
        artists: [const RawArtistDto(id: 1, name: 'Great Artist')],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: [
          TrackArtistPair(trackId: 101, artistId: 1),
          TrackArtistPair(trackId: 102, artistId: 1),
        ],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final album = store.getAlbumById(10)!;

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      backend.emitState(
        PlaybackState(
          playing: true,
          playables: [
            PlaylistEntry.forQueue(id: 1, position: 0, track: playingTrack),
          ],
          index: 0,
        ),
      );

      await tester.pumpWidget(
        createTestHarness(
          child: AlbumDetailScreen(album: album),
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Equalizer icon should be displayed on the active playing track
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);

      // The title of the playing track should have primary color
      final textWidget = tester.widget<Text>(find.text('Playing Album Song'));
      expect(textWidget.style?.color, isNotNull);

      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('TracksScreen highlights and marks currently playing track with equalizer and primary color', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = _PlaybackTestBackendClient(database: db);

      final rawTracks = [
        const RawTrackDto(
          id: 201,
          filePath: '/music/library_playing.mp3',
          title: 'Playing Library Song',
          durationMs: 220000,
          fileSize: 1000,
          modifiedAt: 1000,
          thumbnailHash: 'lib_track_hash',
        ),
        const RawTrackDto(
          id: 202,
          filePath: '/music/library_other.mp3',
          title: 'Other Library Song',
          durationMs: 190000,
          fileSize: 1000,
          modifiedAt: 1000,
        ),
      ];

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: const [],
        artists: const [],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final libraryCtrl = LibraryController(
        backend: backend,
        store: store,
        settingsRepository: settingsRepository,
      );
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      final playingTrack = store.tracks.first;

      backend.emitState(
        PlaybackState(
          playing: true,
          playables: [
            PlaylistEntry.forQueue(id: 1, position: 0, track: playingTrack),
          ],
          index: 0,
        ),
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const TracksScreen(),
          libraryController: libraryCtrl,
          playbackController: playbackCtrl,
          playlistsController: playlistsCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Equalizer icon should be displayed on the active playing track in list view
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);

      final textWidget = tester.widget<Text>(find.text('Playing Library Song'));
      expect(textWidget.style?.color, isNotNull);

      libraryCtrl.dispose();
      playlistsCtrl.dispose();
      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    test('findGenreCoverHash searches internal tracks and picks first non-empty thumbnailHash', () {
      const trackWithoutCover = Track(
        id: 1,
        filePath: '/music/track1.mp3',
        title: 'Track 1',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
      );

      const trackWithCover = Track(
        id: 2,
        filePath: '/music/track2.mp3',
        title: 'Track 2',
        durationMs: 150000,
        fileSize: 1000,
        modifiedAt: 1000,
        thumbnailHash: 'genre_track_cover_hash',
      );

      const emptyGenre = Genre(id: 1, name: 'Empty Genre', tracks: []);
      expect(findGenreCoverHash(emptyGenre), isNull);

      const genreWithCover = Genre(
        id: 2,
        name: 'Rock',
        tracks: [trackWithoutCover, trackWithCover],
      );
      expect(findGenreCoverHash(genreWithCover), 'genre_track_cover_hash');
    });

    testWidgets('GenresScreen renders cover with ThumbnailQuality.medium on genre card', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final rawTracks = [
        const RawTrackDto(
          id: 301,
          filePath: '/music/synth.mp3',
          title: 'Synth Beat',
          durationMs: 200000,
          fileSize: 1000,
          modifiedAt: 1000,
          thumbnailHash: 'synth_cover_hash',
        ),
      ];

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: const [],
        artists: const [],
        genres: [
          const RawGenreDto(id: 30, name: 'Synthwave'),
        ],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: [
          TrackGenrePair(trackId: 301, genreId: 30),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final libraryCtrl = LibraryController(
        backend: backend,
        store: store,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: const GenresScreen(),
          libraryController: libraryCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synthwave'), findsOneWidget);

      final albumArt = tester.widget<AlbumArtImage>(find.byType(AlbumArtImage));
      expect(albumArt.thumbnailHash, 'synth_cover_hash');
      expect(albumArt.quality, ThumbnailQuality.medium);

      libraryCtrl.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('GenreDetailScreen renders AmbientBackdrop and HQ cover of genre', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AppDatabase.inMemory();
      final backend = DirectTachyonBackendClient(database: db);

      final rawTracks = [
        const RawTrackDto(
          id: 401,
          filePath: '/music/ambient.mp3',
          title: 'Deep Space',
          durationMs: 300000,
          fileSize: 1000,
          modifiedAt: 1000,
          thumbnailHash: 'ambient_hash_99',
        ),
      ];

      final snapshot = CatalogSnapshot(
        tracks: rawTracks,
        albums: const [],
        artists: const [],
        genres: [
          const RawGenreDto(id: 40, name: 'Ambient'),
        ],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: [
          TrackGenrePair(trackId: 401, genreId: 40),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);
      final genre = store.getGenreById(40)!;

      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepository,
      );

      await tester.pumpWidget(
        createTestHarness(
          child: GenreDetailScreen(genre: genre),
          playbackController: playbackCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ambient'), findsWidgets);
      expect(find.text('Deep Space'), findsOneWidget);

      final backdrop = tester.widget<AmbientBackdrop>(find.byType(AmbientBackdrop));
      expect(backdrop.thumbnailHash, 'ambient_hash_99');

      final albumArtImages = tester.widgetList<AlbumArtImage>(find.byType(AlbumArtImage));
      final headerArt = albumArtImages.firstWhere(
        (img) => img.quality == ThumbnailQuality.high,
      );
      expect(headerArt.thumbnailHash, 'ambient_hash_99');

      playbackCtrl.dispose();
      await backend.dispose();
      await db.close();
    });
  });
}
