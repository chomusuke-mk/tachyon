import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track.parseReplayGain', () {
    test('parses plain numeric strings and numbers correctly', () {
      expect(Track.parseReplayGain('-6.43'), equals(-6.43));
      expect(Track.parseReplayGain('+1.25'), equals(1.25));
      expect(Track.parseReplayGain('0.981201'), equals(0.981201));
      expect(Track.parseReplayGain(-3.5), equals(-3.5));
      expect(Track.parseReplayGain(1), equals(1.0));
    });

    test('strips dB units and whitespace cleanly', () {
      expect(Track.parseReplayGain('-6.43 dB'), equals(-6.43));
      expect(Track.parseReplayGain('  +2.15 dB '), equals(2.15));
      expect(Track.parseReplayGain('-0.5dB'), equals(-0.5));
    });

    test('returns null for null or invalid inputs', () {
      expect(Track.parseReplayGain(null), isNull);
      expect(Track.parseReplayGain(''), isNull);
      expect(Track.parseReplayGain('invalid'), isNull);
    });
  });

  group('ReplayGain Persistence in AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('insertOrUpdateTrack saves and loads all 4 ReplayGain fields', () async {
      const track = Track(
        filePath: '/music/song_rg.mp3',
        title: 'Song with ReplayGain',
        artist: 'Test Artist',
        album: 'Test Album',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 123456789,
        replayGainTrackGain: -7.52,
        replayGainTrackPeak: 0.9821,
        replayGainAlbumGain: -5.40,
        replayGainAlbumPeak: 1.0000,
      );

      await db.insertOrUpdateTrack(track);

      final byPath = await db.getTrackByFilePath('/music/song_rg.mp3');
      expect(byPath, isNotNull);
      expect(byPath!.replayGainTrackGain, equals(-7.52));
      expect(byPath.replayGainTrackPeak, equals(0.9821));
      expect(byPath.replayGainAlbumGain, equals(-5.40));
      expect(byPath.replayGainAlbumPeak, equals(1.0));

      final allTracks = await db.getAllTracks();
      expect(allTracks.length, equals(1));
      expect(allTracks.first.replayGainTrackGain, equals(-7.52));
      expect(allTracks.first.replayGainTrackPeak, equals(0.9821));
      expect(allTracks.first.replayGainAlbumGain, equals(-5.40));
      expect(allTracks.first.replayGainAlbumPeak, equals(1.0));
    });

    test('batchInsertTracks and queries preserve ReplayGain across albums and playlists', () async {
      const track = Track(
        filePath: '/music/album_track.flac',
        title: 'Album Track',
        artist: 'Great Artist',
        album: 'Masterpiece',
        durationMs: 180000,
        fileSize: 2048,
        modifiedAt: 987654321,
        replayGainTrackGain: -8.12,
        replayGainTrackPeak: 0.9543,
        replayGainAlbumGain: -7.80,
        replayGainAlbumPeak: 0.9990,
      );

      await db.batchInsertTracks([track]);

      final allTracks = await db.getAllTracks();
      final trackId = allTracks.first.id!;
      final albumId = allTracks.first.albumId!;
      final artistId = allTracks.first.artistId!;

      // getTracksByAlbumId
      final albumTracks = await db.getTracksByAlbumId(albumId);
      expect(albumTracks.first.replayGainTrackGain, equals(-8.12));
      expect(albumTracks.first.replayGainTrackPeak, equals(0.9543));
      expect(albumTracks.first.replayGainAlbumGain, equals(-7.80));
      expect(albumTracks.first.replayGainAlbumPeak, equals(0.9990));

      // getTracksByArtistId
      final artistTracks = await db.getTracksByArtistId(artistId);
      expect(artistTracks.first.replayGainTrackGain, equals(-8.12));
      expect(artistTracks.first.replayGainAlbumGain, equals(-7.80));

      // searchTracks
      final searchResults = await db.searchTracks('Album');
      expect(searchResults.first.replayGainTrackGain, equals(-8.12));
      expect(searchResults.first.replayGainAlbumGain, equals(-7.80));

      // Playlist retrieval
      final pId = await db.createPlaylist('RG Playlist');
      await db.addTrackToPlaylist(pId, trackId);
      final playlistTracks = await db.getTracksForPlaylist(pId);
      expect(playlistTracks.first.replayGainTrackGain, equals(-8.12));
      expect(playlistTracks.first.replayGainTrackPeak, equals(0.9543));
      expect(playlistTracks.first.replayGainAlbumGain, equals(-7.80));
      expect(playlistTracks.first.replayGainAlbumPeak, equals(0.9990));
    });
  });

  group('QueueItem ReplayGain propagation', () {
    test('preserves ReplayGain when converting from Track and back to Track', () {
      const track = Track(
        id: 42,
        filePath: '/music/rg.opus',
        title: 'Opus Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 250000,
        fileSize: 1000,
        modifiedAt: 1000,
        replayGainTrackGain: -4.20,
        replayGainTrackPeak: 0.9123,
        replayGainAlbumGain: -3.80,
        replayGainAlbumPeak: 0.9450,
      );

      final queueItem = QueueItem.fromTrack(track);
      expect(queueItem.replayGainTrackGain, equals(-4.20));
      expect(queueItem.replayGainTrackPeak, equals(0.9123));
      expect(queueItem.replayGainAlbumGain, equals(-3.80));
      expect(queueItem.replayGainAlbumPeak, equals(0.9450));

      final convertedTrack = queueItem.toTrack();
      expect(convertedTrack.replayGainTrackGain, equals(-4.20));
      expect(convertedTrack.replayGainTrackPeak, equals(0.9123));
      expect(convertedTrack.replayGainAlbumGain, equals(-3.80));
      expect(convertedTrack.replayGainAlbumPeak, equals(0.9450));
    });
  });
}
