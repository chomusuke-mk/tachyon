import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

// =============================================================================
// Test Doubles & Mocks
// =============================================================================

class StubMetadataExtractor implements MetadataExtractor {
  @override
  Future<Track?> extractMetadata(String filePath) async => null;

  @override
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) =>
      const Stream.empty();

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async => null;
}

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> bundles;
  MockLocaleRepository(this.bundles);

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return bundles[localeCode] ?? {};
  }
}

class CountingSearchDatabase extends AppDatabaseImpl {
  int searchTracksCallCount = 0;
  final List<String> executedQueries = [];

  CountingSearchDatabase() : super(inMemory: true);

  @override
  Future<List<Track>> searchTracks(String query) {
    searchTracksCallCount++;
    executedQueries.add(query);
    return super.searchTracks(query);
  }
}

class MockAudioEngineService implements AudioEngineService {
  final StreamController<MediaPlayerState> _controller =
      StreamController<MediaPlayerState>.broadcast(sync: true);
  MediaPlayerState _state = const MediaPlayerState.initial();

  @override
  Stream<MediaPlayerState> get stateStream => _controller.stream;

  @override
  MediaPlayerState get currentState => _state;

  void emitState(MediaPlayerState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> open(
    List<Playable> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    _state = _state.copyWith(
      playables: playables,
      index: index,
      playing: play,
      duration: playables.isNotEmpty ? playables[index].duration : Duration.zero,
    );
    _controller.add(_state);
  }

  @override
  Future<void> play() async {
    _state = _state.copyWith(playing: true);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
    _controller.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = _state.copyWith(playing: false, position: Duration.zero);
    _controller.add(_state);
  }

  @override
  Future<void> next() async {
    if (_state.index < _state.playables.length - 1) {
      _state = _state.copyWith(index: _state.index + 1);
      _controller.add(_state);
    }
  }

  @override
  Future<void> previous() async {
    if (_state.index > 0) {
      _state = _state.copyWith(index: _state.index - 1);
      _controller.add(_state);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    _controller.add(_state);
  }

  @override
  Future<void> setVolume(double volume) async =>
      emitState(_state.copyWith(volume: volume));

  @override
  Future<void> setRate(double rate) async =>
      emitState(_state.copyWith(rate: rate));

  @override
  Future<void> setPitch(double pitch) async =>
      emitState(_state.copyWith(pitch: pitch));

  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async =>
      emitState(_state.copyWith(crossfadeConfig: config));

  @override
  Future<void> setLoopMode(Loop loop) async =>
      emitState(_state.copyWith(loop: loop));

  @override
  Future<void> toggleShuffle() async =>
      emitState(_state.copyWith(shuffle: !_state.shuffle));

  @override
  Future<void> insertNext(Playable playable) async {}

  @override
  Future<void> append(List<Playable> playables) async {}

  @override
  Future<void> remove(int index) async {}

  @override
  Future<void> reorder(int from, int to) async {}

  @override
  Future<void> setReplayGain(ReplayGainMode mode) async =>
      emitState(_state.copyWith(replayGain: mode));

  @override
  Future<void> setReplayGainPreamp(double preamp) async =>
      emitState(_state.copyWith(replayGainPreamp: preamp));

  @override
  Future<void> setExclusiveAudio(bool exclusive) async =>
      emitState(_state.copyWith(exclusiveAudio: exclusive));

  @override
  Future<void> setMpvProperty(String property, String value) async {}

  @override
  Future<void> setMpvProperties(Map<String, String> properties) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Standard test locale dictionary covering shell and transport labels
  final testLocaleRepo = MockLocaleRepository({
    'en': {
      'app_title': 'Tachyon',
      'tr_title': 'Tracks',
      'al_title': 'Albums',
      'ar_title': 'Artists',
      'pl_title': 'Playlists',
      'g_title': 'Genres',
      'f_title': 'Folders',
      'sr_title': 'Search',
      's_title': 'Settings',
      'np_play': 'Play',
      'np_pause': 'Pause',
      'np_next': 'Next',
      'np_previous': 'Previous',
      's_theme_dark': 'Dark',
      's_theme_light': 'Light',
      's_theme_system': 'System',
    },
    'es': {
      'app_title': 'Tachyon',
      'tr_title': 'Pistas',
      'al_title': 'Álbumes',
      'ar_title': 'Artistas',
      'pl_title': 'Listas',
      'g_title': 'Géneros',
      'f_title': 'Carpetas',
      'sr_title': 'Buscar',
      's_title': 'Ajustes',
      'np_play': 'Reproducir',
      'np_pause': 'Pausar',
      'np_next': 'Siguiente',
      'np_previous': 'Anterior',
      's_theme_dark': 'Oscuro',
      's_theme_light': 'Claro',
      's_theme_system': 'Sistema',
    },
  });

  // ===========================================================================
  // 1. CONTROLLER STRESS TESTING
  // ===========================================================================
  group('1. Controller Stress Testing: Liking / Unliking Consistency', () {
    late AppDatabase db;
    late PlaylistsController controller;

    setUp(() async {
      db = AppDatabaseImpl.inMemory();
      await db.init();
      controller = PlaylistsController(database: db);
      await controller.loadPlaylists();
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test('1.1: 500 rapid toggles on a single track maintaining strict parity with SQLite', () async {
      const initialTrack = Track(
        uri: 'file:///music/stress_toggle.mp3',
        title: 'Stress Toggle Track',
        artist: 'Stress Artist',
        album: 'Stress Album',
        durationMs: 240000,
        fileSize: 10000000,
        modifiedAt: 1600000000,
      );
      await db.insertOrUpdateTrack(initialTrack);
      final tracks = await db.getAllTracks();
      final track = tracks.first;
      final trackId = track.id!;

      expect(controller.isTrackLiked(trackId), isFalse);
      expect(await db.isTrackLiked(trackId), isFalse);

      // Execute 500 rapid sequential toggles
      for (int i = 0; i < 500; i++) {
        await controller.toggleLikeTrack(track);

        final expectedLiked = (i % 2 == 0); // Even index -> liked, odd -> unliked
        expect(
          controller.isTrackLiked(trackId),
          equals(expectedLiked),
          reason: 'In-memory cache mismatch at toggle $i',
        );
        expect(
          await db.isTrackLiked(trackId),
          equals(expectedLiked),
          reason: 'SQLite parity mismatch at toggle $i',
        );
      }

      // After 500 toggles (even number of toggles from unliked), state must be unliked
      expect(controller.isTrackLiked(trackId), isFalse);
      expect(await db.isTrackLiked(trackId), isFalse);

      final dbEntries = await db.database.query(
        'playlist_entries',
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [AppConstants.likedSongsPlaylistId, trackId],
      );
      expect(dbEntries, isEmpty, reason: 'SQLite playlist_entries must have 0 rows for unliked track');
    });

    test('1.2: Concurrent like toggles across distinct tracks maintaining cache and DB parity', () async {
      final batch = List.generate(
        100,
        (i) => Track(
          uri: 'file:///music/concurrent_$i.mp3',
          title: 'Concurrent Track $i',
          artist: 'Artist ${i % 10}',
          album: 'Album ${i % 5}',
          durationMs: 180000 + (i * 100),
          fileSize: 5000000 + i,
          modifiedAt: 1600000000 + i,
        ),
      );
      await db.batchInsertTracks(batch);
      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(100));

      // Ensure all start unliked
      for (final t in tracks) {
        expect(controller.isTrackLiked(t.id!), isFalse);
      }

      // Concurrently toggle all 100 tracks to liked
      await Future.wait(tracks.map((t) => controller.toggleLikeTrack(t)));

      // Assert all are liked in-memory and in SQLite
      for (final t in tracks) {
        expect(controller.isTrackLiked(t.id!), isTrue);
      }
      final likedInDb = await db.getTracksForPlaylist(AppConstants.likedSongsPlaylistId);
      expect(likedInDb.length, equals(100));

      // Concurrently toggle all 100 tracks back to unliked
      await Future.wait(tracks.map((t) => controller.toggleLikeTrack(t)));

      for (final t in tracks) {
        expect(controller.isTrackLiked(t.id!), isFalse);
      }
      final likedAfterUnlike = await db.getTracksForPlaylist(AppConstants.likedSongsPlaylistId);
      expect(likedAfterUnlike, isEmpty);
    });

    test('1.3: loadPlaylists resynchronizes in-memory cache from external SQLite state', () async {
      final batch = List.generate(
        10,
        (i) => Track(
          uri: 'file:///music/resync_$i.mp3',
          title: 'Resync Track $i',
          durationMs: 120000,
          fileSize: 3000000,
          modifiedAt: 1630000000 + i,
        ),
      );
      await db.batchInsertTracks(batch);
      final tracks = await db.getAllTracks();

      // Directly insert 5 tracks into liked songs in SQLite bypassing controller
      for (int i = 0; i < 5; i++) {
        await db.addTrackToPlaylist(AppConstants.likedSongsPlaylistId, tracks[i].id!);
      }

      // Controller cache does not yet know about direct SQLite inserts
      expect(controller.isTrackLiked(tracks[0].id!), isFalse);

      // Reload playlists to resynchronize cache
      await controller.loadPlaylists();

      // Verify that cache is now 100% synchronized with SQLite
      for (int i = 0; i < 5; i++) {
        expect(controller.isTrackLiked(tracks[i].id!), isTrue);
      }
      for (int i = 5; i < 10; i++) {
        expect(controller.isTrackLiked(tracks[i].id!), isFalse);
      }
    });
  });

  group('1. Controller Stress Testing: Search Debouncing Stress', () {
    late CountingSearchDatabase db;
    late TachyonSearchController searchController;

    setUp(() async {
      db = CountingSearchDatabase();
      await db.init();

      const track = Track(
        uri: 'file:///music/beethoven.flac',
        title: 'Beethoven Symphony No. 9 in D Minor',
        artist: 'Ludwig van Beethoven',
        album: 'Beethoven Masterpieces',
        durationMs: 3900000,
        fileSize: 80000000,
        modifiedAt: 1600000000,
      );
      await db.insertOrUpdateTrack(track);

      searchController = TachyonSearchController(database: db);
    });

    tearDown(() async {
      searchController.dispose();
      await db.close();
    });

    test('1.4: 50 rapid sequential query updates cancels prior timers and executes only final query', () async {
      expect(searchController.isSearching, isFalse);
      expect(db.searchTracksCallCount, equals(0));

      // Simulate 50 rapid keystrokes arriving within milliseconds
      for (int i = 1; i <= 50; i++) {
        searchController.onQueryChanged('Beethoven $i');
      }

      // Immediately after keystrokes: searching is true, but NO database query executed yet
      expect(searchController.isSearching, isTrue);
      expect(
        db.searchTracksCallCount,
        equals(0),
        reason: 'Zero DB queries must execute before 250ms debounce window expires',
      );

      // Wait 350ms for the single active debounce timer to fire and execute
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Assert that exactly 1 query hit the database
      expect(
        db.searchTracksCallCount,
        equals(1),
        reason: 'Exactly 1 query must execute after 50 rapid sequential updates',
      );
      expect(db.executedQueries.length, equals(1));
      expect(db.executedQueries.first, equals('Beethoven 50'));
      expect(searchController.isSearching, isFalse);
    });

    test('1.5: Rapid keystrokes followed by whitespace aborts search without querying database', () async {
      for (int i = 1; i <= 50; i++) {
        searchController.onQueryChanged('Query $i');
      }

      // Immediately clear via whitespace
      searchController.onQueryChanged('   ');

      expect(searchController.isEmptyQuery, isTrue);
      expect(searchController.isSearching, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(db.searchTracksCallCount, equals(0), reason: 'Aborted query must not hit SQLite');
    });

    test('1.6: Typing before 250ms resets debounce timer countdown', () async {
      searchController.onQueryChanged('Query1');
      await Future<void>.delayed(const Duration(milliseconds: 150)); // < 250ms

      // Typing new character at 150ms cancels Query1 timer
      searchController.onQueryChanged('Query2');
      await Future<void>.delayed(const Duration(milliseconds: 150)); // Total 300ms from Query1, but 150ms from Query2

      // Query1 was canceled and Query2 only elapsed 150ms -> 0 queries executed
      expect(db.searchTracksCallCount, equals(0));

      // Wait additional 150ms for Query2 (total 300ms from Query2)
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(db.searchTracksCallCount, equals(1));
      expect(db.executedQueries.single, equals('Query2'));
    });

    test('1.7: clear() immediately cancels pending debounced timer', () async {
      searchController.onQueryChanged('Pending Search');
      expect(searchController.isSearching, isTrue);

      searchController.clear();
      expect(searchController.isSearching, isFalse);
      expect(searchController.query, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(db.searchTracksCallCount, equals(0));
    });
  });

  group('1. Controller Stress Testing: Large Library Sorting (5,000 Tracks)', () {
    late AppDatabase db;
    late LibraryController controller;

    setUpAll(() async {
      db = AppDatabaseImpl.inMemory();
      await db.init();

      // Generate 5,000 realistic tracks with diverse metadata
      final List<Track> batch = [];
      for (int i = 0; i < 5000; i++) {
        final paddedIndex = i.toString().padLeft(4, '0');
        final reverseIndex = (5000 - i).toString().padLeft(4, '0');

        batch.add(
          Track(
            uri: 'file:///library/album_${i % 100}/track_$paddedIndex.mp3',
            title: 'Track $reverseIndex Alpha',
            artist: 'Artist ${String.fromCharCode(65 + (i % 26))} Band',
            album: 'Album ${(i % 150).toString().padLeft(3, '0')}',
            year: 1970 + (i % 55),
            durationMs: 60000 + ((i * 37) % 540000), // 1 to 10 minutes
            fileSize: 3000000 + (i * 1000),
            modifiedAt: 1500000000 + (i * 73),
            genres: ['Genre ${i % 12}'],
          ),
        );
      }

      await db.batchInsertTracks(batch);
    });

    setUp(() {
      controller = LibraryController(
        database: db,
        metadataExtractor: StubMetadataExtractor(),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    tearDownAll(() async {
      await db.close();
    });

    test('1.8: Ingestion and load of 5,000 tracks is responsive without exceptions', () async {
      final sw = Stopwatch()..start();
      await controller.loadLibrary();
      sw.stop();

      expect(controller.tracks.length, equals(5000));
      expect(controller.allTracks.length, equals(5000));
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(sw.elapsedMilliseconds, lessThan(4000));
    });

    test('1.9: Sort 5,000 tracks by Title (ASC & DESC) with full order verification', () async {
      await controller.loadLibrary();

      // Title ASC
      await controller.setSortOption(TrackSortOption.title, ascending: true);
      expect(controller.tracks.length, equals(5000));
      expect(controller.sortAscending, isTrue);
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final current = controller.tracks[i].title.toLowerCase();
        final next = controller.tracks[i + 1].title.toLowerCase();
        expect(current.compareTo(next), lessThanOrEqualTo(0));
      }

      // Title DESC
      await controller.setSortOption(TrackSortOption.title, ascending: false);
      expect(controller.tracks.length, equals(5000));
      expect(controller.sortAscending, isFalse);
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final current = controller.tracks[i].title.toLowerCase();
        final next = controller.tracks[i + 1].title.toLowerCase();
        expect(current.compareTo(next), greaterThanOrEqualTo(0));
      }
    });

    test('1.10: Sort 5,000 tracks by Artist (ASC & DESC) with full order verification', () async {
      await controller.loadLibrary();

      // Artist ASC
      await controller.setSortOption(TrackSortOption.artist, ascending: true);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final cur = controller.tracks[i].artist?.toLowerCase() ?? '';
        final nxt = controller.tracks[i + 1].artist?.toLowerCase() ?? '';
        expect(cur.compareTo(nxt), lessThanOrEqualTo(0));
      }

      // Artist DESC
      await controller.setSortOption(TrackSortOption.artist, ascending: false);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final cur = controller.tracks[i].artist?.toLowerCase() ?? '';
        final nxt = controller.tracks[i + 1].artist?.toLowerCase() ?? '';
        expect(cur.compareTo(nxt), greaterThanOrEqualTo(0));
      }
    });

    test('1.11: Sort 5,000 tracks by Album (ASC & DESC) with full order verification', () async {
      await controller.loadLibrary();

      // Album ASC
      await controller.setSortOption(TrackSortOption.album, ascending: true);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final cur = controller.tracks[i].album?.toLowerCase() ?? '';
        final nxt = controller.tracks[i + 1].album?.toLowerCase() ?? '';
        expect(cur.compareTo(nxt), lessThanOrEqualTo(0));
      }

      // Album DESC
      await controller.setSortOption(TrackSortOption.album, ascending: false);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        final cur = controller.tracks[i].album?.toLowerCase() ?? '';
        final nxt = controller.tracks[i + 1].album?.toLowerCase() ?? '';
        expect(cur.compareTo(nxt), greaterThanOrEqualTo(0));
      }
    });

    test('1.12: Sort 5,000 tracks by Duration (ASC & DESC) with numeric order verification', () async {
      await controller.loadLibrary();

      // Duration ASC
      await controller.setSortOption(TrackSortOption.duration, ascending: true);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        expect(controller.tracks[i].durationMs, lessThanOrEqualTo(controller.tracks[i + 1].durationMs));
      }

      // Duration DESC
      await controller.setSortOption(TrackSortOption.duration, ascending: false);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        expect(controller.tracks[i].durationMs, greaterThanOrEqualTo(controller.tracks[i + 1].durationMs));
      }
    });

    test('1.13: Sort 5,000 tracks by DateAdded (ASC & DESC) with numeric order verification', () async {
      await controller.loadLibrary();

      // DateAdded ASC
      await controller.setSortOption(TrackSortOption.dateAdded, ascending: true);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        expect(controller.tracks[i].modifiedAt, lessThanOrEqualTo(controller.tracks[i + 1].modifiedAt));
      }

      // DateAdded DESC
      await controller.setSortOption(TrackSortOption.dateAdded, ascending: false);
      expect(controller.tracks.length, equals(5000));
      expect(controller.errorMessage, isNull);

      for (int i = 0; i < 4999; i++) {
        expect(controller.tracks[i].modifiedAt, greaterThanOrEqualTo(controller.tracks[i + 1].modifiedAt));
      }
    });
  });

  group('1. Controller Stress Testing: Playlist Reordering Boundary Conditions', () {
    late AppDatabase db;
    late PlaylistsController controller;
    late int playlistId;
    late List<Track> tracks;

    setUp(() async {
      db = AppDatabaseImpl.inMemory();
      await db.init();
      controller = PlaylistsController(database: db);

      final batch = List.generate(
        6,
        (i) => Track(
          uri: 'file:///playlist/song_$i.mp3',
          title: 'Entry Title $i',
          durationMs: 180000,
          fileSize: 5000000,
          modifiedAt: 1600000000 + i,
        ),
      );
      await db.batchInsertTracks(batch);
      tracks = await db.getAllTracks();
      await controller.loadPlaylists();

      playlistId = await controller.createPlaylist('Boundary Test Playlist');
      for (final t in tracks) {
        await controller.addTrackToPlaylist(playlistId, t.id!);
      }

      final playlist = controller.userPlaylists.firstWhere((p) => p.id == playlistId);
      await controller.selectPlaylist(playlist);
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    Future<List<int>> fetchPositions() async {
      final rows = await db.database.query(
        'playlist_entries',
        columns: ['position'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );
      return rows.map((r) => r['position'] as int).toList();
    }

    test('1.14: Initial SQLite positions are strictly continuous [0, 1, 2, 3, 4, 5]', () async {
      final positions = await fetchPositions();
      expect(positions, equals([0, 1, 2, 3, 4, 5]));
    });

    test('1.15: Boundary reorder at index 0 (0 to 5) preserves continuous positions', () async {
      await controller.reorderPlaylistEntries(playlistId, 0, 5);

      expect(controller.selectedPlaylistTracks.map((t) => t.title).toList(), equals([
        'Entry Title 1',
        'Entry Title 2',
        'Entry Title 3',
        'Entry Title 4',
        'Entry Title 5',
        'Entry Title 0',
      ]));

      final positions = await fetchPositions();
      expect(positions, equals([0, 1, 2, 3, 4, 5]), reason: 'SQLite positions must remain 0..5');

      final dbTracks = await db.getTracksForPlaylist(playlistId);
      expect(dbTracks.map((t) => t.title).toList(), equals(controller.selectedPlaylistTracks.map((t) => t.title).toList()));
    });

    test('1.16: Boundary reorder at length - 1 (5 to 0) preserves continuous positions', () async {
      await controller.reorderPlaylistEntries(playlistId, 5, 0);

      expect(controller.selectedPlaylistTracks.map((t) => t.title).toList(), equals([
        'Entry Title 5',
        'Entry Title 0',
        'Entry Title 1',
        'Entry Title 2',
        'Entry Title 3',
        'Entry Title 4',
      ]));

      final positions = await fetchPositions();
      expect(positions, equals([0, 1, 2, 3, 4, 5]));

      final dbTracks = await db.getTracksForPlaylist(playlistId);
      expect(dbTracks.map((t) => t.title).toList(), equals(controller.selectedPlaylistTracks.map((t) => t.title).toList()));
    });

    test('1.17: Identity reorder (2 to 2) is a safe no-op with continuous positions', () async {
      await controller.reorderPlaylistEntries(playlistId, 2, 2);

      final positions = await fetchPositions();
      expect(positions, equals([0, 1, 2, 3, 4, 5]));
    });

    test('1.18: Out-of-bounds indices are rejected safely without corrupting order', () async {
      final originalTitles = controller.selectedPlaylistTracks.map((t) => t.title).toList();

      await controller.reorderPlaylistEntries(playlistId, -1, 3);
      await controller.reorderPlaylistEntries(playlistId, 2, -1);
      await controller.reorderPlaylistEntries(playlistId, 6, 2); // 6 is out-of-bounds for length 6
      await controller.reorderPlaylistEntries(playlistId, 2, 6);
      await controller.reorderPlaylistEntries(playlistId, -10, 100);

      expect(controller.selectedPlaylistTracks.map((t) => t.title).toList(), equals(originalTitles));
      final positions = await fetchPositions();
      expect(positions, equals([0, 1, 2, 3, 4, 5]));
    });
  });

  // ===========================================================================
  // 2. ADAPTIVE UI & WIDGET STRESS TESTING
  // ===========================================================================
  group('2. Adaptive UI & Widget Stress: Breakpoint Switching (<720dp vs >=720dp)', () {
    late AppDatabase db;
    late MockAudioEngineService engine;
    late SettingsRepository settingsRepo;
    late LocaleController localeController;
    late LibraryController libraryController;
    late PlaylistsController playlistsController;
    late TachyonSearchController searchController;
    late PlaybackController playbackController;
    late SettingsController settingsController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);

      db = AppDatabaseImpl.inMemory();
      await db.init();

      engine = MockAudioEngineService();

      localeController = LocaleController(testLocaleRepo, 'en');
      await localeController.whenReady;

      libraryController = LibraryController(database: db, metadataExtractor: StubMetadataExtractor());
      playlistsController = PlaylistsController(database: db);
      searchController = TachyonSearchController(database: db);
      playbackController = PlaybackController(
        audioEngineService: engine,
        database: db,
        settingsRepository: settingsRepo,
      );
      settingsController = SettingsController(
        settingsRepository: settingsRepo,
        audioEngineService: engine,
        localeController: localeController,
      );
    });

    tearDown(() async {
      playbackController.dispose();
      libraryController.dispose();
      playlistsController.dispose();
      searchController.dispose();
      settingsController.dispose();
      await engine.dispose();
      await db.close();
    });

    Widget buildTestShell() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ChangeNotifierProvider<LibraryController>.value(value: libraryController),
          ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
          ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
          ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
          ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ],
        child: Consumer2<SettingsController, LocaleController>(
          builder: (context, settings, locale, _) {
            return MaterialApp(
              theme: TachyonTheme.lightTheme,
              darkTheme: TachyonTheme.darkTheme,
              themeMode: settings.themeMode,
              locale: locale.flutterLocale,
              home: const TachyonShell(),
            );
          },
        ),
      );
    }

    testWidgets('2.1: Rapid breakpoint oscillations (20 iterations) swap NavigationRail/NavigationBar without overflow', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestShell());
      await tester.pump();

      final sizes = [
        const Size(400, 800),   // Mobile portrait (<720)
        const Size(1024, 768),  // Desktop (>=720)
        const Size(719, 900),   // Just below 720dp threshold
        const Size(720, 900),   // Exactly at 720dp threshold
        const Size(600, 1024),  // Small mobile/tablet
        const Size(1440, 900),  // Standard desktop
        const Size(320, 568),   // Minimal mobile
        const Size(1920, 1080), // Full HD Desktop
      ];

      // Perform 20 rapid viewport size switches alternating across the breakpoint
      for (int i = 0; i < 20; i++) {
        final vp = sizes[i % sizes.length];
        tester.view.physicalSize = vp;
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'Layout overflow detected at size $vp in iteration $i');

        if (vp.width < 720) {
          expect(find.byType(NavigationBar), findsOneWidget, reason: 'NavigationBar must be present on mobile (<720dp)');
          expect(find.byType(NavigationRail), findsNothing, reason: 'NavigationRail must NOT be present on mobile');
        } else {
          expect(find.byType(NavigationRail), findsOneWidget, reason: 'NavigationRail must be present on desktop (>=720dp)');
          expect(find.byType(NavigationBar), findsNothing, reason: 'NavigationBar must NOT be present on desktop');
        }

        expect(find.byType(MiniPlayerBar), findsOneWidget);
      }
    });

    testWidgets('2.2: Preservation of active navigation index across breakpoint resizing', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Start on desktop
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestShell());
      await tester.pump();

      // Tap on Albums in rail (destination index 1)
      final albumsDest = find.byIcon(Icons.album_outlined);
      expect(albumsDest, findsOneWidget);
      await tester.tap(albumsDest);
      await tester.pump();

      final indexedStackFinder = find.byType(IndexedStack);
      IndexedStack stack = tester.widget(indexedStackFinder);
      expect(stack.index, equals(1));

      // Resize window to mobile width
      tester.view.physicalSize = const Size(500, 800);
      await tester.pump();

      // Verify active view in IndexedStack remains Albums (index 1)
      stack = tester.widget(indexedStackFinder);
      expect(stack.index, equals(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('2. Adaptive UI & Widget Stress: MiniPlayerBar State Updates', () {
    late AppDatabase db;
    late MockAudioEngineService mockEngine;
    late SettingsRepository settingsRepo;
    late LocaleController localeController;
    late PlaybackController playbackController;

    const baseTrack = Track(
      uri: 'file:///music/mini_player_test.mp3',
      title: 'Initial Mini Player Track',
      artist: 'Initial Artist',
      durationMs: 180000,
      fileSize: 5000000,
      modifiedAt: 1600000000,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);

      db = AppDatabaseImpl.inMemory();
      await db.init();

      mockEngine = MockAudioEngineService();

      localeController = LocaleController(testLocaleRepo, 'en');
      await localeController.whenReady;

      playbackController = PlaybackController(
        audioEngineService: mockEngine,
        database: db,
        settingsRepository: settingsRepo,
      );
    });

    tearDown(() async {
      playbackController.dispose();
      await mockEngine.dispose();
      await db.close();
    });

    Widget buildMiniPlayerApp({required bool isDesktop}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ],
        child: MaterialApp(
          theme: TachyonTheme.darkTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayerBar(isDesktop: isDesktop),
            ),
          ),
        ),
      );
    }

    testWidgets('2.3: 50 rapid play/pause state updates toggle UI controls cleanly', (tester) async {
      await playbackController.playTrack(baseTrack);

      await tester.pumpWidget(buildMiniPlayerApp(isDesktop: false));
      await tester.pump();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Rapidly toggle play/pause 50 times
      for (int i = 0; i < 50; i++) {
        playbackController.playOrPause();
        await tester.pump();

        final expectedIcon = playbackController.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
        expect(find.byIcon(expectedIcon), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('2.4: Rapid sequence of 25 distinct track transitions renders without error', (tester) async {
      await tester.pumpWidget(buildMiniPlayerApp(isDesktop: true));
      await tester.pump();

      final stressTracks = List.generate(
        25,
        (i) => Track(
          uri: 'file:///music/stress_track_$i.mp3',
          title: 'Stress Track Title $i with Extended Subtitle for Marquee and Overflow Checks',
          artist: 'Artist Band $i',
          durationMs: (60 + (i * 15)) * 1000,
          fileSize: 4000000 + i,
          modifiedAt: 1600000000 + i,
        ),
      );

      for (int i = 0; i < stressTracks.length; i++) {
        final track = stressTracks[i];
        await playbackController.playTrack(track);
        mockEngine.seek(Duration(seconds: 10 + i));
        await tester.pump();

        expect(find.text(track.title), findsOneWidget);
        expect(find.text(track.artist ?? ''), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('2.5: 50 fast position progress emissions update LinearProgressIndicator cleanly', (tester) async {
      await playbackController.playTrack(baseTrack);
      await tester.pumpWidget(buildMiniPlayerApp(isDesktop: false));
      await tester.pump();

      // Emit 50 fast position seek events across the duration
      for (int sec = 0; sec <= 180; sec += 4) {
        mockEngine.seek(Duration(seconds: sec));
        await tester.pump();

        final progressFinder = find.byType(LinearProgressIndicator);
        expect(progressFinder, findsOneWidget);
        final indicator = tester.widget<LinearProgressIndicator>(progressFinder);
        expect(indicator.value, inInclusiveRange(0.0, 1.0));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('2. Adaptive UI & Widget Stress: Theme & Language Live-Switching', () {
    late AppDatabase db;
    late MockAudioEngineService engine;
    late SettingsRepository settingsRepo;
    late LocaleController localeController;
    late LibraryController libraryController;
    late PlaylistsController playlistsController;
    late TachyonSearchController searchController;
    late PlaybackController playbackController;
    late SettingsController settingsController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);

      db = AppDatabaseImpl.inMemory();
      await db.init();

      engine = MockAudioEngineService();

      localeController = LocaleController(testLocaleRepo, 'en');
      await localeController.whenReady;

      libraryController = LibraryController(database: db, metadataExtractor: StubMetadataExtractor());
      playlistsController = PlaylistsController(database: db);
      searchController = TachyonSearchController(database: db);
      playbackController = PlaybackController(
        audioEngineService: engine,
        database: db,
        settingsRepository: settingsRepo,
      );
      settingsController = SettingsController(
        settingsRepository: settingsRepo,
        audioEngineService: engine,
        localeController: localeController,
      );
    });

    tearDown(() async {
      playbackController.dispose();
      libraryController.dispose();
      playlistsController.dispose();
      searchController.dispose();
      settingsController.dispose();
      await engine.dispose();
      await db.close();
    });

    Widget buildAppWithLiveControllers() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ChangeNotifierProvider<LibraryController>.value(value: libraryController),
          ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
          ChangeNotifierProvider<TachyonSearchController>.value(value: searchController),
          ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
          ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ],
        child: Consumer2<SettingsController, LocaleController>(
          builder: (context, settings, locale, _) {
            return MaterialApp(
              theme: TachyonTheme.lightTheme,
              darkTheme: TachyonTheme.darkTheme,
              themeMode: settings.themeMode,
              locale: locale.flutterLocale,
              home: const TachyonShell(),
            );
          },
        ),
      );
    }

    testWidgets('2.6: 30 rapid theme mode switches rebuild widget tree cleanly without errors', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildAppWithLiveControllers());
      await tester.pump();

      final modes = [
        ThemeMode.dark,
        ThemeMode.light,
        ThemeMode.system,
      ];

      for (int i = 0; i < 30; i++) {
        final mode = modes[i % modes.length];
        await settingsController.setThemeMode(mode);
        await tester.pump();

        expect(settingsController.themeMode, equals(mode));
        expect(tester.takeException(), isNull, reason: 'Theme switch failed at iteration $i with mode $mode');
      }
    });

    testWidgets('2.7: 20 rapid language switches update localized text in real time', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(500, 800); // Mobile NavigationBar
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildAppWithLiveControllers());
      await tester.pump();

      // Verify English label 'Tracks' is visible
      expect(find.text('Tracks'), findsAtLeastNWidgets(1));

      final languages = ['es', 'en'];

      for (int i = 0; i < 20; i++) {
        final lang = languages[i % languages.length];
        await localeController.setLocale(lang);
        await tester.pump();

        if (lang == 'es') {
          expect(find.text('Pistas'), findsAtLeastNWidgets(1), reason: 'Spanish label "Pistas" must be visible');
        } else {
          expect(find.text('Tracks'), findsAtLeastNWidgets(1), reason: 'English label "Tracks" must be visible');
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('2.8: Combined high-intensity stress: simultaneous theme, language, and viewport changes during playback', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;

      const track = Track(
        uri: 'file:///music/combined_stress.mp3',
        title: 'Combined Stress Song',
        artist: 'Combined Artist',
        durationMs: 240000,
        fileSize: 8000000,
        modifiedAt: 1600000000,
      );
      await playbackController.playTrack(track);

      await tester.pumpWidget(buildAppWithLiveControllers());
      await tester.pump();

      final sizes = [
        const Size(500, 800),
        const Size(1280, 800),
        const Size(700, 900),
        const Size(850, 900),
      ];

      for (int i = 0; i < 16; i++) {
        // Change viewport
        tester.view.physicalSize = sizes[i % sizes.length];
        tester.view.devicePixelRatio = 1.0;

        // Toggle theme
        final mode = (i % 2 == 0) ? ThemeMode.dark : ThemeMode.light;
        await settingsController.setThemeMode(mode);

        // Toggle language
        final lang = (i % 2 == 0) ? 'es' : 'en';
        await localeController.setLocale(lang);

        // Toggle play/pause
        playbackController.playOrPause();
        engine.seek(Duration(seconds: 10 * i));

        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'Combined stress failed at iteration $i');
        expect(find.byType(MiniPlayerBar), findsOneWidget);
      }
    });
  });
}
