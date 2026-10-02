import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

class FakePlaybackController extends ChangeNotifier implements PlaybackController {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakePlaybackController playbackController;

  setUp(() async {
    db = AppDatabase.inMemory();
    playbackController = FakePlaybackController();
  });

  tearDown(() async {
    await db.close();
  });

  const sampleSyncedLrc = '''
[ti:Midnight City]
[ar:M83]
[al:Hurry Up, We're Dreaming]
[00:10.00]Waiting in a car
[00:20.00]Waiting for a ride in the dark
[00:30.00]The city is my church
''';

  const samplePlainLyrics = '''
Waiting in a car
Waiting for a ride in the dark
The city is my church
''';

  QueueItem createQueueItem({
    String id = 'q1',
    required String uri,
    required String title,
    String artist = 'Artist',
    String album = 'Album',
    Duration duration = const Duration(seconds: 240),
    String? lyrics,
  }) {
    return QueueItem(
      id: id,
      uri: uri,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      extras: lyrics != null ? {'lyrics': lyrics} : const {},
    );
  }

  group('LyricsController Visibility Gating & Concurrency Engine', () {
    // -------------------------------------------------------------------------
    // 1. Visibility Gating & Background Decoupling
    // -------------------------------------------------------------------------
    group('1. Visibility Gating & Background Decoupling', () {
      test('initial state has isLyricsViewVisible == false', () {
        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        expect(controller.isLyricsViewVisible, isFalse);
        expect(controller.hasLyrics, isFalse);
      });

      test('track change when isLyricsViewVisible == false dispatches ZERO network calls', () async {
        int lrclibQueries = 0;
        int ovhQueries = 0;

        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhQueries++;
            return http.Response('{}', 200);
          }),
        );

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        expect(controller.isLyricsViewVisible, isFalse);

        // Change track in background playback
        playbackController.setTrack(
          createQueueItem(uri: 'file:///music/bg.mp3', title: 'Background Song'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Zero network traffic!
        expect(lrclibQueries, equals(0));
        expect(ovhQueries, equals(0));
        expect(controller.hasLyrics, isFalse);
      });

      test('track change when isLyricsViewVisible == false resolves local embedded lyrics', () async {
        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        expect(controller.isLyricsViewVisible, isFalse);

        final localTrack = createQueueItem(
          uri: 'file:///music/local.mp3',
          title: 'Local Song',
          lyrics: sampleSyncedLrc,
        );

        playbackController.setTrack(localTrack);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Local lyrics resolved offline
        expect(controller.hasLyrics, isTrue);
        expect(controller.currentLyricsSource, equals(LyricsSource.embedded));
      });

      test('setLyricsViewVisible(true) triggers ensureLyricsLoaded() and queries remote APIs', () async {
        int lrclibQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response(
              jsonEncode({
                'id': 50,
                'name': 'Online Track',
                'trackName': 'Online Track',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        playbackController.setTrack(
          createQueueItem(uri: 'file:///music/online.mp3', title: 'Online Track'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(lrclibQueries, equals(0)); // Still 0 while invisible

        // User opens LyricsView
        controller.setLyricsViewVisible(true);
        expect(controller.isLyricsViewVisible, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Remote queries dispatched on-demand
        expect(lrclibQueries, equals(1));
        expect(controller.hasLyrics, isTrue);
        expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      });

      test('setLyricsViewVisible(false) cancels in-flight cancellation tokens and dismisses countdown', () async {
        final cooldownManager = LyricsCooldownManager();
        cooldownManager.startThresholdCountdown(
          seconds: 8,
          onAutoRetry: () async {},
        );

        expect(cooldownManager.isThresholdWaiting, isTrue);

        final service = LyricsService(
          database: db,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);
        expect(controller.isThresholdWaiting, isTrue);

        // User closes LyricsView
        controller.setLyricsViewVisible(false);

        expect(controller.isLyricsViewVisible, isFalse);
        expect(controller.isThresholdWaiting, isFalse);
      });

      test('track change when isLyricsViewVisible == true resolves full lyrics immediately', () async {
        int queries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            queries++;
            return http.Response(
              jsonEncode({
                'id': 60,
                'name': 'Visible Track',
                'trackName': 'Visible Track',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);

        playbackController.setTrack(
          createQueueItem(uri: 'file:///music/visible.mp3', title: 'Visible Track'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(queries, equals(1));
        expect(controller.hasLyrics, isTrue);
        expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Rapid Skip Concurrency & Token Cancellation
    // -------------------------------------------------------------------------
    group('2. Rapid Skip Concurrency & Token Cancellation', () {
      test('burst skip 1 -> 2 -> 3 -> 4 -> 5 cancels intermediate tokens and renders Track 5', () async {
        final queriedTitles = <String>[];
        final mockLrclib = LrclibClient(
          httpClient: MockClient((request) async {
            final uri = request.url;
            final title = uri.queryParameters['track_name'] ?? '';
            queriedTitles.add(title);
            return http.Response(
              jsonEncode({
                'id': title.hashCode,
                'name': title,
                'trackName': title,
                'artistName': 'Artist',
                'syncedLyrics': '[00:05.00]Lyrics for $title',
              }),
              200,
            );
          }),
          minPacing: const Duration(milliseconds: 50),
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);

        // Rapidly skip 1 -> 2 -> 3 -> 4 -> 5 in quick succession
        playbackController.setTrack(createQueueItem(uri: 'file:///1.mp3', title: 'Track 1'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        playbackController.setTrack(createQueueItem(uri: 'file:///2.mp3', title: 'Track 2'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        playbackController.setTrack(createQueueItem(uri: 'file:///3.mp3', title: 'Track 3'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        playbackController.setTrack(createQueueItem(uri: 'file:///4.mp3', title: 'Track 4'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        playbackController.setTrack(createQueueItem(uri: 'file:///5.mp3', title: 'Track 5'));

        // Wait for Track 5 resolution to settle
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(controller.hasLyrics, isTrue);
        expect(controller.lines.first.text, equals('Lyrics for Track 5'));
      });

      test('late arrival from cancelled Track 1 does not overwrite Track 2', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((request) async {
            final title = request.url.queryParameters['track_name'] ?? '';
            if (title == 'Track 1') {
              // Delayed arrival
              await Future<void>.delayed(const Duration(milliseconds: 100));
              return http.Response(
                jsonEncode({
                  'id': 1,
                  'name': 'Track 1',
                  'trackName': 'Track 1',
                  'artistName': 'Artist',
                  'syncedLyrics': '[00:05.00]Late Track 1 Lyrics',
                }),
                200,
              );
            } else {
              return http.Response(
                jsonEncode({
                  'id': 2,
                  'name': 'Track 2',
                  'trackName': 'Track 2',
                  'artistName': 'Artist',
                  'syncedLyrics': '[00:05.00]Track 2 Lyrics',
                }),
                200,
              );
            }
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);

        playbackController.setTrack(createQueueItem(uri: 'file:///1.mp3', title: 'Track 1'));
        // User immediately skips to Track 2 at 10ms
        await Future<void>.delayed(const Duration(milliseconds: 10));
        playbackController.setTrack(createQueueItem(uri: 'file:///2.mp3', title: 'Track 2'));

        // Wait until Track 1 delayed response would have completed (150ms)
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // State MUST remain Track 2 lyrics, not overwritten by Track 1
        expect(controller.hasLyrics, isTrue);
        expect(controller.lines.first.text, equals('Track 2 Lyrics'));
      });

      test('navigating back to earlier track (1 -> 2 -> 1) mints fresh token and resolves Track 1', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((request) async {
            final title = request.url.queryParameters['track_name'] ?? '';
            return http.Response(
              jsonEncode({
                'id': title.hashCode,
                'name': title,
                'trackName': title,
                'artistName': 'Artist',
                'syncedLyrics': '[00:05.00]Lyrics for $title',
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);

        playbackController.setTrack(createQueueItem(uri: 'file:///1.mp3', title: 'Track 1'));
        await Future<void>.delayed(const Duration(milliseconds: 25));

        playbackController.setTrack(createQueueItem(uri: 'file:///2.mp3', title: 'Track 2'));
        await Future<void>.delayed(const Duration(milliseconds: 25));

        playbackController.setTrack(createQueueItem(uri: 'file:///1.mp3', title: 'Track 1'));
        await Future<void>.delayed(const Duration(milliseconds: 25));

        expect(controller.hasLyrics, isTrue);
        expect(controller.lines.first.text, equals('Lyrics for Track 1'));
      });

      test('disposing LyricsController cancels active tokens safely', () {
        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.dispose();
        // Subsequent track update does nothing and does not throw
        playbackController.setTrack(createQueueItem(uri: 'file:///after.mp3', title: 'After'));
        expect(controller.hasLyrics, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 3. HTTP 429 Cooldown & Deferred Upgrade
    // -------------------------------------------------------------------------
    group('3. HTTP 429 Cooldown & Deferred Upgrade', () {
      test('429 response with Retry-After <= 10s starts live countdown', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Rate Limited', 429, headers: {'Retry-After': '4'});
          }),
          minPacing: Duration.zero,
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);

        playbackController.setTrack(
          createQueueItem(uri: 'file:///limited.mp3', title: 'Limited'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(controller.isThresholdWaiting, isTrue);
        expect(controller.thresholdCountdownSeconds, equals(4));

        cooldownManager.cancelThresholdCountdown();
      });

      test('429 response with Retry-After > 10s activates cooldown, falls back to lyrics.ovh and schedules upgrade', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response('Rate Limited', 429, headers: {'Retry-After': '60'});
          }),
          minPacing: Duration.zero,
        );

        int ovhCalls = 0;
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhCalls++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);

        final track = createQueueItem(uri: 'file:///cooldown.mp3', title: 'Cooldown Song');
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(ovhCalls, equals(1));
        expect(controller.hasLyrics, isTrue);
        expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(controller.isCooldownActive, isTrue);
      });

      test('cooldown expiration on active track triggers deferred upgrade to lrclib.net', () async {
        int lrclibCalls = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibCalls++;
            if (lrclibCalls == 1) {
              return http.Response('Rate Limited', 429, headers: {'Retry-After': '60'});
            } else {
              return http.Response(
                jsonEncode({
                  'id': 99,
                  'name': 'Cooldown Song',
                  'trackName': 'Cooldown Song',
                  'artistName': 'Artist',
                  'syncedLyrics': sampleSyncedLrc,
                }),
                200,
              );
            }
          }),
          minPacing: Duration.zero,
        );

        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);

        final track = createQueueItem(uri: 'file:///cooldown2.mp3', title: 'Cooldown Song');
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(controller.isSynced, isFalse);

        // Simulate cooldown expiry
        await cooldownManager.expireCooldownAndTriggerUpgrade();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Upgraded to synchronized lrclib.net lyrics!
        expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
        expect(controller.isSynced, isTrue);
      });

      test('natural timer expiration in real time auto-upgrades active track to lrclib.net without helper', () async {
        int lrclibCalls = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibCalls++;
            return http.Response(
              jsonEncode({
                'trackName': 'Natural Cooldown Song',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async =>
              http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200)),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);
        // Set short 120ms cooldown for fast deterministic test
        cooldownManager.setCooldown(const Duration(milliseconds: 120));

        final track = createQueueItem(
          uri: 'file:///natural_cooldown.mp3',
          title: 'Natural Cooldown Song',
        );
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
        expect(controller.isSynced, isFalse);
        expect(lrclibCalls, equals(0));
        expect(cooldownManager.isDeferredRetryScheduled, isTrue);

        // Wait 160ms for natural timer expiration in Dart event loop
        await Future<void>.delayed(const Duration(milliseconds: 160));

        // Upgraded naturally without any test helper!
        expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
        expect(controller.isSynced, isTrue);
        expect(lrclibCalls, equals(1));
      });

      test('closing lyrics view cancels deferred retry timer', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: Duration.zero,
        );
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async =>
              http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200)),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);
        cooldownManager.setCooldown(const Duration(seconds: 30));

        final track = createQueueItem(
          uri: 'file:///cancel_deferred.mp3',
          title: 'Cancel Deferred Song',
        );
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(cooldownManager.isDeferredRetryScheduled, isTrue);

        // Close lyrics view
        controller.setLyricsViewVisible(false);
        expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      });

      test('disabling lrclib in sources config cancels deferred retry timer', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: Duration.zero,
        );
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async =>
              http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200)),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);
        cooldownManager.setCooldown(const Duration(seconds: 30));

        final track = createQueueItem(
          uri: 'file:///disable_lrclib.mp3',
          title: 'Disable Lrclib Song',
        );
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(cooldownManager.isDeferredRetryScheduled, isTrue);

        // Disable lrclib
        controller.setSourcesConfig(lrclib: false);
        expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      });

      test('disposing controller cancels deferred retry timer', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          minPacing: Duration.zero,
        );
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async =>
              http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200)),
        );

        final cooldownManager = LyricsCooldownManager();
        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);
        cooldownManager.setCooldown(const Duration(seconds: 30));

        final track = createQueueItem(
          uri: 'file:///dispose_cancel.mp3',
          title: 'Dispose Cancel Song',
        );
        playbackController.setTrack(track);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(cooldownManager.isDeferredRetryScheduled, isTrue);

        // Dispose controller
        controller.dispose();
        expect(cooldownManager.isDeferredRetryScheduled, isFalse);
      });

      test('skipping to Track B during cooldown skips lrclib.net and queries lyrics.ovh', () async {
        int lrclibCalls = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibCalls++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        int ovhCalls = 0;
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhCalls++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final cooldownManager = LyricsCooldownManager();
        cooldownManager.setCooldown(const Duration(minutes: 5)); // Pre-activate cooldown

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        controller.setLyricsViewVisible(true);

        playbackController.setTrack(
          createQueueItem(uri: 'file:///track_b.mp3', title: 'Track B'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        // lrclib was completely skipped, ovh was queried
        expect(lrclibCalls, equals(0));
        expect(ovhCalls, equals(1));
        expect(controller.currentLyricsSource, equals(LyricsSource.lyricsOvh));
      });
    });

    // -------------------------------------------------------------------------
    // 4. Source Configuration Switches & Force Re-Search
    // -------------------------------------------------------------------------
    group('4. Source Configuration Switches & Force Re-Search', () {
      test('disabling lrclib dismisses active threshold countdown', () {
        final cooldownManager = LyricsCooldownManager();
        cooldownManager.startThresholdCountdown(
          seconds: 5,
          onAutoRetry: () async {},
        );

        final service = LyricsService(database: db, cooldownManager: cooldownManager);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          cooldownManager: cooldownManager,
        );

        expect(controller.isThresholdWaiting, isTrue);

        controller.setSourcesConfig(lrclib: false);

        expect(controller.isThresholdWaiting, isFalse);
        expect(controller.enableLrclib, isFalse);
      });

      test('forceReSearch forces reload with forceRefresh: true', () async {
        int queries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            queries++;
            return http.Response(
              jsonEncode({
                'id': 123,
                'name': 'Search Track',
                'trackName': 'Search Track',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);

        final track = createQueueItem(uri: 'file:///research.mp3', title: 'Search Track');
        playbackController.setTrack(track);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(queries, equals(1));

        // User clicks "Volver a buscar"
        await controller.forceReSearch();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(queries, equals(2));
      });
    });

    // -------------------------------------------------------------------------
    // 5. Translation & Display Modes
    // -------------------------------------------------------------------------
    group('5. Translation & Display Modes', () {
      test('translateLyrics translates lines and toggles modes', () async {
        final mockTranslation = LyricsTranslationClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'responseData': {
                  'translatedText': 'Esperando en un auto\nEsperando por un viaje\nLa ciudad es mi iglesia',
                  'match': 1.0,
                },
                'responseStatus': 200,
              }),
              200,
            );
          }),
        );

        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
          translationClient: mockTranslation,
        );

        controller.setLyricsViewVisible(true);
        playbackController.setTrack(
          createQueueItem(uri: 'file:///tr.mp3', title: 'Tr', lyrics: sampleSyncedLrc),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.hasLyrics, isTrue);
        expect(controller.isTranslated, isFalse);

        await controller.translateLyrics(targetLanguage: 'es');

        expect(controller.isTranslated, isTrue);
        expect(controller.translatedLines.length, equals(3));
        expect(controller.translatedLines.first, equals('Esperando en un auto'));

        // Cycle translation: translated -> interleaved -> original
        await controller.toggleTranslation();
        expect(controller.displayMode, equals(LyricsDisplayMode.interleaved));
        expect(controller.isInterleaved, isTrue);

        await controller.toggleTranslation();
        expect(controller.displayMode, equals(LyricsDisplayMode.original));
        expect(controller.isTranslated, isFalse);

        controller.toggleInterleaved();
        expect(controller.isInterleaved, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 6. Tap-to-Seek & Manual Scroll Lock
    // -------------------------------------------------------------------------
    group('6. Tap-to-Seek & Manual Scroll Lock', () {
      test('seekToLine seeks playback to lyric line timestamp', () async {
        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        controller.setLyricsViewVisible(true);
        playbackController.setTrack(
          createQueueItem(uri: 'file:///seek.mp3', title: 'Seek Track', lyrics: sampleSyncedLrc),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.lines.length, equals(3));
        expect(playbackController.position, equals(Duration.zero));

        // Tap on line index 1 (timestamp: 20.0s)
        await controller.seekToLine(1);

        expect(playbackController.position, equals(const Duration(seconds: 20)));
        expect(controller.currentIndex, equals(1));
      });

      test('onUserScroll engages scroll lock and resumeAutoScroll releases it', () {
        final service = LyricsService(database: db);
        final controller = LyricsController(
          lyricsService: service,
          playbackController: playbackController,
        );

        expect(controller.isUserScrollLocked, isFalse);

        controller.onUserScroll();
        expect(controller.isUserScrollLocked, isTrue);

        controller.resumeAutoScroll();
        expect(controller.isUserScrollLocked, isFalse);
      });
    });
  });
}
