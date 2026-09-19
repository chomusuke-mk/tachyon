import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Milestone 1 Stress & Concurrency Challenge Suite', () {
    // -------------------------------------------------------------------------
    // 1. MASS BATCH INSERTION & QUERY BENCHMARKS (10,000 SYNTHETIC TRACKS)
    // -------------------------------------------------------------------------
    group('Mass Batch Ingestion (5,000 - 10,000 Tracks)', () {
      late AppDatabase db;
      late Directory tempDir;
      late String dbPath;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('tachyon_stress_batch_');
        dbPath = p.join(tempDir.path, 'stress_test.db');
        db = AppDatabaseImpl(customPath: dbPath);
        await db.init();
      });

      tearDown(() async {
        await db.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('ingests 10,000 tracks in batches, evaluates timing, memory, and query performance', () async {
        const totalTracks = 10000;
        const totalArtists = 100;
        const totalAlbums = 250;

        final syntheticTracks = List.generate(totalTracks, (i) {
          final albumIdx = i % totalAlbums;
          final artistIdx = albumIdx % totalArtists;
          return Track(
            uri: 'file:///media/music/artist_$artistIdx/album_$albumIdx/track_$i.flac',
            title: 'Synthetic Track ${i.toString().padLeft(5, '0')}',
            artist: 'Artist ${artistIdx.toString().padLeft(3, '0')}',
            album: 'Album ${albumIdx.toString().padLeft(3, '0')}',
            albumArtist: 'Artist ${artistIdx.toString().padLeft(3, '0')}',
            trackNumber: (i % 20) + 1,
            discNumber: (i % 2) + 1,
            year: 1980 + (i % 45),
            durationMs: 120000 + (i * 37) % 300000,
            bitrate: 320000 + (i % 3) * 100000,
            sampleRate: 44100,
            channels: 2,
            codec: 'FLAC',
            fileSize: 25000000 + (i * 1000),
            modifiedAt: 1600000000 + i,
            genres: ['Genre ${(i % 10)}'],
          );
        });

        // Batch 1: First 5,000 tracks
        final stopwatchBatch1 = Stopwatch()..start();
        await db.batchInsertTracks(syntheticTracks.sublist(0, 5000));
        stopwatchBatch1.stop();
        final batch1TimeMs = stopwatchBatch1.elapsedMilliseconds;

        // Verify intermediate state
        final tracksCountAfter5k = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM tracks'),
        );
        expect(tracksCountAfter5k, equals(5000));

        // Batch 2: Remaining 5,000 tracks (Total 10,000)
        final stopwatchBatch2 = Stopwatch()..start();
        await db.batchInsertTracks(syntheticTracks.sublist(5000, 10000));
        stopwatchBatch2.stop();
        final batch2TimeMs = stopwatchBatch2.elapsedMilliseconds;

        final totalInsertTimeMs = batch1TimeMs + batch2TimeMs;
        final throughputPerSecond = (totalTracks / (totalInsertTimeMs / 1000)).toStringAsFixed(1);

        // Verification of row counts
        final totalTracksInDb = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM tracks'),
        );
        expect(totalTracksInDb, equals(totalTracks));

        final totalArtistsInDb = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM artists'),
        );
        expect(totalArtistsInDb, equals(totalArtists));

        final totalAlbumsInDb = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM albums'),
        );
        expect(totalAlbumsInDb, equals(totalAlbums));

        // Verify aggregated artist & album track counts sum to 10,000
        final artistTrackSum = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT SUM(track_count) FROM artists'),
        );
        expect(artistTrackSum, equals(totalTracks));

        final albumTrackSum = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT SUM(track_count) FROM albums'),
        );
        expect(albumTrackSum, equals(totalTracks));

        // Query performance benchmarks on 10,000 tracks
        final swQueryTitle = Stopwatch()..start();
        final tracksByTitle = await db.getAllTracks(sortBy: 'title', ascending: true);
        swQueryTitle.stop();
        expect(tracksByTitle.length, equals(totalTracks));
        expect(tracksByTitle.first.title, equals('Synthetic Track 00000'));
        expect(tracksByTitle.last.title, equals('Synthetic Track 09999'));

        final swQueryArtist = Stopwatch()..start();
        final tracksByArtist = await db.getAllTracks(sortBy: 'artist', ascending: true);
        swQueryArtist.stop();
        expect(tracksByArtist.length, equals(totalTracks));

        final swQueryYear = Stopwatch()..start();
        final tracksByYear = await db.getAllTracks(sortBy: 'year', ascending: false);
        swQueryYear.stop();
        expect(tracksByYear.length, equals(totalTracks));
        expect(tracksByYear.first.year, greaterThanOrEqualTo(tracksByYear.last.year!));

        final swQueryAlbums = Stopwatch()..start();
        final albums = await db.getAllAlbums();
        swQueryAlbums.stop();
        expect(albums.length, equals(totalAlbums));

        final swQueryArtists = Stopwatch()..start();
        final artists = await db.getAllArtists();
        swQueryArtists.stop();
        expect(artists.length, equals(totalArtists));

        final swSearch = Stopwatch()..start();
        final searchResults = await db.searchTracks('Synthetic Track 05432');
        swSearch.stop();
        expect(searchResults.length, equals(1));
        expect(searchResults.first.title, equals('Synthetic Track 05432'));

        // Spot-check samples for zero data corruption
        final sampleIndices = [0, 2499, 4999, 7499, 9999];
        for (final idx in sampleIndices) {
          final expected = syntheticTracks[idx];
          final actualRow = await db.database.query(
            'tracks',
            where: 'uri = ?',
            whereArgs: [expected.uri],
            limit: 1,
          );
          expect(actualRow.isNotEmpty, isTrue);
          final r = actualRow.first;
          expect(r['title'], equals(expected.title));
          expect(r['duration_ms'], equals(expected.durationMs));
          expect(r['bitrate'], equals(expected.bitrate));
          expect(r['file_size'], equals(expected.fileSize));
          expect(r['modified_at'], equals(expected.modifiedAt));
          expect(r['codec'], equals('FLAC'));
        }

        // Print benchmark statistics for handoff analysis
        // ignore: avoid_print
        print('''
--- BENCHMARK RESULTS (10,000 TRACKS) ---
Batch 1 (0-5,000):   $batch1TimeMs ms
Batch 2 (5k-10,000): $batch2TimeMs ms
Total Ingestion:     $totalInsertTimeMs ms ($throughputPerSecond tracks/sec)
Query by Title:      ${swQueryTitle.elapsedMilliseconds} ms
Query by Artist:     ${swQueryArtist.elapsedMilliseconds} ms
Query by Year:       ${swQueryYear.elapsedMilliseconds} ms
Query All Albums:    ${swQueryAlbums.elapsedMilliseconds} ms
Query All Artists:   ${swQueryArtists.elapsedMilliseconds} ms
Single Search:       ${swSearch.elapsedMilliseconds} ms
-----------------------------------------
''');
      });
    });

    // -------------------------------------------------------------------------
    // 2. CONCURRENT READ / WRITE TRANSACTIONS & WAL MODE VALIDATION
    // -------------------------------------------------------------------------
    group('Concurrent Transactions (WAL Mode)', () {
      late AppDatabase db;
      late Directory tempDir;
      late String dbPath;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('tachyon_stress_wal_');
        dbPath = p.join(tempDir.path, 'wal_concurrency.db');
        db = AppDatabaseImpl(customPath: dbPath);
        await db.init();
      });

      tearDown(() async {
        await db.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('validates WAL mode PRAGMA configuration on disk', () async {
        final journalModeRes = await db.database.rawQuery('PRAGMA journal_mode;');
        final mode = journalModeRes.first.values.first.toString().toLowerCase();
        expect(mode, equals('wal'), reason: 'Database MUST be configured with WAL journal mode');

        final synchronousRes = await db.database.rawQuery('PRAGMA synchronous;');
        final syncVal = synchronousRes.first.values.first;
        expect(syncVal, equals(1), reason: 'PRAGMA synchronous should be NORMAL (1)');
      });

      test('handles heavy concurrent readers while writer actively inserts batches', () async {
        // Pre-populate with 1,000 tracks
        final initialTracks = List.generate(
          1000,
          (i) => Track(
            uri: 'file:///concurrency/init_$i.mp3',
            title: 'Initial Song $i',
            artist: 'Band ${i % 20}',
            album: 'Record ${i % 10}',
            durationMs: 180000,
            fileSize: 4000000,
            modifiedAt: 1000 + i,
          ),
        );
        await db.batchInsertTracks(initialTracks);

        var readerErrors = 0;
        var writerErrors = 0;
        var totalReadOperations = 0;
        var isWriterDone = false;

        // Writer Future: Inserts 1,000 more tracks in batches
        final writerFuture = () async {
          try {
            for (int batch = 0; batch < 5; batch++) {
              final newTracks = List.generate(
                200,
                (i) => Track(
                  uri: 'file:///concurrency/batch_${batch}_$i.mp3',
                  title: 'Concurrent Batch Song $batch-$i',
                  artist: 'Band ${i % 20}',
                  album: 'Record ${i % 10}',
                  durationMs: 200000,
                  fileSize: 5000000,
                  modifiedAt: 2000 + batch * 1000 + i,
                ),
              );
              await db.batchInsertTracks(newTracks);
              await Future.delayed(const Duration(milliseconds: 5));
            }
          } catch (e) {
            writerErrors++;
          } finally {
            isWriterDone = true;
          }
        }();

        // Reader Futures: 10 parallel reader loops executing queries until writer completes
        final readerFutures = List.generate(10, (readerId) async {
          while (!isWriterDone) {
            try {
              final tracks = await db.getAllTracks();
              expect(tracks.length, greaterThanOrEqualTo(1000));

              final searchRes = await db.searchTracks('Song 5');
              expect(searchRes, isNotNull);

              final albums = await db.getAllAlbums();
              expect(albums, isNotEmpty);

              final artists = await db.getAllArtists();
              expect(artists, isNotEmpty);

              totalReadOperations++;
              await Future.delayed(const Duration(milliseconds: 2));
            } catch (e) {
              readerErrors++;
            }
          }
        });

        // Concurrently mutate playlist operations
        final playlistWorkerFuture = () async {
          try {
            final plId = await db.createPlaylist('Concurrent Playlist');
            for (int i = 1; i <= 50; i++) {
              await db.addTrackToPlaylist(plId, i);
              if (i % 10 == 0) {
                final tracks = await db.getTracksForPlaylist(plId);
                expect(tracks.length, equals(i));
              }
            }
          } catch (e) {
            writerErrors++;
          }
        }();

        await Future.wait([
          writerFuture,
          playlistWorkerFuture,
          ...readerFutures,
        ]);

        expect(writerErrors, equals(0), reason: 'Zero writer transactions should fail under WAL');
        expect(readerErrors, equals(0), reason: 'Zero reader transactions should fail under WAL');
        expect(totalReadOperations, greaterThan(20), reason: 'Multiple read transactions should execute during writes');

        final finalCount = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM tracks'),
        );
        expect(finalCount, equals(2000));
      });
    });

    // -------------------------------------------------------------------------
    // 3. EXTREME PLAYLIST REORDERING (600 TRACKS)
    // -------------------------------------------------------------------------
    group('Large Playlist Reordering (600 Tracks)', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabaseImpl.inMemory();
        await db.init();
      });

      tearDown(() async {
        await db.close();
      });

      test('populates 600 tracks in a playlist, tests extreme reordering and boundary operations', () async {
        const trackCount = 600;

        // Insert 600 synthetic tracks
        final tracks = List.generate(
          trackCount,
          (i) => Track(
            uri: 'file:///playlist_tracks/track_$i.mp3',
            title: 'Playlist Track ${i.toString().padLeft(4, '0')}',
            artist: 'Artist ${i % 10}',
            album: 'Album ${i % 5}',
            durationMs: 180000,
            fileSize: 3000000,
            modifiedAt: 1000 + i,
          ),
        );
        await db.batchInsertTracks(tracks);

        final insertedTracks = await db.getAllTracks(sortBy: 'title', ascending: true);
        expect(insertedTracks.length, equals(trackCount));

        // Create playlist
        final playlistId = await db.createPlaylist('Massive 600-Track Workout');

        // Add all 600 tracks into playlist sequentially
        final swAdd = Stopwatch()..start();
        for (final t in insertedTracks) {
          await db.addTrackToPlaylist(playlistId, t.id!);
        }
        swAdd.stop();

        var plTracks = await db.getTracksForPlaylist(playlistId);
        expect(plTracks.length, equals(trackCount));

        // Helper to verify position invariants: 0, 1, 2, ..., N-1 with no duplicates or gaps
        Future<void> verifySequentialPositions(int expectedLength) async {
          final rows = await db.database.query(
            'playlist_entries',
            columns: ['position', 'track_id'],
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
            orderBy: 'position ASC',
          );
          expect(rows.length, equals(expectedLength));
          for (int i = 0; i < expectedLength; i++) {
            expect(rows[i]['position'], equals(i), reason: 'Position at index $i must be exactly $i');
          }
        }

        await verifySequentialPositions(trackCount);

        // Operation A: Move first track (0) to last (599)
        final firstTrackId = plTracks.first.id!;
        final swMoveEnd = Stopwatch()..start();
        await db.reorderPlaylistEntries(playlistId, 0, trackCount - 1);
        swMoveEnd.stop();

        plTracks = await db.getTracksForPlaylist(playlistId);
        expect(plTracks.length, equals(trackCount));
        expect(plTracks.last.id, equals(firstTrackId), reason: 'Track moved to end must be at index 599');
        await verifySequentialPositions(trackCount);

        // Operation B: Move last track (599) back to first (0)
        final lastTrackId = plTracks.last.id!;
        final swMoveStart = Stopwatch()..start();
        await db.reorderPlaylistEntries(playlistId, trackCount - 1, 0);
        swMoveStart.stop();

        plTracks = await db.getTracksForPlaylist(playlistId);
        expect(plTracks.first.id, equals(lastTrackId), reason: 'Track moved to start must be at index 0');
        await verifySequentialPositions(trackCount);

        // Operation C: Move middle item (300) to index 50
        final middleTrackId = plTracks[300].id!;
        final swMoveMiddle = Stopwatch()..start();
        await db.reorderPlaylistEntries(playlistId, 300, 50);
        swMoveMiddle.stop();

        plTracks = await db.getTracksForPlaylist(playlistId);
        expect(plTracks[50].id, equals(middleTrackId), reason: 'Track moved to 50 must be at index 50');
        await verifySequentialPositions(trackCount);

        // Operation D: Out of bounds reorders (must be no-ops)
        await db.reorderPlaylistEntries(playlistId, -1, 50);
        await db.reorderPlaylistEntries(playlistId, 10, 1000);
        await db.reorderPlaylistEntries(playlistId, 1000, 10);
        await verifySequentialPositions(trackCount);

        // Operation E: Reorder to same position (no-op)
        await db.reorderPlaylistEntries(playlistId, 120, 120);
        await verifySequentialPositions(trackCount);

        // Operation F: Remove an item from middle (index 200) and verify re-compaction
        final trackToRemove = plTracks[200].id!;
        await db.removeTrackFromPlaylist(playlistId, trackToRemove);

        plTracks = await db.getTracksForPlaylist(playlistId);
        expect(plTracks.length, equals(trackCount - 1));
        expect(plTracks.any((t) => t.id == trackToRemove), isFalse);
        await verifySequentialPositions(trackCount - 1);

        // ignore: avoid_print
        print('''
--- PLAYLIST REORDER BENCHMARKS (600 TRACKS) ---
Populate 600 items:     ${swAdd.elapsedMilliseconds} ms
Move 0 -> 599:          ${swMoveEnd.elapsedMilliseconds} ms
Move 599 -> 0:          ${swMoveStart.elapsedMilliseconds} ms
Move 300 -> 50:         ${swMoveMiddle.elapsedMilliseconds} ms
------------------------------------------------
''');
      });
    });

    // -------------------------------------------------------------------------
    // 4. SQL INJECTION RESILIENCE & ADVERSARIAL PAYLOADS
    // -------------------------------------------------------------------------
    group('SQL Injection Resilience & Adversarial Inputs', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabaseImpl.inMemory();
        await db.init();
      });

      tearDown(() async {
        await db.close();
      });

      test('handles adversarial SQL injection payloads across all search queries', () async {
        // Pre-insert valid track
        await db.insertOrUpdateTrack(const Track(
          uri: 'file:///safe/song.mp3',
          title: 'Safe Song',
          artist: 'Safe Artist',
          album: 'Safe Album',
          durationMs: 180000,
          fileSize: 1000,
          modifiedAt: 100,
        ));

        final injectionPayloads = [
          "'; DROP TABLE tracks; --",
          "' OR '1'='1",
          "' OR 1=1 --",
          "'; DELETE FROM playlists; --",
          "\" OR \"\"=\"",
          "' UNION SELECT id, name, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM artists --",
          "Robert'); DROP TABLE albums;--",
          "'; VACUUM; --",
          "' OR ''='",
          "%%",
          "___",
          "\\",
          "\\x00'--",
          "🔥🎸🎶🚀💎",
          "' AND (SELECT COUNT(*) FROM tracks) > 0 --",
          "'; UPDATE tracks SET title='PWNED'; --",
        ];

        for (final payload in injectionPayloads) {
          // searchTracks
          final results = await db.searchTracks(payload);
          expect(results, isA<List<Track>>());

          // Verify tables still intact
          final tracksCount = Sqflite.firstIntValue(
            await db.database.rawQuery('SELECT COUNT(*) FROM tracks'),
          );
          expect(tracksCount, equals(1), reason: 'tracks table was compromised by payload: $payload');

          final albumsCount = Sqflite.firstIntValue(
            await db.database.rawQuery('SELECT COUNT(*) FROM albums'),
          );
          expect(albumsCount, equals(1), reason: 'albums table was compromised by payload: $payload');
        }
      });

      test('getAllTracks gracefully falls back on malicious sortBy inputs without executing SQL injection', () async {
        await db.insertOrUpdateTrack(const Track(
          uri: 'file:///safe/song.mp3',
          title: 'Beta Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          fileSize: 1000,
          modifiedAt: 100,
        ));
        await db.insertOrUpdateTrack(const Track(
          uri: 'file:///safe/song2.mp3',
          title: 'Alpha Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          fileSize: 1000,
          modifiedAt: 200,
        ));

        final maliciousSorts = [
          "title; DROP TABLE tracks;--",
          "title DESC; DELETE FROM artists;--",
          "' OR 1=1 --",
          "RANDOM()",
          "case when (1=1) then title else year end",
          "'; SHUTDOWN; --",
        ];

        for (final maliciousSort in maliciousSorts) {
          // Should not throw or compromise DB; fallback to default title sorting
          final tracks = await db.getAllTracks(sortBy: maliciousSort, ascending: true);
          expect(tracks.length, equals(2));
          expect(tracks.first.title, equals('Alpha Song'), reason: 'Malicious sort must default to title ASC');

          final tracksCount = Sqflite.firstIntValue(
            await db.database.rawQuery('SELECT COUNT(*) FROM tracks'),
          );
          expect(tracksCount, equals(2), reason: 'DB altered by sortBy injection: $maliciousSort');
        }
      });

      test('stores and retrieves adversarial string payloads verbatim via insertOrUpdateTrack', () async {
        const maliciousTrack = Track(
          uri: "file:///music/it's a song; with 'quotes' & -- comments.mp3",
          title: "'; DROP TABLE tracks; DROP TABLE playlists; --",
          artist: "Artist'); DELETE FROM albums;--",
          album: "Album ' OR '1'='1",
          albumArtist: "Robert'); DROP TABLE artists;--",
          lyrics: "[00:00.00] Injected lyrics with ' and \" and ; and --",
          codec: "FLAC'; DROP TABLE genres;--",
          durationMs: 240000,
          fileSize: 1234567,
          modifiedAt: 1700000000,
          genres: ["Rock'; DROP TABLE track_genres;--", "Heavy' OR '1'='1"],
        );

        await db.insertOrUpdateTrack(maliciousTrack);

        // Verify tables intact
        final tables = await db.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        );
        final tableNames = tables.map((r) => r['name']).toSet();
        expect(
          tableNames.containsAll([
            'tracks',
            'artists',
            'albums',
            'genres',
            'track_genres',
            'playlists',
            'playlist_entries',
            'lyrics_cache',
          ]),
          isTrue,
        );

        // Verify track retrieved verbatim
        final retrieved = await db.getAllTracks();
        expect(retrieved.length, equals(1));
        final t = retrieved.first;
        expect(t.title, equals("'; DROP TABLE tracks; DROP TABLE playlists; --"));
        expect(t.artist, equals("Artist'); DELETE FROM albums;--"));
        expect(t.album, equals("Album ' OR '1'='1"));
        expect(t.uri, equals("file:///music/it's a song; with 'quotes' & -- comments.mp3"));

        // Verify search can find the verbatim injection string
        final found = await db.searchTracks("DROP TABLE tracks");
        expect(found.length, equals(1));
        expect(found.first.title, equals(t.title));
      });

      test('playlist creation and deletion with injection payloads and special playlist protection', () async {
        const hostileName = "'; DROP TABLE playlists; SELECT * FROM '";
        final plId = await db.createPlaylist(hostileName);
        expect(plId, greaterThan(2));

        final playlists = await db.getAllPlaylists();
        final created = playlists.firstWhere((p) => p.id == plId);
        expect(created.name, equals(hostileName));

        // Attempt deletion of special playlists
        await db.deletePlaylist(AppConstants.likedSongsPlaylistId);
        await db.deletePlaylist(AppConstants.historyPlaylistId);

        final afterSpecialDelete = await db.getAllPlaylists();
        expect(afterSpecialDelete.any((p) => p.id == AppConstants.likedSongsPlaylistId), isTrue);
        expect(afterSpecialDelete.any((p) => p.id == AppConstants.historyPlaylistId), isTrue);

        // Delete user playlist succeeds
        await db.deletePlaylist(plId);
        final afterUserDelete = await db.getAllPlaylists();
        expect(afterUserDelete.any((p) => p.id == plId), isFalse);
      });

      test('lyrics cache storage and retrieval with hostile payload keys and content', () async {
        const hostileKey = "hash'; DROP TABLE lyrics_cache;--";
        const hostileLrc = "[00:01.00] Line with ' and \"; DROP TABLE tracks;--\n[00:05.00] End";
        const hostileSource = "source' OR '1'='1";

        await db.saveLyrics(hostileKey, hostileLrc, hostileSource);

        final cached = await db.getLyrics(hostileKey);
        expect(cached, equals(hostileLrc));

        // Verify lyrics_cache table still exists and has 1 row
        final count = Sqflite.firstIntValue(
          await db.database.rawQuery('SELECT COUNT(*) FROM lyrics_cache'),
        );
        expect(count, equals(1));
      });
    });

    // -------------------------------------------------------------------------
    // 5. DATA PERSISTENCE, RECONNECTION & BOUNDARY EDGE CASES
    // -------------------------------------------------------------------------
    group('Data Persistence, Reconnection & Boundary Edge Cases', () {
      late Directory tempDir;
      late String dbPath;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('tachyon_stress_persist_');
        dbPath = p.join(tempDir.path, 'persist_test.db');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('persists 2,000 tracks to physical disk and recovers cleanly after close and reopen', () async {
        // Phase 1: Open, populate, and close
        final db1 = AppDatabaseImpl(customPath: dbPath);
        await db1.init();

        final tracks = List.generate(
          2000,
          (i) => Track(
            uri: 'file:///persist/track_$i.flac',
            title: 'Persisted Track $i',
            artist: 'Artist ${i % 20}',
            album: 'Album ${i % 10}',
            durationMs: 200000,
            fileSize: 10000000,
            modifiedAt: 1600000000 + i,
          ),
        );
        await db1.batchInsertTracks(tracks);

        final plId = await db1.createPlaylist('Permanent Favorites');
        await db1.addTrackToPlaylist(plId, 1);
        await db1.addTrackToPlaylist(plId, 2);
        await db1.saveLyrics('hash_persist', '[00:01.00] Persisted', 'local');

        await db1.close();

        // Verify physical file exists on disk
        final dbFile = File(dbPath);
        expect(dbFile.existsSync(), isTrue);
        expect(dbFile.lengthSync(), greaterThan(0));

        // Phase 2: Reopen with new instance and verify all records intact
        final db2 = AppDatabaseImpl(customPath: dbPath);
        await db2.init();

        final recoveredTracks = await db2.getAllTracks();
        expect(recoveredTracks.length, equals(2000));

        final playlists = await db2.getAllPlaylists();
        expect(playlists.length, equals(3)); // Liked, History, and Permanent Favorites
        final customPl = playlists.firstWhere((p) => p.name == 'Permanent Favorites');
        expect(customPl.trackCount, equals(2));

        final recoveredLyrics = await db2.getLyrics('hash_persist');
        expect(recoveredLyrics, equals('[00:01.00] Persisted'));

        await db2.close();
      });

      test('handles rescan updates: updates existing tracks without duplicating rows and updates counters', () async {
        final db = AppDatabaseImpl(customPath: dbPath);
        await db.init();

        // Initial scan of 500 tracks
        final initialTracks = List.generate(
          500,
          (i) => Track(
            uri: 'file:///library/song_$i.mp3',
            title: 'Old Title $i',
            artist: 'Old Artist',
            album: 'Old Album',
            durationMs: 180000,
            fileSize: 4000000,
            modifiedAt: 1000,
          ),
        );
        await db.batchInsertTracks(initialTracks);

        var count = Sqflite.firstIntValue(await db.database.rawQuery('SELECT COUNT(*) FROM tracks'));
        expect(count, equals(500));

        // Rescan with updated metadata on same URIs
        final updatedTracks = List.generate(
          500,
          (i) => Track(
            uri: 'file:///library/song_$i.mp3',
            title: 'New Remastered Title $i',
            artist: 'New Artist',
            album: 'New Album',
            durationMs: 185000,
            fileSize: 4500000,
            modifiedAt: 2000,
          ),
        );
        await db.batchInsertTracks(updatedTracks);

        count = Sqflite.firstIntValue(await db.database.rawQuery('SELECT COUNT(*) FROM tracks'));
        expect(count, equals(500), reason: 'Track count must stay 500 when URIs match');

        final all = await db.getAllTracks();
        expect(all.first.title, startsWith('New Remastered Title'));
        expect(all.first.durationMs, equals(185000));

        // Artists should reflect updated track counts
        final artists = await db.getAllArtists();
        final newArtist = artists.firstWhere((a) => a.name == 'New Artist');
        expect(newArtist.trackCount, equals(500));

        await db.close();
      });

      test('safely handles boundary edge cases: null fields, empty titles, and long strings', () async {
        final db = AppDatabaseImpl(customPath: dbPath);
        await db.init();

        final longString = 'A' * 4000;
        final boundaryTrack = Track(
          uri: 'file:///boundary/minimal.mp3',
          title: longString,
          artist: null,
          album: null,
          albumArtist: null,
          year: null,
          trackNumber: null,
          discNumber: null,
          durationMs: 0,
          fileSize: 0,
          modifiedAt: 0,
        );

        await db.insertOrUpdateTrack(boundaryTrack);

        final tracks = await db.getAllTracks();
        expect(tracks.length, equals(1));
        expect(tracks.first.title.length, equals(4000));
        expect(tracks.first.artist, isNull);
        expect(tracks.first.album, isNull);
        expect(tracks.first.year, isNull);

        // Batch insert tracks with null artists and albums
        final nullTracks = List.generate(
          50,
          (i) => Track(
            uri: 'file:///null_artists/track_$i.mp3',
            title: 'Untitled $i',
            artist: null,
            album: null,
            durationMs: 1000,
            fileSize: 500,
            modifiedAt: 100,
          ),
        );
        await db.batchInsertTracks(nullTracks);

        final totalTracks = await db.getAllTracks();
        expect(totalTracks.length, equals(51));

        await db.close();
      });
    });
  });
}

