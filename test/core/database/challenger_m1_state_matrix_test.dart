import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('Challenger M1.2: State Matrix & Persistence Invariants Verification', () {
    // =========================================================================
    // INVARIANT 1: FOUND State Invariant
    // =========================================================================
    group('Invariant 1: FOUND State Storage, Retrieval & Legacy Mirroring', () {
      test('stores and retrieves valid raw_lrc with full content fidelity (synced)', () async {
        const keyHash = 'challenger_track_found_synced';
        const rawLrc = '[00:01.00]Line 1\n[00:04.50]Line 2 with UTF-8: 🎵 こんにちは 🚀\n[00:08.99]Line 3';

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: rawLrc,
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
        expect(retrieved.isFound, isTrue);
        expect(retrieved.isNotFound, isFalse);
        expect(retrieved.isTemporaryError, isFalse);
        expect(retrieved.hasLyrics, isTrue);
        expect(retrieved.updatedAt, equals(1700000000000));

        // Legacy mirroring in lyrics_cache
        final legacyLyrics = await db.getLyrics(keyHash);
        expect(legacyLyrics, equals(rawLrc));

        final legacyRow = await db.database.rawQuery(
          'SELECT key_hash, raw_lrc, source, updated_at FROM lyrics_cache WHERE key_hash = ?',
          [keyHash],
        );
        expect(legacyRow.length, equals(1));
        expect(legacyRow.first['raw_lrc'], equals(rawLrc));
        expect(legacyRow.first['source'], equals('lrclib'));
      });

      test('stores and retrieves unsynced plain text lyrics without timestamp markers', () async {
        const keyHash = 'challenger_track_found_plain';
        const plainLyrics = 'Line one\nLine two without any timestamp tags\nLine three';

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          rawLrc: plainLyrics,
          updatedAt: 1700000001000,
        );

        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(retrieved, isNotNull);
        expect(retrieved!.isSynced, isFalse);
        expect(retrieved.rawLrc, equals(plainLyrics));
        expect(retrieved.hasLyrics, isTrue);
      });

      test('stores extremely large raw_lrc text (100KB) without truncation or corruption', () async {
        const keyHash = 'challenger_track_large_lyrics';
        final largeLrcBuffer = StringBuffer();
        for (int i = 0; i < 2000; i++) {
          largeLrcBuffer.writeln('[$i:00.00] Line number $i of very long lyric text stream');
        }
        final largeLrc = largeLrcBuffer.toString();

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: largeLrc,
          isSynced: true,
        );

        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.rawLrc?.length, equals(largeLrc.length));
        expect(retrieved.rawLrc, equals(largeLrc));
      });
    });

    // =========================================================================
    // INVARIANT 2: NOT_FOUND State & Null raw_lrc Invariant
    // =========================================================================
    group('Invariant 2: NOT_FOUND State, Null raw_lrc & Persistence Across Re-queries', () {
      test('stores notFound entry with raw_lrc == null without violating SQLite constraints', () async {
        const keyHash = 'challenger_track_404';

        final entry = LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          updatedAt: 1700000002000,
        );

        await db.saveLyricsSourceEntry(entry);

        // Verify direct SQLite row column types
        final rawRows = await db.database.rawQuery(
          'SELECT key_hash, source, state, raw_lrc, is_synced, updated_at FROM lyrics_source_cache WHERE key_hash = ?',
          [keyHash],
        );
        expect(rawRows.length, equals(1));
        expect(rawRows.first['key_hash'], equals(keyHash));
        expect(rawRows.first['source'], equals('lrclib'));
        expect(rawRows.first['state'], equals('NOT_FOUND'));
        expect(rawRows.first['raw_lrc'], isNull);
        expect(rawRows.first['is_synced'], equals(0));
        expect(rawRows.first['updated_at'], equals(1700000002000));

        // Domain entry getters
        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.state, equals(LyricsSourceState.notFound));
        expect(retrieved.rawLrc, isNull);
        expect(retrieved.isNotFound, isTrue);
        expect(retrieved.isFound, isFalse);
        expect(retrieved.isTemporaryError, isFalse);
        expect(retrieved.hasLyrics, isFalse);
        expect(retrieved.isSynced, isFalse);

        // Crucial invariant: NOT_FOUND must NEVER pollute legacy lyrics_cache
        final legacyRows = await db.database.rawQuery(
          'SELECT * FROM lyrics_cache WHERE key_hash = ?',
          [keyHash],
        );
        expect(legacyRows, isEmpty);
        expect(await db.getLyrics(keyHash), isNull);
      });

      test('NOT_FOUND entry persists across multiple successive queries and operations', () async {
        const keyHash = 'challenger_track_persistent_404';
        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          updatedAt: 100,
        ));

        // Query 10 times consecutively
        for (int i = 0; i < 10; i++) {
          final res = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
          expect(res, isNotNull);
          expect(res!.state, equals(LyricsSourceState.notFound));
          expect(res.rawLrc, isNull);
        }
      });
    });

    // =========================================================================
    // INVARIANT 3: TEMPORARY_ERROR Retryability & Clean State Transition
    // =========================================================================
    group('Invariant 3: TEMPORARY_ERROR Retryability & State Transition Dynamics', () {
      test('TEMPORARY_ERROR is not marked as notFound and leaves legacy cache null', () async {
        const keyHash = 'challenger_track_429_rate_limit';

        final tempError = LyricsSourceEntry.temporaryError(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          updatedAt: 1000,
        );
        await db.saveLyricsSourceEntry(tempError);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.state, equals(LyricsSourceState.temporaryError));
        expect(retrieved.isTemporaryError, isTrue);
        expect(retrieved.isNotFound, isFalse);
        expect(retrieved.isFound, isFalse);
        expect(retrieved.hasLyrics, isFalse);
        expect(retrieved.rawLrc, isNull);

        // Must not exist in legacy cache
        expect(await db.getLyrics(keyHash), isNull);
        final legacyRows = await db.database.rawQuery(
          'SELECT * FROM lyrics_cache WHERE key_hash = ?',
          [keyHash],
        );
        expect(legacyRows, isEmpty);
      });

      test('Clean transition: TEMPORARY_ERROR -> FOUND on successful retry replaces state and mirrors to legacy cache', () async {
        const keyHash = 'challenger_track_retry_success';

        // 1. Initial 429 rate limit
        await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          updatedAt: 1000,
        ));

        var current = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(current!.state, equals(LyricsSourceState.temporaryError));

        // 2. Retry succeeds after cooldown
        const successLyrics = '[00:05.00]Success on retry after 429';
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: successLyrics,
          isSynced: true,
          updatedAt: 2000,
        ));

        current = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(current, isNotNull);
        expect(current!.state, equals(LyricsSourceState.found));
        expect(current.rawLrc, equals(successLyrics));
        expect(current.updatedAt, equals(2000));
        expect(current.isSynced, isTrue);

        // Row count for (keyHash, lrclib) must remain exactly 1 (no duplicate rows)
        final rawRows = await db.database.rawQuery(
          'SELECT * FROM lyrics_source_cache WHERE key_hash = ? AND source = ?',
          [keyHash, 'lrclib'],
        );
        expect(rawRows.length, equals(1));

        // Now legacy cache MUST have this entry
        expect(await db.getLyrics(keyHash), equals(successLyrics));
      });

      test('Clean transition: TEMPORARY_ERROR -> NOT_FOUND when API returns 404 after network recovery', () async {
        const keyHash = 'challenger_track_retry_404';

        // 1. Transient network drop
        await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          updatedAt: 500,
        ));

        // 2. Retry connects, but song is not in the remote catalog (404)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          updatedAt: 1500,
        ));

        final current = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(current, isNotNull);
        expect(current!.state, equals(LyricsSourceState.notFound));
        expect(current.rawLrc, isNull);
        expect(current.updatedAt, equals(1500));
        expect(current.isNotFound, isTrue);
        expect(current.isTemporaryError, isFalse);

        final rawRows = await db.database.rawQuery(
          'SELECT * FROM lyrics_source_cache WHERE key_hash = ? AND source = ?',
          [keyHash, 'lyrics_ovh'],
        );
        expect(rawRows.length, equals(1));
      });

      test('Multiple consecutive TEMPORARY_ERROR occurrences update timestamp without duplicating rows', () async {
        const keyHash = 'challenger_track_repeated_429';

        for (int t = 100; t <= 500; t += 100) {
          await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
            keyHash: keyHash,
            source: LyricsSource.lrclib,
            updatedAt: t,
          ));
        }

        final countRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt, updated_at FROM lyrics_source_cache WHERE key_hash = ? AND source = ?',
          [keyHash, 'lrclib'],
        );
        expect(countRows.first['cnt'], equals(1));
        expect(countRows.first['updated_at'], equals(500));
      });
    });

    // =========================================================================
    // INVARIANT 4: Multi-Source Coexistence & Mutation Isolation
    // =========================================================================
    group('Invariant 4: Multi-Source Independent Coexistence & Isolation', () {
      test('all 4 sources coexist concurrently under a single key_hash with distinct states', () async {
        const keyHash = 'challenger_track_coexistence_all4';

        final initialEntries = [
          LyricsSourceEntry.notFound(
            keyHash: keyHash,
            source: LyricsSource.embedded,
            updatedAt: 10,
          ),
          LyricsSourceEntry.notFound(
            keyHash: keyHash,
            source: LyricsSource.file,
            updatedAt: 20,
          ),
          LyricsSourceEntry.temporaryError(
            keyHash: keyHash,
            source: LyricsSource.lrclib,
            updatedAt: 30,
          ),
          LyricsSourceEntry.found(
            keyHash: keyHash,
            source: LyricsSource.lyricsOvh,
            rawLrc: 'Plain text lyrics from secondary fallback',
            isSynced: false,
            updatedAt: 40,
          ),
        ];

        for (final entry in initialEntries) {
          await db.saveLyricsSourceEntry(entry);
        }

        final map = await db.getAllLyricsSourceEntries(keyHash);
        expect(map.length, equals(4));

        expect(map[LyricsSource.embedded]?.state, equals(LyricsSourceState.notFound));
        expect(map[LyricsSource.embedded]?.rawLrc, isNull);

        expect(map[LyricsSource.file]?.state, equals(LyricsSourceState.notFound));
        expect(map[LyricsSource.file]?.rawLrc, isNull);

        expect(map[LyricsSource.lrclib]?.state, equals(LyricsSourceState.temporaryError));
        expect(map[LyricsSource.lrclib]?.rawLrc, isNull);

        expect(map[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.found));
        expect(map[LyricsSource.lyricsOvh]?.rawLrc, equals('Plain text lyrics from secondary fallback'));
        expect(map[LyricsSource.lyricsOvh]?.isSynced, isFalse);

        // Fallback getLyrics returns lyricsOvh since it is the only FOUND source
        expect(await db.getLyrics(keyHash), equals('Plain text lyrics from secondary fallback'));
      });

      test('mutating one source never modifies or corrupts any sibling sources', () async {
        const keyHash = 'challenger_track_mutation_isolation';

        // Set up 4 sources
        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.embedded,
          updatedAt: 100,
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.file,
          updatedAt: 200,
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          updatedAt: 300,
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          rawLrc: 'Plain text',
          isSynced: false,
          updatedAt: 400,
        ));

        // Now mutate ONLY lrclib from temporaryError to found
        const freshLrclib = '[00:10.00]Fresh lrclib synced lyric';
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: freshLrclib,
          isSynced: true,
          updatedAt: 500,
        ));

        // Verify lrclib is updated
        final lrclib = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(lrclib?.state, equals(LyricsSourceState.found));
        expect(lrclib?.rawLrc, equals(freshLrclib));
        expect(lrclib?.updatedAt, equals(500));

        // Verify siblings remained 100% UNCHANGED
        final embedded = await db.getLyricsSourceEntry(keyHash, LyricsSource.embedded);
        expect(embedded?.state, equals(LyricsSourceState.notFound));
        expect(embedded?.updatedAt, equals(100));

        final file = await db.getLyricsSourceEntry(keyHash, LyricsSource.file);
        expect(file?.state, equals(LyricsSourceState.notFound));
        expect(file?.updatedAt, equals(200));

        final lyricsOvh = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(lyricsOvh?.state, equals(LyricsSourceState.found));
        expect(lyricsOvh?.rawLrc, equals('Plain text'));
        expect(lyricsOvh?.updatedAt, equals(400));

        // Deleting lyricsOvh deletes ONLY lyricsOvh
        await db.deleteLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh), isNull);
        expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib), isNotNull);
        expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.embedded), isNotNull);
        expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.file), isNotNull);
      });

      test('Priority resolution in getLyrics selects highest-priority FOUND source', () async {
        const keyHash = 'challenger_track_priority_resolution';

        // 1. Only lyricsOvh (priority 4) is found
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          rawLrc: 'lyricsOvh text (priority 4)',
        ));
        expect(await db.getLyrics(keyHash), equals('lyricsOvh text (priority 4)'));

        // Clear legacy cache to test fallback resolution logic in getLyrics
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('lyricsOvh text (priority 4)'));

        // 2. Add lrclib (priority 3)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: '[00:01.00]lrclib text (priority 3)',
        ));
        // Clear legacy cache to trigger priority evaluation in lyrics_source_cache
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('[00:01.00]lrclib text (priority 3)'));

        // 3. Add file (priority 2)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.file,
          rawLrc: '[00:01.00]file text (priority 2)',
        ));
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('[00:01.00]file text (priority 2)'));

        // 4. Add embedded (priority 1)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.embedded,
          rawLrc: '[00:01.00]embedded text (priority 1)',
        ));
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('[00:01.00]embedded text (priority 1)'));
      });
    });

    // =========================================================================
    // INVARIANT 5: Single-Song Clear Isolation Invariant
    // =========================================================================
    group('Invariant 5: Single-Song Clear Isolation & Target Scoping', () {
      test('clearLyricsSourceEntries purges all sources and legacy cache for target song without touching adjacent songs', () async {
        const targetSong = 'track_target_clear';
        const adjacentSong1 = 'track_target_clear_suffix'; // prefix collision edge case
        const adjacentSong2 = 'track_completely_different';

        // Target song with 3 sources + legacy
        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: targetSong,
          source: LyricsSource.embedded,
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: targetSong,
          source: LyricsSource.lrclib,
          rawLrc: 'Target song lrclib',
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
          keyHash: targetSong,
          source: LyricsSource.lyricsOvh,
        ));

        // Adjacent song 1 (has targetSong as prefix)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: adjacentSong1,
          source: LyricsSource.file,
          rawLrc: 'Adjacent song 1 lyrics',
        ));

        // Adjacent song 2
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: adjacentSong2,
          source: LyricsSource.lyricsOvh,
          rawLrc: 'Adjacent song 2 lyrics',
        ));

        // Verify setup
        expect((await db.getAllLyricsSourceEntries(targetSong)).length, equals(3));
        expect((await db.getAllLyricsSourceEntries(adjacentSong1)).length, equals(1));
        expect((await db.getAllLyricsSourceEntries(adjacentSong2)).length, equals(1));
        expect(await db.getLyrics(targetSong), equals('Target song lrclib'));
        expect(await db.getLyrics(adjacentSong1), equals('Adjacent song 1 lyrics'));
        expect(await db.getLyrics(adjacentSong2), equals('Adjacent song 2 lyrics'));

        // Execute clear on targetSong ONLY
        final deletedCount = await db.clearLyricsSourceEntries(targetSong);
        expect(deletedCount, equals(3));

        // Target song must be completely purged from BOTH tables
        expect(await db.getAllLyricsSourceEntries(targetSong), isEmpty);
        expect(await db.getLyrics(targetSong), isNull);

        final targetLegacy = await db.database.rawQuery(
          'SELECT * FROM lyrics_cache WHERE key_hash = ?',
          [targetSong],
        );
        expect(targetLegacy, isEmpty);

        // Adjacent songs MUST BE 100% UNTOUCHED
        final adj1Entries = await db.getAllLyricsSourceEntries(adjacentSong1);
        expect(adj1Entries.length, equals(1));
        expect(await db.getLyrics(adjacentSong1), equals('Adjacent song 1 lyrics'));

        final adj2Entries = await db.getAllLyricsSourceEntries(adjacentSong2);
        expect(adj2Entries.length, equals(1));
        expect(await db.getLyrics(adjacentSong2), equals('Adjacent song 2 lyrics'));
      });

      test('clearLyricsSourceEntries on non-existent track returns 0 without side effects', () async {
        const dummyKey = 'non_existent_key_999';
        final count = await db.clearLyricsSourceEntries(dummyKey);
        expect(count, equals(0));
      });

      test('clearLyricsSourceEntries handles SQL wildcard characters in key_hash safely', () async {
        const wildcardKey = 'track%test_with_underscore_and_percent';
        const otherKey = 'trackXtest_with_underscore_and_percent';

        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: wildcardKey,
          source: LyricsSource.lrclib,
          rawLrc: 'Wildcard track lyrics',
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: otherKey,
          source: LyricsSource.lrclib,
          rawLrc: 'Other track lyrics',
        ));

        // Clearing wildcardKey should not match otherKey via SQL LIKE injection
        await db.clearLyricsSourceEntries(wildcardKey);

        expect(await db.getAllLyricsSourceEntries(wildcardKey), isEmpty);
        expect(await db.getLyricsSourceEntry(otherKey, LyricsSource.lrclib), isNotNull);
      });
    });

    // =========================================================================
    // INVARIANT 6: Concurrency, Batch Transactions & SQL Injection Resilience
    // =========================================================================
    group('Invariant 6: Concurrency, Batch Operations & Security Resilience', () {
      test('high-volume concurrent async writes maintain consistency and zero deadlocks', () async {
        const numTracks = 25;
        final futures = <Future<void>>[];

        for (int i = 0; i < numTracks; i++) {
          final key = 'concurrent_track_$i';
          futures.add(db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
            keyHash: key,
            source: LyricsSource.embedded,
          )));
          futures.add(db.saveLyricsSourceEntry(LyricsSourceEntry.found(
            keyHash: key,
            source: LyricsSource.lrclib,
            rawLrc: '[$i:00.00]Concurrent lyric $i',
          )));
        }

        await Future.wait(futures);

        // Verify all 25 tracks have both records (50 total rows)
        final totalRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt FROM lyrics_source_cache',
        );
        expect(totalRows.first['cnt'], equals(numTracks * 2));

        for (int i = 0; i < numTracks; i++) {
          final key = 'concurrent_track_$i';
          final all = await db.getAllLyricsSourceEntries(key);
          expect(all.length, equals(2));
          expect(all[LyricsSource.embedded]?.state, equals(LyricsSourceState.notFound));
          expect(all[LyricsSource.lrclib]?.state, equals(LyricsSourceState.found));
        }
      });

      test('saveLyricsSourceEntries batch saves heterogeneous entries atomically and mirrors found entries', () async {
        final batch = <LyricsSourceEntry>[
          for (int i = 0; i < 20; i++)
            i.isEven
                ? LyricsSourceEntry.found(
                    keyHash: 'batch_item_$i',
                    source: LyricsSource.lrclib,
                    rawLrc: '[$i:00.00]Batch lyric $i',
                    isSynced: true,
                    updatedAt: 1000 + i,
                  )
                : LyricsSourceEntry.notFound(
                    keyHash: 'batch_item_$i',
                    source: LyricsSource.file,
                    updatedAt: 2000 + i,
                  ),
        ];

        await db.saveLyricsSourceEntries(batch);

        final totalRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt FROM lyrics_source_cache',
        );
        expect(totalRows.first['cnt'], equals(20));

        // 10 even tracks should be in legacy lyrics_cache
        final legacyRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt FROM lyrics_cache',
        );
        expect(legacyRows.first['cnt'], equals(10));
      });

      test('SQL injection attempts in key_hash and raw_lrc are safely parameterized', () async {
        const sqlInjectionKey = "h'; DROP TABLE lyrics_source_cache; --";
        const sqlInjectionLrc = "Robert'); DROP TABLE lyrics_cache; SELECT * FROM '";

        final entry = LyricsSourceEntry.found(
          keyHash: sqlInjectionKey,
          source: LyricsSource.lrclib,
          rawLrc: sqlInjectionLrc,
          isSynced: false,
        );

        // Should not drop tables or crash
        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(sqlInjectionKey, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.keyHash, equals(sqlInjectionKey));
        expect(retrieved.rawLrc, equals(sqlInjectionLrc));

        // Verify table still exists and is healthy
        final tables = await db.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='lyrics_source_cache'",
        );
        expect(tables.length, equals(1));

        // Clear works safely with injection key
        final deleted = await db.clearLyricsSourceEntries(sqlInjectionKey);
        expect(deleted, equals(1));
        expect(await db.getLyricsSourceEntry(sqlInjectionKey, LyricsSource.lrclib), isNull);
      });
    });

    // =========================================================================
    // INVARIANT 7: Domain Models Serialization, Types & Contract Robustness
    // =========================================================================
    group('Invariant 7: Domain Models & Parser Robustness', () {
      test('LyricsSource enum priority, dbValue and case-insensitive string parsing', () {
        expect(LyricsSource.embedded.priority, equals(1));
        expect(LyricsSource.file.priority, equals(2));
        expect(LyricsSource.lrclib.priority, equals(3));
        expect(LyricsSource.lyricsOvh.priority, equals(4));

        expect(LyricsSource.embedded.isLocal, isTrue);
        expect(LyricsSource.file.isLocal, isTrue);
        expect(LyricsSource.lrclib.isRemote, isTrue);
        expect(LyricsSource.lyricsOvh.isRemote, isTrue);

        // Parsing with aliases
        expect(LyricsSource.fromString('embedded'), equals(LyricsSource.embedded));
        expect(LyricsSource.fromString('EMBEDDED'), equals(LyricsSource.embedded));
        expect(LyricsSource.fromString('file'), equals(LyricsSource.file));
        expect(LyricsSource.fromString('lrc_file'), equals(LyricsSource.file));
        expect(LyricsSource.fromString('LRC'), equals(LyricsSource.file));
        expect(LyricsSource.fromString('lrclib'), equals(LyricsSource.lrclib));
        expect(LyricsSource.fromString('lrclib.net'), equals(LyricsSource.lrclib));
        expect(LyricsSource.fromString('lyrics_ovh'), equals(LyricsSource.lyricsOvh));
        expect(LyricsSource.fromString('LYRICSOVH'), equals(LyricsSource.lyricsOvh));
        expect(LyricsSource.fromString('ovh'), equals(LyricsSource.lyricsOvh));

        // Unknown throws ArgumentError on fromString, returns defaultValue on tryParse
        expect(() => LyricsSource.fromString('unknown_provider'), throwsArgumentError);
        expect(LyricsSource.tryParse('unknown_provider'), isNull);
        expect(LyricsSource.tryParse(null, defaultValue: LyricsSource.file), equals(LyricsSource.file));
      });

      test('LyricsSourceState enum dbValue and case-insensitive string parsing', () {
        expect(LyricsSourceState.found.dbValue, equals('FOUND'));
        expect(LyricsSourceState.notFound.dbValue, equals('NOT_FOUND'));
        expect(LyricsSourceState.temporaryError.dbValue, equals('TEMPORARY_ERROR'));

        expect(LyricsSourceState.fromString('FOUND'), equals(LyricsSourceState.found));
        expect(LyricsSourceState.fromString('found'), equals(LyricsSourceState.found));
        expect(LyricsSourceState.fromString('NOT_FOUND'), equals(LyricsSourceState.notFound));
        expect(LyricsSourceState.fromString('notfound'), equals(LyricsSourceState.notFound));
        expect(LyricsSourceState.fromString('TEMPORARY_ERROR'), equals(LyricsSourceState.temporaryError));
        expect(LyricsSourceState.fromString('temporaryerror'), equals(LyricsSourceState.temporaryError));

        expect(() => LyricsSourceState.fromString('INVALID'), throwsArgumentError);
        expect(LyricsSourceState.tryParse('INVALID'), isNull);
        expect(LyricsSourceState.tryParse(null, defaultValue: LyricsSourceState.temporaryError),
            equals(LyricsSourceState.temporaryError));
      });

      test('LyricsSourceEntry isSynced auto-detection matches standard timestamp formats', () {
        // [mm:ss.xx]
        final e1 = LyricsSourceEntry.found(
          keyHash: 'k1',
          source: LyricsSource.lrclib,
          rawLrc: '[01:23.45]Hello',
        );
        expect(e1.isSynced, isTrue);

        // [mm:ss.xxx]
        final e2 = LyricsSourceEntry.found(
          keyHash: 'k2',
          source: LyricsSource.lrclib,
          rawLrc: '[00:05.123]Hello 3 digits',
        );
        expect(e2.isSynced, isTrue);

        // [m:ss.xx]
        final e3 = LyricsSourceEntry.found(
          keyHash: 'k3',
          source: LyricsSource.lrclib,
          rawLrc: '[5:30.50]Single digit minute',
        );
        expect(e3.isSynced, isTrue);

        // Plain text (no timestamps)
        final e4 = LyricsSourceEntry.found(
          keyHash: 'k4',
          source: LyricsSource.lyricsOvh,
          rawLrc: 'Just normal words and lines without any bracketed timestamp',
        );
        expect(e4.isSynced, isFalse);

        // Explicit isSynced override takes precedence
        final e5 = LyricsSourceEntry.found(
          keyHash: 'k5',
          source: LyricsSource.lyricsOvh,
          rawLrc: '[01:23.45]Has timestamps but forced unsynced',
          isSynced: false,
        );
        expect(e5.isSynced, isFalse);
      });

      test('fromDbMap resilient to integer and boolean is_synced values', () {
        final mapWithInt = {
          'key_hash': 'k_int',
          'source': 'lrclib',
          'state': 'FOUND',
          'raw_lrc': 'test',
          'is_synced': 1,
          'updated_at': 100,
        };
        expect(LyricsSourceEntry.fromDbMap(mapWithInt).isSynced, isTrue);

        final mapWithZero = {
          'key_hash': 'k_zero',
          'source': 'lrclib',
          'state': 'FOUND',
          'raw_lrc': 'test',
          'is_synced': 0,
          'updated_at': 100,
        };
        expect(LyricsSourceEntry.fromDbMap(mapWithZero).isSynced, isFalse);

        final mapWithBool = {
          'key_hash': 'k_bool',
          'source': 'lrclib',
          'state': 'FOUND',
          'raw_lrc': 'test',
          'is_synced': true,
          'updated_at': 100,
        };
        expect(LyricsSourceEntry.fromDbMap(mapWithBool).isSynced, isTrue);
      });
    });
  });
}
