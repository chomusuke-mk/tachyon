import 'dart:math';
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

  group('Challenger M1.1: Empirical Stress, Concurrency, Payloads & Invariants', () {
    // =========================================================================
    // GROUP 1: Extreme High Concurrency & Parallel Contention Stress Tests
    // =========================================================================
    group('1. High Concurrency & Parallel Contention', () {
      test('1.1: 50 concurrent tracks x 4 sources (200 simultaneous writes) + concurrent reads', () async {
        const trackCount = 50;
        final sources = [
          LyricsSource.embedded,
          LyricsSource.file,
          LyricsSource.lrclib,
          LyricsSource.lyricsOvh,
        ];

        final writeFutures = <Future<void>>[];
        final readResults = <Future<Map<LyricsSource, LyricsSourceEntry>>>[];

        // Launch 200 concurrent write operations
        for (int i = 0; i < trackCount; i++) {
          final key = 'concurrent_track_key_$i';
          for (final source in sources) {
            final entry = switch (source) {
              LyricsSource.embedded => LyricsSourceEntry.notFound(
                  keyHash: key,
                  source: source,
                  updatedAt: 1000 + i,
                ),
              LyricsSource.file => LyricsSourceEntry.notFound(
                  keyHash: key,
                  source: source,
                  updatedAt: 1000 + i,
                ),
              LyricsSource.lrclib => LyricsSourceEntry.found(
                  keyHash: key,
                  source: source,
                  rawLrc: '[$i:00.00] Synced lyric for track $i from lrclib',
                  isSynced: true,
                  updatedAt: 2000 + i,
                ),
              LyricsSource.lyricsOvh => LyricsSourceEntry.temporaryError(
                  keyHash: key,
                  source: source,
                  updatedAt: 3000 + i,
                ),
            };
            writeFutures.add(db.saveLyricsSourceEntry(entry));
          }
          // Interleave concurrent reads
          if (i % 5 == 0) {
            readResults.add(db.getAllLyricsSourceEntries(key));
          }
        }

        // Wait for all writes and reads to complete without deadlock
        await Future.wait(writeFutures);
        await Future.wait(readResults);

        // Verify database state: exactly 200 rows in lyrics_source_cache
        final totalSourceRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt FROM lyrics_source_cache',
        );
        expect(totalSourceRows.first['cnt'], equals(trackCount * 4));

        // Verify exactly 50 rows in legacy lyrics_cache (from lrclib found entries)
        final totalLegacyRows = await db.database.rawQuery(
          'SELECT COUNT(*) as cnt FROM lyrics_cache',
        );
        expect(totalLegacyRows.first['cnt'], equals(trackCount));

        // Spot check 10 random tracks
        final rng = Random(42);
        for (int k = 0; k < 10; k++) {
          final idx = rng.nextInt(trackCount);
          final key = 'concurrent_track_key_$idx';
          final entries = await db.getAllLyricsSourceEntries(key);
          expect(entries.length, equals(4));
          expect(entries[LyricsSource.embedded]?.state, equals(LyricsSourceState.notFound));
          expect(entries[LyricsSource.file]?.state, equals(LyricsSourceState.notFound));
          expect(entries[LyricsSource.lrclib]?.state, equals(LyricsSourceState.found));
          expect(entries[LyricsSource.lrclib]?.rawLrc, contains('from lrclib'));
          expect(entries[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.temporaryError));
          expect(await db.getLyrics(key), contains('from lrclib'));
        }
      });

      test('1.2: Extreme single-track contention: 100 simultaneous concurrent writes to same key', () async {
        const targetKey = 'hotspot_contention_track';
        final writeFutures = <Future<void>>[];

        // 100 concurrent writes mutating across the 4 sources
        for (int i = 0; i < 100; i++) {
          final source = LyricsSource.values[i % LyricsSource.values.length];
          final state = LyricsSourceState.values[i % LyricsSourceState.values.length];
          final entry = LyricsSourceEntry(
            keyHash: targetKey,
            source: source,
            state: state,
            rawLrc: state == LyricsSourceState.found ? '[$i:00.00] Contention text $i' : null,
            isSynced: state == LyricsSourceState.found,
            updatedAt: 10000 + i,
          );
          writeFutures.add(db.saveLyricsSourceEntry(entry));
        }

        await Future.wait(writeFutures);

        // Even with 100 concurrent upserts to the same key, there must be at most 4 rows
        // (1 per distinct source) due to PRIMARY KEY (key_hash, source)
        final rows = await db.database.rawQuery(
          'SELECT * FROM lyrics_source_cache WHERE key_hash = ?',
          [targetKey],
        );
        expect(rows.length, lessThanOrEqualTo(4));
        expect(rows.length, greaterThan(0));

        final all = await db.getAllLyricsSourceEntries(targetKey);
        expect(all.length, equals(rows.length));
        for (final entry in all.values) {
          expect(entry.keyHash, equals(targetKey));
          expect(entry.updatedAt, greaterThanOrEqualTo(10000));
        }
      });

      test('1.3: Concurrent write vs clear race: simultaneous saves and clears', () async {
        const targetKey = 'race_clear_track';
        final ops = <Future<void>>[];

        for (int i = 0; i < 30; i++) {
          ops.add(db.saveLyricsSourceEntry(LyricsSourceEntry.found(
            keyHash: targetKey,
            source: LyricsSource.lrclib,
            rawLrc: 'Lyric version $i',
            updatedAt: i,
          )));

          if (i % 6 == 0) {
            ops.add(db.clearLyricsSourceEntries(targetKey));
          }
        }

        // All ops finish cleanly without throwing SQLite locked / syntax errors
        await Future.wait(ops);

        // Database remains in a consistent state
        final result = await db.getAllLyricsSourceEntries(targetKey);
        expect(result.length, anyOf(equals(0), equals(1)));
      });
    });

    // =========================================================================
    // GROUP 2: Massive Payloads, UTF-8 & Pathological LRC Stress Tests
    // =========================================================================
    group('2. Massive Payloads, UTF-8 & Pathological LRC', () {
      test('2.1: 500KB massive LRC (>10,000 lines) writes and reads back with zero data loss', () async {
        const keyHash = 'massive_500kb_lyrics_track';
        final buffer = StringBuffer();
        buffer.writeln('[ti:Massive Stress Symphony]');
        buffer.writeln('[ar:Stress Tester]');
        buffer.writeln('[al:Empirical Verification]');

        for (int i = 0; i < 10000; i++) {
          final mm = (i ~/ 60).toString().padLeft(2, '0');
          final ss = (i % 60).toString().padLeft(2, '0');
          buffer.writeln('[$mm:$ss.50] Lyric line $i with repeated stress payload padding text content ABCDEFGHIJKLMNOPQRSTUVWXYZ');
        }

        final hugeLrc = buffer.toString();
        expect(hugeLrc.length, greaterThan(500 * 1024)); // > 500KB

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: hugeLrc,
          isSynced: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.rawLrc?.length, equals(hugeLrc.length));
        expect(retrieved.rawLrc, equals(hugeLrc));
        expect(retrieved.isSynced, isTrue);

        // Also check legacy getLyrics
        final legacyRetrieved = await db.getLyrics(keyHash);
        expect(legacyRetrieved, equals(hugeLrc));
      });

      test('2.2: Extreme Unicode, multi-script, CJK, Arabic RTL and complex emoji sequences', () async {
        const keyHash = 'unicode_stress_🎧_مرحبا_你好_🚀';
        const complexUnicodeLrc = '''
[00:01.00] 🎵 English & Latin-1: Café, résumé, naïve, señor, façade
[00:05.50] 🇯🇵 Japanese Kanji & Hiragana: こんにちは世界！君の名は。夢のしずく
[00:10.00] 🇰🇷 Korean Hangul: 안녕하세요! 음악이 흐르는 밤
[00:15.00] 🇸🇦 Arabic (RTL): مرحبا بالعالم! كيف حالك؟ الموسيقى حياة
[00:20.00] 🇷🇺 Cyrillic: Привет мир! Прекрасная песня играет
[00:25.00] 🇮🇳 Devanagari: नमस्ते दुनिया! संगीत ही जीवन है
[00:30.00] 🇹🇭 Thai: สวัสดีชาวโลก เพลงเพราะมาก
[00:35.00] 👨‍👩‍👧‍👦 Complex Emojis: 👨‍👩‍👧‍👦 🏳️‍🌈 🏴‍☠️ 🧑🏽‍💻 🧙‍♂️ 🧟‍♀️ 🧚‍♂️
[00:40.00] Symbols: ∀x ∈ ℝ, ∃y: y > x ∧ ∑(1/n²) = π²/6
''';

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: complexUnicodeLrc,
          isSynced: true,
        );

        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.keyHash, equals(keyHash));
        expect(retrieved.rawLrc, equals(complexUnicodeLrc));

        // Test clear on unicode keyHash
        final deleted = await db.clearLyricsSourceEntries(keyHash);
        expect(deleted, equals(1));
        expect(await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib), isNull);
      });

      test('2.3: Pathological string characters: embedded null bytes, CRLF, solo CR, ZWNJ, BOM', () async {
        const keyHash = 'pathological_chars_track';
        // Strings containing \r\n, \r, tabs, zero-width non-joiner \u200C, null byte \x00, and mid-string BOM
        const pathologicalLrc = "[00:01.00]Line with mid-BOM: \uFEFFcontent\r\n"
            "[00:02.00]Line with CRLF\r"
            "[00:03.00]Line with solo CR\twith tab\n"
            "[00:04.00]Line with ZWNJ: Persian می\u200Cخواهم\n"
            "[00:05.00]Line with Null Byte: before\x00after";

        final entry = LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.file,
          rawLrc: pathologicalLrc,
          isSynced: true,
        );

        await db.saveLyricsSourceEntry(entry);

        final retrieved = await db.getLyricsSourceEntry(keyHash, LyricsSource.file);
        expect(retrieved, isNotNull);
        expect(retrieved!.rawLrc, equals(pathologicalLrc));

        // Empirical check on leading BOM (0xFEFF):
        // Unicode UTF-8 decoders strip leading 0xFEFF stream signature at offset 0
        const leadingBomLrc = "\uFEFF[00:01.00]Leading BOM";
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: 'leading_bom_track',
          source: LyricsSource.file,
          rawLrc: leadingBomLrc,
        ));
        final retrievedBom = await db.getLyricsSourceEntry('leading_bom_track', LyricsSource.file);
        // Direct empirical observation: SQLite/UTF-8 strips the leading BOM marker
        expect(retrievedBom!.rawLrc, equals('[00:01.00]Leading BOM'));
      });

      test('2.4: Malformed timestamps & Regex ReDoS resilience in _detectIsSynced', () {
        // ReDoS stress test: 20,000 opening brackets followed by a valid timestamp
        final redosInput = '${'[' * 20000}[00:00.00]';
        final stopwatch = Stopwatch()..start();
        final entryRedos = LyricsSourceEntry.found(
          keyHash: 'redos_check',
          source: LyricsSource.lrclib,
          rawLrc: redosInput,
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Must evaluate in <1s
        expect(entryRedos.isSynced, isTrue); // Ends in valid timestamp

        // Unsynced ReDoS stress test: 20,000 brackets without valid timestamp
        final redosUnsynced = '${'[' * 20000}no_valid_timestamp';
        final entryUnsynced = LyricsSourceEntry.found(
          keyHash: 'redos_unsynced',
          source: LyricsSource.lrclib,
          rawLrc: redosUnsynced,
        );
        expect(entryUnsynced.isSynced, isFalse);

        // Various timestamp variations
        expect(LyricsSourceEntry.found(
          keyHash: 't1',
          source: LyricsSource.lrclib,
          rawLrc: '[00:00.00]Standard',
        ).isSynced, isTrue);

        expect(LyricsSourceEntry.found(
          keyHash: 't2',
          source: LyricsSource.lrclib,
          rawLrc: '[00:00.000]3-digit millis',
        ).isSynced, isTrue);

        expect(LyricsSourceEntry.found(
          keyHash: 't3',
          source: LyricsSource.lrclib,
          rawLrc: '[123:45.67]Triple digit minute',
        ).isSynced, isTrue);

        expect(LyricsSourceEntry.found(
          keyHash: 't4',
          source: LyricsSource.lrclib,
          rawLrc: '[1:23.45]Single digit minute',
        ).isSynced, isTrue);

        expect(LyricsSourceEntry.found(
          keyHash: 't5',
          source: LyricsSource.lrclib,
          rawLrc: '[invalid:timestamp.tag]Text',
        ).isSynced, isFalse);

        expect(LyricsSourceEntry.found(
          keyHash: 't6',
          source: LyricsSource.lrclib,
          rawLrc: '[-01:00.00]Negative minute',
        ).isSynced, isFalse);
      });
    });

    // =========================================================================
    // GROUP 3: SQL Injection, Hostile Key Hashes & Malicious Inputs
    // =========================================================================
    group('3. SQL Injection & Hostile Key Hashes', () {
      final hostileKeys = [
        "' OR '1'='1",
        "'; DROP TABLE lyrics_source_cache; --",
        "'; DROP TABLE lyrics_cache; --",
        "' UNION SELECT * FROM sqlite_master; --",
        "admin'--",
        "\" OR \"1\"=\"1",
        "`key_hash`",
        "'; DELETE FROM tracks; --",
        "'; VACUUM; --",
        "Robert'); DROP TABLE Students;--",
        "'/*comment*/--",
        "1; ATTACH DATABASE '/tmp/pwned' AS pwn; --",
      ];

      for (int i = 0; i < hostileKeys.length; i++) {
        final hostileKey = hostileKeys[i];
        test('3.1.$i: injection key "$hostileKey" is fully parameterized without execution', () async {
          const maliciousLrc = "'; DROP TABLE lyrics_source_cache; --\n[00:01.00] Injection payload";

          final entry = LyricsSourceEntry.found(
            keyHash: hostileKey,
            source: LyricsSource.lrclib,
            rawLrc: maliciousLrc,
            isSynced: true,
          );

          // 1. Save entry
          await db.saveLyricsSourceEntry(entry);

          // 2. Query single entry
          final retrieved = await db.getLyricsSourceEntry(hostileKey, LyricsSource.lrclib);
          expect(retrieved, isNotNull);
          expect(retrieved!.keyHash, equals(hostileKey));
          expect(retrieved.rawLrc, equals(maliciousLrc));

          // 3. Query all entries
          final all = await db.getAllLyricsSourceEntries(hostileKey);
          expect(all.length, equals(1));
          expect(all[LyricsSource.lrclib]?.rawLrc, equals(maliciousLrc));

          // 4. Verify tables were not dropped or damaged
          final tables = await db.database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('lyrics_source_cache', 'lyrics_cache');",
          );
          expect(tables.length, equals(2));

          // 5. Clear entries using hostile key
          final deleted = await db.clearLyricsSourceEntries(hostileKey);
          expect(deleted, equals(1));
          expect(await db.getLyricsSourceEntry(hostileKey, LyricsSource.lrclib), isNull);
        });
      }

      test('3.2: SQL LIKE wildcards in keyHash (% and _) do not bleed or cross-match', () async {
        const prefix = 'song_pattern';
        const keyWildcard1 = '$prefix%';
        const keyWildcard2 = '${prefix}_';
        const keyLiteral = '${prefix}A';

        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyWildcard1,
          source: LyricsSource.lrclib,
          rawLrc: 'Wildcard Percent',
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyWildcard2,
          source: LyricsSource.lrclib,
          rawLrc: 'Wildcard Underscore',
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyLiteral,
          source: LyricsSource.lrclib,
          rawLrc: 'Literal Match',
        ));

        // Delete only the percent key
        await db.clearLyricsSourceEntries(keyWildcard1);

        expect(await db.getLyricsSourceEntry(keyWildcard1, LyricsSource.lrclib), isNull);
        expect(await db.getLyricsSourceEntry(keyWildcard2, LyricsSource.lrclib), isNotNull);
        expect(await db.getLyricsSourceEntry(keyLiteral, LyricsSource.lrclib), isNotNull);
      });

      test('3.3: Hostile/unrecognized source strings in legacy saveLyrics handle gracefully', () async {
        const keyHash = 'hostile_source_track';
        const maliciousSource = "lrclib'; DROP TABLE dummy; --";

        // Should fall back to LyricsSource.embedded without throwing or crashing
        await db.saveLyrics(keyHash, '[00:01.00]Test', maliciousSource);

        final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.embedded);
        expect(entry, isNotNull);
        expect(entry!.source, equals(LyricsSource.embedded));
      });
    });

    // =========================================================================
    // GROUP 4: Transaction Rollbacks, Atomicity & Recovery Stress Tests
    // =========================================================================
    group('4. Transaction Rollbacks, Atomicity & Recovery', () {
      test('4.1: Atomic rollback of saveLyricsSourceEntries leaves 0 entries if any item causes failure', () async {
        final validEntries = [
          LyricsSourceEntry.found(
            keyHash: 'batch_tx_track_1',
            source: LyricsSource.lrclib,
            rawLrc: 'Valid 1',
          ),
          LyricsSourceEntry.found(
            keyHash: 'batch_tx_track_2',
            source: LyricsSource.lyricsOvh,
            rawLrc: 'Valid 2',
          ),
        ];

        // Ensure initially clean
        expect(await db.getLyricsSourceEntry('batch_tx_track_1', LyricsSource.lrclib), isNull);
        expect(await db.getLyricsSourceEntry('batch_tx_track_2', LyricsSource.lyricsOvh), isNull);

        // Attempt a transaction where an error occurs midway
        bool didThrow = false;
        try {
          await db.database.transaction((txn) async {
            for (final entry in validEntries) {
              await txn.insert('lyrics_source_cache', entry.toDbMap());
            }
            // Trigger failure midway
            throw StateError('Simulated unexpected power outage or unhandled exception');
          });
        } on StateError catch (e) {
          didThrow = true;
          expect(e.message, contains('Simulated unexpected power outage'));
        }
        expect(didThrow, isTrue);

        // Verify transaction was rolled back: neither item exists in the database
        expect(await db.getLyricsSourceEntry('batch_tx_track_1', LyricsSource.lrclib), isNull);
        expect(await db.getLyricsSourceEntry('batch_tx_track_2', LyricsSource.lyricsOvh), isNull);

        final count = await db.database.rawQuery(
          "SELECT COUNT(*) as cnt FROM lyrics_source_cache WHERE key_hash IN ('batch_tx_track_1', 'batch_tx_track_2')",
        );
        expect(count.first['cnt'], equals(0));
      });

      test('4.2: Database connection remains healthy and operational after rolled-back transaction', () async {
        // Step 1: Cause a rollback
        try {
          await db.database.transaction((txn) async {
            await txn.insert('lyrics_source_cache', {
              'key_hash': 'doomed_track',
              'source': 'lrclib',
              'state': 'FOUND',
              'raw_lrc': 'Doomed text',
              'is_synced': 1,
              'updated_at': 100,
            });
            throw Exception('Abort transaction');
          });
        } catch (_) {}

        // Step 2: Immediately execute a normal write
        const healthyKey = 'healthy_track_after_rollback';
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: healthyKey,
          source: LyricsSource.file,
          rawLrc: 'Healthy text',
        ));

        // Step 3: Verify the write succeeded and doomed item is absent
        final doomed = await db.getLyricsSourceEntry('doomed_track', LyricsSource.lrclib);
        expect(doomed, isNull);

        final healthy = await db.getLyricsSourceEntry(healthyKey, LyricsSource.file);
        expect(healthy, isNotNull);
        expect(healthy!.rawLrc, equals('Healthy text'));
      });

      test('4.3: 50 rapid sequential transactions commit without leakage or corruption', () async {
        for (int i = 0; i < 50; i++) {
          await db.database.transaction((txn) async {
            await txn.insert('lyrics_source_cache', {
              'key_hash': 'rapid_tx_$i',
              'source': 'lrclib',
              'state': 'FOUND',
              'raw_lrc': 'Lyric $i',
              'is_synced': 0,
              'updated_at': 1000 + i,
            });
          });
        }

        final total = await db.database.rawQuery(
          "SELECT COUNT(*) as cnt FROM lyrics_source_cache WHERE key_hash LIKE 'rapid_tx_%'",
        );
        expect(total.first['cnt'], equals(50));
      });
    });

    // =========================================================================
    // GROUP 5: Legacy Dual-Write & Fallback Priority Invariants
    // =========================================================================
    group('5. Legacy Dual-Write & Fallback Priority Invariants', () {
      test('5.1: Legacy saveLyrics and getLyrics dual-write and priority fallback under all 4 sources', () async {
        const keyHash = 'priority_matrix_track';

        // 1. Initially null
        expect(await db.getLyrics(keyHash), isNull);

        // 2. Insert priority 4 (lyrics_ovh)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
          rawLrc: 'Priority 4: lyricsOvh',
        ));
        // Clear legacy cache to force fallback logic in getLyrics
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('Priority 4: lyricsOvh'));

        // 3. Insert priority 3 (lrclib)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
          rawLrc: 'Priority 3: lrclib',
        ));
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('Priority 3: lrclib'));

        // 4. Insert priority 2 (file)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.file,
          rawLrc: 'Priority 2: file',
        ));
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('Priority 2: file'));

        // 5. Insert priority 1 (embedded)
        await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
          keyHash: keyHash,
          source: LyricsSource.embedded,
          rawLrc: 'Priority 1: embedded',
        ));
        await db.database.delete('lyrics_cache', where: 'key_hash = ?', whereArgs: [keyHash]);
        expect(await db.getLyrics(keyHash), equals('Priority 1: embedded'));

        // 6. Delete priority 1 (embedded) -> falls back to priority 2 (file)
        await db.deleteLyricsSourceEntry(keyHash, LyricsSource.embedded);
        expect(await db.getLyrics(keyHash), equals('Priority 2: file'));

        // 7. Delete priority 2 (file) -> falls back to priority 3 (lrclib)
        await db.deleteLyricsSourceEntry(keyHash, LyricsSource.file);
        expect(await db.getLyrics(keyHash), equals('Priority 3: lrclib'));

        // 8. Delete priority 3 (lrclib) -> falls back to priority 4 (lyricsOvh)
        await db.deleteLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(await db.getLyrics(keyHash), equals('Priority 4: lyricsOvh'));

        // 9. Delete priority 4 (lyricsOvh) -> returns null
        await db.deleteLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(await db.getLyrics(keyHash), isNull);
      });

      test('5.2: notFound and temporaryError never populate legacy lyrics_cache', () async {
        const keyHash = 'unfound_track';

        await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
          keyHash: keyHash,
          source: LyricsSource.lrclib,
        ));
        await db.saveLyricsSourceEntry(LyricsSourceEntry.temporaryError(
          keyHash: keyHash,
          source: LyricsSource.lyricsOvh,
        ));

        // Legacy table must be completely empty for this track
        final legacyRows = await db.database.rawQuery(
          'SELECT * FROM lyrics_cache WHERE key_hash = ?',
          [keyHash],
        );
        expect(legacyRows, isEmpty);
        expect(await db.getLyrics(keyHash), isNull);
      });
    });

    // =========================================================================
    // GROUP 6: Domain Model Extreme Boundary Tests
    // =========================================================================
    group('6. Domain Model Boundaries & Serialization Fidelity', () {
      test('6.1: Boundary updatedAt timestamps: 0, negative, and int64 max', () {
        const maxInt64 = 9223372036854775807;

        final eMax = LyricsSourceEntry(
          keyHash: 'k_max',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: 'Max timestamp',
          isSynced: false,
          updatedAt: maxInt64,
        );

        final dbMapMax = eMax.toDbMap();
        expect(dbMapMax['updated_at'], equals(maxInt64));
        final roundTripMax = LyricsSourceEntry.fromDbMap(dbMapMax);
        expect(roundTripMax.updatedAt, equals(maxInt64));

        // Negative updatedAt
        final eNeg = LyricsSourceEntry(
          keyHash: 'k_neg',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.notFound,
          updatedAt: -5000,
        );
        final dbMapNeg = eNeg.toDbMap();
        expect(dbMapNeg['updated_at'], greaterThan(0)); // toDbMap enforces positive timestamp when <= 0
      });

      test('6.2: fromDbMap and fromJson handle various numeric types for is_synced', () {
        // SQLite integer (1 / 0)
        final e1 = LyricsSourceEntry.fromDbMap({
          'key_hash': 'k1',
          'source': 'lrclib',
          'state': 'FOUND',
          'is_synced': 1,
          'updated_at': 100,
        });
        expect(e1.isSynced, isTrue);

        final e2 = LyricsSourceEntry.fromDbMap({
          'key_hash': 'k2',
          'source': 'lrclib',
          'state': 'FOUND',
          'is_synced': 0,
          'updated_at': 100,
        });
        expect(e2.isSynced, isFalse);

        // Dart bool
        final e3 = LyricsSourceEntry.fromDbMap({
          'key_hash': 'k3',
          'source': 'lrclib',
          'state': 'FOUND',
          'is_synced': true,
          'updated_at': 100,
        });
        expect(e3.isSynced, isTrue);

        // JSON map with alternate naming
        final e4 = LyricsSourceEntry.fromJson({
          'key_hash': 'k4',
          'sourceName': 'file',
          'stateName': 'NOT_FOUND',
          'is_synced': 1,
          'updated_at': 50,
        });
        expect(e4.isSynced, isTrue);
        expect(e4.source, equals(LyricsSource.file));
        expect(e4.state, equals(LyricsSourceState.notFound));
      });

      test('6.3: Value equality, copyWith, and hashCode contract', () {
        final a = LyricsSourceEntry(
          keyHash: 'key_hash_test',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:01.00]Hello',
          isSynced: true,
          updatedAt: 12345,
        );

        final b = LyricsSourceEntry(
          keyHash: 'key_hash_test',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:01.00]Hello',
          isSynced: true,
          updatedAt: 12345,
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));

        final modified = a.copyWith(isSynced: false, updatedAt: 99999);
        expect(modified == a, isFalse);
        expect(modified.isSynced, isFalse);
        expect(modified.updatedAt, equals(99999));
        expect(modified.keyHash, equals(a.keyHash));

        // Empirical observation on copyWith:
        // Passing null to copyWith preserves existing rawLrc due to 'rawLrc ?? this.rawLrc' fallback
        final copyWithNull = a.copyWith(rawLrc: null);
        expect(copyWithNull.rawLrc, equals(a.rawLrc));

        // Clean transition to notFound with null rawLrc uses the designated factory
        final notFoundEntry = LyricsSourceEntry.notFound(
          keyHash: a.keyHash,
          source: a.source,
        );
        expect(notFoundEntry.rawLrc, isNull);
        expect(notFoundEntry.isNotFound, isTrue);
      });
    });
  });
}
