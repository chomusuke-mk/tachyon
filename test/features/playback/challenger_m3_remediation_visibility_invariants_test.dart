import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

/// Test Spy for PlaybackController.
class SpyPlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = Duration.zero;

  @override
  QueueItem? get currentTrack => _currentTrack;

  @override
  Duration get position => _position;

  void setTrack(QueueItem? track) {
    _currentTrack = track;
    notifyListeners();
  }

  void setPosition(Duration position) {
    _position = position;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QueueItem makeTrack(
  String id,
  String title, {
  String artist = 'Artist',
  int durationSec = 180,
  String? embeddedLyrics,
}) {
  final extras = <String, dynamic>{};
  if (embeddedLyrics != null) {
    extras['lyrics'] = embeddedLyrics;
  }
  return QueueItem(
    id: id,
    uri: 'file:///music/$id.mp3',
    title: title,
    artist: artist,
    album: 'Album',
    duration: Duration(seconds: durationSec),
    extras: extras,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SpyPlaybackController playbackController;

  setUp(() async {
    db = AppDatabase.inMemory();
    playbackController = SpyPlaybackController();
  });

  tearDown(() async {
    await db.close();
  });

  const sampleSynced = '''
[ti:Test Title]
[ar:Artist]
[00:01.00]Line 1
[00:05.00]Line 2
''';

  // ===========================================================================
  // GROUP 1: Visibility Gating Invariants & Zero Background Network Calls
  // ===========================================================================
  group('Invariant Group 1: Zero Background Network Calls when isLyricsViewVisible == false', () {
    test('1.1: 100 consecutive background track changes produce exactly zero network queries', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('{"syncedLyrics": "$sampleSynced"}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          ovhCalls++;
          return http.Response('{"lyrics": "plain lyrics"}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
      );

      expect(controller.isLyricsViewVisible, isFalse);

      for (int i = 1; i <= 100; i++) {
        playbackController.setTrack(makeTrack('track_$i', 'Song $i'));
        if (i % 25 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(lrclibCalls, equals(0), reason: 'Zero lrclib calls permitted in background');
      expect(ovhCalls, equals(0), reason: 'Zero ovh calls permitted in background');
      expect(controller.hasLyrics, isFalse);
      expect(controller.isLoading, isFalse);
    });

    test('1.2: Direct call to ensureLyricsLoaded() while isLyricsViewVisible == false makes zero network calls', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('{"syncedLyrics": "$sampleSynced"}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          ovhCalls++;
          return http.Response('{"lyrics": "plain lyrics"}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
      );

      playbackController.setTrack(makeTrack('bg_direct', 'Background Direct Song'));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Call ensureLyricsLoaded directly while visible is false
      await controller.ensureLyricsLoaded(forceRefresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(controller.isLyricsViewVisible, isFalse);
      expect(lrclibCalls, equals(0), reason: 'ensureLyricsLoaded must respect _isLyricsViewVisible');
      expect(ovhCalls, equals(0), reason: 'ensureLyricsLoaded must respect _isLyricsViewVisible');
      expect(controller.hasLyrics, isFalse);
    });

    test('1.3: Background track changes with local sources disabled make zero network queries', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('{}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          ovhCalls++;
          return http.Response('{}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
      );

      controller.setSourcesConfig(local: false);
      expect(controller.enableLocalSources, isFalse);

      playbackController.setTrack(
        makeTrack('no_local', 'No Local Song', embeddedLyrics: sampleSynced),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(lrclibCalls, equals(0));
      expect(ovhCalls, equals(0));
      expect(controller.hasLyrics, isFalse);
    });

    test('1.4: During active cooldown, rapid background track changes create 0 deferred timers and 0 network calls', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('{}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          ovhCalls++;
          return http.Response('{}', 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );
      expect(controller.isLyricsViewVisible, isFalse);

      // Pre-arm cooldown in memory (300ms)
      cooldownManager.setCooldown(const Duration(milliseconds: 300));
      expect(cooldownManager.isCooldownActive, isTrue);

      // 10 track changes in background
      for (int i = 1; i <= 10; i++) {
        playbackController.setTrack(makeTrack('cd_bg_$i', 'Cooldown BG $i'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // No deferred retry should be scheduled because view is not visible
      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackUri, isNull);

      // Wait for cooldown to expire
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Assert zero network calls
      expect(lrclibCalls, equals(0));
      expect(ovhCalls, equals(0));
    });

    test('1.5: Closing view during active threshold countdown (<=10s) cancels countdown and prevents auto-retry', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('Rate limited', 429, headers: {'Retry-After': '2'});
        }),
        minPacing: Duration.zero,
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(makeTrack('thresh_cancel', 'Threshold Song'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(lrclibCalls, equals(1));
      expect(controller.isThresholdWaiting, isTrue);
      expect(controller.thresholdCountdownSeconds, equals(2));

      // Close view while countdown is running (at t = 50ms of 2s countdown)
      controller.setLyricsViewVisible(false);

      expect(controller.isLyricsViewVisible, isFalse);
      expect(controller.isThresholdWaiting, isFalse);
      expect(controller.thresholdCountdownSeconds, isNull);

      // Wait 2.5 seconds (past the 2s threshold countdown)
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      // Network call MUST NOT have re-fired in background
      expect(lrclibCalls, equals(1), reason: 'Dismissed countdown must never auto-retry in background');
    });
  });

  // ===========================================================================
  // GROUP 2: Deferred Retry Timer Cancellation & Lifecycle Invariants
  // ===========================================================================
  group('Invariant Group 2: Deferred Retry Timer Immediate Cancellation & Lifecycle', () {
    test('2.1: Closing lyrics view immediately cancels running deferred retry timer', () async {
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          return http.Response('Rate limit', 429, headers: {'Retry-After': '60'});
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          return http.Response(jsonEncode({'lyrics': 'Plain OVH text'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set 300ms cooldown
      cooldownManager.setCooldown(const Duration(milliseconds: 300));

      playbackController.setTrack(makeTrack('def_cancel', 'Deferred Cancel Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);
      expect(cooldownManager.deferredTrackUri, equals('file:///music/def_cancel.mp3'));

      // Close view immediately
      controller.setLyricsViewVisible(false);

      // Check disarming invariants
      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackUri, isNull);
      expect(cooldownManager.deferredGenerationToken, isNull);
    });

    test('2.2: Empirical silence: timer cancelled on close fires zero network calls after cooldown expiry', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Silence Track',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Upgraded Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain text'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set 200ms cooldown
      cooldownManager.setCooldown(const Duration(milliseconds: 200));

      playbackController.setTrack(makeTrack('silence', 'Silence Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);
      expect(lrclibCalls, equals(0));

      // Close view mid-cooldown (at ~30ms of 200ms)
      controller.setLyricsViewVisible(false);
      expect(cooldownManager.isDeferredRetryScheduled, isFalse);

      // Wait 300ms (100ms past cooldown expiry)
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Invariant: ZERO network queries occurred!
      expect(lrclibCalls, equals(0), reason: 'Timer was cancelled on close; must never fire after cooldown expiry');
    });

    test('2.3: setSourcesConfig(lrclib: false) cancels deferred retry timer immediately', () async {
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          return http.Response('Rate limit', 429, headers: {'Retry-After': '60'});
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain text'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 250));

      playbackController.setTrack(makeTrack('cfg_lrclib', 'Config Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Disable lrclib in sources config
      controller.setSourcesConfig(lrclib: false);

      expect(controller.enableLrclib, isFalse);
      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackUri, isNull);
    });

    test('2.4: forceReSearch() cancels deferred retry timer before initiating fresh search', () async {
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'trackName': 'Force Track',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Fresh Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain text'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 300));

      playbackController.setTrack(makeTrack('force_track', 'Force Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Trigger forceReSearch
      await controller.forceReSearch();

      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
    });

    test('2.5: dispose() cancels deferred retry timer immediately', () async {
      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      cooldownManager.setCooldown(const Duration(milliseconds: 300));
      cooldownManager.scheduleDeferredRetry(
        trackUri: 'file:///music/dispose.mp3',
        token: 1,
        onRetry: () async {},
      );

      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      controller.dispose();

      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackUri, isNull);
    });

    test('2.6: Mid-cooldown visibility flip (true -> false -> true) safely manages timer and state', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Flip Track',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Flipped Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain ovh lyrics'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set 300ms cooldown
      cooldownManager.setCooldown(const Duration(milliseconds: 300));

      playbackController.setTrack(makeTrack('flip', 'Flip Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Flip visible to false at 50ms
      controller.setLyricsViewVisible(false);
      expect(cooldownManager.isDeferredRetryScheduled, isFalse);

      // Flip visible back to true at 80ms (still during active cooldown)
      controller.setLyricsViewVisible(true);
      expect(controller.isLyricsViewVisible, isTrue);

      // Wait for cooldown to expire (past 300ms)
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Trigger re-search / ensure lyrics loaded
      await controller.ensureLyricsLoaded(forceRefresh: true);

      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
      expect(controller.lines.first.text, equals('Flipped Synced Lyrics'));
      expect(lrclibCalls, equals(1));
    });

    test('2.7: Natural timer auto-upgrades active track to lrclib.net when view remains open', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Natural Track',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Natural Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain ovh lyrics'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );

      final controller = LyricsController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set 250ms cooldown
      cooldownManager.setCooldown(const Duration(milliseconds: 250));

      playbackController.setTrack(makeTrack('natural', 'Natural Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);
      expect(lrclibCalls, equals(0));

      // Wait 350ms for natural timer expiration in real event loop
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Auto-upgrade occurred naturally
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
      expect(controller.lines.first.text, equals('Natural Synced Lyrics'));
      expect(lrclibCalls, equals(1));
    });
  });

  // ===========================================================================
  // GROUP 3: SQLite Per-Origin Persistence & Caching Invariants
  // ===========================================================================
  group('Invariant Group 3: SQLite Per-Origin Persistence & Caching Invariants', () {
    test('3.1: Coexistence of distinct source states (NOT_FOUND vs FOUND) for the same keyHash', () async {
      const keyHash = 'test_hash_multisource';

      final entryLrclib = LyricsSourceEntry.notFound(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
      );
      final entryOvh = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lyricsOvh,
        rawLrc: 'Plain text lyrics from OVH',
        isSynced: false,
      );

      await db.saveLyricsSourceEntry(entryLrclib);
      await db.saveLyricsSourceEntry(entryOvh);

      final entries = await db.getAllLyricsSourceEntries(keyHash);

      expect(entries.length, equals(2));
      expect(entries[LyricsSource.lrclib]?.state, equals(LyricsSourceState.notFound));
      expect(entries[LyricsSource.lrclib]?.rawLrc, isNull);
      expect(entries[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.found));
      expect(entries[LyricsSource.lyricsOvh]?.rawLrc, equals('Plain text lyrics from OVH'));
      expect(entries[LyricsSource.lyricsOvh]?.isSynced, isFalse);
    });

    test('3.2: FOUND state caching: subsequent queries with allowRemote: true return from cache with zero network calls', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Cached Track',
              'artistName': 'Artist',
              'syncedLyrics': sampleSynced,
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      // Query 1: Hits network and caches in SQLite
      final res1 = await service.resolveLyricsByUri(
        uri: 'file:///music/cached.mp3',
        title: 'Cached Track',
        artist: 'Artist',
        allowRemote: true,
      );

      expect(res1, isNotNull);
      expect(res1!.source, equals(LyricsSource.lrclib));
      expect(res1.state, equals(LyricsSourceState.found));
      expect(lrclibCalls, equals(1));

      // Clear in-memory LRU cache to force SQLite read
      final service2 = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      // Query 2: Must read from SQLite without querying network
      final res2 = await service2.resolveLyricsByUri(
        uri: 'file:///music/cached.mp3',
        title: 'Cached Track',
        artist: 'Artist',
        allowRemote: true,
      );

      expect(res2, isNotNull);
      expect(res2!.source, equals(LyricsSource.lrclib));
      expect(res2.state, equals(LyricsSourceState.found));
      expect(lrclibCalls, equals(1), reason: 'Cached entry must satisfy query without network hit');
    });

    test('3.3: NOT_FOUND state caching: skips only that specific source and allows fallback to next tier', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('Not found', 404);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          ovhCalls++;
          return http.Response(jsonEncode({'lyrics': 'Fallback ovh lyrics'}), 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      // Query 1: lrclib -> 404 (persists NOT_FOUND), ovh -> 200 (persists FOUND)
      final res1 = await service.resolveLyricsByUri(
        uri: 'file:///music/fallback.mp3',
        title: 'Fallback Track',
        artist: 'Artist',
        allowRemote: true,
      );

      expect(res1?.source, equals(LyricsSource.lyricsOvh));
      expect(lrclibCalls, equals(1));
      expect(ovhCalls, equals(1));

      // Clear memory cache to test SQLite persistence directly
      final serviceFresh = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      // Query 2: lrclib MUST be skipped due to NOT_FOUND in SQLite; ovh returned from cache
      final res2 = await serviceFresh.resolveLyricsByUri(
        uri: 'file:///music/fallback.mp3',
        title: 'Fallback Track',
        artist: 'Artist',
        allowRemote: true,
      );

      expect(res2?.source, equals(LyricsSource.lyricsOvh));
      expect(lrclibCalls, equals(1), reason: 'lrclib must be skipped due to NOT_FOUND in SQLite');
      expect(ovhCalls, equals(1), reason: 'ovh retrieved from SQLite cache');
    });

    test('3.4: TEMPORARY_ERROR invariant: does NOT block subsequent queries and allows automatic retry', () async {
      int lrclibCalls = 0;
      bool serverRecovered = false;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          if (!serverRecovered) {
            return http.Response('Server Error', 500);
          }
          return http.Response(
            jsonEncode({
              'trackName': 'Recover Track',
              'artistName': 'Artist',
              'syncedLyrics': sampleSynced,
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        ),
      );

      const trackUri = 'file:///music/recover.mp3';
      const title = 'Recover Track';
      const artist = 'Artist';

      // 1. Initial attempt fails with 500
      final res1 = await service.resolveLyricsByUri(
        uri: trackUri,
        title: title,
        artist: artist,
        allowRemote: true,
      );

      expect(res1, isNull);
      expect(lrclibCalls, equals(1));

      // Verify SQLite stored TEMPORARY_ERROR
      final keyHash = LyricsService.computeLyricsKey(uri: trackUri, title: title, artist: artist);
      final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(entry?.state, equals(LyricsSourceState.temporaryError));

      // 2. Server recovers!
      serverRecovered = true;

      // Fresh service instance (bypassing in-memory cache)
      final service2 = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: LyricsOvhClient(
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        ),
      );

      // Attempt 2: Must retry lrclib because temporaryError does not block queries
      final res2 = await service2.resolveLyricsByUri(
        uri: trackUri,
        title: title,
        artist: artist,
        allowRemote: true,
      );

      expect(res2, isNotNull);
      expect(res2!.source, equals(LyricsSource.lrclib));
      expect(res2.state, equals(LyricsSourceState.found));
      expect(lrclibCalls, equals(2), reason: 'TEMPORARY_ERROR must allow retry');
    });

    test('3.5: State transition from TEMPORARY_ERROR to FOUND updates SQLite row cleanly', () async {
      const keyHash = 'transition_test_hash';

      // Write TEMPORARY_ERROR
      final initialEntry = LyricsSourceEntry.temporaryError(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
      );
      await db.saveLyricsSourceEntry(initialEntry);

      final check1 = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(check1?.state, equals(LyricsSourceState.temporaryError));
      expect(check1?.rawLrc, isNull);

      // Overwrite with FOUND
      final foundEntry = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        rawLrc: sampleSynced,
        isSynced: true,
      );
      await db.saveLyricsSourceEntry(foundEntry);

      final check2 = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(check2?.state, equals(LyricsSourceState.found));
      expect(check2?.rawLrc, equals(sampleSynced));
      expect(check2?.isSynced, isTrue);
    });

    test('3.6: forceReSearch / clearLyricsSourceEntries completely purges cache for keyHash across all sources', () async {
      const keyHash = 'purge_test_hash';

      await db.saveLyricsSourceEntry(LyricsSourceEntry.notFound(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
      ));
      await db.saveLyricsSourceEntry(LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lyricsOvh,
        rawLrc: 'Some lyrics',
        isSynced: false,
      ));

      final before = await db.getAllLyricsSourceEntries(keyHash);
      expect(before.length, equals(2));

      // Clear entries
      await db.clearLyricsSourceEntries(keyHash);

      final after = await db.getAllLyricsSourceEntries(keyHash);
      expect(after, isEmpty);

      final legacyCache = await db.getLyrics(keyHash);
      expect(legacyCache, isNull);
    });

    test('3.7: Cancelled requests never record NOT_FOUND or TEMPORARY_ERROR in SQLite', () async {
      final tCompleter = Completer<http.Response>();

      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async => await tCompleter.future),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      final token = LyricsCancellationToken();
      const trackUri = 'file:///music/cancel_db.mp3';
      const title = 'Cancel DB Track';
      const artist = 'Artist';

      // Launch request with token
      final future = service.resolveLyricsByUri(
        uri: trackUri,
        title: title,
        artist: artist,
        cancellationToken: token,
        allowRemote: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Cancel token before network responds
      token.cancel();

      // Server responds with 404 after token was cancelled
      tCompleter.complete(http.Response('Not found', 404));

      final res = await future;
      expect(res, isNull);

      // Verify SQLite was NOT written to with NOT_FOUND
      final keyHash = LyricsService.computeLyricsKey(uri: trackUri, title: title, artist: artist);
      final entries = await db.getAllLyricsSourceEntries(keyHash);
      expect(entries, isEmpty, reason: 'Cancelled request must not write to SQLite');
    });

    test('3.8: Dual-table mirroring: saving FOUND mirrors to legacy lyrics_cache', () async {
      const keyHash = 'mirror_test_hash';
      final entry = LyricsSourceEntry.found(
        keyHash: keyHash,
        source: LyricsSource.lrclib,
        rawLrc: sampleSynced,
        isSynced: true,
      );

      await db.saveLyricsSourceEntry(entry);

      // Check lyrics_source_cache
      final sourceEntry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
      expect(sourceEntry?.state, equals(LyricsSourceState.found));

      // Check legacy lyrics_cache
      final legacyLrc = await db.getLyrics(keyHash);
      expect(legacyLrc, equals(sampleSynced));
    });
  });
}
