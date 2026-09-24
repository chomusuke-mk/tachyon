import 'package:flutter_test/flutter_test.dart';

import 'harness/lyrics_e2e_models.dart';
import 'harness/lyrics_test_driver.dart';

void main() {
  group('Tier 4: Real-World End-to-End Application Scenarios', () {
    late LyricsTestDriver driver;

    setUp(() {
      driver = LyricsTestDriver();
    });

    tearDown(() async {
      await driver.dispose();
    });

    // =========================================================================
    // Scenario 1: Full Happy Path
    // =========================================================================
    test('Scenario 1: Full Happy Path - Track plays with open Now Playing -> fetched from lrclib.net -> synced lyrics displayed', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/queen_bohemian_rhapsody.flac',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        durationMs: 354000,
      );

      // Verify UI is visible
      expect(driver.isLyricsViewVisible, isTrue);

      driver.lrclibMockResponder = (query) {
        expect(query.trackName, equals('Bohemian Rhapsody'));
        expect(query.artistName, equals('Queen'));
        expect(query.albumName, equals('A Night at the Opera'));
        expect(query.durationSeconds, equals(354));
        return const LrclibResponse(
          statusCode: 200,
          trackName: 'Bohemian Rhapsody',
          artistName: 'Queen',
          duration: 354.0,
          syncedLyrics: '[00:00.93]Is this the real life?\n[00:04.50]Is this just fantasy?\n[00:08.20]Caught in a landslide',
          plainLyrics: 'Is this the real life?\nIs this just fantasy?\nCaught in a landslide',
        );
      };

      final lyrics = await driver.playTrack(track);

      // 1. Verify lyrics returned and parsed
      expect(lyrics, isNotNull);
      expect(lyrics!.isSynced, isTrue);
      expect(lyrics.lines.length, equals(3));
      expect(lyrics.lines[0].text, equals('Is this the real life?'));
      expect(lyrics.lines[0].timestampMs, equals(930));

      // 2. Verify state on driver
      expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(driver.currentLyrics, equals(lyrics));

      // 3. Verify SQLite persistence
      final keyHash = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final dbEntry = await driver.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(dbEntry, isNotNull);
      expect(dbEntry!.state, equals(LyricsSourceState.found));
      expect(dbEntry.isSynced, isTrue);
      expect(dbEntry.rawLrc, contains('Is this the real life?'));

      // 4. Verify request pacing recorded
      expect(driver.lrclibRequestTimestamps.length, equals(1));
    });

    // =========================================================================
    // Scenario 2: Offline / Local First
    // =========================================================================
    test('Scenario 2: Offline/Local First - Track with embedded USLT tag plays -> instant display without web calls', () async {
      const embeddedLrc = '[00:01.00]Local embedded line 1\n[00:05.00]Local embedded line 2';
      final track = const TrackMetadata(
        uri: 'file:///music/daft_punk_get_lucky.mp3',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        album: 'Random Access Memories',
        durationMs: 248000,
        embeddedLyrics: embeddedLrc,
      );

      // In offline mode or local-first, web clients should not be invoked
      driver.lrclibMockResponder = (_) => throw StateError('Web API should not be called when embedded tags exist');
      driver.lyricsOvhMockResponder = (_, _) => throw StateError('Secondary API should not be called');

      final sw = Stopwatch()..start();
      final lyrics = await driver.playTrack(track);
      sw.stop();

      // 1. Verify instant resolution without network delay
      expect(lyrics, isNotNull);
      expect(lyrics!.isSynced, isTrue);
      expect(lyrics.lines.length, equals(2));
      expect(lyrics.lines[0].text, equals('Local embedded line 1'));
      expect(sw.elapsedMilliseconds, lessThan(100));

      // 2. Verify source marked as embedded
      expect(driver.currentLyricsSource, equals(LyricsSource.embedded));

      // 3. Verify 0 web requests made
      expect(driver.lrclibRecordedQueries, isEmpty);
      expect(driver.lyricsOvhRequestedUrls, isEmpty);

      // 4. Verify SQLite recorded embedded source
      final keyHash = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final dbEntry = await driver.getLyricsSourceEntry(keyHash, LyricsSource.embedded);
      expect(dbEntry, isNotNull);
      expect(dbEntry!.state, equals(LyricsSourceState.found));
    });

    // =========================================================================
    // Scenario 3: Contiguous .lrc Fallback
    // =========================================================================
    test('Scenario 3: Contiguous .lrc Fallback - External .lrc file in folder loaded before web APIs', () async {
      const contiguousFileLrc = '[00:02.00]Contiguous file verse 1\n[00:06.00]Contiguous file verse 2';
      final track = const TrackMetadata(
        uri: 'file:///music/pink_floyd_time.flac',
        title: 'Time',
        artist: 'Pink Floyd',
        durationMs: 425000,
        embeddedLyrics: null, // No embedded tags
        localLrcContent: contiguousFileLrc, // Contiguous <track>.lrc exists
      );

      driver.lrclibMockResponder = (_) => throw StateError('Web APIs should not be queried when local .lrc exists');

      final lyrics = await driver.playTrack(track);

      expect(lyrics, isNotNull);
      expect(lyrics!.lines.first.text, equals('Contiguous file verse 1'));
      expect(driver.currentLyricsSource, equals(LyricsSource.file));

      // Verify no web requests dispatched
      expect(driver.lrclibRecordedQueries, isEmpty);

      final keyHash = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final dbEntry = await driver.getLyricsSourceEntry(keyHash, LyricsSource.file);
      expect(dbEntry?.state, equals(LyricsSourceState.found));
    });

    // =========================================================================
    // Scenario 4: 404 Caching
    // =========================================================================
    test('Scenario 4: 404 Caching - lrclib returns 404 -> lyrics.ovh returns plain lyrics -> next play skips lrclib', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/rare_indie_track.mp3',
        title: 'Rare Indie Track',
        artist: 'Indie Band',
        durationMs: 195000,
      );

      int lrclibCallCount = 0;
      int ovhCallCount = 0;

      driver.lrclibMockResponder = (_) {
        lrclibCallCount++;
        return const LrclibResponse(statusCode: 404);
      };
      driver.lyricsOvhMockResponder = (artist, title) {
        ovhCallCount++;
        return const LyricsOvhResponse(
          statusCode: 200,
          lyrics: 'Indie lyrics verse 1\nIndie lyrics verse 2',
        );
      };

      // Play Track First Time
      final firstPlayLyrics = await driver.playTrack(track);
      expect(firstPlayLyrics, isNotNull);
      expect(firstPlayLyrics!.isSynced, isFalse);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(lrclibCallCount, equals(1));
      expect(ovhCallCount, equals(1));

      // Verify SQLite state: lrclib is NOT_FOUND, lyricsOvh is FOUND
      final keyHash = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final lrclibDb = await driver.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      final ovhDb = await driver.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
      expect(lrclibDb?.state, equals(LyricsSourceState.notFound));
      expect(ovhDb?.state, equals(LyricsSourceState.found));

      // Play Track Second Time: should skip lrclib entirely and load cached ovh lyrics from DB
      final secondPlayLyrics = await driver.playTrack(track);
      expect(secondPlayLyrics, isNotNull);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      // lrclib was NOT queried again!
      expect(lrclibCallCount, equals(1));
      // ovh was NOT queried again either (cached in DB)!
      expect(ovhCallCount, equals(1));
    });

    // =========================================================================
    // Scenario 5: Short 429 Threshold
    // =========================================================================
    test('Scenario 5: Short 429 Threshold - lrclib returns 429 Retry-After: 3s -> countdown banner -> auto-retry succeeds', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/rate_limited_track.mp3',
        title: 'Rate Limited Track',
        artist: 'Popular Artist',
        durationMs: 210000,
      );

      int lrclibCalls = 0;
      driver.lrclibMockResponder = (_) {
        lrclibCalls++;
        if (lrclibCalls == 1) {
          return const LrclibResponse(
            statusCode: 429,
            retryAfterSeconds: 2,
          );
        }
        return const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Success after 429 threshold',
        );
      };

      // 1. Play track
      await driver.playTrack(track);

      // 2. Banner activated with countdown
      expect(driver.isThresholdWaiting, isTrue);
      expect(driver.thresholdCountdownSeconds, equals(2));
      expect(driver.currentLyrics, isNull);

      // 3. Wait for countdown (2s) to expire and auto-retry
      await Future.delayed(const Duration(milliseconds: 2400));

      // 4. Verify auto-retry completed successfully
      expect(driver.isThresholdWaiting, isFalse);
      expect(driver.thresholdCountdownSeconds, isNull);
      expect(lrclibCalls, equals(2));
      expect(driver.currentLyrics, isNotNull);
      expect(driver.currentLyrics?.lines.first.text, equals('Success after 429 threshold'));
    });

    // =========================================================================
    // Scenario 6: Long 429 Fallback & Deferred Upgrade
    // =========================================================================
    test('Scenario 6: Long 429 Fallback & Deferred Upgrade - 429 Retry-After: 60s -> fallback to lyrics.ovh -> cooldown expires -> auto-upgrades to lrclib synced', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/long_cooldown_track.mp3',
        title: 'Long Cooldown Track',
        artist: 'Major Artist',
        durationMs: 200000,
      );

      int lrclibCalls = 0;
      driver.lrclibMockResponder = (_) {
        lrclibCalls++;
        if (lrclibCalls == 1) {
          return const LrclibResponse(
            statusCode: 429,
            retryAfterSeconds: 60, // Long cooldown (e.g. 1 min)
          );
        }
        return const LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Synced lyrics after cooldown expired',
        );
      };
      driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
        statusCode: 200,
        lyrics: 'Plain lyrics fallback during cooldown',
      );

      // 1. Initial play: triggers long 429 and falls back immediately to lyrics.ovh
      final initialLyrics = await driver.playTrack(track);
      expect(initialLyrics, isNotNull);
      expect(initialLyrics!.isSynced, isFalse);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(driver.isCooldownActive, isTrue);
      expect(driver.isThresholdWaiting, isFalse); // No 429 banner for long cooldown

      // 2. Cooldown expires while user is still playing this song
      await driver.expireCooldownAndTriggerUpgrade();

      // 3. User automatically gets upgraded to synced lyrics from lrclib!
      expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(driver.currentLyrics?.isSynced, isTrue);
      expect(driver.currentLyrics?.lines.first.text, equals('Synced lyrics after cooldown expired'));
      expect(lrclibCalls, equals(2));
    });

    // =========================================================================
    // Scenario 7: Rapid Skip Burst
    // =========================================================================
    test('Scenario 7: Rapid Skip Burst - User jumps 1 -> 2 -> 3 -> 4 -> 5 -> only track 5 queries network; no 429', () async {
      final playlist = List.generate(
        5,
        (i) => TrackMetadata(
          uri: 'file:///music/track_${i + 1}.mp3',
          title: 'Track ${i + 1}',
          artist: 'Artist',
          durationMs: 180000,
        ),
      );

      final lrclibQueries = <String>[];
      driver.lrclibMockResponder = (query) {
        lrclibQueries.add(query.trackName);
        return LrclibResponse(
          statusCode: 200,
          syncedLyrics: '[00:01.00]Lyrics for ${query.trackName}',
        );
      };

      // User skips rapidly across tracks 1, 2, 3, 4, 5
      final p1 = driver.playTrack(playlist[0]);
      final p2 = driver.playTrack(playlist[1]);
      final p3 = driver.playTrack(playlist[2]);
      final p4 = driver.playTrack(playlist[3]);
      final p5 = driver.playTrack(playlist[4]);
      await Future.wait([p1, p2, p3, p4, p5]);

      // Only the final track (track 5) lyrics should be visible!
      expect(driver.currentTrack?.title, equals('Track 5'));
      expect(driver.currentLyrics?.lines.first.text, equals('Lyrics for Track 5'));
    });

    // =========================================================================
    // Scenario 8: Background Playback Suppression
    // =========================================================================
    test('Scenario 8: Background Playback Suppression - Track plays while Now Playing is closed -> web APIs never queried', () async {
      // 1. User closes Now Playing screen
      driver.setLyricsViewVisible(false);

      final track = const TrackMetadata(
        uri: 'file:///music/bg_track.mp3',
        title: 'Background Track',
        artist: 'Artist',
        durationMs: 240000,
      );

      driver.lrclibMockResponder = (_) => throw StateError('Should never query web in background');

      // Track plays in background
      final bgResult = await driver.playTrack(track);
      expect(bgResult, isNull);
      expect(driver.lrclibRecordedQueries, isEmpty);

      // 2. Later, user taps player bar and opens Now Playing
      driver.lrclibMockResponder = (_) => const LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]Now Playing Opened Lyrics',
      );

      driver.setLyricsViewVisible(true);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.currentLyrics, isNotNull);
      expect(driver.currentLyrics?.lines.first.text, equals('Now Playing Opened Lyrics'));
      expect(driver.lrclibRecordedQueries.length, equals(1));
    });

    // =========================================================================
    // Scenario 9: Translation Flow
    // =========================================================================
    test('Scenario 9: Translation Flow - User clicks translate -> fetched via free endpoint -> interleaved display', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/japanese_song.mp3',
        title: 'Japanese Song',
        artist: 'J-Pop Artist',
        durationMs: 200000,
        embeddedLyrics: '[00:01.00]こんにちは\n[00:05.00]さようなら',
      );

      await driver.playTrack(track);
      expect(driver.currentLyrics?.lines.length, equals(2));
      expect(driver.displayMode, equals(LyricsDisplayMode.original));

      // User clicks Translation button
      driver.translationMockResponder = (batch, targetLang) {
        expect(targetLang, equals('es'));
        return ['Hola', 'Adiós'];
      };

      final transResult = await driver.translateLyrics(targetLanguage: 'es');
      expect(transResult.isSuccess, isTrue);

      // User sets display mode to Interleaved
      driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
      final displayLines = driver.effectiveDisplayLines;

      expect(displayLines.length, equals(4));
      expect(displayLines[0].text, equals('こんにちは'));
      expect(displayLines[1].text, equals('Hola'));
      expect(displayLines[2].text, equals('さようなら'));
      expect(displayLines[3].text, equals('Adiós'));
    });

    // =========================================================================
    // Scenario 10: Source Disabling & Re-search
    // =========================================================================
    test('Scenario 10: Source Disabling & Re-search - User disables web sources in dialog -> clicks re-search -> only local checked', () async {
      final track = const TrackMetadata(
        uri: 'file:///music/local_only_pref.mp3',
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        localLrcContent: '[00:01.00]Local file only',
      );

      // Initial play: with all sources enabled
      driver.lrclibMockResponder = (_) => const LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]lrclib lyrics',
      );
      await driver.playTrack(track);
      expect(driver.currentLyrics?.lines.first.text, equals('Local file only'));

      // User opens Sources Dialog and disables web sources (lrclib and lyricsOvh)
      driver.setSourcesConfig(local: true, lrclib: false, lyricsOvh: false);
      expect(driver.enableLrclib, isFalse);
      expect(driver.enableLyricsOvh, isFalse);

      // User clicks "Volver a buscar" (force re-search)
      driver.lrclibMockResponder = (_) => throw StateError('lrclib was queried despite being disabled');
      driver.lyricsOvhMockResponder = (_, _) => throw StateError('lyrics.ovh was queried despite being disabled');

      await driver.forceReSearch();

      expect(driver.currentLyrics?.lines.first.text, equals('Local file only'));
      expect(driver.currentLyricsSource, equals(LyricsSource.file));
    });
  });
}
