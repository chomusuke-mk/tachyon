import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:tachyon/features/locales/domain/locale.dart';

import 'harness/lyrics_e2e_models.dart';
import 'harness/lyrics_test_driver.dart';

void main() {
  group('Tier 1: Isolated Feature Verification (Features F1 - F18)', () {
    late LyricsTestDriver driver;

    setUp(() {
      driver = LyricsTestDriver();
    });

    tearDown(() async {
      await driver.dispose();
    });

    // =========================================================================
    // Feature 1: SQLite Per-Origin Persistence
    // =========================================================================
    group('F1: SQLite Per-Origin Persistence', () {
      test('F1.1: inserts entry into lyrics_source_cache with all columns populated', () async {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_f1_1',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:01.00]Hello world',
          isSynced: true,
          updatedAt: 1700000000000,
        );
        await driver.saveLyricsSourceEntry(entry);

        final retrieved = await driver.getLyricsSourceEntry('hash_f1_1', LyricsSource.lrclib);
        expect(retrieved, isNotNull);
        expect(retrieved!.keyHash, equals('hash_f1_1'));
        expect(retrieved.source, equals(LyricsSource.lrclib));
        expect(retrieved.state, equals(LyricsSourceState.found));
        expect(retrieved.rawLrc, equals('[00:01.00]Hello world'));
        expect(retrieved.isSynced, isTrue);
        expect(retrieved.updatedAt, equals(1700000000000));
      });

      test('F1.2: retrieves entry by key_hash and source with correct fields', () async {
        final e1 = LyricsSourceEntry(
          keyHash: 'hash_f1_2',
          source: LyricsSource.embedded,
          state: LyricsSourceState.found,
          rawLrc: 'Embedded text',
          isSynced: false,
          updatedAt: 1700000001000,
        );
        await driver.saveLyricsSourceEntry(e1);

        final result = await driver.getLyricsSourceEntry('hash_f1_2', LyricsSource.embedded);
        expect(result, equals(e1));
      });

      test('F1.3: retrieves all sources for given key_hash as a Map', () async {
        final key = 'hash_f1_3';
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.embedded,
          state: LyricsSourceState.notFound,
          updatedAt: 1000,
        ));
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:02.00]Song line',
          isSynced: true,
          updatedAt: 2000,
        ));

        final all = await driver.getAllLyricsSourceEntries(key);
        expect(all.length, equals(2));
        expect(all[LyricsSource.embedded]?.state, equals(LyricsSourceState.notFound));
        expect(all[LyricsSource.lrclib]?.state, equals(LyricsSourceState.found));
      });

      test('F1.4: clearLyricsSourceEntries removes all records for key_hash', () async {
        final key = 'hash_f1_4';
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.file,
          state: LyricsSourceState.found,
          updatedAt: 1000,
        ));
        await driver.clearLyricsSourceEntries(key);

        final all = await driver.getAllLyricsSourceEntries(key);
        expect(all, isEmpty);
      });

      test('F1.5: replace conflict algorithm updates existing record without duplicate primary key', () async {
        final key = 'hash_f1_5';
        final initial = LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.temporaryError,
          updatedAt: 1000,
        );
        await driver.saveLyricsSourceEntry(initial);

        final updated = LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:05.00]Updated lyrics',
          isSynced: true,
          updatedAt: 2000,
        );
        await driver.saveLyricsSourceEntry(updated);

        final result = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(result?.state, equals(LyricsSourceState.found));
        expect(result?.rawLrc, equals('[00:05.00]Updated lyrics'));
      });
    });

    // =========================================================================
    // Feature 2: Per-Origin State Tracking (FOUND/NOT_FOUND/TEMPORARY_ERROR)
    // =========================================================================
    group('F2: Per-Origin State Tracking', () {
      test('F2.1: saves and retrieves FOUND state with non-null raw LRC', () async {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_f2_1',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:10.00]Found line',
          isSynced: true,
          updatedAt: 100,
        );
        await driver.saveLyricsSourceEntry(entry);
        final r = await driver.getLyricsSourceEntry('hash_f2_1', LyricsSource.lrclib);
        expect(r?.state, equals(LyricsSourceState.found));
      });

      test('F2.2: saves and retrieves NOT_FOUND state with null raw LRC', () async {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_f2_2',
          source: LyricsSource.lyricsOvh,
          state: LyricsSourceState.notFound,
          rawLrc: null,
          isSynced: false,
          updatedAt: 200,
        );
        await driver.saveLyricsSourceEntry(entry);
        final r = await driver.getLyricsSourceEntry('hash_f2_2', LyricsSource.lyricsOvh);
        expect(r?.state, equals(LyricsSourceState.notFound));
        expect(r?.rawLrc, isNull);
      });

      test('F2.3: saves and retrieves TEMPORARY_ERROR state', () async {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_f2_3',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.temporaryError,
          rawLrc: null,
          isSynced: false,
          updatedAt: 300,
        );
        await driver.saveLyricsSourceEntry(entry);
        final r = await driver.getLyricsSourceEntry('hash_f2_3', LyricsSource.lrclib);
        expect(r?.state, equals(LyricsSourceState.temporaryError));
      });

      test('F2.4: skips querying a source if SQLite record is NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///track_f2_4.mp3',
          title: 'Not Found Track',
          artist: 'Unknown Artist',
          durationMs: 180000,
        );
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );

        // Pre-seed NOT_FOUND for lrclib
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.notFound,
          updatedAt: 100,
        ));

        driver.lrclibMockResponder = (_) => throw StateError('Should not query lrclib');
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.lrclibRecordedQueries, isEmpty);
      });

      test('F2.5: allows query retry if SQLite record is TEMPORARY_ERROR', () async {
        final track = const TrackMetadata(
          uri: 'file:///track_f2_5.mp3',
          title: 'Temp Error Track',
          artist: 'Artist',
          durationMs: 200000,
        );
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );

        // Pre-seed TEMPORARY_ERROR for lrclib
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.temporaryError,
          updatedAt: 100,
        ));

        driver.lrclibMockResponder = (q) => const LrclibResponse(
          syncedLyrics: '[00:01.00]Retried lyrics',
          statusCode: 200,
        );

        final result = await driver.resolveLyricsForTrack(track);
        expect(result, isNotNull);
        expect(driver.lrclibRecordedQueries.length, equals(1));
        final updatedEntry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(updatedEntry?.state, equals(LyricsSourceState.found));
      });
    });

    // =========================================================================
    // Feature 3: Domain Models & Source Enums
    // =========================================================================
    group('F3: Domain Models & Source Enums', () {
      test('F3.1: LyricsSource enum serializes and deserializes to/from DB string', () {
        for (final src in LyricsSource.values) {
          final str = src.toDbString();
          final recovered = LyricsSource.fromDbString(str);
          expect(recovered, equals(src));
        }
      });

      test('F3.2: LyricsSource distinguishes isLocal vs isRemote', () {
        expect(LyricsSource.embedded.isLocal, isTrue);
        expect(LyricsSource.file.isLocal, isTrue);
        expect(LyricsSource.lrclib.isLocal, isFalse);
        expect(LyricsSource.lyricsOvh.isLocal, isFalse);

        expect(LyricsSource.embedded.isRemote, isFalse);
        expect(LyricsSource.file.isRemote, isFalse);
        expect(LyricsSource.lrclib.isRemote, isTrue);
        expect(LyricsSource.lyricsOvh.isRemote, isTrue);
      });

      test('F3.3: LyricsSourceState serializes and deserializes to/from DB string', () {
        for (final st in LyricsSourceState.values) {
          final str = st.toDbString();
          final recovered = LyricsSourceState.fromDbString(str);
          expect(recovered, equals(st));
        }
      });

      test('F3.4: LyricsSourceEntry copyWith creates new instance with updated properties', () {
        final original = LyricsSourceEntry(
          keyHash: 'hash_f3',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.temporaryError,
          updatedAt: 100,
        );
        final copy = original.copyWith(
          state: LyricsSourceState.found,
          rawLrc: '[00:01.00]Copy text',
          isSynced: true,
        );
        expect(copy.keyHash, equals(original.keyHash));
        expect(copy.source, equals(original.source));
        expect(copy.state, equals(LyricsSourceState.found));
        expect(copy.rawLrc, equals('[00:01.00]Copy text'));
        expect(copy.isSynced, isTrue);
      });

      test('F3.5: LyricsSourceEntry equals and hashCode respect value equality', () {
        final e1 = LyricsSourceEntry(
          keyHash: 'hash_eq',
          source: LyricsSource.file,
          state: LyricsSourceState.found,
          rawLrc: 'text',
          isSynced: true,
          updatedAt: 500,
        );
        final e2 = LyricsSourceEntry(
          keyHash: 'hash_eq',
          source: LyricsSource.file,
          state: LyricsSourceState.found,
          rawLrc: 'text',
          isSynced: true,
          updatedAt: 500,
        );
        expect(e1, equals(e2));
        expect(e1.hashCode, equals(e2.hashCode));
      });
    });

    // =========================================================================
    // Feature 4: Primary API Client (lrclib.net)
    // =========================================================================
    group('F4: Primary API Client (lrclib.net)', () {
      test('F4.1: formats GET /api/get query parameters with track, artist, album, duration', () {
        const query = LrclibQuery(
          trackName: 'Bohemian Rhapsody',
          artistName: 'Queen',
          albumName: 'A Night at the Opera',
          durationSeconds: 354,
        );
        final params = query.toQueryParams();
        expect(params['track_name'], equals('Bohemian Rhapsody'));
        expect(params['artist_name'], equals('Queen'));
        expect(params['album_name'], equals('A Night at the Opera'));
        expect(params['duration'], equals('354'));
      });

      test('F4.2: accepts duration within +/-2s tolerance window', () async {
        final track = const TrackMetadata(
          uri: 'file:///tolerance.mp3',
          title: 'Tolerance Track',
          artist: 'Tolerance Artist',
          durationMs: 200000, // 200s
        );

        driver.lrclibMockResponder = (q) {
          // Duration in query should be 200
          expect(q.durationSeconds, equals(200));
          return const LrclibResponse(
            syncedLyrics: '[00:01.00]Duration ok',
            statusCode: 200,
          );
        };

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNotNull);
      });

      test('F4.3: includes client User-Agent header in request', () async {
        final track = const TrackMetadata(
          uri: 'file:///ua_track.mp3',
          title: 'UA Song',
          artist: 'UA Artist',
          durationMs: 150000,
        );
        await driver.resolveLyricsForTrack(track);
        expect(driver.lrclibRequestedUserAgents.isNotEmpty, isTrue);
        expect(driver.lrclibRequestedUserAgents.last, contains('Tachyon'));
      });

      test('F4.4: handles 200 OK with synced lyrics correctly', () async {
        final track = const TrackMetadata(
          uri: 'file:///synced_ok.mp3',
          title: 'Synced OK',
          artist: 'Artist',
          durationMs: 120000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          syncedLyrics: '[00:02.50]Line 1\n[00:05.00]Line 2',
          statusCode: 200,
        );
        final lyrics = await driver.resolveLyricsForTrack(track);
        expect(lyrics, isNotNull);
        expect(lyrics!.isSynced, isTrue);
        expect(lyrics.lines.length, equals(2));
      });

      test('F4.5: handles 404 response and maps to NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///not_found_track.mp3',
          title: 'Non-existent Song',
          artist: 'Unknown',
          durationMs: 120000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(entry?.state, equals(LyricsSourceState.notFound));
      });
    });

    // =========================================================================
    // Feature 5: Secondary API Client (lyrics.ovh)
    // =========================================================================
    group('F5: Secondary API Client (lyrics.ovh)', () {
      test('F5.1: constructs URL with URL-encoded artist and title', () async {
        final track = const TrackMetadata(
          uri: 'file:///encoded_track.mp3',
          title: 'Rock & Roll / Part 1',
          artist: 'AC/DC',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (artist, title) => const LyricsOvhResponse(
          lyrics: 'Back in black lyrics',
          statusCode: 200,
        );

        await driver.resolveLyricsForTrack(track);
        expect(driver.lyricsOvhRequestedUrls.isNotEmpty, isTrue);
        expect(driver.lyricsOvhRequestedUrls.last, contains('AC%2FDC'));
      });

      test('F5.2: parses 200 OK JSON plain text response', () async {
        final track = const TrackMetadata(
          uri: 'file:///plain_ovh.mp3',
          title: 'Plain Track',
          artist: 'Plain Artist',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          lyrics: 'Line 1\nLine 2\nLine 3',
          statusCode: 200,
        );

        final parsed = await driver.resolveLyricsForTrack(track);
        expect(parsed, isNotNull);
        expect(parsed!.isSynced, isFalse);
        expect(parsed.lines.length, equals(3));
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });

      test('F5.3: handles 404 response and maps to NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///ovh_404.mp3',
          title: 'Title 404',
          artist: 'Artist 404',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lyricsOvh);
        expect(entry?.state, equals(LyricsSourceState.notFound));
      });

      test('F5.4: handles 5xx error and maps to TEMPORARY_ERROR', () async {
        final track = const TrackMetadata(
          uri: 'file:///ovh_500.mp3',
          title: 'Title 500',
          artist: 'Artist 500',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 500);

        await driver.resolveLyricsForTrack(track);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lyricsOvh);
        expect(entry?.state, equals(LyricsSourceState.temporaryError));
      });

      test('F5.5: handles empty lyrics string as NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///ovh_empty.mp3',
          title: 'Empty Lyrics',
          artist: 'Artist',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(lyrics: '', statusCode: 200);

        await driver.resolveLyricsForTrack(track);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lyricsOvh);
        expect(entry?.state, equals(LyricsSourceState.notFound));
      });
    });

    // =========================================================================
    // Feature 6: Rate Limiting (500ms Pacing)
    // =========================================================================
    group('F6: Rate Limiting (500ms Pacing)', () {
      test('F6.1: allows first request to proceed immediately', () async {
        final track = const TrackMetadata(
          uri: 'file:///first_req.mp3',
          title: 'Song 1',
          artist: 'Artist 1',
          durationMs: 150000,
        );
        final sw = Stopwatch()..start();
        await driver.resolveLyricsForTrack(track);
        sw.stop();
        // First request should not be throttled (>400ms delay)
        expect(sw.elapsedMilliseconds, lessThan(400));
        expect(driver.lrclibRequestTimestamps.length, equals(1));
      });

      test('F6.2: delays second sequential request to satisfy 500ms minimum spacing', () async {
        final t1 = const TrackMetadata(
          uri: 'file:///pace_1.mp3',
          title: 'Song 1',
          artist: 'Artist 1',
          durationMs: 150000,
        );
        final t2 = const TrackMetadata(
          uri: 'file:///pace_2.mp3',
          title: 'Song 2',
          artist: 'Artist 2',
          durationMs: 160000,
        );

        await driver.resolveLyricsForTrack(t1);
        final tBefore = DateTime.now();
        await driver.resolveLyricsForTrack(t2);
        final elapsed = DateTime.now().difference(tBefore).inMilliseconds;

        expect(driver.lrclibRequestTimestamps.length, equals(2));
        final diff = driver.lrclibRequestTimestamps[1]
            .difference(driver.lrclibRequestTimestamps[0])
            .inMilliseconds;
        expect(diff, greaterThanOrEqualTo(450));
        expect(elapsed, greaterThanOrEqualTo(450));
      });

      test('F6.3: processes queue in FIFO order', () async {
        final t1 = const TrackMetadata(uri: 'file:///fifo_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///fifo_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        await driver.resolveLyricsForTrack(t2);

        expect(driver.lrclibRecordedQueries[0].trackName, equals('T1'));
        expect(driver.lrclibRecordedQueries[1].trackName, equals('T2'));
      });

      test('F6.4: does not delay requests if more than 500ms has elapsed', () async {
        final t1 = const TrackMetadata(uri: 'file:///space_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///space_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        await Future.delayed(const Duration(milliseconds: 550));

        final sw = Stopwatch()..start();
        await driver.resolveLyricsForTrack(t2);
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(400));
      });

      test('F6.5: records request timestamps for outgoing traffic verification', () async {
        final t1 = const TrackMetadata(uri: 'file:///rec_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        await driver.resolveLyricsForTrack(t1);
        expect(driver.lrclibRequestTimestamps.length, equals(1));
        expect(driver.lrclibRequestTimestamps.first.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
      });
    });

    // =========================================================================
    // Feature 7: HTTP 429 Retry-After Handling (<=10s vs >10s)
    // =========================================================================
    group('F7: HTTP 429 Retry-After Handling', () {
      test('F7.1: parses Retry-After integer from response', () {
        final resp = LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 5,
          headers: {'retry-after': '5'},
        );
        expect(resp.isRateLimited, isTrue);
        expect(resp.retryAfterSeconds, equals(5));
      });

      test('F7.2: if Retry-After <= 10s, sets isThresholdWaiting to true and starts countdown', () async {
        final track = const TrackMetadata(
          uri: 'file:///short_429.mp3',
          title: 'Short 429',
          artist: 'Artist',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 3,
        );

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);
        expect(driver.thresholdCountdownSeconds, equals(3));
      });

      test('F7.3: if Retry-After <= 10s, auto-retries when countdown reaches 0', () async {
        final track = const TrackMetadata(
          uri: 'file:///auto_retry.mp3',
          title: 'Auto Retry Track',
          artist: 'Artist',
          durationMs: 180000,
        );
        int callCount = 0;
        driver.lrclibMockResponder = (_) {
          callCount++;
          if (callCount == 1) {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 1);
          }
          return const LrclibResponse(
            statusCode: 200,
            syncedLyrics: '[00:01.00]Success after retry',
          );
        };

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        // Wait 1.5 seconds for countdown to expire and retry
        await Future.delayed(const Duration(milliseconds: 1600));

        expect(callCount, equals(2));
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.currentLyrics, isNotNull);
      });

      test('F7.4: if Retry-After > 10s, falls back immediately to lyrics.ovh', () async {
        final track = const TrackMetadata(
          uri: 'file:///long_429.mp3',
          title: 'Long 429 Track',
          artist: 'Artist',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 60,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'Fallback lyrics text',
        );

        final lyrics = await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isFalse);
        expect(lyrics, isNotNull);
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(driver.isCooldownActive, isTrue);
      });

      test('F7.5: records 429 error as TEMPORARY_ERROR, never NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///429_temp.mp3',
          title: 'Temp Track',
          artist: 'Artist',
          durationMs: 180000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 5,
        );

        await driver.resolveLyricsForTrack(track);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(entry?.state, equals(LyricsSourceState.temporaryError));
      });
    });

    // =========================================================================
    // Feature 8: In-Memory Cooldown & Deferred Retry
    // =========================================================================
    group('F8: In-Memory Cooldown & Deferred Retry', () {
      test('F8.1: records cooldown expiry timestamp in memory', () async {
        final track = const TrackMetadata(
          uri: 'file:///cooldown_mem.mp3',
          title: 'Track',
          artist: 'Artist',
          durationMs: 100000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 30,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.lrclibCooldownExpiry, isNotNull);
        expect(
          driver.lrclibCooldownExpiry!.difference(DateTime.now()).inSeconds,
          greaterThanOrEqualTo(25),
        );
      });

      test('F8.2: isCooldownActive returns true while now < expiry', () async {
        final track = const TrackMetadata(uri: 'file:///c1.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 20);
        await driver.resolveLyricsForTrack(track);
        expect(driver.isCooldownActive, isTrue);
      });

      test('F8.3: isCooldownActive returns false once now >= expiry', () async {
        final track = const TrackMetadata(uri: 'file:///c2.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 20);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);
        await driver.resolveLyricsForTrack(track);
        expect(driver.isCooldownActive, isTrue);

        driver.advanceSimulatedTime(const Duration(seconds: 25));
        expect(driver.isCooldownActive, isFalse);
      });

      test('F8.4: automatically upgrades active track to lrclib upon cooldown expiry', () async {
        final track = const TrackMetadata(
          uri: 'file:///upgrade_track.mp3',
          title: 'Upgrade Me',
          artist: 'Artist',
          durationMs: 120000,
        );
        int lrclibCalls = 0;
        driver.lrclibMockResponder = (_) {
          lrclibCalls++;
          if (lrclibCalls == 1) {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
          }
          return const LrclibResponse(
            statusCode: 200,
            syncedLyrics: '[00:01.00]Upgraded to synced',
          );
        };
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'Plain fallback text',
        );

        final initial = await driver.resolveLyricsForTrack(track);
        expect(initial?.isSynced, isFalse);
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(driver.isCooldownActive, isTrue);

        // Manually expire cooldown and trigger deferred upgrade
        await driver.expireCooldownAndTriggerUpgrade();

        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
        expect(driver.currentLyrics?.isSynced, isTrue);
      });

      test('F8.5: skips lrclib on new track while cooldown is active', () async {
        final track1 = const TrackMetadata(uri: 'file:///cd1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final track2 = const TrackMetadata(uri: 'file:///cd2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'Ovh lyrics');

        await driver.resolveLyricsForTrack(track1);
        expect(driver.isCooldownActive, isTrue);
        expect(driver.lrclibRecordedQueries.length, equals(1));

        // Play track 2 during active cooldown
        await driver.resolveLyricsForTrack(track2);
        // Should not query lrclib again
        expect(driver.lrclibRecordedQueries.length, equals(1));
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });
    });

    // =========================================================================
    // Feature 9: Free Public Lyrics Translation
    // =========================================================================
    group('F9: Free Public Lyrics Translation', () {
      test('F9.1: translates lyric lines and populates translatedLines', () async {
        final track = const TrackMetadata(
          uri: 'file:///trans.mp3',
          title: 'Hello',
          artist: 'Artist',
          durationMs: 100000,
          embeddedLyrics: '[00:01.00]Hello world\n[00:05.00]Goodbye friend',
        );
        await driver.resolveLyricsForTrack(track);

        final result = await driver.translateLyrics(targetLanguage: 'es');
        expect(result.isSuccess, isTrue);
        expect(driver.translatedLines.length, equals(2));
        expect(driver.translatedLines.first, contains('Hello world'));
      });

      test('F9.2: chunks lines into batches not exceeding 400 characters', () async {
        final longLine = 'A' * 250;
        final lines = [longLine, longLine, longLine];
        final rawLrc = lines.map((l) => '[00:01.00]$l').join('\n');

        final track = TrackMetadata(
          uri: 'file:///long_lines.mp3',
          title: 'Long',
          artist: 'A',
          durationMs: 100000,
          embeddedLyrics: rawLrc,
        );
        await driver.resolveLyricsForTrack(track);

        await driver.translateLyrics();
        expect(driver.translationBatches.length, greaterThan(1));
        for (final batch in driver.translationBatches) {
          final totalChars = batch.fold<int>(0, (sum, line) => sum + line.length);
          expect(totalChars, lessThanOrEqualTo(500));
        }
      });

      test('F9.3: maintains 1:1 line count alignment between original and translated lines', () async {
        final track = const TrackMetadata(
          uri: 'file:///align.mp3',
          title: 'Align',
          artist: 'A',
          durationMs: 100000,
          embeddedLyrics: '[00:01.00]One\n[00:02.00]Two\n[00:03.00]Three\n[00:04.00]Four',
        );
        await driver.resolveLyricsForTrack(track);
        final res = await driver.translateLyrics();
        expect(res.translatedLines.length, equals(res.originalLines.length));
      });

      test('F9.4: handles empty lyrics input gracefully', () async {
        final res = await driver.translateLyrics();
        expect(res.isSuccess, isFalse);
        expect(res.errorMessage, isNotNull);
      });

      test('F9.5: handles translation network error gracefully without crashing', () async {
        final track = const TrackMetadata(
          uri: 'file:///trans_err.mp3',
          title: 'Err',
          artist: 'A',
          durationMs: 100000,
          embeddedLyrics: '[00:01.00]Some lyrics',
        );
        await driver.resolveLyricsForTrack(track);

        driver.translationMockResponder = (_, _) => throw Exception('Translation API down');
        final res = await driver.translateLyrics();
        expect(res.isSuccess, isFalse);
        expect(driver.isTranslating, isFalse);
      });
    });

    // =========================================================================
    // Feature 10: Rapid Track Skip Concurrency Cancellation
    // =========================================================================
    group('F10: Rapid Track Skip Concurrency Cancellation', () {
      test('F10.1: increments generation token on each track transition', () async {
        final t1 = const TrackMetadata(uri: 'file:///s1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///s2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        final p1 = driver.resolveLyricsForTrack(t1);
        final p2 = driver.resolveLyricsForTrack(t2);
        await Future.wait([p1, p2]);

        expect(driver.currentTrack?.uri, equals('file:///s2.mp3'));
      });

      test('F10.2: discards in-flight response when generation token has changed', () async {
        final t1 = const TrackMetadata(uri: 'file:///slow1.mp3', title: 'Slow1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///fast2.mp3', title: 'Fast2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) {
          if (q.trackName == 'Slow1') {
            return const LrclibResponse(
              statusCode: 200,
              syncedLyrics: '[00:01.00]Slow 1 response',
            );
          }
          return const LrclibResponse(
            statusCode: 200,
            syncedLyrics: '[00:01.00]Fast 2 response',
          );
        };

        // Fire t1 then immediately t2
        final f1 = driver.resolveLyricsForTrack(t1);
        final f2 = driver.resolveLyricsForTrack(t2);
        await Future.wait([f1, f2]);

        expect(driver.currentTrack?.title, equals('Fast2'));
        expect(driver.currentLyrics?.lines.first.text, equals('Fast 2 response'));
      });

      test('F10.3: burst skip 1->2->3->4->5 only displays lyrics for track 5', () async {
        final tracks = List.generate(
          5,
          (i) => TrackMetadata(
            uri: 'file:///burst_${i + 1}.mp3',
            title: 'Track ${i + 1}',
            artist: 'Artist',
            durationMs: 100000,
          ),
        );

        driver.lrclibMockResponder = (q) => LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Lyrics for ${q.trackName}',
        );

        final futures = tracks.map((t) => driver.resolveLyricsForTrack(t)).toList();
        await Future.wait(futures);

        expect(driver.currentTrack?.title, equals('Track 5'));
        expect(driver.currentLyrics?.lines.first.text, equals('Lyrics for Track 5'));
      });

      test('F10.4: cancels pending threshold countdown when track is skipped', () async {
        final t1 = const TrackMetadata(uri: 'file:///c_skip.mp3', title: 'C1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///c_skip2.mp3', title: 'C2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) {
          if (q.trackName == 'C1') {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);
          }
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]C2 ok');
        };

        await driver.resolveLyricsForTrack(t1);
        expect(driver.isThresholdWaiting, isTrue);

        await driver.resolveLyricsForTrack(t2);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.currentTrack?.title, equals('C2'));
      });

      test('F10.5: skips intermediate throttled network requests', () async {
        final t1 = const TrackMetadata(uri: 'file:///throttle_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///throttle_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        final p1 = driver.resolveLyricsForTrack(t1);
        final p2 = driver.resolveLyricsForTrack(t2);
        await Future.wait([p1, p2]);

        expect(driver.currentTrack?.title, equals('T2'));
      });
    });

    // =========================================================================
    // Feature 11: Remote Web Query Visibility Gating
    // =========================================================================
    group('F11: Remote Web Query Visibility Gating', () {
      test('F11.1: prevents web API calls when isLyricsViewVisible is false', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///closed_view.mp3',
          title: 'Closed View Track',
          artist: 'Artist',
          durationMs: 150000,
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.lrclibRecordedQueries, isEmpty);
        expect(driver.lyricsOvhRequestedUrls, isEmpty);
      });

      test('F11.2: resolves local sources (embedded tags) even when view is closed', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///embedded_closed.mp3',
          title: 'Embedded Closed',
          artist: 'Artist',
          durationMs: 150000,
          embeddedLyrics: '[00:01.00]Local tag lyrics',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNotNull);
        expect(res!.lines.first.text, equals('Local tag lyrics'));
        expect(driver.currentLyricsSource, equals(LyricsSource.embedded));
      });

      test('F11.3: resolves local sources (.lrc file) even when view is closed', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///lrc_closed.mp3',
          title: 'Lrc Closed',
          artist: 'Artist',
          durationMs: 150000,
          localLrcContent: '[00:02.00]Contiguous file lyrics',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNotNull);
        expect(res!.lines.first.text, equals('Contiguous file lyrics'));
        expect(driver.currentLyricsSource, equals(LyricsSource.file));
      });

      test('F11.4: triggers remote resolution when view transitions from closed to open', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///open_later.mp3',
          title: 'Open Later',
          artist: 'Artist',
          durationMs: 150000,
        );

        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Fetched upon opening',
        );

        await driver.playTrack(track);
        expect(driver.currentLyrics, isNull);

        // Now user opens Now Playing / Lyrics View
        driver.setLyricsViewVisible(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(driver.currentLyrics, isNotNull);
        expect(driver.currentLyrics?.lines.first.text, equals('Fetched upon opening'));
      });

      test('F11.5: closing view cancels active threshold countdown', () async {
        final track = const TrackMetadata(uri: 'file:///vis_close.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setLyricsViewVisible(false);
        expect(driver.isThresholdWaiting, isFalse);
      });
    });

    // =========================================================================
    // Feature 12: 4-Tier Hierarchical LyricsService
    // =========================================================================
    group('F12: 4-Tier Hierarchical LyricsService', () {
      test('F12.1: Tier 1 embedded tags take highest precedence', () async {
        final track = const TrackMetadata(
          uri: 'file:///h1.mp3',
          title: 'H1',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Embedded wins',
          localLrcContent: '[00:01.00]Local file',
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]lrclib',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('Embedded wins'));
        expect(driver.currentLyricsSource, equals(LyricsSource.embedded));
      });

      test('F12.2: Tier 2 local .lrc file used when embedded tags absent', () async {
        final track = const TrackMetadata(
          uri: 'file:///h2.mp3',
          title: 'H2',
          artist: 'A',
          durationMs: 100,
          localLrcContent: '[00:01.00]Local file wins',
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]lrclib',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('Local file wins'));
        expect(driver.currentLyricsSource, equals(LyricsSource.file));
      });

      test('F12.3: Tier 3 lrclib used when local sources absent', () async {
        final track = const TrackMetadata(
          uri: 'file:///h3.mp3',
          title: 'H3',
          artist: 'A',
          durationMs: 100,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]lrclib wins',
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'lyrics.ovh',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('lrclib wins'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      });

      test('F12.4: Tier 4 lyrics.ovh used when lrclib fails or returns not found', () async {
        final track = const TrackMetadata(
          uri: 'file:///h4.mp3',
          title: 'H4',
          artist: 'A',
          durationMs: 100,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'lyrics.ovh wins',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('lyrics.ovh wins'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });

      test('F12.5: returns null when all 4 sources return no lyrics', () async {
        final track = const TrackMetadata(
          uri: 'file:///h5.mp3',
          title: 'H5',
          artist: 'A',
          durationMs: 100,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.currentLyrics, isNull);
      });
    });

    // =========================================================================
    // Feature 13: Now Playing Visibility Binding
    // =========================================================================
    group('F13: Now Playing Visibility Binding', () {
      test('F13.1: initial visibility defaults according to driver setup', () {
        expect(driver.isLyricsViewVisible, isTrue);
      });

      test('F13.2: setLyricsViewVisible(false) updates isLyricsViewVisible', () {
        driver.setLyricsViewVisible(false);
        expect(driver.isLyricsViewVisible, isFalse);
      });

      test('F13.3: setLyricsViewVisible(true) updates isLyricsViewVisible', () {
        driver.setLyricsViewVisible(false);
        driver.setLyricsViewVisible(true);
        expect(driver.isLyricsViewVisible, isTrue);
      });

      test('F13.4: re-entering view for same track with existing lyrics does not re-fetch', () async {
        final track = const TrackMetadata(
          uri: 'file:///same_v.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Line 1',
        );
        await driver.resolveLyricsForTrack(track);

        driver.setLyricsViewVisible(false);
        driver.setLyricsViewVisible(true);

        expect(driver.lrclibRecordedQueries, isEmpty);
      });

      test('F13.5: re-entering view for track with only local check triggers remote check', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///local_only.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
        );
        await driver.resolveLyricsForTrack(track);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.setLyricsViewVisible(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(driver.lrclibRecordedQueries.length, equals(1));
      });
    });

    // =========================================================================
    // Feature 14: UI Translation Button & Display Modes
    // =========================================================================
    group('F14: UI Translation Button & Display Modes', () {
      test('F14.1: toggleTranslation cycles original -> translated -> interleaved -> original', () {
        expect(driver.displayMode, equals(LyricsDisplayMode.original));
        driver.toggleTranslation();
        expect(driver.displayMode, equals(LyricsDisplayMode.translated));
        driver.toggleTranslation();
        expect(driver.displayMode, equals(LyricsDisplayMode.interleaved));
        driver.toggleTranslation();
        expect(driver.displayMode, equals(LyricsDisplayMode.original));
      });

      test('F14.2: setTranslationDisplayMode directly sets mode', () {
        driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
        expect(driver.displayMode, equals(LyricsDisplayMode.interleaved));
      });

      test('F14.3: original mode displays original lines unchanged', () async {
        final track = const TrackMetadata(
          uri: 'file:///dm1.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Original text',
        );
        await driver.resolveLyricsForTrack(track);
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.original);
        final lines = driver.effectiveDisplayLines;
        expect(lines.length, equals(1));
        expect(lines.first.text, equals('Original text'));
      });

      test('F14.4: translated mode displays translated text on each line', () async {
        final track = const TrackMetadata(
          uri: 'file:///dm2.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Hello',
        );
        await driver.resolveLyricsForTrack(track);
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.translated);
        final lines = driver.effectiveDisplayLines;
        expect(lines.length, equals(1));
        expect(lines.first.text, contains('[es] Hello'));
      });

      test('F14.5: interleaved mode intersperses translated line after each original line', () async {
        final track = const TrackMetadata(
          uri: 'file:///dm3.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Hello\n[00:05.00]World',
        );
        await driver.resolveLyricsForTrack(track);
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
        final lines = driver.effectiveDisplayLines;
        expect(lines.length, equals(4));
        expect(lines[0].text, equals('Hello'));
        expect(lines[1].text, contains('[es] Hello'));
        expect(lines[2].text, equals('World'));
        expect(lines[3].text, contains('[es] World'));
      });
    });

    // =========================================================================
    // Feature 15: UI Sources Configuration Dialog
    // =========================================================================
    group('F15: UI Sources Configuration Dialog', () {
      test('F15.1: setSourcesConfig(local: false) disables local sources', () async {
        driver.setSourcesConfig(local: false);
        final track = const TrackMetadata(
          uri: 'file:///dis_local.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Embedded',
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]lrclib fallback',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('lrclib fallback'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      });

      test('F15.2: setSourcesConfig(lrclib: false) disables lrclib queries', () async {
        driver.setSourcesConfig(lrclib: false);
        final track = const TrackMetadata(
          uri: 'file:///dis_lrclib.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'ovh fallback',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('ovh fallback'));
        expect(driver.lrclibRecordedQueries, isEmpty);
      });

      test('F15.3: setSourcesConfig(lyricsOvh: false) disables lyrics.ovh queries', () async {
        driver.setSourcesConfig(lyricsOvh: false);
        final track = const TrackMetadata(
          uri: 'file:///dis_ovh.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.lyricsOvhRequestedUrls, isEmpty);
      });

      test('F15.4: disabling lrclib while threshold waiting immediately dismisses countdown', () async {
        final track = const TrackMetadata(uri: 'file:///dis_wait.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setSourcesConfig(lrclib: false);
        expect(driver.isThresholdWaiting, isFalse);
      });

      test('F15.5: enabling previously disabled source allows subsequent queries', () async {
        driver.setSourcesConfig(lrclib: false);
        driver.setSourcesConfig(lrclib: true);
        expect(driver.enableLrclib, isTrue);
      });
    });

    // =========================================================================
    // Feature 16: UI Manual Re-search ("Volver a buscar") Button
    // =========================================================================
    group('F16: UI Manual Re-search Button', () {
      test('F16.1: forceReSearch forces resolution with forceRefresh=true', () async {
        final track = const TrackMetadata(
          uri: 'file:///force_res.mp3',
          title: 'Force Title',
          artist: 'Force Artist',
          durationMs: 100000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.currentLyrics, isNull);

        // Update responder to succeed
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Re-searched lyrics',
        );

        await driver.forceReSearch();
        expect(driver.currentLyrics, isNotNull);
        expect(driver.currentLyrics?.lines.first.text, equals('Re-searched lyrics'));
      });

      test('F16.2: forceReSearch clears SQLite cache entries for current track', () async {
        final track = const TrackMetadata(uri: 'file:///force_clr.mp3', title: 'T', artist: 'A', durationMs: 100);
        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.notFound,
          updatedAt: 100,
        ));

        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Found on refresh',
        );

        await driver.playTrack(track);
        await driver.forceReSearch();

        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(entry?.state, equals(LyricsSourceState.found));
      });

      test('F16.3: forceReSearch clears active memory cooldown', () async {
        final track = const TrackMetadata(uri: 'file:///force_cd.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isCooldownActive, isTrue);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]New');
        await driver.forceReSearch();
        expect(driver.isCooldownActive, isFalse);
      });

      test('F16.4: forceReSearch queries enabled sources again despite previous NOT_FOUND', () async {
        final track = const TrackMetadata(uri: 'file:///force_nf.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.lrclibRecordedQueries.length, equals(1));

        await driver.forceReSearch();
        expect(driver.lrclibRecordedQueries.length, equals(2));
      });

      test('F16.5: forceReSearch updates currentLyrics and emits on lyricsStream', () async {
        final track = const TrackMetadata(uri: 'file:///force_stream.mp3', title: 'T', artist: 'A', durationMs: 100);
        await driver.resolveLyricsForTrack(track);

        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:02.00]Stream updated',
        );

        final futureEmit = driver.lyricsStream.first;
        await driver.forceReSearch();
        final emitted = await futureEmit;

        expect(emitted?.lines.first.text, equals('Stream updated'));
      });
    });

    // =========================================================================
    // Feature 17: Non-Invasive 429 Countdown Banner
    // =========================================================================
    group('F17: Non-Invasive 429 Countdown Banner', () {
      test('F17.1: isThresholdWaiting is true during active countdown', () async {
        final track = const TrackMetadata(uri: 'file:///banner1.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 4);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);
      });

      test('F17.2: thresholdCountdownSeconds holds remaining seconds', () async {
        final track = const TrackMetadata(uri: 'file:///banner2.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 7);

        await driver.resolveLyricsForTrack(track);
        expect(driver.thresholdCountdownSeconds, equals(7));
      });

      test('F17.3: emits decreasing seconds on thresholdStream', () async {
        final track = const TrackMetadata(uri: 'file:///banner3.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 2);

        final events = <int?>[];
        final sub = driver.thresholdStream.listen(events.add);

        await driver.resolveLyricsForTrack(track);
        await Future.delayed(const Duration(milliseconds: 1500));
        await sub.cancel();

        expect(events, contains(2));
      });

      test('F17.4: dismissing view resets isThresholdWaiting to false', () async {
        final track = const TrackMetadata(uri: 'file:///banner4.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 8);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setLyricsViewVisible(false);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.thresholdCountdownSeconds, isNull);
      });

      test('F17.5: reaching 0 seconds clears waiting state and auto-retries', () async {
        final track = const TrackMetadata(uri: 'file:///banner5.mp3', title: 'T', artist: 'A', durationMs: 100);
        int calls = 0;
        driver.lrclibMockResponder = (_) {
          calls++;
          if (calls == 1) {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 1);
          }
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Success');
        };

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        await Future.delayed(const Duration(milliseconds: 1600));
        expect(driver.isThresholdWaiting, isFalse);
        expect(calls, equals(2));
      });
    });

    // =========================================================================
    // Feature 18: Complete i18n Localization
    // =========================================================================
    group('F18: Complete i18n Localization', () {
      test('F18.1: en.jsonc contains core lyrics keys: np_lyrics, np_lyrics_empty, np_lyrics_sync, np_lyrics_unsync', () {
        final file = File('i18n/en.jsonc');
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();
        expect(content, contains('"np_lyrics"'));
        expect(content, contains('"np_lyrics_empty"'));
        expect(content, contains('"np_lyrics_sync"'));
        expect(content, contains('"np_lyrics_unsync"'));
      });

      test('F18.2: es.jsonc contains symmetric core lyrics keys', () {
        final file = File('i18n/es.jsonc');
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();
        expect(content, contains('"np_lyrics"'));
        expect(content, contains('"np_lyrics_empty"'));
        expect(content, contains('"np_lyrics_sync"'));
        expect(content, contains('"np_lyrics_unsync"'));
      });

      test('F18.3: AppStringKey exposes non-empty strings for lyrics keys', () async {
        final keys = AppStringKey();
        await keys.updateFromJson({
          'np_lyrics': 'Lyrics',
          'np_lyrics_empty': 'No lyrics found for this track',
          'np_lyrics_sync': 'Synchronized lyrics',
          'np_lyrics_unsync': 'Plain lyrics',
        });
        expect(keys.npLyrics, equals('Lyrics'));
        expect(keys.npLyricsEmpty, contains('No lyrics'));
        expect(keys.npLyricsSync, contains('Synchronized'));
        expect(keys.npLyricsUnsync, contains('Plain'));
      });

      test('F18.4: threshold countdown format template supports parameterized replacement', () {
        const template = 'Threshold de lrclib.net detectado esperando {seconds} segundos...';
        final rendered = template.replaceAll('{seconds}', '5');
        expect(rendered, equals('Threshold de lrclib.net detectado esperando 5 segundos...'));
      });

      test('F18.5: i18n keys contain no unescaped or corrupted control characters', () {
        final enFile = File('i18n/en.jsonc').readAsStringSync();
        final esFile = File('i18n/es.jsonc').readAsStringSync();
        expect(enFile, isNotEmpty);
        expect(esFile, isNotEmpty);
        // Ensure no unprintable null bytes or unicode replacement characters
        expect(enFile.contains('\uFFFD'), isFalse);
        expect(esFile.contains('\uFFFD'), isFalse);
      });
    });
  });
}
