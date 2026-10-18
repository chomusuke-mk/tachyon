import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Error Resilience & Missing Data Tests', () {
    late AppDatabase database;
    late SettingsRepository settingsRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('AppDatabase.addTrackToPlaylist ignores non-existent trackId without throwing SqliteException(787)', () async {
      await expectLater(
        database.addTrackToPlaylist(AppDatabase.historyPlaylistId, 999),
        completes,
      );

      final snapshot = await database.getCatalogSnapshot();
      final historyEntries = snapshot.playlistEntries
          .where((e) => e.playlistId == AppDatabase.historyPlaylistId)
          .toList();
      expect(historyEntries, isEmpty);
    });

    test('AppDatabase.addTracksToPlaylist ignores deleted trackIds without throwing SqliteException(787)', () async {
      final validTrack = ExtractedTrackData(
        filePath: '/music/song1.mp3',
        title: 'Song One',
        artistNames: ['Artist A'],
        albumName: 'Album One',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 123456789,
      );
      await database.upsertTracks([validTrack]);

      var snapshot = await database.getCatalogSnapshot();
      final validId = snapshot.tracks.first.id;

      await expectLater(
        database.addTracksToPlaylist(AppDatabase.historyPlaylistId, [validId, 999, 1000]),
        completes,
      );

      snapshot = await database.getCatalogSnapshot();
      final historyEntries = snapshot.playlistEntries
          .where((e) => e.playlistId == AppDatabase.historyPlaylistId)
          .map((e) => e.trackId)
          .toList();
      expect(historyEntries, [validId]);
    });

    test('AppDatabase handles operations on deleted track when music directory was removed', () async {
      final track = ExtractedTrackData(
        filePath: '/music/deleted_dir/song2.mp3',
        title: 'Song Two',
        artistNames: ['Artist B'],
        durationMs: 200000,
        fileSize: 4000000,
        modifiedAt: 123456790,
      );
      await database.upsertTracks([track]);

      final snapshot = await database.getCatalogSnapshot();
      final trackId = snapshot.tracks.first.id;

      await database.deleteTracksAndPurgeOrphans([trackId]);

      await expectLater(
        database.addTracksToPlaylist(AppDatabase.historyPlaylistId, [trackId]),
        completes,
      );

      await expectLater(
        database.toggleLikeTrack(trackId),
        completes,
      );

      await expectLater(
        database.removeTrackFromPlaylist(AppDatabase.historyPlaylistId, trackId),
        completes,
      );
    });

    test('LibraryStore handles null/missing tracks safely in playlist mutations', () {
      final store = LibraryStore.fromSnapshot(const CatalogSnapshot.empty());

      expect(
        () => store.addTrackToPlaylist(AppDatabase.historyPlaylistId, 999),
        returnsNormally,
      );

      expect(
        () => store.setTrackLiked(999, true),
        returnsNormally,
      );
      expect(
        () => store.toggleTrackLiked(999),
        returnsNormally,
      );
    });

    test('PlaylistsController and PlaybackController gracefully tolerate non-existent track operations', () async {
      final store = LibraryStore(database);
      await store.reloadFromDatabase();
      final playlistsCtrl = PlaylistsController(store: store);
      final playbackCtrl = PlaybackController(
        store: store,
        settingsRepository: settingsRepo,
      );

      await expectLater(
        playlistsCtrl.addTrackToPlaylist(AppDatabase.historyPlaylistId, 99999),
        completes,
      );

      await expectLater(
        playlistsCtrl.toggleLike(99999),
        completes,
      );

      await expectLater(playbackCtrl.play(), completes);
      await expectLater(playbackCtrl.pause(), completes);
      await expectLater(playbackCtrl.next(), completes);
      await expectLater(playbackCtrl.previous(), completes);
      await expectLater(playbackCtrl.seek(const Duration(seconds: 10)), completes);

      const fakeTrack = Track(
        id: 99999,
        filePath: '/non_existent/song.mp3',
        title: 'Ghost Track',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 1000,
      );
      await expectLater(playbackCtrl.addToQueue(fakeTrack), completes);
      await expectLater(playbackCtrl.playNext(fakeTrack), completes);

      playlistsCtrl.dispose();
      playbackCtrl.dispose();
    });
  });
}
