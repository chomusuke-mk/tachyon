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

  group('AppDatabase.getExistingTrackMetas', () {
    test('returns empty map on fresh database with no tracks', () async {
      final metas = await db.getExistingTrackMetas();
      expect(metas, isEmpty);
    });

    test('returns populated map with exact uri, modifiedAt, and fileSize', () async {
      const track1 = Track(
        uri: '/music/song1.mp3',
        title: 'Song 1',
        fileSize: 1024000,
        modifiedAt: 1700000000000,
        durationMs: 180000,
      );
      const track2 = Track(
        uri: '/music/song2.flac',
        title: 'Song 2',
        fileSize: 20480000,
        modifiedAt: 1700000500000,
        durationMs: 240000,
      );

      await db.batchInsertTracks([track1, track2]);

      final metas = await db.getExistingTrackMetas();
      expect(metas.length, equals(2));
      expect(metas.containsKey('/music/song1.mp3'), isTrue);
      expect(metas.containsKey('/music/song2.flac'), isTrue);

      final meta1 = metas['/music/song1.mp3']!;
      expect(meta1.modifiedAt, equals(1700000000000));
      expect(meta1.fileSize, equals(1024000));

      final meta2 = metas['/music/song2.flac']!;
      expect(meta2.modifiedAt, equals(1700000500000));
      expect(meta2.fileSize, equals(20480000));
    });

    test('reflects updated modifiedAt and fileSize after track re-insertion', () async {
      const initialTrack = Track(
        uri: '/music/song1.mp3',
        title: 'Song 1',
        fileSize: 1024000,
        modifiedAt: 1700000000000,
        durationMs: 180000,
      );
      await db.batchInsertTracks([initialTrack]);

      final initialMetas = await db.getExistingTrackMetas();
      expect(initialMetas['/music/song1.mp3']!.fileSize, equals(1024000));

      // Update track with new size and timestamp
      const updatedTrack = Track(
        uri: '/music/song1.mp3',
        title: 'Song 1 Remastered',
        fileSize: 1050000,
        modifiedAt: 1700000999000,
        durationMs: 185000,
      );
      await db.batchInsertTracks([updatedTrack]);

      final updatedMetas = await db.getExistingTrackMetas();
      expect(updatedMetas.length, equals(1));
      expect(updatedMetas['/music/song1.mp3']!.fileSize, equals(1050000));
      expect(updatedMetas['/music/song1.mp3']!.modifiedAt, equals(1700000999000));
    });

    test('excludes tracks that were deleted', () async {
      const track1 = Track(
        uri: '/music/song1.mp3',
        title: 'Song 1',
        fileSize: 1024000,
        modifiedAt: 1700000000000,
        durationMs: 180000,
      );
      await db.batchInsertTracks([track1]);

      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(1));

      await db.database.delete('tracks', where: 'id = ?', whereArgs: [tracks.first.id]);

      final metas = await db.getExistingTrackMetas();
      expect(metas, isEmpty);
    });
  });
}
