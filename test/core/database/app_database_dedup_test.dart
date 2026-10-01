import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase Album/Artist Deduplication and Orphan Cleanup', () {
    test('getAllAlbums and getAllArtists exclude 0-track entries', () async {
      // Insert empty album and artist directly
      await db.database.insert('artists', {
        'name': 'Ghost Artist',
        'track_count': 0,
        'album_count': 0,
      });
      await db.database.insert('albums', {
        'name': 'Empty Album',
        'artist_name': 'Ghost Artist',
        'track_count': 0,
      });

      final albumsBefore = await db.getAllAlbums();
      final artistsBefore = await db.getAllArtists();
      expect(albumsBefore.any((a) => a.name == 'Empty Album'), isFalse);
      expect(artistsBefore.any((a) => a.name == 'Ghost Artist'), isFalse);
    });

    test('cleanOrphanAlbumsAndArtists removes albums and artists with 0 tracks', () async {
      await db.database.insert('artists', {
        'name': 'Orphan Artist',
        'track_count': 0,
        'album_count': 0,
      });
      await db.database.insert('albums', {
        'name': 'Orphan Album',
        'artist_name': 'Orphan Artist',
        'track_count': 0,
      });

      await db.cleanOrphanAlbumsAndArtists();

      final albumRows = await db.database.query(
        'albums',
        where: 'name = ?',
        whereArgs: ['Orphan Album'],
      );
      expect(albumRows, isEmpty);

      final artistRows = await db.database.query(
        'artists',
        where: 'name = ?',
        whereArgs: ['Orphan Artist'],
      );
      expect(artistRows, isEmpty);
    });

    test('cleanOrphanAlbumsAndArtists merges duplicate albums and re-links tracks', () async {
      // Insert two duplicate albums
      final album1Id = await db.database.insert('albums', {
        'name': 'Thriller',
        'artist_name': 'Michael Jackson',
        'track_count': 1,
      });
      final album2Id = await db.database.insert('albums', {
        'name': 'thriller',
        'artist_name': 'michael jackson',
        'track_count': 1,
      });

      // Insert two tracks, each pointing to one of the album IDs
      final track1 = Track(
        filePath: '/music/track1.mp3',
        title: 'Billie Jean',
        album: 'Thriller',
        artist: 'Michael Jackson',
        albumId: album1Id,
        durationMs: 294000,
        fileSize: 5000000,
        modifiedAt: 123456,
      );
      final track2 = Track(
        filePath: '/music/track2.mp3',
        title: 'Beat It',
        album: 'thriller',
        artist: 'michael jackson',
        albumId: album2Id,
        durationMs: 258000,
        fileSize: 4500000,
        modifiedAt: 123456,
      );

      await db.database.insert('tracks', {
        'file_path': track1.filePath,
        'title': track1.title,
        'album_id': album1Id,
        'duration_ms': track1.durationMs,
        'file_size': track1.fileSize,
        'modified_at': track1.modifiedAt,
      });
      await db.database.insert('tracks', {
        'file_path': track2.filePath,
        'title': track2.title,
        'album_id': album2Id,
        'duration_ms': track2.durationMs,
        'file_size': track2.fileSize,
        'modified_at': track2.modifiedAt,
      });

      await db.cleanOrphanAlbumsAndArtists();

      // Should now only be 1 album
      final albums = await db.getAllAlbums();
      expect(albums.length, equals(1));
      expect(albums.first.name.toLowerCase(), equals('thriller'));
      expect(albums.first.trackCount, equals(2));

      // Both tracks should now point to the canonical album ID
      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(2));
      expect(tracks[0].albumId, equals(albums.first.id));
      expect(tracks[1].albumId, equals(albums.first.id));
    });

    test('batchInsertTracks groups tracks with same albumArtist into single album despite featured artists', () async {
      final tracks = [
        Track(
          filePath: '/music/song1.mp3',
          title: 'Say Say Say',
          artist: 'Paul McCartney & Michael Jackson',
          albumArtist: 'Paul McCartney',
          album: 'Pipes of Peace',
          durationMs: 235000,
          fileSize: 4000000,
          modifiedAt: 123456,
        ),
        Track(
          filePath: '/music/song2.mp3',
          title: 'Pipes of Peace',
          artist: 'Paul McCartney',
          albumArtist: 'Paul McCartney',
          album: 'Pipes of Peace',
          durationMs: 236000,
          fileSize: 4100000,
          modifiedAt: 123456,
        ),
      ];

      await db.batchInsertTracks(tracks);

      final albums = await db.getAllAlbums();
      expect(albums.length, equals(1));
      expect(albums.first.name, equals('Pipes of Peace'));
      expect(albums.first.trackCount, equals(2));
    });

    test('deleteTrack removes track and cleans orphan album/artist', () async {
      final track = Track(
        filePath: '/music/solo.mp3',
        title: 'Only Song',
        artist: 'One Hit Wonder',
        album: 'One Hit Album',
        durationMs: 180000,
        fileSize: 3000000,
        modifiedAt: 123456,
      );

      await db.batchInsertTracks([track]);

      var albums = await db.getAllAlbums();
      var artists = await db.getAllArtists();
      expect(albums.length, equals(1));
      expect(artists.length, equals(1));

      final tracks = await db.getAllTracks();
      await db.deleteTrack(tracks.first.id!);

      albums = await db.getAllAlbums();
      artists = await db.getAllArtists();
      expect(albums, isEmpty);
      expect(artists, isEmpty);
    });
  });
}
