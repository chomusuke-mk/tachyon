import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/database/app_database.dart';
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

QueueItem makeItem(
  String id,
  String title, {
  String artist = 'Artist',
  int durationSec = 180,
  String? embeddedLyrics,
}) {
  return QueueItem(
    id: id,
    filePath: 'file:///music/$id.mp3',
    title: title,
    artist: artist,
    album: 'Album',
    duration: Duration(seconds: durationSec),
    extras: {
      'lyrics': ?embeddedLyrics,
    },
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

  group('Challenger M3 Iteration 2.2: Armed Timer & Rapid Skipping Stress Tests', () {
    // -------------------------------------------------------------------------
    // TEST 1: Rapid skipping while deferred timer is armed
    // -------------------------------------------------------------------------
    test('1. Rapid skip 1 -> 2 -> 3 -> 4 -> 5 under armed timer cleanly targets final track', () async {
      final lrclibRequestedTitles = <String>[];
      final ovhRequestedTitles = <String>[];

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          lrclibRequestedTitles.add(title);

          if (title == 'Track 1') {
            // Track 1 triggers 429 with 300ms cooldown
            return http.Response('Too Many Requests', 429, headers: {'Retry-After': '60'});
          }

          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Upgraded Synced Lyrics for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          final uri = req.url.path;
          final title = Uri.decodeComponent(uri.split('/').last);
          ovhRequestedTitles.add(title);
          return http.Response(
            jsonEncode({'lyrics': 'Plain OVH Lyrics for $title'}),
            200,
          );
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Pre-set 350ms cooldown
      cooldownManager.setCooldown(const Duration(milliseconds: 350));

      // Play Track 1 -> gets 429, falls back to OVH, arms deferred timer
      playbackController.setTrack(makeItem('1', 'Track 1'));
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/1.mp3'));

      // While timer is armed, rapidly burst-skip: 2 -> 3 -> 4 -> 5
      playbackController.setTrack(makeItem('2', 'Track 2'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      playbackController.setTrack(makeItem('3', 'Track 3'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      playbackController.setTrack(makeItem('4', 'Track 4'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      playbackController.setTrack(makeItem('5', 'Track 5'));

      // Wait for Track 5 to settle on ovh fallback during remaining cooldown
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(controller.lines.first.text, equals('Plain OVH Lyrics for Track 5'));
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/5.mp3'));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Now wait for the natural timer to expire (remaining of 350ms)
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Active track 5 must be upgraded cleanly to lrclib synced lyrics!
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
      expect(controller.lines.first.text, equals('Upgraded Synced Lyrics for Track 5'));

      // Stale tracks 1, 2, 3, 4 must NOT have been upgraded to lrclib
      expect(lrclibRequestedTitles, contains('Track 5'));
      expect(lrclibRequestedTitles.where((t) => t == 'Track 5').length, equals(1));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Switching to track with local lyrics cancels / avoids remote query
    // -------------------------------------------------------------------------
    test('2. Skipping to track with embedded lyrics does not get overwritten by expired timer', () async {
      int lrclibCalls = 0;
      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCalls++;
          return http.Response('Too Many Requests', 429, headers: {'Retry-After': '60'});
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'lyrics': 'Plain OVH'}), 200)),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Cooldown of 200ms
      cooldownManager.setCooldown(const Duration(milliseconds: 200));

      // Track A falls back to OVH and arms deferred timer
      playbackController.setTrack(makeItem('A', 'Track A'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Switch to Track B which has EMBEDDED lyrics
      playbackController.setTrack(
        makeItem('B', 'Track B', embeddedLyrics: '[00:01.00]Embedded Local Lyrics'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.embedded));
      expect(controller.lines.first.text, equals('Embedded Local Lyrics'));

      // Wait 250ms for cooldown timer of Track A to expire naturally in wall-clock time
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Track B's embedded lyrics must NOT be overwritten!
      expect(controller.currentLyricsSource, equals(LyricsSource.embedded));
      expect(controller.lines.first.text, equals('Embedded Local Lyrics'));
      expect(lrclibCalls, equals(0), reason: 'Track B already has higher-priority local lyrics');
    });

    // -------------------------------------------------------------------------
    // TEST 3: Closing LyricsView cancels deferred timer cleanly
    // -------------------------------------------------------------------------
    test('3. Dismissing LyricsView disarms deferred timer and prevents background network query', () async {
      int lrclibCalls = 0;
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Track Close',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Late Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'lyrics': 'Plain OVH'}), 200)),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 200));

      playbackController.setTrack(makeItem('close_test', 'Track Close'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // User navigates away / closes LyricsView
      controller.setLyricsViewVisible(false);

      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackFilePath, isNull);

      // Wait 250ms for what would have been the timer firing time
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // No network calls must occur in background!
      expect(lrclibCalls, equals(0));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Re-opening LyricsView after cooldown expired loads synced lyrics
    // -------------------------------------------------------------------------
    test('4. Re-opening LyricsView after cooldown expired on active track fetches synced lyrics', () async {
      int lrclibCalls = 0;
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async {
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': 'Track Reopen',
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Fresh Synced Lyrics',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'lyrics': 'Plain OVH'}), 200)),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 150));

      playbackController.setTrack(makeItem('reopen_test', 'Track Reopen'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));

      // Close view
      controller.setLyricsViewVisible(false);

      // Wait 200ms (cooldown expires while view is closed)
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(cooldownManager.isCooldownActive, isFalse);

      // User re-opens LyricsView
      controller.setLyricsViewVisible(true);
      await controller.ensureLyricsLoaded(forceRefresh: true);

      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.isSynced, isTrue);
      expect(lrclibCalls, equals(1));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Switching back and forth A -> B -> A during cooldown
    // -------------------------------------------------------------------------
    test('5. Oscillating between Track A -> Track B -> Track A during cooldown updates target to A', () async {
      final lrclibRequestedTitles = <String>[];
      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          lrclibRequestedTitles.add(title);
          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Synced Lyrics for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          final uri = req.url.path;
          final title = uri.split('/').last;
          return http.Response(jsonEncode({'lyrics': 'Plain OVH for $title'}), 200);
        }),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 300));

      // Play A
      playbackController.setTrack(makeItem('A', 'Track A'));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/A.mp3'));

      // Switch to B
      playbackController.setTrack(makeItem('B', 'Track B'));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/B.mp3'));

      // Switch back to A
      playbackController.setTrack(makeItem('A', 'Track A'));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(cooldownManager.deferredTrackFilePath, equals('file:///music/A.mp3'));

      // Wait for timer to expire naturally
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Track A must be upgraded to lrclib synced lyrics
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.lines.first.text, equals('Synced Lyrics for Track A'));
      expect(lrclibRequestedTitles, equals(['Track A']));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Disabling lrclib disarms timer and cancels pending retry
    // -------------------------------------------------------------------------
    test('6. Disabling lrclib in sources configuration disarms deferred timer', () async {
      final lrclibClient = LrclibClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'lyrics': 'Plain OVH'}), 200)),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 200));

      playbackController.setTrack(makeItem('disable_test', 'Track Disable'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cooldownManager.isDeferredRetryScheduled, isTrue);

      // Disable lrclib in config
      controller.setSourcesConfig(lrclib: false);

      expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      expect(cooldownManager.deferredTrackFilePath, isNull);
    });

    // -------------------------------------------------------------------------
    // TEST 7: Cooldown expires while lyrics.ovh fallback request is still in-flight
    // -------------------------------------------------------------------------
    test('7. If cooldown expires while fallback request is in flight, state completes cleanly', () async {
      final ovhCompleter = Completer<http.Response>();

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Synced Lyrics for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async => await ovhCompleter.future),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);

      // Very short cooldown of 50ms
      cooldownManager.setCooldown(const Duration(milliseconds: 50));

      // Start Track SlowOVH
      playbackController.setTrack(makeItem('slow_ovh', 'Track SlowOVH'));

      // Wait 80ms: cooldown has now EXPIRED while OVH request was still pending!
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cooldownManager.isCooldownActive, isFalse);

      // Now complete the pending OVH request
      ovhCompleter.complete(http.Response(jsonEncode({'lyrics': 'Delayed Plain OVH'}), 200));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Verify state is clean and no uncaught exceptions occurred
      expect(controller.hasLyrics, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 8: Track with 404 on ovh fallback during active cooldown
    // -------------------------------------------------------------------------
    test('8. Track skipped during cooldown where fallback returns 404', () async {
      int lrclibCalls = 0;
      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          lrclibCalls++;
          return http.Response(
            jsonEncode({
              'trackName': title,
              'artistName': 'Artist',
              'syncedLyrics': '[00:01.00]Synced for $title',
            }),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((_) async => http.Response('Not found', 404)),
      );

      final cooldownManager = LyricsCooldownManager();
      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
        cooldownManager: cooldownManager,
      );
      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
        cooldownManager: cooldownManager,
      );

      controller.setLyricsViewVisible(true);
      cooldownManager.setCooldown(const Duration(milliseconds: 150));

      // Play Track 2 during cooldown. OVH returns 404.
      playbackController.setTrack(makeItem('2', 'Track 2'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.currentLyricsSource, isNull);
      expect(controller.hasLyrics, isFalse);
      expect(lrclibCalls, equals(0));

      // Wait for cooldown to expire
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
