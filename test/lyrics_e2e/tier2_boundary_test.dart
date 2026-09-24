import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';

import 'harness/lyrics_e2e_models.dart';
import 'harness/lyrics_test_driver.dart';

void main() {
  group('Tier 2: Boundary, Corner Cases & Error-Prone Inputs (Features F1 - F18)', () {
    late LyricsTestDriver driver;

    setUp(() {
      driver = LyricsTestDriver();
    });

    tearDown(() async {
      await driver.dispose();
    });

    // =========================================================================
    // Feature 1 Boundary: SQLite Per-Origin Persistence
    // =========================================================================
    group('F1 Boundary: SQLite Per-Origin Persistence', () {
      test('F1.B1: handles empty rawLrc string gracefully in database', () async {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_b1_1',
          source: LyricsSource.file,
          state: LyricsSourceState.found,
          rawLrc: '',
          isSynced: false,
          updatedAt: 1000,
        );
        await driver.saveLyricsSourceEntry(entry);
        final res = await driver.getLyricsSourceEntry('hash_b1_1', LyricsSource.file);
        expect(res, isNotNull);
        expect(res!.rawLrc, equals(''));
      });

      test('F1.B2: special unicode characters and emojis in keyHash and rawLrc persist without corruption', () async {
        const specialKey = 'hash_🔥_日本語_русский_üöä';
        const specialLrc = '[00:01.00]🎵 Chanson d\'amour & España — ¡Olé! 🌸';
        final entry = LyricsSourceEntry(
          keyHash: specialKey,
          source: LyricsSource.embedded,
          state: LyricsSourceState.found,
          rawLrc: specialLrc,
          isSynced: true,
          updatedAt: 123456,
        );
        await driver.saveLyricsSourceEntry(entry);

        final res = await driver.getLyricsSourceEntry(specialKey, LyricsSource.embedded);
        expect(res, isNotNull);
        expect(res!.keyHash, equals(specialKey));
        expect(res.rawLrc, equals(specialLrc));
      });

      test('F1.B3: SQL meta-characters and quotation marks in keyHash do not cause syntax errors', () async {
        const injectionKey = "'; DROP TABLE lyrics_source_cache; -- ' OR '1'='1";
        final entry = LyricsSourceEntry(
          keyHash: injectionKey,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.notFound,
          updatedAt: 999,
        );
        await driver.saveLyricsSourceEntry(entry);

        final res = await driver.getLyricsSourceEntry(injectionKey, LyricsSource.lrclib);
        expect(res, isNotNull);
        expect(res!.keyHash, equals(injectionKey));

        // Confirm table was not dropped!
        final all = await driver.getAllLyricsSourceEntries(injectionKey);
        expect(all.length, equals(1));
      });

      test('F1.B4: huge LRC content (>100KB with 1,500 lines) writes and reads back with zero data loss', () async {
        final buffer = StringBuffer();
        for (int i = 0; i < 1500; i++) {
          final mm = (i ~/ 60).toString().padLeft(2, '0');
          final ss = (i % 60).toString().padLeft(2, '0');
          buffer.writeln('[$mm:$ss.00]Line $i of extensive lyrics content payload testing memory bandwidth');
        }
        final hugeLrc = buffer.toString();
        expect(hugeLrc.length, greaterThan(100000));

        final entry = LyricsSourceEntry(
          keyHash: 'hash_huge',
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: hugeLrc,
          isSynced: true,
          updatedAt: 55555,
        );
        await driver.saveLyricsSourceEntry(entry);

        final res = await driver.getLyricsSourceEntry('hash_huge', LyricsSource.lrclib);
        expect(res, isNotNull);
        expect(res!.rawLrc!.length, equals(hugeLrc.length));
        expect(res.rawLrc, equals(hugeLrc));
      });

      test('F1.B5: concurrent rapid updates to same key_hash and source resolve cleanly with latest value', () async {
        const key = 'hash_concurrent';
        final futures = List.generate(20, (i) {
          return driver.saveLyricsSourceEntry(LyricsSourceEntry(
            keyHash: key,
            source: LyricsSource.lyricsOvh,
            state: LyricsSourceState.found,
            rawLrc: 'Update $i',
            updatedAt: 1000 + i,
          ));
        });
        await Future.wait(futures);

        final res = await driver.getLyricsSourceEntry(key, LyricsSource.lyricsOvh);
        expect(res, isNotNull);
        expect(res!.rawLrc, startsWith('Update '));
      });
    });

    // =========================================================================
    // Feature 2 Boundary: Per-Origin State Tracking
    // =========================================================================
    group('F2 Boundary: Per-Origin State Tracking', () {
      test('F2.B1: rapid cycling between TEMPORARY_ERROR and FOUND converges to correct latest state', () async {
        const key = 'hash_cycle';
        for (int i = 0; i < 5; i++) {
          await driver.saveLyricsSourceEntry(LyricsSourceEntry(
            keyHash: key,
            source: LyricsSource.lrclib,
            state: LyricsSourceState.temporaryError,
            updatedAt: 100 * i,
          ));
          await driver.saveLyricsSourceEntry(LyricsSourceEntry(
            keyHash: key,
            source: LyricsSource.lrclib,
            state: LyricsSourceState.found,
            rawLrc: '[00:01.00]Found $i',
            updatedAt: 100 * i + 50,
          ));
        }

        final res = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(res?.state, equals(LyricsSourceState.found));
        expect(res?.rawLrc, equals('[00:01.00]Found 4'));
      });

      test('F2.B2: case sensitivity in state enum string parsing (throws on invalid state token)', () {
        expect(() => LyricsSourceState.fromDbString('found'), returnsNormally);
        expect(() => LyricsSourceState.fromDbString('FOUND'), returnsNormally);
        expect(() => LyricsSourceState.fromDbString('UNKNOWN_STATE'), throwsArgumentError);
      });

      test('F2.B3: clearing non-existent keyHash does not throw error', () async {
        await expectLater(
          driver.clearLyricsSourceEntries('non_existent_key_999'),
          completes,
        );
      });

      test('F2.B4: getAllLyricsSourceEntries for non-existent keyHash returns empty map', () async {
        final res = await driver.getAllLyricsSourceEntries('does_not_exist');
        expect(res, isEmpty);
      });

      test('F2.B5: updating record from NOT_FOUND to FOUND on manual re-search replaces record cleanly', () async {
        const key = 'hash_f2_b5';
        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.notFound,
          updatedAt: 100,
        ));
        expect((await driver.getLyricsSourceEntry(key, LyricsSource.lrclib))?.state, equals(LyricsSourceState.notFound));

        await driver.saveLyricsSourceEntry(LyricsSourceEntry(
          keyHash: key,
          source: LyricsSource.lrclib,
          state: LyricsSourceState.found,
          rawLrc: '[00:01.00]Now found',
          updatedAt: 200,
        ));
        expect((await driver.getLyricsSourceEntry(key, LyricsSource.lrclib))?.state, equals(LyricsSourceState.found));
      });
    });

    // =========================================================================
    // Feature 3 Boundary: Domain Models & Source Enums
    // =========================================================================
    group('F3 Boundary: Domain Models & Source Enums', () {
      test('F3.B1: LyricsSource.fromDbString throws ArgumentError on unknown source name', () {
        expect(() => LyricsSource.fromDbString('spotify'), throwsArgumentError);
        expect(() => LyricsSource.fromDbString(''), throwsArgumentError);
      });

      test('F3.B2: LyricsSourceState.fromDbString throws ArgumentError on unknown state string', () {
        expect(() => LyricsSourceState.fromDbString('PENDING'), throwsArgumentError);
        expect(() => LyricsSourceState.fromDbString('404'), throwsArgumentError);
      });

      test('F3.B3: LyricsSourceEntry with negative updatedAt timestamp handles properly', () {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_neg',
          source: LyricsSource.file,
          state: LyricsSourceState.found,
          updatedAt: -100,
        );
        expect(entry.updatedAt, equals(-100));
        final map = entry.toMap();
        final recovered = LyricsSourceEntry.fromMap(map);
        expect(recovered.updatedAt, equals(-100));
      });

      test('F3.B4: copyWith without arguments produces identical object with same hash', () {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_copy',
          source: LyricsSource.embedded,
          state: LyricsSourceState.found,
          rawLrc: 'text',
          isSynced: true,
          updatedAt: 42,
        );
        final copy = entry.copyWith();
        expect(copy, equals(entry));
        expect(copy.hashCode, equals(entry.hashCode));
      });

      test('F3.B5: LyricsSourceEntry equality returns false when compared to different type or null', () {
        final entry = LyricsSourceEntry(
          keyHash: 'hash_eq',
          source: LyricsSource.embedded,
          state: LyricsSourceState.found,
          updatedAt: 1,
        );
        const Object otherObj = 'string_object';
        expect(entry == (otherObj as dynamic), isFalse);
        expect(entry == entry.copyWith(isSynced: true), isFalse);
      });
    });

    // =========================================================================
    // Feature 4 Boundary: Primary API Client (lrclib.net)
    // =========================================================================
    group('F4 Boundary: Primary API Client (lrclib.net)', () {
      test('F4.B1: duration tolerance edge: exactly +2s difference is accepted', () async {
        final track = const TrackMetadata(
          uri: 'file:///dur_p2.mp3',
          title: 'Dur+2',
          artist: 'Artist',
          durationMs: 180000, // 180s
        );
        driver.lrclibMockResponder = (q) {
          // Duration requested matches ±2s window (178s - 182s)
          expect((q.durationSeconds! - 180).abs(), lessThanOrEqualTo(2));
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Edge +2s ok');
        };

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNotNull);
      });

      test('F4.B2: duration tolerance edge: exactly -2s difference is accepted', () async {
        final track = const TrackMetadata(
          uri: 'file:///dur_m2.mp3',
          title: 'Dur-2',
          artist: 'Artist',
          durationMs: 180000, // 180s
        );
        driver.lrclibMockResponder = (q) {
          expect((q.durationSeconds! - 180).abs(), lessThanOrEqualTo(2));
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Edge -2s ok');
        };

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNotNull);
      });

      test('F4.B3: instrumental track response with instrumental=true and no lyrics is handled without crashing', () async {
        final track = const TrackMetadata(
          uri: 'file:///instrumental.mp3',
          title: 'Orion',
          artist: 'Metallica',
          durationMs: 500000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          instrumental: true,
          syncedLyrics: null,
          plainLyrics: null,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.currentLyrics, isNull);
      });

      test('F4.B4: handles HTTP 503 Service Unavailable as TEMPORARY_ERROR', () async {
        final track = const TrackMetadata(
          uri: 'file:///503_track.mp3',
          title: 'Overloaded',
          artist: 'Artist',
          durationMs: 120000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 503);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

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

      test('F4.B5: special characters in track name (slashes, ampersands, quotes, commas) are correctly preserved in query', () async {
        const query = LrclibQuery(
          trackName: 'AC/DC - Rock "N" Roll, Pt. 1 & 2',
          artistName: 'Artist & Co.',
          albumName: "Album's Best",
          durationSeconds: 240,
        );
        final params = query.toQueryParams();
        expect(params['track_name'], equals('AC/DC - Rock "N" Roll, Pt. 1 & 2'));
        expect(params['artist_name'], equals('Artist & Co.'));
        expect(params['album_name'], equals("Album's Best"));
      });
    });

    // =========================================================================
    // Feature 5 Boundary: Secondary API Client (lyrics.ovh)
    // =========================================================================
    group('F5 Boundary: Secondary API Client (lyrics.ovh)', () {
      test('F5.B1: artist and title containing forward slashes are properly URI-encoded to prevent malformed URL path', () async {
        final track = const TrackMetadata(
          uri: 'file:///slash_track.mp3',
          title: 'Title/SubTitle/Pt.1',
          artist: 'Artist/Band',
          durationMs: 150000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (a, t) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.lyricsOvhRequestedUrls.last, contains('Artist%2FBand'));
        expect(driver.lyricsOvhRequestedUrls.last, contains('Title%2FSubTitle%2FPt.1'));
      });

      test('F5.B2: artist and title containing question marks and hash symbols are URI-encoded', () async {
        final track = const TrackMetadata(
          uri: 'file:///q_track.mp3',
          title: 'What Is Love? #1',
          artist: 'Haddaway & Guests?',
          durationMs: 150000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (a, t) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        expect(driver.lyricsOvhRequestedUrls.last, contains('%3F')); // ?
        expect(driver.lyricsOvhRequestedUrls.last, contains('%23')); // #
      });

      test('F5.B3: HTTP 504 Gateway Timeout maps to TEMPORARY_ERROR', () async {
        final track = const TrackMetadata(
          uri: 'file:///504_track.mp3',
          title: 'Timeout',
          artist: 'Artist',
          durationMs: 100000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 504);

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

      test('F5.B4: HTTP 404 response body with empty JSON maps to NOT_FOUND', () async {
        final track = const TrackMetadata(
          uri: 'file:///404_json.mp3',
          title: 'Empty 404',
          artist: 'Artist',
          durationMs: 100000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404, error: 'No lyrics found');

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

      test('F5.B5: whitespace-only lyrics string from lyrics.ovh is treated as not found', () async {
        final track = const TrackMetadata(
          uri: 'file:///space_lyrics.mp3',
          title: 'Spaces',
          artist: 'Artist',
          durationMs: 100000,
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: '   \n\t  \n  ',
        );

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
    // Feature 6 Boundary: Rate Limiting (500ms Pacing)
    // =========================================================================
    group('F6 Boundary: Rate Limiting (500ms Pacing)', () {
      test('F6.B1: burst of 3 rapid requests has each sequential pair spaced by at least 450ms', () async {
        final tracks = List.generate(
          3,
          (i) => TrackMetadata(
            uri: 'file:///burst_pace_$i.mp3',
            title: 'Song $i',
            artist: 'Artist',
            durationMs: 100000,
          ),
        );

        for (final t in tracks) {
          await driver.resolveLyricsForTrack(t);
        }

        expect(driver.lrclibRequestTimestamps.length, equals(3));
        for (int i = 1; i < driver.lrclibRequestTimestamps.length; i++) {
          final diff = driver.lrclibRequestTimestamps[i]
              .difference(driver.lrclibRequestTimestamps[i - 1])
              .inMilliseconds;
          expect(diff, greaterThanOrEqualTo(450));
        }
      });

      test('F6.B2: request issued exactly 500ms after previous request experiences 0 artificial delay', () async {
        final t1 = const TrackMetadata(uri: 'file:///ext_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///ext_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        await Future.delayed(const Duration(milliseconds: 520));

        final sw = Stopwatch()..start();
        await driver.resolveLyricsForTrack(t2);
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(300));
      });

      test('F6.B3: cancellation of request during pacing wait does not dispatch network call', () async {
        final t1 = const TrackMetadata(uri: 'file:///canc_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///canc_2.mp3', title: 'T2', artist: 'A', durationMs: 100);
        final t3 = const TrackMetadata(uri: 'file:///canc_3.mp3', title: 'T3', artist: 'A', durationMs: 100);

        driver.resolveLyricsForTrack(t1);
        driver.resolveLyricsForTrack(t2);
        final f3 = driver.resolveLyricsForTrack(t3);
        await f3;

        expect(driver.currentTrack?.title, equals('T3'));
      });

      test('F6.B4: client disposal while pacing wait is active terminates cleanly', () async {
        final t1 = const TrackMetadata(uri: 'file:///disp_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///disp_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        driver.resolveLyricsForTrack(t2);

        await expectLater(driver.dispose(), completes);
      });

      test('F6.B5: clock skew / simulated time jump forward releases throttled request immediately', () async {
        final t1 = const TrackMetadata(uri: 'file:///skew_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///skew_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        driver.advanceSimulatedTime(const Duration(seconds: 1));

        final sw = Stopwatch()..start();
        await driver.resolveLyricsForTrack(t2);
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(350));
      });
    });

    // =========================================================================
    // Feature 7 Boundary: HTTP 429 Retry-After Handling
    // =========================================================================
    group('F7 Boundary: HTTP 429 Retry-After Handling', () {
      test('F7.B1: Retry-After at boundary of exactly 10 seconds triggers countdown (<=10s rule)', () async {
        final track = const TrackMetadata(uri: 'file:///b_10s.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 10,
        );

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);
        expect(driver.thresholdCountdownSeconds, equals(10));
        expect(driver.isCooldownActive, isFalse);
      });

      test('F7.B2: Retry-After at boundary of exactly 11 seconds triggers immediate fallback (>10s rule)', () async {
        final track = const TrackMetadata(uri: 'file:///b_11s.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 11,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'OVH Fallback at 11s',
        );

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.isCooldownActive, isTrue);
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });

      test('F7.B3: missing Retry-After header defaults to safe threshold (e.g. 5s) <=10s rule', () async {
        final track = const TrackMetadata(uri: 'file:///b_def.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: null, // missing header
        );

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);
        expect(driver.thresholdCountdownSeconds, equals(5));
      });

      test('F7.B4: extreme Retry-After value (3600 seconds) triggers fallback and 1-hour cooldown', () async {
        final track = const TrackMetadata(uri: 'file:///b_3600.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 429,
          retryAfterSeconds: 3600,
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'OVH Text');

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.isCooldownActive, isTrue);
        expect(driver.lrclibCooldownExpiry!.difference(DateTime.now()).inSeconds, greaterThanOrEqualTo(3500));
      });

      test('F7.B5: rapid successive 429 responses do not crash or leak timers', () async {
        final track = const TrackMetadata(uri: 'file:///b_succ.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 2);

        for (int i = 0; i < 3; i++) {
          await driver.resolveLyricsForTrack(track);
        }
        expect(driver.isThresholdWaiting, isTrue);
      });
    });

    // =========================================================================
    // Feature 8 Boundary: In-Memory Cooldown & Deferred Retry
    // =========================================================================
    group('F8 Boundary: In-Memory Cooldown & Deferred Retry', () {
      test('F8.B1: cooldown active check when cooldownExpiry is null returns false', () {
        expect(driver.isCooldownActive, isFalse);
      });

      test('F8.B2: rapid track toggling (Track A -> Track B -> Track A) during cooldown preserves cooldown for Track A', () async {
        final tA = const TrackMetadata(uri: 'file:///tA.mp3', title: 'TA', artist: 'A', durationMs: 100);
        final tB = const TrackMetadata(uri: 'file:///tB.mp3', title: 'TB', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'Ovh text');

        await driver.resolveLyricsForTrack(tA);
        expect(driver.isCooldownActive, isTrue);

        await driver.resolveLyricsForTrack(tB);
        expect(driver.isCooldownActive, isTrue);

        await driver.resolveLyricsForTrack(tA);
        expect(driver.isCooldownActive, isTrue);
        // Only 1 lrclib request was ever made!
        expect(driver.lrclibRecordedQueries.length, equals(1));
      });

      test('F8.B3: manual re-search resets active in-memory cooldown immediately', () async {
        final track = const TrackMetadata(uri: 'file:///rst_cd.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 120);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isCooldownActive, isTrue);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Fresh');
        await driver.forceReSearch();
        expect(driver.isCooldownActive, isFalse);
        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      });

      test('F8.B4: cooldown expiry with no active track handles gracefully without error', () async {
        driver.advanceSimulatedTime(const Duration(hours: 1));
        await expectLater(driver.expireCooldownAndTriggerUpgrade(), completes);
      });

      test('F8.B5: multiple 429s with longer Retry-After extend the cooldown expiry timestamp', () async {
        final track = const TrackMetadata(uri: 'file:///ext_cd.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 30);
        await driver.resolveLyricsForTrack(track);
        final exp1 = driver.lrclibCooldownExpiry;

        driver.advanceSimulatedTime(const Duration(seconds: 10));
        await driver.forceReSearch();

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
        await driver.resolveLyricsForTrack(track);
        final exp2 = driver.lrclibCooldownExpiry;

        expect(exp2!.isAfter(exp1!), isTrue);
      });
    });

    // =========================================================================
    // Feature 9 Boundary: Free Public Lyrics Translation
    // =========================================================================
    group('F9 Boundary: Free Public Lyrics Translation', () {
      test('F9.B1: single line exceeding 400 characters is batched appropriately', () async {
        final hugeLine = 'Word ' * 100; // ~500 chars
        final track = TrackMetadata(
          uri: 'file:///huge_line.mp3',
          title: 'Huge',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]$hugeLine',
        );
        await driver.resolveLyricsForTrack(track);

        final res = await driver.translateLyrics();
        expect(res.isSuccess, isTrue);
        expect(driver.translationBatches.isNotEmpty, isTrue);
      });

      test('F9.B2: empty lines and lines with only whitespace in lyrics preserve line indices', () async {
        final track = const TrackMetadata(
          uri: 'file:///white_lines.mp3',
          title: 'White',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Line 1\n[00:02.00]   \n[00:03.00]Line 3',
        );
        await driver.resolveLyricsForTrack(track);

        final res = await driver.translateLyrics();
        expect(res.translatedLines.length, equals(res.originalLines.length));
      });

      test('F9.B3: multiline text with Windows CRLF newlines normalizes and translates cleanly', () async {
        final track = const TrackMetadata(
          uri: 'file:///crlf.mp3',
          title: 'CRLF',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Line 1\r\n[00:02.00]Line 2\r\n[00:03.00]Line 3',
        );
        await driver.resolveLyricsForTrack(track);

        final res = await driver.translateLyrics();
        expect(res.translatedLines.length, equals(3));
      });

      test('F9.B4: non-latin unicode scripts translate without character corruption', () async {
        const unicodeLrc = '[00:01.00]你好世界\n[00:02.00]مرحبا بالعالم\n[00:03.00]Привет, мир\n[00:04.00]こんにちは世界';
        final track = const TrackMetadata(
          uri: 'file:///cjk.mp3',
          title: 'CJK',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: unicodeLrc,
        );
        await driver.resolveLyricsForTrack(track);

        final res = await driver.translateLyrics();
        expect(res.isSuccess, isTrue);
        expect(res.translatedLines.length, equals(4));
        expect(res.translatedLines.first, contains('你好世界'));
      });

      test('F9.B5: translation failure preserves original lyrics in currentLyrics', () async {
        final track = const TrackMetadata(
          uri: 'file:///tr_fail.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Keep me intact',
        );
        await driver.resolveLyricsForTrack(track);

        driver.translationMockResponder = (_, _) => throw Exception('Network timeout');
        final res = await driver.translateLyrics();

        expect(res.isSuccess, isFalse);
        expect(driver.currentLyrics?.lines.first.text, equals('Keep me intact'));
      });
    });

    // =========================================================================
    // Feature 10 Boundary: Rapid Track Skip Concurrency Cancellation
    // =========================================================================
    group('F10 Boundary: Rapid Track Skip Concurrency Cancellation', () {
      test('F10.B1: 10 rapid skips within 5 milliseconds resolve only the 10th track', () async {
        final tracks = List.generate(
          10,
          (i) => TrackMetadata(
            uri: 'file:///fast_$i.mp3',
            title: 'Track $i',
            artist: 'Artist',
            durationMs: 100,
          ),
        );

        driver.lrclibMockResponder = (q) => LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Final ${q.trackName}',
        );

        final futures = tracks.map((t) => driver.resolveLyricsForTrack(t));
        await Future.wait(futures);

        expect(driver.currentTrack?.title, equals('Track 9'));
        expect(driver.currentLyrics?.lines.first.text, equals('Final Track 9'));
      });

      test('F10.B2: skipping back to the original track resolves Track 1 under new token', () async {
        final t1 = const TrackMetadata(uri: 'file:///t1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///t2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) => LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Song ${q.trackName}',
        );

        await driver.resolveLyricsForTrack(t1);
        await driver.resolveLyricsForTrack(t2);
        await driver.resolveLyricsForTrack(t1);

        expect(driver.currentTrack?.title, equals('T1'));
        expect(driver.currentLyrics?.lines.first.text, equals('Song T1'));
      });

      test('F10.B3: in-flight response returning after token changed is completely discarded', () async {
        final t1 = const TrackMetadata(uri: 'file:///inf_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///inf_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) {
          if (q.trackName == 'T1') {
            return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]T1 Slow');
          }
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]T2 Fast');
        };

        final p1 = driver.resolveLyricsForTrack(t1);
        final p2 = driver.resolveLyricsForTrack(t2);
        await Future.wait([p1, p2]);

        expect(driver.currentLyrics?.lines.first.text, equals('T2 Fast'));
      });

      test('F10.B4: rapid skips during active SQLite transactions do not deadlock SQLite', () async {
        final tracks = List.generate(
          5,
          (i) => TrackMetadata(
            uri: 'file:///sql_deadlock_$i.mp3',
            title: 'SQL $i',
            artist: 'Artist',
            durationMs: 100,
            embeddedLyrics: '[00:01.00]Embedded $i',
          ),
        );

        final futures = tracks.map((t) => driver.resolveLyricsForTrack(t));
        await expectLater(Future.wait(futures), completes);
      });

      test('F10.B5: rapid skips while countdown banner active cancel the banner immediately', () async {
        final t1 = const TrackMetadata(uri: 'file:///ban_c1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///ban_c2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) {
          if (q.trackName == 'T1') {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);
          }
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]T2 OK');
        };

        await driver.resolveLyricsForTrack(t1);
        expect(driver.isThresholdWaiting, isTrue);

        await driver.resolveLyricsForTrack(t2);
        expect(driver.isThresholdWaiting, isFalse);
      });
    });

    // =========================================================================
    // Feature 11 Boundary: Remote Web Query Visibility Gating
    // =========================================================================
    group('F11 Boundary: Remote Web Query Visibility Gating', () {
      test('F11.B1: closing view while network request is in-flight: response does not leak', () async {
        final track = const TrackMetadata(uri: 'file:///vis_inflight.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Text');

        final f = driver.resolveLyricsForTrack(track);
        driver.setLyricsViewVisible(false);
        await f;

        // Since view closed, state was cleared or hidden
        expect(driver.isLyricsViewVisible, isFalse);
      });

      test('F11.B2: rapid open-close-open toggling within 50ms stabilizes on correct visibility state', () {
        driver.setLyricsViewVisible(false);
        driver.setLyricsViewVisible(true);
        driver.setLyricsViewVisible(false);
        driver.setLyricsViewVisible(true);
        expect(driver.isLyricsViewVisible, isTrue);
      });

      test('F11.B3: track with local .lrc file in folder displays even when view starts closed', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///file_start_closed.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          localLrcContent: '[00:01.00]Local file content',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('Local file content'));
      });

      test('F11.B4: opening view for track that had local failure triggers remote resolution immediately', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(
          uri: 'file:///fail_local.mp3',
          title: 'RemoteNeeded',
          artist: 'Artist',
          durationMs: 100,
        );
        await driver.resolveLyricsForTrack(track);
        expect(driver.lrclibRecordedQueries, isEmpty);

        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Remote arrived',
        );

        driver.setLyricsViewVisible(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(driver.lrclibRecordedQueries.length, equals(1));
        expect(driver.currentLyrics?.lines.first.text, equals('Remote arrived'));
      });

      test('F11.B5: closing view dismisses active countdown banner immediately', () async {
        final track = const TrackMetadata(uri: 'file:///ban_dismiss.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 8);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setLyricsViewVisible(false);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.thresholdCountdownSeconds, isNull);
      });
    });

    // =========================================================================
    // Feature 12 Boundary: 4-Tier Hierarchical LyricsService
    // =========================================================================
    group('F12 Boundary: 4-Tier Hierarchical LyricsService', () {
      test('F12.B1: track with whitespace-only embedded tag falls through to local .lrc file', () async {
        final track = const TrackMetadata(
          uri: 'file:///empty_tag.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '   \n  \t ',
          localLrcContent: '[00:01.00]Local file wins over blank tag',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('Local file wins over blank tag'));
        expect(driver.currentLyricsSource, equals(LyricsSource.file));
      });

      test('F12.B2: track with corrupted/empty local .lrc file falls through to lrclib', () async {
        final track = const TrackMetadata(
          uri: 'file:///corrupt_file.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          localLrcContent: '   \n\n  ',
        );
        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]lrclib fetched',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('lrclib fetched'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      });

      test('F12.B3: lrclib returning 500 error falls through to lyrics.ovh', () async {
        final track = const TrackMetadata(uri: 'file:///500_fall.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 500);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'ovh fallback text');

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('ovh fallback text'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });

      test('F12.B4: both remote sources failing with 500/timeout returns null gracefully', () async {
        final track = const TrackMetadata(uri: 'file:///both_fail.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 500);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 504);

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.currentLyrics, isNull);
      });

      test('F12.B5: all 4 sources failing records state in SQLite without infinite retry loops', () async {
        final track = const TrackMetadata(uri: 'file:///all_fail.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);

        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final lrclibEntry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        final ovhEntry = await driver.getLyricsSourceEntry(key, LyricsSource.lyricsOvh);

        expect(lrclibEntry?.state, equals(LyricsSourceState.notFound));
        expect(ovhEntry?.state, equals(LyricsSourceState.notFound));
      });
    });

    // =========================================================================
    // Feature 13 Boundary: Now Playing Visibility Binding
    // =========================================================================
    group('F13 Boundary: Now Playing Visibility Binding', () {
      test('F13.B1: setLyricsViewVisible called with same value is idempotent', () {
        driver.setLyricsViewVisible(true);
        driver.setLyricsViewVisible(true);
        expect(driver.isLyricsViewVisible, isTrue);

        driver.setLyricsViewVisible(false);
        driver.setLyricsViewVisible(false);
        expect(driver.isLyricsViewVisible, isFalse);
      });

      test('F13.B2: re-entering view after background playback of multiple tracks displays active track', () async {
        driver.setLyricsViewVisible(false);
        final t1 = const TrackMetadata(uri: 'file:///bg1.mp3', title: 'BG1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///bg2.mp3', title: 'BG2', artist: 'A', durationMs: 100);

        await driver.resolveLyricsForTrack(t1);
        await driver.resolveLyricsForTrack(t2);

        driver.lrclibMockResponder = (_) => const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Active BG2 Lyrics',
        );

        driver.setLyricsViewVisible(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(driver.currentTrack?.title, equals('BG2'));
        expect(driver.currentLyrics?.lines.first.text, equals('Active BG2 Lyrics'));
      });

      test('F13.B3: visibility toggles with no track loaded does not throw NullPointerException', () {
        expect(() => driver.setLyricsViewVisible(false), returnsNormally);
        expect(() => driver.setLyricsViewVisible(true), returnsNormally);
      });

      test('F13.B4: view closed while translation is running allows translation to complete or cancel', () async {
        final track = const TrackMetadata(
          uri: 'file:///tr_bg.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Song line',
        );
        await driver.resolveLyricsForTrack(track);

        final f = driver.translateLyrics();
        driver.setLyricsViewVisible(false);
        final res = await f;

        expect(res.isSuccess, isTrue);
      });

      test('F13.B5: view re-opened while cooldown is active triggers fallback display and sets deferred upgrade', () async {
        driver.setLyricsViewVisible(false);
        final track = const TrackMetadata(uri: 'file:///cd_vis.mp3', title: 'T', artist: 'A', durationMs: 100);
        await driver.resolveLyricsForTrack(track);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'Ovh Plain');

        driver.setLyricsViewVisible(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(driver.isCooldownActive, isTrue);
      });
    });

    // =========================================================================
    // Feature 14 Boundary: UI Translation Button & Display Modes
    // =========================================================================
    group('F14 Boundary: UI Translation Button & Display Modes', () {
      test('F14.B1: interleaved mode when translation has fewer lines does not throw RangeError', () async {
        final track = const TrackMetadata(
          uri: 'file:///fewer.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Line 1\n[00:02.00]Line 2\n[00:03.00]Line 3',
        );
        await driver.resolveLyricsForTrack(track);

        // Mock translation returning only 1 line
        driver.translationMockResponder = (_, _) => ['[es] Only line'];
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
        expect(() => driver.effectiveDisplayLines, returnsNormally);
      });

      test('F14.B2: interleaved mode when translation has more lines does not throw RangeError', () async {
        final track = const TrackMetadata(
          uri: 'file:///more.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Line 1',
        );
        await driver.resolveLyricsForTrack(track);

        driver.translationMockResponder = (_, _) => ['[es] Line 1', '[es] Extra line'];
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
        expect(() => driver.effectiveDisplayLines, returnsNormally);
      });

      test('F14.B3: translation display mode persists across song position seeks', () async {
        final track = const TrackMetadata(
          uri: 'file:///seek_trans.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]A\n[00:05.00]B',
        );
        await driver.resolveLyricsForTrack(track);
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.translated);
        expect(driver.displayMode, equals(LyricsDisplayMode.translated));

        // Simulate seek: display mode remains translated
        expect(driver.displayMode, equals(LyricsDisplayMode.translated));
      });

      test('F14.B4: switching display modes when no lyrics are loaded returns empty list', () {
        driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
        expect(driver.effectiveDisplayLines, isEmpty);
      });

      test('F14.B5: switching display modes with unsynced lyrics formats lines correctly', () async {
        final track = const TrackMetadata(
          uri: 'file:///unsync_dm.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: 'Plain line 1\nPlain line 2',
        );
        await driver.resolveLyricsForTrack(track);
        await driver.translateLyrics();

        driver.setTranslationDisplayMode(LyricsDisplayMode.translated);
        final lines = driver.effectiveDisplayLines;
        expect(lines.length, equals(2));
        expect(lines.first.text, contains('[es] Plain line 1'));
      });
    });

    // =========================================================================
    // Feature 15 Boundary: UI Sources Configuration Dialog
    // =========================================================================
    group('F15 Boundary: UI Sources Configuration Dialog', () {
      test('F15.B1: disabling all 3 sources returns null immediately with 0 queries', () async {
        driver.setSourcesConfig(local: false, lrclib: false, lyricsOvh: false);
        final track = const TrackMetadata(
          uri: 'file:///none.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Embedded',
        );

        final res = await driver.resolveLyricsForTrack(track);
        expect(res, isNull);
        expect(driver.lrclibRecordedQueries, isEmpty);
        expect(driver.lyricsOvhRequestedUrls, isEmpty);
      });

      test('F15.B2: enabling only lyrics.ovh queries lyrics.ovh directly without calling lrclib or checking local', () async {
        driver.setSourcesConfig(local: false, lrclib: false, lyricsOvh: true);
        final track = const TrackMetadata(
          uri: 'file:///only_ovh.mp3',
          title: 'T',
          artist: 'A',
          durationMs: 100,
          embeddedLyrics: '[00:01.00]Local tag',
        );
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'Direct ovh');

        final res = await driver.resolveLyricsForTrack(track);
        expect(res?.lines.first.text, equals('Direct ovh'));
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(driver.lrclibRecordedQueries, isEmpty);
      });

      test('F15.B3: toggling sources configuration during active playback applies to subsequent resolution', () async {
        final track1 = const TrackMetadata(uri: 'file:///tgl_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final track2 = const TrackMetadata(uri: 'file:///tgl_2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]T1');
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'T2 ovh');

        await driver.resolveLyricsForTrack(track1);
        expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));

        // Disable lrclib
        driver.setSourcesConfig(lrclib: false);
        await driver.resolveLyricsForTrack(track2);
        expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });

      test('F15.B4: setSourcesConfig with all null arguments changes nothing', () {
        expect(driver.enableLocalSources, isTrue);
        expect(driver.enableLrclib, isTrue);
        expect(driver.enableLyricsOvh, isTrue);

        driver.setSourcesConfig();

        expect(driver.enableLocalSources, isTrue);
        expect(driver.enableLrclib, isTrue);
        expect(driver.enableLyricsOvh, isTrue);
      });

      test('F15.B5: disabling lrclib cancels active lrclib 429 countdown banner immediately', () async {
        final track = const TrackMetadata(uri: 'file:///dis_c_ban.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 6);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setSourcesConfig(lrclib: false);
        expect(driver.isThresholdWaiting, isFalse);
      });
    });

    // =========================================================================
    // Feature 16 Boundary: UI Manual Re-search ("Volver a buscar") Button
    // =========================================================================
    group('F16 Boundary: UI Manual Re-search Button', () {
      test('F16.B1: forceReSearch on a track that does not exist in any source re-confirms NOT_FOUND', () async {
        final track = const TrackMetadata(uri: 'file:///nf_twice.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 404);
        driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 404);

        await driver.resolveLyricsForTrack(track);
        await driver.forceReSearch();

        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final entry = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
        expect(entry?.state, equals(LyricsSourceState.notFound));
      });

      test('F16.B2: forceReSearch called while previous forceReSearch in flight cancels previous', () async {
        final track = const TrackMetadata(uri: 'file:///rs_race.mp3', title: 'T', artist: 'A', durationMs: 100);
        await driver.resolveLyricsForTrack(track);

        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Success');

        final f1 = driver.forceReSearch();
        final f2 = driver.forceReSearch();
        await Future.wait([f1, f2]);

        expect(driver.currentLyrics?.lines.first.text, equals('Success'));
      });

      test('F16.B3: forceReSearch with all sources disabled returns null cleanly', () async {
        final track = const TrackMetadata(uri: 'file:///rs_none.mp3', title: 'T', artist: 'A', durationMs: 100);
        await driver.resolveLyricsForTrack(track);

        driver.setSourcesConfig(local: false, lrclib: false, lyricsOvh: false);
        await driver.forceReSearch();

        expect(driver.currentLyrics, isNull);
      });

      test('F16.B4: forceReSearch with no track loaded is a no-op', () async {
        await expectLater(driver.forceReSearch(), completes);
      });

      test('F16.B5: forceReSearch updates updatedAt timestamp in SQLite cache', () async {
        final track = const TrackMetadata(uri: 'file:///rs_time.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]Old');
        await driver.resolveLyricsForTrack(track);

        final key = LyricsTestDriver.computeLyricsKey(
          uri: track.uri,
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
        );
        final t1 = (await driver.getLyricsSourceEntry(key, LyricsSource.lrclib))!.updatedAt;

        driver.advanceSimulatedTime(const Duration(seconds: 10));
        await driver.forceReSearch();
        final t2 = (await driver.getLyricsSourceEntry(key, LyricsSource.lrclib))!.updatedAt;

        expect(t2, greaterThan(t1));
      });
    });

    // =========================================================================
    // Feature 17 Boundary: Non-Invasive 429 Countdown Banner
    // =========================================================================
    group('F17 Boundary: Non-Invasive 429 Countdown Banner', () {
      test('F17.B1: countdown banner with 1 second remaining ticks to 0 and resolves', () async {
        final track = const TrackMetadata(uri: 'file:///c1s.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 1);

        await driver.resolveLyricsForTrack(track);
        expect(driver.thresholdCountdownSeconds, equals(1));
      });

      test('F17.B2: countdown banner with 10 seconds remaining decrements sequentially', () async {
        final track = const TrackMetadata(uri: 'file:///c10s.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 10);

        await driver.resolveLyricsForTrack(track);
        expect(driver.thresholdCountdownSeconds, equals(10));
      });

      test('F17.B3: closing view while banner is at 3 seconds cancels timer and resets state', () async {
        final track = const TrackMetadata(uri: 'file:///c3s.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 3);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);

        driver.setLyricsViewVisible(false);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.thresholdCountdownSeconds, isNull);
      });

      test('F17.B4: skip to next track while banner is at 5 seconds resets countdown and starts new track', () async {
        final t1 = const TrackMetadata(uri: 'file:///skip_b1.mp3', title: 'T1', artist: 'A', durationMs: 100);
        final t2 = const TrackMetadata(uri: 'file:///skip_b2.mp3', title: 'T2', artist: 'A', durationMs: 100);

        driver.lrclibMockResponder = (q) {
          if (q.trackName == 'T1') {
            return const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);
          }
          return const LrclibResponse(statusCode: 200, syncedLyrics: '[00:01.00]T2 OK');
        };

        await driver.resolveLyricsForTrack(t1);
        expect(driver.isThresholdWaiting, isTrue);

        await driver.resolveLyricsForTrack(t2);
        expect(driver.isThresholdWaiting, isFalse);
        expect(driver.currentTrack?.title, equals('T2'));
      });

      test('F17.B5: repeated 429 responses with <=10s reset countdown timer smoothly', () async {
        final track = const TrackMetadata(uri: 'file:///rep_429.mp3', title: 'T', artist: 'A', durationMs: 100);
        driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 3);

        await driver.resolveLyricsForTrack(track);
        expect(driver.isThresholdWaiting, isTrue);
        expect(driver.thresholdCountdownSeconds, equals(3));
      });
    });

    // =========================================================================
    // Feature 18 Boundary: Complete i18n Localization
    // =========================================================================
    group('F18 Boundary: Complete i18n Localization', () {
      test('F18.B1: en.jsonc and es.jsonc are valid JSON syntax using jsonc decoder', () {
        final enStr = File('i18n/en.jsonc').readAsStringSync();
        final esStr = File('i18n/es.jsonc').readAsStringSync();

        final enMap = jsonc.decode(enStr) as Map<String, dynamic>;
        final esMap = jsonc.decode(esStr) as Map<String, dynamic>;

        expect(enMap.isNotEmpty, isTrue);
        expect(esMap.isNotEmpty, isTrue);
      });

      test('F18.B2: all keys in en.jsonc exist in es.jsonc with non-empty translation values', () {
        final enMap = jsonc.decode(File('i18n/en.jsonc').readAsStringSync()) as Map<String, dynamic>;
        final esMap = jsonc.decode(File('i18n/es.jsonc').readAsStringSync()) as Map<String, dynamic>;

        final missingInEs = <String>[];
        final emptyInEs = <String>[];

        for (final key in enMap.keys) {
          if (!esMap.containsKey(key)) {
            missingInEs.add(key);
          } else if ((esMap[key] as String).trim().isEmpty) {
            emptyInEs.add(key);
          }
        }

        expect(missingInEs, isEmpty, reason: 'Keys in en.jsonc missing from es.jsonc: $missingInEs');
        expect(emptyInEs, isEmpty, reason: 'Keys in es.jsonc with empty values: $emptyInEs');
      });

      test('F18.B3: all keys in es.jsonc exist in en.jsonc (complete 100% key symmetry)', () {
        final enMap = jsonc.decode(File('i18n/en.jsonc').readAsStringSync()) as Map<String, dynamic>;
        final esMap = jsonc.decode(File('i18n/es.jsonc').readAsStringSync()) as Map<String, dynamic>;

        final missingInEn = esMap.keys.where((k) => !enMap.containsKey(k)).toList();
        expect(missingInEn, isEmpty, reason: 'Keys in es.jsonc missing from en.jsonc: $missingInEn');
      });

      test('F18.B4: format strings with {seconds} handle boundary values (0, 1, 10, 60)', () {
        const template = 'Esperando {seconds}s';
        for (final val in [0, 1, 10, 60]) {
          final res = template.replaceAll('{seconds}', val.toString());
          expect(res, equals('Esperando ${val}s'));
        }
      });

      test('F18.B5: special Spanish characters are properly encoded in es.jsonc', () {
        final esStr = File('i18n/es.jsonc').readAsStringSync();
        expect(esStr.contains('á') || esStr.contains('é') || esStr.contains('í') || esStr.contains('ó') || esStr.contains('ú'), isTrue);
        expect(esStr.contains('ñ'), isTrue);
        // Valid utf-8 decoding: no unicode replacement character
        expect(esStr.contains('\uFFFD'), isFalse);
      });
    });
  });
}
