import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late PlaylistsController controller;

  const sampleTrack1 = Track(
    uri: 'file:///music/song1.mp3',
    title: 'Song One',
    artist: 'Artist One',
    album: 'Album One',
    durationMs: 180000,
    fileSize: 5000000,
    modifiedAt: 1600000000,
  );

  const sampleTrack2 = Track(
    uri: 'file:///music/song2.mp3',
    title: 'Song Two',
    artist: 'Artist Two',
    album: 'Album Two',
    durationMs: 210000,
    fileSize: 6000000,
    modifiedAt: 1600000001,
  );

  setUp(() async {
    db = AppDatabaseImpl.inMemory();
    await db.init();
    controller = PlaylistsController(database: db);
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  group('PlaylistsController Initial State & Loading', () {
    test('loadPlaylists populates system playlists and caches liked tracks', () async {
      await controller.loadPlaylists();

      expect(controller.playlists.length, equals(2));
      expect(controller.likedSongsPlaylist, isNotNull);
      expect(controller.historyPlaylist, isNotNull);
      expect(controller.userPlaylists, isEmpty);
      expect(controller.isLoading, isFalse);
    });
  });

  group('PlaylistsController CRUD Operations', () {
    test('createPlaylist creates user playlist and reloads', () async {
      final id = await controller.createPlaylist('Chill Beats');
      expect(id, isPositive);

      expect(controller.userPlaylists.length, equals(1));
      expect(controller.userPlaylists.first.name, equals('Chill Beats'));
      expect(controller.userPlaylists.first.type, equals(PlaylistType.user));
    });

    test('renamePlaylist renames user playlist but ignores system playlists', () async {
      final id = await controller.createPlaylist('Original Name');
      await controller.renamePlaylist(id, 'Renamed Playlist');

      expect(controller.userPlaylists.first.name, equals('Renamed Playlist'));

      // Attempt to rename Liked Songs system playlist
      await controller.renamePlaylist(AppConstants.likedSongsPlaylistId, 'Hacked Liked');
      expect(controller.likedSongsPlaylist?.name, equals(AppConstants.likedSongsPlaylistName));
    });

    test('deletePlaylist removes user playlist but protects system playlists', () async {
      final id = await controller.createPlaylist('To Be Deleted');
      expect(controller.userPlaylists.length, equals(1));

      await controller.deletePlaylist(id);
      expect(controller.userPlaylists, isEmpty);

      // Attempt to delete Liked Songs
      await controller.deletePlaylist(AppConstants.likedSongsPlaylistId);
      expect(controller.likedSongsPlaylist, isNotNull);
    });
  });

  group('PlaylistsController Track Management', () {
    late Track track1;
    late Track track2;

    setUp(() async {
      await db.insertOrUpdateTrack(sampleTrack1);
      await db.insertOrUpdateTrack(sampleTrack2);
      final tracks = await db.getAllTracks();
      track1 = tracks.firstWhere((t) => t.title == 'Song One');
      track2 = tracks.firstWhere((t) => t.title == 'Song Two');
      await controller.loadPlaylists();
    });

    test('addTrackToPlaylist and removeTrackFromPlaylist update tracks and liked cache', () async {
      final playlistId = await controller.createPlaylist('Workout');

      await controller.addTrackToPlaylist(playlistId, track1.id!);
      await controller.selectPlaylist(controller.userPlaylists.first);
      expect(controller.selectedPlaylistTracks.length, equals(1));
      expect(controller.selectedPlaylistTracks.first.title, equals('Song One'));

      await controller.removeTrackFromPlaylist(playlistId, track1.id!);
      expect(controller.selectedPlaylistTracks, isEmpty);
    });

    test('toggleLikeTrack updates in-memory cache and database', () async {
      expect(controller.isTrackLiked(track1.id!), isFalse);

      await controller.toggleLikeTrack(track1);
      expect(controller.isTrackLiked(track1.id!), isTrue);

      final isLikedInDb = await db.isTrackLiked(track1.id!);
      expect(isLikedInDb, isTrue);

      await controller.toggleLikeTrack(track1);
      expect(controller.isTrackLiked(track1.id!), isFalse);
    });

    test('reorderPlaylistEntries updates track order optimistically and in DB', () async {
      final playlistId = await controller.createPlaylist('Mix');
      await controller.addTrackToPlaylist(playlistId, track1.id!);
      await controller.addTrackToPlaylist(playlistId, track2.id!);

      final createdPlaylist = controller.userPlaylists.firstWhere((p) => p.id == playlistId);
      await controller.selectPlaylist(createdPlaylist);
      expect(controller.selectedPlaylistTracks[0].title, equals('Song One'));
      expect(controller.selectedPlaylistTracks[1].title, equals('Song Two'));

      await controller.reorderPlaylistEntries(playlistId, 0, 1);
      expect(controller.selectedPlaylistTracks[0].title, equals('Song Two'));
      expect(controller.selectedPlaylistTracks[1].title, equals('Song One'));
    });
  });
}
