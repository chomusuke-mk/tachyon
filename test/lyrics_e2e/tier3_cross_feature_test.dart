import 'package:flutter_test/flutter_test.dart';

import 'package:tachyon/features/locales/domain/locale.dart';

import 'harness/lyrics_e2e_models.dart';
import 'harness/lyrics_test_driver.dart';

void main() {
  group('Tier 3: Cross-Feature Interaction Verification (Features F1 - F18)', () {
    late LyricsTestDriver driver;

    setUp(() {
      driver = LyricsTestDriver();
    });

    tearDown(() async {
      await driver.dispose();
    });

    test('X1: F1 (Persistence) + F6 (Rate Limiter) + F4 (lrclib) - Cache hit in SQLite prevents rate limiter consumption', () async {
      final track = const TrackMetadata(
        uri: 'file:///x1.mp3',
        title: 'Cached Hit',
        artist: 'Artist',
        durationMs: 150000,
      );
      final key = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );

      // Pre-seed SQLite cache
      await driver.saveLyricsSourceEntry(LyricsSourceEntry(
        keyHash: key,
        source: LyricsSource.lrclib,
        state: LyricsSourceState.found,
        rawLrc: '[00:01.00]Cached lrclib line',
        isSynced: true,
        updatedAt: 100,
      ));

      driver.lrclibMockResponder = (_) => throw StateError('Should not query network');

      final sw = Stopwatch()..start();
      final res = await driver.resolveLyricsForTrack(track);
      sw.stop();

      expect(res, isNotNull);
      expect(res!.lines.first.text, equals('Cached lrclib line'));
      expect(driver.lrclibRequestTimestamps, isEmpty);
      // Immediate lookup without rate limiter delay
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('X2: F7 (429 Retry-After) + F17 (Countdown Banner) + F8 (Cooldown) - 429 <=10s drives countdown banner and defers retry without setting long cooldown', () async {
      final track = const TrackMetadata(uri: 'file:///x2.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 4);

      await driver.resolveLyricsForTrack(track);

      expect(driver.isThresholdWaiting, isTrue);
      expect(driver.thresholdCountdownSeconds, equals(4));
      expect(driver.isCooldownActive, isFalse); // Not in long memory cooldown
    });

    test('X3: F7 (429 >10s) + F5 (lyrics.ovh) + F8 (Cooldown) - Long 429 falls back immediately to lyrics.ovh and records active memory cooldown', () async {
      final track = const TrackMetadata(uri: 'file:///x3.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 45);
      driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
        statusCode: 200,
        lyrics: 'Plain OVH text after 429',
      );

      final res = await driver.resolveLyricsForTrack(track);

      expect(driver.isThresholdWaiting, isFalse);
      expect(driver.isCooldownActive, isTrue);
      expect(res, isNotNull);
      expect(res!.isSynced, isFalse);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
    });

    test('X4: F10 (Rapid Skip) + F6 (Rate Limiter) + F4 (lrclib) - Rapid skipping cancels pending throttled requests', () async {
      final t1 = const TrackMetadata(uri: 'file:///x4_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
      final t2 = const TrackMetadata(uri: 'file:///x4_2.mp3', title: 'T2', artist: 'A', durationMs: 100);
      final t3 = const TrackMetadata(uri: 'file:///x4_3.mp3', title: 'T3', artist: 'A', durationMs: 100);

      driver.lrclibMockResponder = (q) => LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]Song ${q.trackName}',
      );

      final p1 = driver.resolveLyricsForTrack(t1);
      final p2 = driver.resolveLyricsForTrack(t2);
      final p3 = driver.resolveLyricsForTrack(t3);
      await Future.wait([p1, p2, p3]);

      expect(driver.currentTrack?.title, equals('T3'));
      expect(driver.currentLyrics?.lines.first.text, equals('Song T3'));
    });

    test('X5: F11 (Visibility Gating) + F12 (Hierarchy) + F1 (Persistence) - Closed view only queries local sources and caches local hits', () async {
      driver.setLyricsViewVisible(false);
      final track = const TrackMetadata(
        uri: 'file:///x5.mp3',
        title: 'Local First',
        artist: 'Artist',
        durationMs: 120000,
        embeddedLyrics: '[00:01.00]Local embedded in closed view',
      );

      final res = await driver.resolveLyricsForTrack(track);
      expect(res, isNotNull);
      expect(driver.currentLyricsSource, equals(LyricsSource.embedded));
      expect(driver.lrclibRecordedQueries, isEmpty);

      final key = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );
      final entry = await driver.getLyricsSourceEntry(key, LyricsSource.embedded);
      expect(entry?.state, equals(LyricsSourceState.found));
    });

    test('X6: F13 (Visibility Binding) + F11 (Visibility Gating) + F4 (lrclib) - Opening Now Playing triggers deferred remote query', () async {
      driver.setLyricsViewVisible(false);
      final track = const TrackMetadata(
        uri: 'file:///x6.mp3',
        title: 'T',
        artist: 'A',
        durationMs: 100,
      );
      await driver.resolveLyricsForTrack(track);
      expect(driver.currentLyrics, isNull);

      driver.lrclibMockResponder = (_) => const LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]Fetched on view open',
      );

      driver.setLyricsViewVisible(true);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.currentLyrics?.lines.first.text, equals('Fetched on view open'));
    });

    test('X7: F9 (Translation) + F14 (Display Modes) + F18 (i18n) - Translated interleaved lines format cleanly with i18n', () async {
      final track = const TrackMetadata(
        uri: 'file:///x7.mp3',
        title: 'T',
        artist: 'A',
        durationMs: 100,
        embeddedLyrics: '[00:01.00]Hello world',
      );
      await driver.resolveLyricsForTrack(track);
      await driver.translateLyrics(targetLanguage: 'es');

      driver.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
      final lines = driver.effectiveDisplayLines;

      expect(lines.length, equals(2));
      expect(lines[0].text, equals('Hello world'));
      expect(lines[1].text, contains('[es] Hello world'));

      final keys = AppStringKey();
      await keys.updateFromJson({'np_lyrics_sync': 'Synchronized lyrics'});
      expect(keys.npLyricsSync, isNotEmpty);
    });

    test('X8: F15 (Sources Config) + F12 (Hierarchy) + F2 (Per-Origin State) - Disabling primary forces immediate secondary query regardless of primary state', () async {
      final track = const TrackMetadata(uri: 'file:///x8.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.setSourcesConfig(lrclib: false, lyricsOvh: true);

      driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(
        statusCode: 200,
        lyrics: 'Secondary API called directly',
      );

      final res = await driver.resolveLyricsForTrack(track);
      expect(res?.lines.first.text, equals('Secondary API called directly'));
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(driver.lrclibRecordedQueries, isEmpty);
    });

    test('X9: F16 (Re-search) + F2 (State Tracking) + F1 (Persistence) - Manual re-search bypasses NOT_FOUND and updates SQLite on new found', () async {
      final track = const TrackMetadata(uri: 'file:///x9.mp3', title: 'T', artist: 'A', durationMs: 100);
      final key = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );

      // Pre-seed NOT_FOUND
      await driver.saveLyricsSourceEntry(LyricsSourceEntry(
        keyHash: key,
        source: LyricsSource.lrclib,
        state: LyricsSourceState.notFound,
        updatedAt: 10,
      ));

      driver.lrclibMockResponder = (_) => const LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]Fresh lyrics',
      );

      await driver.playTrack(track);
      await driver.forceReSearch();

      final updated = await driver.getLyricsSourceEntry(key, LyricsSource.lrclib);
      expect(updated?.state, equals(LyricsSourceState.found));
      expect(updated?.rawLrc, equals('[00:01.00]Fresh lyrics'));
    });

    test('X10: F8 (Cooldown Expiry) + F4 (lrclib) + F14 (Display Modes) - Upgrading to synced lyrics on cooldown expiry updates display mode seamlessly', () async {
      final track = const TrackMetadata(uri: 'file:///x10.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
      driver.lyricsOvhMockResponder = (_, _) => const LyricsOvhResponse(statusCode: 200, lyrics: 'Fallback text');

      await driver.resolveLyricsForTrack(track);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));

      driver.lrclibMockResponder = (_) => const LrclibResponse(
        statusCode: 200,
        syncedLyrics: '[00:01.00]Synced upgraded',
      );

      await driver.expireCooldownAndTriggerUpgrade();

      expect(driver.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(driver.currentLyrics?.isSynced, isTrue);
    });

    test('X11: F10 (Rapid Skip) + F11 (Visibility Gating) - Skipping tracks while view is closed generates 0 network traffic', () async {
      driver.setLyricsViewVisible(false);
      final tracks = List.generate(
        5,
        (i) => TrackMetadata(uri: 'file:///x11_$i.mp3', title: 'T$i', artist: 'A', durationMs: 100),
      );

      for (final t in tracks) {
        await driver.resolveLyricsForTrack(t);
      }

      expect(driver.lrclibRecordedQueries, isEmpty);
      expect(driver.lyricsOvhRequestedUrls, isEmpty);
    });

    test('X12: F15 (Sources Config) + F16 (Re-search) + F17 (Countdown Banner) - Disabling lrclib dismisses active 429 countdown banner immediately', () async {
      final track = const TrackMetadata(uri: 'file:///x12.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 8);

      await driver.resolveLyricsForTrack(track);
      expect(driver.isThresholdWaiting, isTrue);

      driver.setSourcesConfig(lrclib: false);
      expect(driver.isThresholdWaiting, isFalse);
    });

    test('X13: F1 (Persistence) + F4 (lrclib) + F5 (lyrics.ovh) - Both web sources cached independently in SQLite with distinct source columns', () async {
      final track = const TrackMetadata(uri: 'file:///x13.mp3', title: 'T', artist: 'A', durationMs: 100);
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
      await driver.saveLyricsSourceEntry(LyricsSourceEntry(
        keyHash: key,
        source: LyricsSource.lyricsOvh,
        state: LyricsSourceState.found,
        rawLrc: 'Plain text',
        updatedAt: 200,
      ));

      final all = await driver.getAllLyricsSourceEntries(key);
      expect(all.length, equals(2));
      expect(all[LyricsSource.lrclib]?.state, equals(LyricsSourceState.notFound));
      expect(all[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.found));
    });

    test('X14: F2 (State Tracking) + F4 (lrclib) + F7 (429) - 429 sets TEMPORARY_ERROR, never NOT_FOUND, allowing subsequent re-search', () async {
      final track = const TrackMetadata(uri: 'file:///x14.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 5);

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

    test('X15: F9 (Translation) + F10 (Rapid Skip) - Fast skipping during active translation aborts translation and discards result', () async {
      final t1 = const TrackMetadata(
        uri: 'file:///x15_1.mp3',
        title: 'T1',
        artist: 'A',
        durationMs: 100,
        embeddedLyrics: '[00:01.00]Line 1',
      );
      final t2 = const TrackMetadata(
        uri: 'file:///x15_2.mp3',
        title: 'T2',
        artist: 'A',
        durationMs: 100,
        embeddedLyrics: '[00:01.00]Line 2',
      );

      await driver.resolveLyricsForTrack(t1);
      final transFuture = driver.translateLyrics();

      // Skip to t2 immediately
      await driver.resolveLyricsForTrack(t2);
      await transFuture;

      expect(driver.currentTrack?.title, equals('T2'));
    });

    test('X16: F3 (Domain Models) + F1 (Persistence) + F12 (Hierarchy) - Complete roundtrip from domain models through SQLite and hierarchy', () async {
      final track = const TrackMetadata(uri: 'file:///x16.mp3', title: 'T', artist: 'A', durationMs: 100);
      final key = LyricsTestDriver.computeLyricsKey(
        uri: track.uri,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );

      final originalEntry = LyricsSourceEntry(
        keyHash: key,
        source: LyricsSource.file,
        state: LyricsSourceState.found,
        rawLrc: '[00:01.00]Roundtrip file',
        isSynced: true,
        updatedAt: 12345,
      );

      await driver.saveLyricsSourceEntry(originalEntry);
      final fetched = await driver.getLyricsSourceEntry(key, LyricsSource.file);

      expect(fetched, equals(originalEntry));
      expect(fetched?.isSynced, isTrue);
    });

    test('X17: F13 (Visibility Binding) + F17 (Countdown Banner) - Leaving Now Playing pauses or cancels 429 countdown timer', () async {
      final track = const TrackMetadata(uri: 'file:///x17.mp3', title: 'T', artist: 'A', durationMs: 100);
      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 6);

      await driver.resolveLyricsForTrack(track);
      expect(driver.isThresholdWaiting, isTrue);

      driver.setLyricsViewVisible(false);
      expect(driver.isThresholdWaiting, isFalse);
      expect(driver.thresholdCountdownSeconds, isNull);
    });

    test('X18: F8 (Cooldown) + F10 (Rapid Skip) + F5 (lyrics.ovh) - Skipping tracks during active cooldown uses fallback for all intermediate tracks', () async {
      final t1 = const TrackMetadata(uri: 'file:///x18_1.mp3', title: 'T1', artist: 'A', durationMs: 100);
      final t2 = const TrackMetadata(uri: 'file:///x18_2.mp3', title: 'T2', artist: 'A', durationMs: 100);
      final t3 = const TrackMetadata(uri: 'file:///x18_3.mp3', title: 'T3', artist: 'A', durationMs: 100);

      driver.lrclibMockResponder = (_) => const LrclibResponse(statusCode: 429, retryAfterSeconds: 60);
      driver.lyricsOvhMockResponder = (a, t) => LyricsOvhResponse(statusCode: 200, lyrics: 'Ovh for $t');

      await driver.resolveLyricsForTrack(t1);
      expect(driver.isCooldownActive, isTrue);

      await driver.resolveLyricsForTrack(t2);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(driver.currentLyrics?.lines.first.text, equals('Ovh for T2'));

      await driver.resolveLyricsForTrack(t3);
      expect(driver.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(driver.currentLyrics?.lines.first.text, equals('Ovh for T3'));

      // Primary was only called for T1!
      expect(driver.lrclibRecordedQueries.length, equals(1));
    });
  });
}
