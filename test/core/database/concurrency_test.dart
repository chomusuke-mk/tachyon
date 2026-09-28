import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('SQLite AppDatabase Concurrency & Single-Writer Isolation Tests', () {
    test('Simultaneous 100 concurrent reads and 50 writes complete without database is locked errors', () async {
      // 1. Seed initial database records
      for (int i = 0; i < 20; i++) {
        await db.database.insert('tracks', {
          'id': i + 1,
          'uri': '/music/initial_track_$i.mp3',
          'title': 'Initial Track $i',
          'duration_ms': 180000 + i * 1000,
          'file_size': 3000000 + i * 1000,
          'modified_at': 1700000000000 + i,
        });
      }

      final readErrors = <Object>[];
      final writeErrors = <Object>[];

      // 2. Prepare 50 concurrent write futures (bulk/streamed inserts from scan isolate)
      final writeFutures = List.generate(50, (index) async {
        try {
          final trackId = 100 + index;
          await db.database.insert('tracks', {
            'id': trackId,
            'uri': '/music/concurrent_track_$index.mp3',
            'title': 'Concurrent Track $index',
            'duration_ms': 200000,
            'file_size': 4000000,
            'modified_at': 1700000000000 + index,
          });
        } catch (e) {
          writeErrors.add(e);
        }
      });

      // 3. Prepare 100 concurrent read futures (UI and controller queries)
      final readFutures = List.generate(100, (index) async {
        try {
          // Query all tracks
          final tracks = await db.getAllTracks();
          expect(tracks, isNotEmpty);

          // Check liked status on random track
          final randomId = (index % 20) + 1;
          await db.isTrackLiked(randomId);

          // Search catalog
          await db.searchTracks('Track');

          // Query lyrics cache
          await db.getLyrics('hash_$index');
        } catch (e) {
          readErrors.add(e);
        }
      });

      // 4. Interleave and execute all 150 operations concurrently
      await Future.wait([...writeFutures, ...readFutures]);

      // 5. Assert zero locked database errors
      expect(
        writeErrors,
        isEmpty,
        reason: 'Write operations encountered concurrency errors: $writeErrors',
      );
      expect(
        readErrors,
        isEmpty,
        reason: 'Read operations encountered concurrency errors: $readErrors',
      );

      // 6. Verify data integrity: 20 initial + 50 concurrent = 70 tracks
      final totalTracks = await db.getAllTracks();
      expect(totalTracks.length, equals(70));
    });

    test('Transaction rollback on write error releases lock and leaves database consistent', () async {
      await db.database.insert('tracks', {
        'id': 1,
        'uri': '/music/existing.mp3',
        'title': 'Existing Track',
        'duration_ms': 180000,
        'file_size': 3000000,
        'modified_at': 1700000000000,
      });

      // Attempt transaction that violates UNIQUE constraint on uri
      bool failedAsExpected = false;
      try {
        await db.database.transaction((txn) async {
          await txn.insert('tracks', {
            'id': 2,
            'uri': '/music/new_valid.mp3',
            'title': 'Valid Track',
            'duration_ms': 180000,
            'file_size': 3000000,
            'modified_at': 1700000000000,
          });

          // Duplicate URI causes unique constraint abort
          await txn.insert('tracks', {
            'id': 3,
            'uri': '/music/existing.mp3', // Duplicate!
            'title': 'Duplicate URI Track',
            'duration_ms': 180000,
            'file_size': 3000000,
            'modified_at': 1700000000000,
          });
        });
      } catch (e) {
        failedAsExpected = true;
      }

      expect(failedAsExpected, isTrue);

      // Verify that 'new_valid.mp3' was rolled back completely
      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(1));
      expect(tracks.first.uri, equals('/music/existing.mp3'));

      // Verify database remains responsive to subsequent queries and writes
      await db.database.insert('tracks', {
        'id': 4,
        'uri': '/music/after_rollback.mp3',
        'title': 'After Rollback',
        'duration_ms': 180000,
        'file_size': 3000000,
        'modified_at': 1700000000000,
      });

      final updatedTracks = await db.getAllTracks();
      expect(updatedTracks.length, equals(2));
    });
  });
}
