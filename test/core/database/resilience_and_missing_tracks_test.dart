import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Error Resilience & Missing Data Tests', () {
    late AppDatabase database;
    late TachyonBackendClient backend;
    late SettingsRepository settingsRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      database = AppDatabase.inMemory();
      backend = DirectTachyonBackendClient(database: database);
    });

    tearDown(() async {
      await database.close();
    });

    test('AppDatabase.addTrackToPlaylist ignores non-existent trackId without throwing SqliteException(787)', () {
      // Playlist exists (History = 2), but track 999 does not exist
      expect(
        () => database.addTrackToPlaylist(AppDatabase.historyPlaylistId, 999),
        returnsNormally,
      );

      final historyEntries = database.getTrackIdsForPlaylist(AppDatabase.historyPlaylistId);
      expect(historyEntries, isEmpty);
    });

    test('AppDatabase.addTracksToPlaylist ignores deleted trackIds without throwing SqliteException(787)', () {
      // Insert one valid track
      final validTrack = ExtractedTrackData(
        filePath: '/music/song1.mp3',
        title: 'Song One',
        artistNames: ['Artist A'],
        albumName: 'Album One',
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 123456789,
      );
      database.upsertTracks([validTrack]);

      final snapshot = database.getCatalogSnapshot();
      final validId = snapshot.tracks.first.id;

      // Add validId and non-existent id 999
      expect(
        () => database.addTracksToPlaylist(AppDatabase.historyPlaylistId, [validId, 999, 1000]),
        returnsNormally,
      );

      final historyEntries = database.getTrackIdsForPlaylist(AppDatabase.historyPlaylistId);
      expect(historyEntries, [validId]);
    });

    test('AppDatabase handles operations on deleted track when music directory was removed', () {
      final track = ExtractedTrackData(
        filePath: '/music/deleted_dir/song2.mp3',
        title: 'Song Two',
        artistNames: ['Artist B'],
        durationMs: 200000,
        fileSize: 4000000,
        modifiedAt: 123456790,
      );
      database.upsertTracks([track]);

      final snapshot = database.getCatalogSnapshot();
      final trackId = snapshot.tracks.first.id;

      // Simulate directory removal and rescan: track is deleted from database
      database.deleteTrack(trackId);

      // Subsequent attempt by player history logger to record the deleted track
      expect(
        () => database.addTracksToPlaylist(AppDatabase.historyPlaylistId, [trackId]),
        returnsNormally,
      );

      // Attempt to toggle like on deleted track
      expect(
        () => database.toggleLikeTrack(trackId),
        returnsNormally,
      );

      // Attempt to remove deleted track from playlist
      expect(
        () => database.removeTrackFromPlaylist(AppDatabase.historyPlaylistId, trackId),
        returnsNormally,
      );
    });

    test('LibraryStore handles null/missing tracks safely in playlist mutations', () {
      final store = LibraryStore.fromSnapshot(CatalogSnapshot.empty());

      // Try adding non-existent trackId to a playlist
      expect(
        () => store.addTrackToPlaylist(AppDatabase.historyPlaylistId, 999),
        returnsNormally,
      );

      // Try toggling like for non-existent trackId
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
      final store = LibraryStore.fromSnapshot(database.getCatalogSnapshot());
      final playlistsCtrl = PlaylistsController(backend: backend, store: store);
      final playbackCtrl = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      // Calling addTrackToPlaylist with invalid IDs does not throw
      await expectLater(
        playlistsCtrl.addTrackToPlaylist(AppDatabase.historyPlaylistId, 99999),
        completes,
      );

      await expectLater(
        playlistsCtrl.toggleLike(99999),
        completes,
      );

      // Transport controls on PlaybackController with empty queue do not throw
      await expectLater(playbackCtrl.play(), completes);
      await expectLater(playbackCtrl.pause(), completes);
      await expectLater(playbackCtrl.next(), completes);
      await expectLater(playbackCtrl.previous(), completes);
      await expectLater(playbackCtrl.seek(const Duration(seconds: 10)), completes);

      // Adding deleted track to queue does not crash
      final fakeTrack = const Track(
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
