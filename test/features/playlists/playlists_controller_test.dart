import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DirectTachyonBackendClient backend;
  late PlaylistsController controller;

  setUp(() async {
    db = AppDatabase.inMemory();
    await db.init();
    backend = DirectTachyonBackendClient(database: db);
    controller = PlaylistsController(backend: backend);
  });

  tearDown(() async {
    await db.close();
  });

  group('PlaylistsController Tests', () {
    test('loadPlaylists loads default playlists and caches liked track IDs', () async {
      // Insert a dummy track
      final track = Track(
        filePath: '/music/song1.mp3',
        title: 'Song 1',
        artist: 'Artist 1',
        album: 'Album 1',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 123456,
      );
      await db.insertTrack(track);
      final inserted = await db.getTrackByFilePath(track.filePath);
      final trackId = inserted!.id!;

      // Like the track
      await backend.toggleLikeTrack(trackId, track.filePath);

      // Load playlists
      await controller.loadPlaylists();

      expect(controller.errorMessage, isNull);
      expect(controller.playlists, isNotEmpty);
      expect(controller.isTrackLiked(trackId), isTrue);
      expect(controller.isTrackLiked(9999), isFalse);
    });

    test('getPlaylistTrackIds returns List<int> correctly', () async {
      final track = Track(
        filePath: '/music/song2.mp3',
        title: 'Song 2',
        artist: 'Artist 2',
        album: 'Album 2',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 123456,
      );
      await db.insertTrack(track);
      final inserted = await db.getTrackByFilePath(track.filePath);
      final trackId = inserted!.id!;
      await backend.toggleLikeTrack(trackId, track.filePath);

      final trackIds = await backend.getPlaylistTrackIds(AppDatabase.likedSongsPlaylistId);
      expect(trackIds, isA<List<int>>());
      expect(trackIds, contains(trackId));
    });
  });
}
