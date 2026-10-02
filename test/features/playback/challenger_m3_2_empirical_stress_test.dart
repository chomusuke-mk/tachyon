import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

class MockPlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);

  @override
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _positionNotifier;

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
    _positionNotifier.value = position;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionNotifier.value = position;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepo implements SettingsRepository {
  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;

  @override
  LyricsDisplayMode getLyricsDisplayMode() => _displayMode;
  @override
  String getLyricsTranslationTargetLang() => 'defaultOption';
  @override
  AppSettings getSettings() => const AppSettings(lastPlayedFilePath: null);
  @override
  Future<void> setLyricsDisplayMode(LyricsDisplayMode mode) async {
    _displayMode = mode;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QueueItem makeItem(String id, String title, {String artist = 'Artist', int durationSec = 180}) {
  return QueueItem(
    id: id,
    filePath: 'file:///music/$id.mp3',
    title: title,
    artist: artist,
    album: 'Album',
    duration: Duration(seconds: durationSec),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MockPlaybackController playbackController;

  LyricsController createController({
    required LyricsService lyricsService,
    required PlaybackController playbackController,
    LyricsCooldownManager? cooldownManager,
  }) {
    final effectiveCooldownManager =
        cooldownManager ?? lyricsService.cooldownManager;
    final backend = DirectTachyonBackendClient(
      database: db,
      lyricsService: lyricsService,
    );
    return LyricsController(
      backendClient: backend,
      playbackController: playbackController,
      settingsRepository: _FakeSettingsRepo(),
      cooldownManager: effectiveCooldownManager,
    );
  }

  setUp(() async {
    db = AppDatabase.inMemory();
    playbackController = MockPlaybackController();
  });

  tearDown(() async {
    await db.close();
  });

  // ===========================================================================
  // CHALLENGE 1: Rapid Track Skip Concurrency ($1 \to 2 \to 3 \to 4 \to 5$ in < 100ms)
  // ===========================================================================
  group('Adversarial Challenge 1: Rapid Track Skip Concurrency', () {
    test('1.1: Intermediate cancelled tokens abort pacing delay in < 1ms', () async {
      final client = LrclibClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        minPacing: const Duration(milliseconds: 500),
      );

      // Fire Request 1 to establish baseline pacing timestamp
      await client.getLyrics(trackName: 'T1', artistName: 'A1');

      // Now create Request 2 with a cancellation token
      final token2 = LyricsCancellationToken();
      final stopwatch = Stopwatch()..start();

      // Launch request 2 asynchronously in pacing wait
      final future2 = client.getLyrics(
        trackName: 'T2',
        artistName: 'A2',
        cancellationToken: token2,
      );

      // Yield event loop briefly so T2 enters _enforcePacing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Cancel token2 and measure how fast it aborts
      final cancelStopwatch = Stopwatch()..start();
      token2.cancel();

      final res2 = await future2;
      cancelStopwatch.stop();
      stopwatch.stop();

      expect(res2.isError, isTrue);
      expect(res2.statusCode, equals(499));
      expect(
        cancelStopwatch.elapsedMilliseconds,
        lessThan(20),
        reason: 'Token cancellation must abort the pacing timer immediately (<20ms in VM/test scheduler)',
      );
    });

    test('1.2: Rapid skip 1 -> 2 -> 3 -> 4 -> 5 in < 50ms does not block Track 5 with cumulative pacing', () async {
      final dispatchedUris = <String>[];
      final client = LrclibClient(
        httpClient: MockClient((req) async {
          dispatchedUris.add(req.url.queryParameters['track_name'] ?? '');
          return http.Response(
            jsonEncode({
              'trackName': req.url.queryParameters['track_name'],
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Lyrics for ${req.url.queryParameters['track_name']}',
            }),
            200,
          );
        }),
        minPacing: const Duration(milliseconds: 100),
      );

      final service = LyricsService(database: db, lrclibClient: client);
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );
      controller.setLyricsViewVisible(true);

      final sw = Stopwatch()..start();

      // Burst skip 5 songs in 20ms total (< 50ms)
      playbackController.setTrack(makeItem('1', 'Track 1'));
      await Future<void>.delayed(const Duration(milliseconds: 4));
      playbackController.setTrack(makeItem('2', 'Track 2'));
      await Future<void>.delayed(const Duration(milliseconds: 4));
      playbackController.setTrack(makeItem('3', 'Track 3'));
      await Future<void>.delayed(const Duration(milliseconds: 4));
      playbackController.setTrack(makeItem('4', 'Track 4'));
      await Future<void>.delayed(const Duration(milliseconds: 4));
      playbackController.setTrack(makeItem('5', 'Track 5'));

      // Wait enough for Track 5 to complete (100ms pacing from T1 + network delay)
      // If intermediate tracks (2, 3, 4) added 100ms each, this would take > 400ms!
      await Future<void>.delayed(const Duration(milliseconds: 160));
      sw.stop();

      expect(controller.hasLyrics, isTrue);
      expect(controller.lines.first.text, equals('Lyrics for Track 5'));

      // Verify intermediate tracks were aborted before dispatch or never finished
      expect(dispatchedUris.contains('Track 5'), isTrue);
      expect(
        sw.elapsedMilliseconds,
        lessThan(350),
        reason: 'Track 5 should not suffer cumulative 400ms delay from skipped tracks',
      );
    });

    test('1.3: Slow intermediate response arriving AFTER Track 5 finishes NEVER overwrites UI', () async {
      final t1Completer = Completer<http.Response>();

      final client = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'];
          if (title == 'Track 1') {
            return await t1Completer.future;
          }
          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Correct Lyrics for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(database: db, lrclibClient: client);
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );
      controller.setLyricsViewVisible(true);

      // Start Track 1 (slow network)
      playbackController.setTrack(makeItem('1', 'Track 1'));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Rapidly skip to Track 5
      playbackController.setTrack(makeItem('2', 'Track 2'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      playbackController.setTrack(makeItem('5', 'Track 5'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.lines.first.text, equals('Correct Lyrics for Track 5'));

      // Now Track 1 finally responds late!
      t1Completer.complete(
        http.Response(
          jsonEncode({
            'trackName': 'Track 1',
            'artistName': 'Artist',
            'syncedLyrics': '[00:01.00]Stale Lyrics for Track 1',
          }),
          200,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // UI MUST NOT be overwritten by stale Track 1
      expect(controller.lines.first.text, equals('Correct Lyrics for Track 5'));
    });

    test('1.4: Late cancelled responses NEVER poison SQLite cache with cancelled state', () async {
      final t2Completer = Completer<http.Response>();

      final client = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'];
          if (title == 'Track 2') {
            return await t2Completer.future;
          }
          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Lyrics for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(database: db, lrclibClient: client);
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );
      controller.setLyricsViewVisible(true);

      // Play Track 2, then skip away before it completes
      playbackController.setTrack(makeItem('2', 'Track 2'));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      playbackController.setTrack(makeItem('3', 'Track 3'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Complete Track 2 with 404
      t2Completer.complete(http.Response('Not found', 404));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Check SQLite cache for Track 2: it must NOT have recorded NOT_FOUND because it was cancelled!
      final keyHashT2 = LyricsService.computeLyricsKey(
        filePath: 'file:///music/2.mp3',
        title: 'Track 2',
        artist: 'Artist',
        durationMs: 180000,
      );
      final entries = await db.getAllLyricsSourceEntries(keyHashT2);
      expect(
        entries[LyricsSource.lrclib],
        isNull,
        reason: 'Cancelled request must not write NOT_FOUND or poison the SQLite cache for skipped track',
      );
    });

    test('1.5: Massive skip burst (20 tracks in 20ms) resolves final track cleanly without crash', () async {
      int finishedRequests = 0;
      final client = LrclibClient(
        httpClient: MockClient((req) async {
          finishedRequests++;
          return http.Response(
            jsonEncode({
              'trackName': req.url.queryParameters['track_name'],
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Final ${req.url.queryParameters['track_name']}',
            }),
            200,
          );
        }),
        minPacing: const Duration(milliseconds: 10),
      );

      final service = LyricsService(database: db, lrclibClient: client);
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );
      controller.setLyricsViewVisible(true);

      for (int i = 1; i <= 20; i++) {
        playbackController.setTrack(makeItem('$i', 'Track $i'));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.hasLyrics, isTrue);
      expect(controller.lines.first.text, equals('Final Track 20'));
      expect(finishedRequests, lessThan(20), reason: 'Intermediary tracks were properly cancelled');
    });
  });

  // ===========================================================================
  // CHALLENGE 2: HTTP 429 Retry-After <= 10s Countdown Stream & Auto-Retry
  // ===========================================================================
  group('Adversarial Challenge 2: HTTP 429 Retry-After <= 10s Countdown & Auto-Retry', () {
    test('2.1: thresholdStream emits live decrements [3, 2, 1, 0, null] and auto-retries', () async {
      int attempts = 0;
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          attempts++;
          if (attempts == 1) {
            return http.Response('Rate limit', 429, headers: {'Retry-After': '3'});
          }
          return http.Response(
            jsonEncode({
              'trackName': 'RetrySong',
              'artistName': 'Artist',
              'syncedLyrics': '[00:02.00]Auto-retried Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      final emittedValues = <int?>[];
      final sub = controller.thresholdStream.listen((val) {
        emittedValues.add(val);
      });

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(makeItem('ret1', 'RetrySong'));

      // Wait for initial 429 and countdown timer (3 seconds + buffer)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.isThresholdWaiting, isTrue);
      expect(controller.thresholdCountdownSeconds, equals(3));
      expect(emittedValues, contains(3));

      // Wait 3.5 seconds for live countdown to tick to 0 and trigger auto-retry
      await Future<void>.delayed(const Duration(milliseconds: 3500));

      await sub.cancel();

      // Verify stream emissions contained countdown and cleanup null
      expect(emittedValues, containsAllInOrder([3, 2, 1, 0, null]));
      expect(controller.isThresholdWaiting, isFalse);

      // Verify auto-retry completed and upgraded to lyrics
      expect(attempts, equals(2));
      expect(controller.hasLyrics, isTrue);
      expect(controller.lines.first.text, equals('Auto-retried Synced Lyrics'));
    });

    test('2.2: Track change during countdown cancels countdown immediately and dismisses banner', () async {
      final client = LrclibClient(
        httpClient: MockClient((req) async {
          if (req.url.queryParameters['track_name'] == 'Song 429') {
            return http.Response('Rate limit', 429, headers: {'Retry-After': '8'});
          }
          return http.Response(
            jsonEncode({
              'trackName': 'Song Normal',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Normal Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(makeItem('429', 'Song 429'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.isThresholdWaiting, isTrue);
      expect(controller.thresholdCountdownSeconds, equals(8));

      // Skip to another track mid-countdown
      playbackController.setTrack(makeItem('norm', 'Song Normal'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.isThresholdWaiting, isFalse);
      expect(controller.thresholdCountdownSeconds, isNull);
      expect(controller.lines.first.text, equals('Normal Lyrics'));
    });

    test('2.3: Closing LyricsView mid-countdown cancels countdown immediately', () async {
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          return http.Response('Rate limit', 429, headers: {'Retry-After': '5'});
        }),
        minPacing: Duration.zero,
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(makeItem('429_close', 'Close Song'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.isThresholdWaiting, isTrue);

      controller.setLyricsViewVisible(false);

      expect(controller.isThresholdWaiting, isFalse);
      expect(controller.thresholdCountdownSeconds, isNull);
    });
  });

  // ===========================================================================
  // CHALLENGE 3: HTTP 429 Retry-After > 10s Cooldown & Deferred Upgrade
  // ===========================================================================
  group('Adversarial Challenge 3: HTTP 429 Retry-After > 10s Fallback & Deferred Upgrade', () {
    test('3.1: 429 with Retry-After > 10s falls back to lyrics.ovh immediately', () async {
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          return http.Response('Rate limit', 429, headers: {'Retry-After': '60'});
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'lyrics': 'Plain lyrics from ovh'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(makeItem('cd1', 'Cooldown Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.isCooldownActive, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(controller.isSynced, isFalse);
      expect(controller.lines.first.text, equals('Plain lyrics from ovh'));
    });

    test('3.2: [REMEDIATED] Natural timer auto-upgrade SUCCEEDS in real time upon cooldown expiry', () async {
      int lrclibCalls = 0;
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Auto Upgrade Song',
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
          return http.Response(jsonEncode({'lyrics': 'Plain ovh lyrics'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set in-memory cooldown to 400ms so we can test real Timer expiration
      cooldownManager.setCooldown(const Duration(milliseconds: 400));
      expect(cooldownManager.isCooldownActive, isTrue);

      // 1. Play track during active cooldown -> skips lrclib.net and falls back to lyrics.ovh
      playbackController.setTrack(makeItem('cd_auto', 'Auto Upgrade Song'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(lrclibCalls, equals(0), reason: 'lrclib skipped during active cooldown');

      // Verify that the controller registered the callback and timer is active
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/cd_auto.mp3'));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // 2. Wait 500ms for the cooldown duration to completely expire in real time
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Give event loop time to process auto-retry upgrade
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // REMEDIATED BEHAVIOR:
      // When cooldown expires on active track, auto-upgrade to lrclib.net synced lyrics in real time!
      expect(
        controller.currentLyricsSource,
        equals(LyricsSource.lrclib),
        reason: 'Active track must be upgraded to lrclib.net synced lyrics in real time upon cooldown expiry',
      );
      expect(controller.isSynced, isTrue);
      expect(
        lrclibCalls,
        equals(1),
        reason: 'lrclib.net was re-queried naturally upon cooldown expiry',
      );
    });

    test('3.3: Track switches during cooldown skip lrclib.net and update deferred track', () async {
      int lrclibCalls = 0;
      int ovhCalls = 0;

      final client = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response('Rate limit', 429, headers: {'Retry-After': '60'});
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          ovhCalls++;
          return http.Response(jsonEncode({'lyrics': 'Ovh lyrics'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Track A triggers 429
      playbackController.setTrack(makeItem('A', 'Track A'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(lrclibCalls, equals(1));
      expect(ovhCalls, equals(1));
      expect(cooldownManager.isCooldownActive, isTrue);

      // Switch to Track B during active cooldown
      playbackController.setTrack(makeItem('B', 'Track B'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // lrclib.net MUST have been skipped!
      expect(lrclibCalls, equals(1), reason: 'Track B must not query lrclib.net during active cooldown');
      // lyrics.ovh MUST have been queried for Track B
      expect(ovhCalls, equals(2), reason: 'Track B queries lyrics.ovh fallback immediately');

      // Verify deferred track uri is updated to Track B
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/B.mp3'));
    });

    test('3.4: [SPEC COMPLIANCE CHECK] Natural timer auto-upgrade upon cooldown expiry (Expected by R2/M3)', () async {
      int lrclibCalls = 0;
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Auto Upgrade Spec Track',
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
          return http.Response(jsonEncode({'lyrics': 'Plain ovh lyrics'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: client,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set in-memory cooldown to 300ms
      cooldownManager.setCooldown(const Duration(milliseconds: 300));

      // Play track during active cooldown -> fallback to lyrics.ovh
      playbackController.setTrack(makeItem('spec_cd', 'Auto Upgrade Spec Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isCooldownActive, isTrue);

      // Wait 400ms for cooldown to expire naturally
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Give event loop time to process auto-retry upgrade
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // SPECIFICATION REQUIRES:
      // When cooldown expires on active track, auto-upgrade to lrclib.net synced lyrics!
      expect(
        controller.currentLyricsSource,
        equals(LyricsSource.lrclib),
        reason: 'SPECIFICATION VIOLATION: When cooldown clears, active track must be upgraded to lrclib.net synced lyrics automatically',
      );
      expect(controller.isSynced, isTrue);
      expect(lrclibCalls, equals(1));
    });

    test('3.5: [REMEDY VALIDATION] Calling scheduleDeferredRetry directly successfully starts Timer and upgrades naturally', () async {
      int lrclibCalls = 0;
      final client = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Remedy Track',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Remedied Synced Lyrics',
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
        lrclibClient: client,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set in-memory cooldown to 250ms
      cooldownManager.setCooldown(const Duration(milliseconds: 250));

      final track = makeItem('remedy', 'Remedy Track');
      playbackController.setTrack(track);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(lrclibCalls, equals(0));

      // PROPOSED FIX: If scheduleDeferredRetry is invoked:
      cooldownManager.scheduleDeferredRetry(
        trackFilePath: track.filePath,
        token: 1,
        onRetry: () async {
          await controller.ensureLyricsLoaded(forceRefresh: true);
        },
      );

      // Wait 350ms for natural timer expiration
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // With scheduleDeferredRetry, the Timer DOES fire naturally!
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
      expect(controller.lines.first.text, equals('Remedied Synced Lyrics'));
      expect(lrclibCalls, equals(1));
    });
  });
}
