import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  group('Track Domain Model', () {
    test('instantiates with defaults and provides duration/dateTime getters', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final track = Track(
        uri: 'file:///music/song.mp3',
        title: 'Song Title',
        durationMs: 184500,
        fileSize: 1024000,
        modifiedAt: nowMs,
      );

      expect(track.uri, equals('file:///music/song.mp3'));
      expect(track.title, equals('Song Title'));
      expect(track.durationMs, equals(184500));
      expect(track.duration, equals(const Duration(minutes: 3, seconds: 4, milliseconds: 500)));
      expect(track.discNumber, equals(1));
      expect(track.hasCover, isFalse);
      expect(track.artists, isEmpty);
      expect(track.genres, isEmpty);
      expect(track.modifiedDateTime.millisecondsSinceEpoch, equals(nowMs));
      expect(track.artistName, isNull);
      expect(track.albumName, isNull);
    });

    test('copyWith updates specified fields while preserving others', () {
      const track = Track(
        id: 1,
        uri: 'file:///music/track1.flac',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 200000,
        fileSize: 5000000,
        modifiedAt: 1700000000,
      );

      final updated = track.copyWith(
        title: 'Updated Title',
        bitrate: 320000,
        hasCover: true,
        genres: ['Rock', 'Metal'],
      );

      expect(updated.id, equals(1));
      expect(updated.uri, equals('file:///music/track1.flac'));
      expect(updated.title, equals('Updated Title'));
      expect(updated.artist, equals('Original Artist'));
      expect(updated.bitrate, equals(320000));
      expect(updated.hasCover, isTrue);
      expect(updated.genres, equals(['Rock', 'Metal']));
      expect(track.title, equals('Original Title')); // original untouched
    });

    test('toDbMap and fromDbMap handle SQLite mapping properly', () {
      const track = Track(
        id: 42,
        uri: 'file:///music/metallica/one.flac',
        title: 'One',
        albumId: 5,
        album: '...And Justice for All',
        artistId: 10,
        artist: 'Metallica',
        albumArtist: 'Metallica',
        trackNumber: 4,
        discNumber: 1,
        year: 1988,
        durationMs: 446000,
        bitrate: 980000,
        sampleRate: 44100,
        channels: 2,
        codec: 'flac',
        fileSize: 45000000,
        modifiedAt: 1690000000,
        lyrics: 'I cannot remember anything...',
        hasCover: true,
        genres: ['Thrash Metal'],
      );

      final dbMap = track.toDbMap();
      expect(dbMap['id'], equals(42));
      expect(dbMap['uri'], equals('file:///music/metallica/one.flac'));
      expect(dbMap['has_cover'], equals(1));
      expect(dbMap['duration_ms'], equals(446000));
      expect(dbMap['album_id'], equals(5));
      expect(dbMap['artist_id'], equals(10));

      final restored = Track.fromDbMap(
        dbMap,
        albumName: '...And Justice for All',
        artistName: 'Metallica',
        artists: ['Metallica'],
        genres: ['Thrash Metal'],
      );

      expect(restored.id, equals(track.id));
      expect(restored.uri, equals(track.uri));
      expect(restored.title, equals(track.title));
      expect(restored.album, equals(track.album));
      expect(restored.artist, equals(track.artist));
      expect(restored.hasCover, isTrue);
      expect(restored.genres, equals(['Thrash Metal']));
      expect(restored.artists, equals(['Metallica']));
    });

    test('toJson and fromJson serialize and deserialize accurately', () {
      const track = Track(
        id: 7,
        uri: 'file:///music/daftpunk/get_lucky.mp3',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        artists: ['Daft Punk', 'Pharrell Williams'],
        album: 'Random Access Memories',
        albumArtist: 'Daft Punk',
        trackNumber: 8,
        discNumber: 1,
        year: 2013,
        durationMs: 248000,
        bitrate: 320000,
        sampleRate: 48000,
        channels: 2,
        codec: 'mp3',
        fileSize: 9800000,
        modifiedAt: 1680000000,
        hasCover: true,
        genres: ['Disco', 'Funk'],
      );

      final json = track.toJson();
      final fromJson = Track.fromJson(json);

      expect(fromJson, equals(track));
      expect(fromJson.hashCode, equals(track.hashCode));
    });

    test('equality and hashCode distinguish different tracks', () {
      const track1 = Track(
        uri: 'file:///track1.mp3',
        title: 'Title 1',
        durationMs: 100,
        fileSize: 1000,
        modifiedAt: 10,
      );

      const track2 = Track(
        uri: 'file:///track1.mp3',
        title: 'Title 1',
        durationMs: 100,
        fileSize: 1000,
        modifiedAt: 10,
      );

      final track3 = track1.copyWith(title: 'Title 2');

      expect(track1, equals(track2));
      expect(track1.hashCode, equals(track2.hashCode));
      expect(track1, isNot(equals(track3)));
    });
  });

  group('Album Domain Model', () {
    test('constructor and copyWith operate properly', () {
      const album = Album(
        id: 1,
        name: 'Dark Side of the Moon',
        artistId: 2,
        artistName: 'Pink Floyd',
        year: 1973,
        trackCount: 10,
      );

      expect(album.name, equals('Dark Side of the Moon'));
      expect(album.trackCount, equals(10));

      final updated = album.copyWith(trackCount: 11);
      expect(updated.trackCount, equals(11));
      expect(updated.name, equals('Dark Side of the Moon'));
    });

    test('toDbMap and fromDbMap roundtrip successfully', () {
      const album = Album(
        id: 3,
        name: 'Abbey Road',
        artistId: 1,
        artistName: 'The Beatles',
        year: 1969,
        trackCount: 17,
      );

      final dbMap = album.toDbMap();
      expect(dbMap['id'], equals(3));
      expect(dbMap['name'], equals('Abbey Road'));
      expect(dbMap['track_count'], equals(17));

      final restored = Album.fromDbMap(dbMap);
      expect(restored.id, equals(3));
      expect(restored.name, equals('Abbey Road'));
      expect(restored.artistName, equals('The Beatles'));
      expect(restored.trackCount, equals(17));
    });

    test('toJson and fromJson support nested tracks', () {
      const track = Track(
        uri: 'file:///music/song.mp3',
        title: 'Come Together',
        durationMs: 260000,
        fileSize: 8000000,
        modifiedAt: 1000,
      );

      const album = Album(
        id: 4,
        name: 'Abbey Road',
        artistName: 'The Beatles',
        year: 1969,
        trackCount: 1,
        tracks: [track],
      );

      final json = album.toJson();
      final fromJson = Album.fromJson(json);

      expect(fromJson.name, equals('Abbey Road'));
      expect(fromJson.tracks.length, equals(1));
      expect(fromJson.tracks.first.title, equals('Come Together'));
      expect(fromJson, equals(album));
      expect(fromJson.hashCode, equals(album.hashCode));
    });
  });

  group('Artist Domain Model', () {
    test('constructor, copyWith, toDbMap, fromDbMap, and toJson', () {
      const artist = Artist(
        id: 5,
        name: 'Led Zeppelin',
        trackCount: 80,
        albumCount: 8,
      );

      expect(artist.name, equals('Led Zeppelin'));
      expect(artist.trackCount, equals(80));
      expect(artist.albumCount, equals(8));

      final copy = artist.copyWith(trackCount: 82);
      expect(copy.trackCount, equals(82));

      final dbMap = artist.toDbMap();
      final fromDb = Artist.fromDbMap(dbMap);
      expect(fromDb.name, equals('Led Zeppelin'));
      expect(fromDb.trackCount, equals(80));

      final json = artist.toJson();
      final fromJson = Artist.fromJson(json);
      expect(fromJson, equals(artist));
      expect(fromJson.hashCode, equals(artist.hashCode));
    });
  });

  group('Genre Domain Model', () {
    test('constructor, copyWith, toDbMap, fromDbMap, and toJson', () {
      const genre = Genre(
        id: 8,
        name: 'Progressive Rock',
        trackCount: 35,
      );

      expect(genre.name, equals('Progressive Rock'));
      expect(genre.trackCount, equals(35));

      final copy = genre.copyWith(trackCount: 36);
      expect(copy.trackCount, equals(36));

      final dbMap = genre.toDbMap();
      final fromDb = Genre.fromDbMap(dbMap);
      expect(fromDb.name, equals('Progressive Rock'));

      final json = genre.toJson();
      final fromJson = Genre.fromJson(json);
      expect(fromJson.name, equals('Progressive Rock'));
      expect(fromJson, equals(genre));
    });
  });

  group('Playlist & PlaylistEntry Domain Models', () {
    test('PlaylistType enum handles value mapping', () {
      expect(PlaylistType.fromValue(0), equals(PlaylistType.user));
      expect(PlaylistType.fromValue(1), equals(PlaylistType.liked));
      expect(PlaylistType.fromValue(2), equals(PlaylistType.history));
      expect(PlaylistType.fromValue(99), equals(PlaylistType.user));
    });

    test('PlaylistEntry constructor, copyWith, toDbMap, fromDbMap, and toJson', () {
      const entry = PlaylistEntry(
        id: 1,
        playlistId: 10,
        trackId: 100,
        uri: 'file:///song.mp3',
        customTitle: 'Special Track',
        position: 0,
        addedAt: 12345678,
      );

      expect(entry.playlistId, equals(10));
      expect(entry.position, equals(0));

      final copy = entry.copyWith(position: 1);
      expect(copy.position, equals(1));

      final dbMap = entry.toDbMap();
      expect(dbMap['playlist_id'], equals(10));
      expect(dbMap['position'], equals(0));

      final fromDb = PlaylistEntry.fromDbMap(dbMap);
      expect(fromDb.playlistId, equals(10));
      expect(fromDb.uri, equals('file:///song.mp3'));

      final json = entry.toJson();
      final fromJson = PlaylistEntry.fromJson(json);
      expect(fromJson, equals(entry));
      expect(fromJson.hashCode, equals(entry.hashCode));
    });

    test('Playlist constructor, properties, special status, and json mapping', () {
      const likedPlaylist = Playlist(
        id: 1,
        name: 'Liked Songs',
        createdAt: 1000000,
        type: PlaylistType.liked,
      );

      expect(likedPlaylist.isSpecial, equals(1));
      expect(likedPlaylist.isSpecialPlaylist, isTrue);

      const userPlaylist = Playlist(
        id: 12,
        name: 'Road Trip',
        createdAt: 2000000,
        type: PlaylistType.user,
        explicitTrackCount: 5,
      );

      expect(userPlaylist.isSpecial, equals(0));
      expect(userPlaylist.isSpecialPlaylist, isFalse);
      expect(userPlaylist.trackCount, equals(5));

      final dbMap = userPlaylist.toDbMap();
      expect(dbMap['name'], equals('Road Trip'));
      expect(dbMap['is_special'], equals(0));

      final fromDb = Playlist.fromDbMap(dbMap);
      expect(fromDb.name, equals('Road Trip'));
      expect(fromDb.type, equals(PlaylistType.user));

      final json = userPlaylist.toJson();
      final fromJson = Playlist.fromJson(json);
      expect(fromJson.name, equals('Road Trip'));
      expect(fromJson.type, equals(PlaylistType.user));
    });
  });
}
