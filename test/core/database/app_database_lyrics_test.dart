import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase Lyrics Source Persistence (Milestone 1)', () {
    // -------------------------------------------------------------------------
    // Test Spec 1: Schema & Table Initialization
    // -------------------------------------------------------------------------
    test('1. lyrics_source_cache and lyrics_cache tables exist with correct schema and index', () async {
      final tables = await db.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('lyrics_source_cache', 'lyrics_cache');",
      );
      final tableNames = tables.map((r) => r['name']).toSet();
      expect(tableNames.contains('lyrics_source_cache'), isTrue);
      expect(tableNames.contains('lyrics_cache'), isTrue);

      final tableInfo = await db.database.rawQuery(
        "PRAGMA table_info('lyrics_source_cache');",
      );
      final columnNames = tableInfo.map((r) => r['name'] as String).toList();
      expect(
        columnNames,
        containsAll([
          'key_hash',
          'source',
          'state',
          'raw_lrc',
          'is_synced',
          'updated_at',
        ]),
      );

      // Verify composite primary key: key_hash (pk=1) and source (pk=2)
      final pkColumns = tableInfo.where((r) => (r['pk'] as int) > 0).toList();
      expect(pkColumns.length, equals(2));
      final pkNames = pkColumns.map((r) => r['name']).toSet();
      expect(pkNames, equals({'key_hash', 'source'}));

      // Verify index on key_hash exists
      final indexes = await db.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_lyrics_source_cache_key';",
      );
      expect(indexes.isNotEmpty, isTrue);
    });

    // -------------------------------------------------------------------------
    // Test Spec 2: CRUD with Full Fidelity
    // -------------------------------------------------------------------------
    test('2. saves and retrieves entry with full fidelity across all fields', () async {
      const keyHash = 'track_hash_full_fidelity';
      const rawLrc = '[00:15.00]Line 1\n[00:20.00]Line 2';
      final entry = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        rawLrc: rawLrc,
        isSynced: true,
        updatedAt: 1700000000000,
      );

      await db.saveLyricsSourceEntry(entry);

      final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(retrieved, isNotNull);
      expect(retrieved!.keyHash, equals(keyHash));
      expect(retrieved.source, equals(LyricsSource.lrclib));
      expect(retrieved.state, equals(LyricsSourceState.found));
      expect(retrieved.rawLrc, equals(rawLrc));
      expect(retrieved.isSynced, isTrue);
      expect(retrieved.updatedAt, equals(1700000000000));
      expect(retrieved.hasLyrics, isTrue);
      expect(retrieved.isFound, isTrue);
      expect(retrieved.isNotFound, isFalse);
      expect(retrieved.isTemporaryError, isFalse);

      // Deletion of single source
      final deleted = await db.deleteLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(deleted, equals(1));
      expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib), isNull);
    });

    // -------------------------------------------------------------------------
    // Test Spec 3: Edge Case: Null raw_lrc in NOT_FOUND entry
    // -------------------------------------------------------------------------
    test('3. edge case: null raw_lrc in notFound entry succeeds without NOT NULL constraint error', () async {
      const keyHash = 'track_hash_404';
      const entry = LyricsSourceEntry(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        state: LyricsSourceState.notFound,
        rawLrc: null,
        isSynced: false,
        updatedAt: 1700000000000,
      );

      await db.saveLyricsSourceEntry(entry);

      final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(retrieved, isNotNull);
      expect(retrieved!.state, equals(LyricsSourceState.notFound));
      expect(retrieved.rawLrc, isNull);
      expect(retrieved.isSynced, isFalse);
      expect(retrieved.isNotFound, isTrue);
      expect(retrieved.hasLyrics, isFalse);
    });

    // -------------------------------------------------------------------------
    // Test Spec 4: Edge Case: Empty String raw_lrc vs Null
    // -------------------------------------------------------------------------
    test('4. edge case: empty string raw_lrc is preserved distinct from null', () async {
      const keyHash = 'track_hash_instrumental';
      const entry = LyricsSourceEntry(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        state: LyricsSourceState.found,
        rawLrc: '',
        isSynced: false,
        updatedAt: 1700000000000,
      );

      await db.saveLyricsSourceEntry(entry);

      final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(retrieved, isNotNull);
      expect(retrieved!.rawLrc, isNotNull);
      expect(retrieved.rawLrc, equals(''));
      expect(retrieved.hasLyrics, isFalse);
    });

    // -------------------------------------------------------------------------
    // Test Spec 5: Edge Case: Boolean is_synced stored as 0 or 1 in SQLite
    // -------------------------------------------------------------------------
    test('5. edge case: is_synced stores 0 or 1 in SQLite integer column', () async {
      const syncedEntry = LyricsSourceEntry(
        keyHash: 'hash_synced_flag',
        source: LyricsSource.lrclib,
        state: LyricsSourceState.found,
        rawLrc: '[00:01.00]Synced',
        isSynced: true,
        updatedAt: 100,
      );
      const plainEntry = LyricsSourceEntry(
        keyHash: 'hash_synced_flag',
        source: LyricsSource.lyricsOvh,
        state: LyricsSourceState.found,
        rawLrc: 'Plain text',
        isSynced: false,
        updatedAt: 100,
      );

      await db.saveLyricsSourceEntry(syncedEntry);
      await db.saveLyricsSourceEntry(plainEntry);

      final rawRows = await db.database.rawQuery(
        'SELECT source, is_synced FROM lyrics_source_cache WHERE key_hash = ? ORDER BY source ASC',
        ['hash_synced_flag'],
      );
      expect(rawRows.length, equals(2));
      expect(rawRows[0]['is_synced'], equals(1)); // lrclib
      expect(rawRows[1]['is_synced'], equals(0)); // lyrics_ovh

      // Deserialized entries verify boolean types
      final all = await db.getAllLyricsSourceEntries('hash_synced_flag');
      expect(all[LyricsSource.lrclib]?.isSynced, isTrue);
      expect(all[LyricsSource.lyricsOvh]?.isSynced, isFalse);
    });

    // -------------------------------------------------------------------------
    // Test Spec 6: Edge Case: Multiple sources coexist independently
    // -------------------------------------------------------------------------
    test('6. edge case: multiple sources coexist independently under the same key_hash', () async {
      const keyHash = 'multi_source_hash';

      final entries = [
        const LyricsSourceEntry(
          keyHash: keyHash,
          source: LyricsSource.embedded,
          state: LyricsSourceState.notFound,
          updatedAt: 10,
        ),
        const LyricsSourceEntry(
          keyHash: keyHash,
          source: LyricsSource.file,
          state: LyricsSourceState.notFound,
          updatedAt: 20,
        ),
        const LyricsSourceEntry(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:05.00]Lrclib lyrics',
          isSynced: true,
          updatedAt: 30,
        ),
        const LyricsSourceEntry(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          state: LyricsSourceState.temporaryError,
          updatedAt: 40,
        ),
      ];

      for (final e in entries) {
        await db.saveLyricsSourceEntry(e);
      }

      final all = await db.getAllLyricsSourceEntries(keyHash);
      expect(all.length, equals(4));
      expect(all[LyricsSource.embedded]?.state, equals(LyricsSourceState.notFound));
      expect(all[LyricsSource.file]?.state, equals(LyricsSourceState.notFound));
      expect(all[LyricsSource.lrclib]?.state, equals(LyricsSourceState.found));
      expect(all[LyricsSource.lrclib]?.rawLrc, equals('[00:05.00]Lrclib lyrics'));
      expect(all[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.temporaryError));
    });

    // -------------------------------------------------------------------------
    // Test Spec 7: Edge Case: NOT_FOUND preservation & TEMPORARY_ERROR non-poisoning
    // -------------------------------------------------------------------------
    test('7. NOT_FOUND preservation and TEMPORARY_ERROR retry / upsert', () async {
      const keyHash = 'track_state_transitions';

      // 1. Initial 429 or network drop produces TEMPORARY_ERROR
      final tempErrorEntry = LyricsSourceEntry.temporaryError(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        updatedAt: 1000,
      );
      await db.saveLyricsSourceEntry(tempErrorEntry);

      var entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(entry, isNotNull);
      expect(entry!.state, equals(LyricsSourceState.temporaryError));
      expect(entry.isTemporaryError, isTrue);
      expect(entry.isNotFound, isFalse);

      // Legacy table must NOT contain an entry for temporaryError
      expect(await db.getLyrics(keyHash), isNull);

      // 2. Later, a retry succeeds and replaces the row with FOUND
      const freshLrc = '[01:00.00]Loaded on retry';
      final foundEntry = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        rawLrc: freshLrc,
        isSynced: true,
        updatedAt: 2500,
      );
      await db.saveLyricsSourceEntry(foundEntry);

      entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(entry, isNotNull);
      expect(entry!.state, equals(LyricsSourceState.found));
      expect(entry.rawLrc, equals(freshLrc));
      expect(entry.updatedAt, equals(2500));

      // Row count for (keyHash, lrclib) must remain exactly 1
      final rows = await db.database.query(
        'lyrics_source_cache',
        where: 'key_hash = ? AND source = ?',
        whereArgs: [keyHash, LyricsSource.lrclib.dbValue],
      );
      expect(rows.length, equals(1));
    });

    // -------------------------------------------------------------------------
    // Test Spec 8: Cache purge on re-search (clearLyricsSourceEntries)
    // -------------------------------------------------------------------------
    test('8. edge case: clearLyricsSourceEntries wipes all sources and legacy cache for target key_hash only', () async {
      const h1 = 'track_to_clear';
      const h2 = 'track_to_keep';

      await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
        keyHash: h1,
        source: LyricsSource.embedded,
      ));
      await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
        keyHash: h1,
        source: LyricsSource.lrclib,
        rawLrc: '[00:01.00]Song 1',
      ));
      await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
        keyHash: h2,
        source: LyricsSource.lyricsOvh,
        rawLrc: 'Song 2 lyrics',
      ));

      expect((await db.getAllLyricsSourceEntries(h1)).length, equals(2));
      expect(await db.getLyrics(h1), equals('[00:01.00]Song 1'));

      final deletedCount = await db.clearLyricsSourceEntries(h1);
      expect(deletedCount, equals(2));

      expect(await db.getAllLyricsSourceEntries(h1), isEmpty);
      expect(await db.getLyrics(h1), isNull);

      // Track 2 is completely preserved
      final remainingH2 = await db.getAllLyricsSourceEntries(h2);
      expect(remainingH2.length, equals(1));
      expect(await db.getLyrics(h2), equals('Song 2 lyrics'));
    });

    // -------------------------------------------------------------------------
    // Test Spec 9: Transaction Rollback & Batch Operations
    // -------------------------------------------------------------------------
    test('9. transaction rollback leaves table intact on failure and batch saves succeed', () async {
      const keyHash = 'tx_test_track';
      await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
        keyHash: keyHash,
        source: LyricsSource.embedded,
      ));

      try {
        await db.database.transaction((txn) async {
          await txn.insert('lyrics_source_cache', {
            'key_hash': keyHash,
            'source': LyricsSource.lrclib.dbValue,
            'state': LyricsSourceState.found.dbValue,
            'raw_lrc': 'Aborted lyrics',
            'is_synced': 1,
            'updated_at': 200,
          });
          throw Exception('Simulated transaction failure');
        });
      } catch (_) {
        // Expected exception triggers transaction rollback
      }

      final all = await db.getAllLyricsSourceEntries(keyHash);
      expect(all.length, equals(1));
      expect(all.containsKey(LyricsSource.embedded), isTrue);
      expect(all.containsKey(LyricsSource.lrclib), isFalse);

      // Batch save operation
      final batch = [
        const LyricsSourceEntry(
          keyHash: 'batch_track_1',
          source: LyricsSource.file,
          state: LyricsSourceState.notFound,
          updatedAt: 100,
        ),
        const LyricsSourceEntry(
          keyHash: 'batch_track_2',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:10.00]Batch lyric',
          isSynced: true,
          updatedAt: 200,
        ),
      ];
      await db.saveLyricsSourceEntries(batch);

      expect(await db.getLyricsSourceEntry('batch_track_1', LyricsSource.file), isNotNull);
      expect(await db.getLyricsSourceEntry('batch_track_2', LyricsSource.lrclib), isNotNull);
      expect(await db.getLyrics('batch_track_2'), equals('[00:10.00]Batch lyric'));
    });

    // -------------------------------------------------------------------------
    // Test Spec 10: Backward Compatibility with Legacy saveLyrics & getLyrics
    // -------------------------------------------------------------------------
    test('10. backward compatibility: legacy saveLyrics and getLyrics dual-write and fallback correctly', () async {
      const keyHash = 'legacy_interop_track';
      const rawLrc = '[00:05.00]Legacy synced lyric';

      // 1. Initial query returns null
      expect(await db.getLyrics(keyHash), isNull);

      // 2. Legacy saveLyrics writes to both tables
      await db.saveLyrics(keyHash, rawLrc, 'lrclib');

      // Legacy getLyrics reads from legacy cache
      expect(await db.getLyrics(keyHash), equals(rawLrc));

      // New API reads corresponding LyricsSourceEntry
      final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(entry, isNotNull);
      expect(entry!.state, equals(LyricsSourceState.found));
      expect(entry.rawLrc, equals(rawLrc));
      expect(entry.isSynced, isTrue);

      // 3. Fallback: if legacy table row is deleted, getLyrics falls back to lyrics_source_cache
      await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
      final fallbackResult = await db.getLyrics(keyHash);
      expect(fallbackResult, equals(rawLrc));
    });

    // -------------------------------------------------------------------------
    // Additional Test Spec: Model Auto-detection & Serialization
    // -------------------------------------------------------------------------
    test('11. model auto-detection of isSynced and round-trip serialization fidelity', () {
      final synced = LyricsSourceEntry.found(
        keyHash: 'h_sync',
        source: LyricsSource.lrclib,
        rawLrc: '[02:15.30]Detected synced',
      );
      expect(synced.isSynced, isTrue);

      final unsynced = LyricsSourceEntry.found(
        keyHash: 'h_unsync',
        source: LyricsSource.lyricsOvh,
        rawLrc: 'Plain text without timestamps',
      );
      expect(unsynced.isSynced, isFalse);

      final original = LyricsSourceEntry(
        keyHash: 'h_serial',
        source: LyricsSource.lyricsOvh,
        state: LyricsSourceState.found,
        rawLrc: 'Plain text',
        isSynced: false,
        updatedAt: 123456789,
      );

      // DB map serialization
      final dbMap = original.toDbMap();
      final fromDb = LyricsSourceEntry.fromDbMap(dbMap);
      expect(fromDb, equals(original));

      // JSON serialization
      final json = original.toJson();
      final fromJson = LyricsSourceEntry.fromJson(json);
      expect(fromJson, equals(original));

      // CopyWith
      final copy = original.copyWith(isSynced: true);
      expect(copy.isSynced, isTrue);
      expect(copy.keyHash, equals(original.keyHash));
      expect(copy == original, isFalse);
    });
  });
}
