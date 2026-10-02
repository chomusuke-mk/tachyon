import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';

/// Test spy for PlaybackController.
class SpyPlaybackController extends ChangeNotifier implements PlaybackController {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SpyPlaybackController playbackController;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.inMemory();
    playbackController = SpyPlaybackController();
    tempDir = await Directory.systemTemp.createTemp('visibility_gating_adv_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const sampleSyncedLrc = '''
[ti:Test Title]
[ar:Test Artist]
[00:05.00]Line 1
[00:10.00]Line 2
[00:15.00]Line 3
''';

  LyricsController createController({
    required LyricsService lyricsService,
    required PlaybackController playbackController,
  }) {
    final backend = DirectTachyonBackendClient(
      database: db,
      lyricsService: lyricsService,
    );
    return LyricsController(
      backendClient: backend,
      playbackController: playbackController,
      settingsRepository: _FakeSettingsRepo(),
      cooldownManager: lyricsService.cooldownManager,
    );
  }

  QueueItem createQueueItem({
    required String uri,
    required String title,
    String artist = 'Test Artist',
    String album = 'Test Album',
    Duration duration = const Duration(seconds: 180),
    String? lyrics,
  }) {
    return QueueItem(
      id: 'q_${uri.hashCode}',
      filePath: uri,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      extras: lyrics != null ? {'lyrics': lyrics} : const {},
    );
  }

  group('Visibility Gating Adversarial Stress Suite', () {
    // -------------------------------------------------------------------------
    // Scenario 1: Passive Background Song Changes Burst (Zero Network Guarantee)
    // -------------------------------------------------------------------------
    test('100 consecutive background song changes emit ZERO network calls', () async {
      int lrclibCount = 0;
      int ovhCount = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCount++;
          return http.Response('{"syncedLyrics": "$sampleSyncedLrc"}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          ovhCount++;
          return http.Response('{"lyrics": "Line 1\\nLine 2"}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      expect(controller.isLyricsViewVisible, isFalse);

      // Simulate 100 song changes rapidly in background
      for (int i = 1; i <= 100; i++) {
        playbackController.setTrack(
          createQueueItem(
            uri: 'file:///music/bg_track_$i.mp3',
            title: 'Background Track $i',
            artist: 'Background Artist $i',
          ),
        );
        // Vary interval slightly: 0ms, 1ms, 2ms
        if (i % 10 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert ABSOLUTE ZERO network traffic
      expect(lrclibCount, equals(0), reason: 'lrclib must never be called while isLyricsViewVisible is false');
      expect(ovhCount, equals(0), reason: 'lyrics.ovh must never be called while isLyricsViewVisible is false');
      expect(controller.hasLyrics, isFalse);
      expect(controller.isLoading, isFalse);
    });

    // -------------------------------------------------------------------------
    // Scenario 2: Background Playback with Local Embedded & File Lyrics
    // -------------------------------------------------------------------------
    test('background playback resolves local embedded lyrics without remote calls', () async {
      int lrclibCount = 0;
      int ovhCount = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCount++;
          return http.Response('{}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          ovhCount++;
          return http.Response('{}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      expect(controller.isLyricsViewVisible, isFalse);

      // Song with embedded lyrics played in background
      playbackController.setTrack(
        createQueueItem(
          uri: 'file:///music/embedded.mp3',
          title: 'Embedded Song',
          lyrics: sampleSyncedLrc,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lrclibCount, equals(0));
      expect(ovhCount, equals(0));
      expect(controller.hasLyrics, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.embedded));
      expect(controller.lines.length, equals(3));
    });

    test('background playback resolves local .lrc file without remote calls', () async {
      int lrclibCount = 0;
      int ovhCount = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCount++;
          return http.Response('{}', 200);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          ovhCount++;
          return http.Response('{}', 200);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      // Create contiguous .lrc file in tempDir
      final audioFile = File('${tempDir.path}/song.flac');
      await audioFile.writeAsString('audio');
      final lrcFile = File('${tempDir.path}/song.lrc');
      await lrcFile.writeAsString(sampleSyncedLrc);

      playbackController.setTrack(
        createQueueItem(
          uri: audioFile.path,
          title: 'Local File Song',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lrclibCount, equals(0));
      expect(ovhCount, equals(0));
      expect(controller.hasLyrics, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.file));
    });

    // -------------------------------------------------------------------------
    // Scenario 3: Activation of LyricsView triggers immediate remote resolution
    // -------------------------------------------------------------------------
    test('calling setLyricsViewVisible(true) immediately triggers remote resolution for active track', () async {
      int lrclibCount = 0;
      final lrclibCompleter = Completer<void>();

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCount++;
          await lrclibCompleter.future;
          return http.Response(
            jsonEncode({
              'trackName': 'Remote Song',
              'artistName': 'Test Artist',
              'syncedLyrics': sampleSyncedLrc,
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

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      // Play song without local lyrics in background
      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/remote.mp3', title: 'Remote Song'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lrclibCount, equals(0));
      expect(controller.hasLyrics, isFalse);

      // User now opens LyricsView
      controller.setLyricsViewVisible(true);
      expect(controller.isLyricsViewVisible, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Remote query must have been dispatched
      expect(lrclibCount, equals(1));
      expect(controller.isLoading, isTrue);

      // Finish remote request
      lrclibCompleter.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isLoading, isFalse);
      expect(controller.hasLyrics, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
      expect(controller.lines.length, equals(3));
    });

    // -------------------------------------------------------------------------
    // Scenario 4: Track change while isLyricsViewVisible == true resolves remotely
    // -------------------------------------------------------------------------
    test('track change while isLyricsViewVisible == true triggers remote resolution immediately', () async {
      final requestedTracks = <String>[];

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final uri = req.url;
          final trackName = uri.queryParameters['track_name'] ?? '';
          requestedTracks.add(trackName);
          return http.Response(
            jsonEncode({
              'trackName': trackName,
              'artistName': 'Test Artist',
              'syncedLyrics': '[00:05.00] Lyrics for $trackName',
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

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      controller.setLyricsViewVisible(true);

      // Play Track 1
      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/t1.mp3', title: 'Track One'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(requestedTracks, contains('Track One'));
      expect(controller.lines.any((l) => l.text.contains('Lyrics for Track One')), isTrue);

      // Switch to Track 2 while still visible
      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/t2.mp3', title: 'Track Two'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(requestedTracks, contains('Track Two'));
      expect(controller.lines.any((l) => l.text.contains('Lyrics for Track Two')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 5: Closing LyricsView mid-flight cancels network request cleanly
    // -------------------------------------------------------------------------
    test('setLyricsViewVisible(false) mid-flight cancels token, resets loading, and discards response', () async {
      final requestStarted = Completer<void>();
      final requestHold = Completer<void>();
      int serverResponseCount = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          requestStarted.complete();
          await requestHold.future;
          serverResponseCount++;
          return http.Response(
            jsonEncode({'syncedLyrics': sampleSyncedLrc}),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      controller.setLyricsViewVisible(true);

      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/midflight.mp3', title: 'Mid Flight'),
      );

      // Wait until HTTP request actually starts
      await requestStarted.future;
      expect(controller.isLoading, isTrue);

      // User closes LyricsView while request is in flight
      controller.setLyricsViewVisible(false);

      expect(controller.isLyricsViewVisible, isFalse);
      expect(controller.isLoading, isFalse);

      // Now server responds
      requestHold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Result must NOT be applied to controller!
      expect(serverResponseCount, equals(1));
      expect(controller.hasLyrics, isFalse);
      expect(controller.lyrics, isNull);
    });

    // -------------------------------------------------------------------------
    // Scenario 6: Rapid Visibility Toggling (Jitter / Fast Switching)
    // -------------------------------------------------------------------------
    test('rapid visibility toggling (true -> false -> true -> false) cleanly cancels tokens', () async {
      int lrclibCalls = 0;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({'syncedLyrics': sampleSyncedLrc}),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/toggle.mp3', title: 'Toggle Song'),
      );

      // Rapidly toggle visibility: true -> false -> true -> false
      controller.setLyricsViewVisible(true);
      controller.setLyricsViewVisible(false);
      controller.setLyricsViewVisible(true);
      controller.setLyricsViewVisible(false);

      expect(controller.isLyricsViewVisible, isFalse);
      expect(controller.isLoading, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Final state was false, so controller must NOT hold lyrics
      expect(controller.hasLyrics, isFalse);
      expect(lrclibCalls, greaterThanOrEqualTo(0));
    });

    test('rapid visibility toggling ending in true resolves active track lyrics', () async {
      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({'syncedLyrics': sampleSyncedLrc}),
            200,
          );
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/toggle_true.mp3', title: 'Toggle True'),
      );

      // Fast toggle ending in true
      controller.setLyricsViewVisible(true);
      controller.setLyricsViewVisible(false);
      controller.setLyricsViewVisible(true);

      expect(controller.isLyricsViewVisible, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.hasLyrics, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));
    });

    // -------------------------------------------------------------------------
    // Scenario 7: SQLite Caching: NOT_FOUND Prevents Redundant Network Calls
    // -------------------------------------------------------------------------
    test('NOT_FOUND response is cached in SQLite and prevents any subsequent network calls', () async {
      final lrclibCallsByTrack = <String, int>{};
      final ovhCallsByTrack = <String, int>{};

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          lrclibCallsByTrack[title] = (lrclibCallsByTrack[title] ?? 0) + 1;
          return http.Response('{"message": "Track not found"}', 404);
        }),
        minPacing: Duration.zero,
      );

      final ovhClient = LyricsOvhClient(
        httpClient: MockClient((req) async {
          final segments = req.url.pathSegments;
          final title = segments.isNotEmpty ? Uri.decodeComponent(segments.last) : '';
          ovhCallsByTrack[title] = (ovhCallsByTrack[title] ?? 0) + 1;
          return http.Response('{"error": "No lyrics found"}', 404);
        }),
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: ovhClient,
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      final track404 = createQueueItem(
        uri: 'file:///music/not_found_song.mp3',
        title: 'Non-Existent Song',
        artist: 'Unknown Artist',
      );

      // 1. Play track with LyricsView active -> initial remote search triggers 404s
      controller.setLyricsViewVisible(true);
      playbackController.setTrack(track404);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lrclibCallsByTrack['Non-Existent Song'], equals(1));
      expect(ovhCallsByTrack['Non-Existent Song'], equals(1));
      expect(controller.hasLyrics, isFalse);

      // Verify SQLite persisted NOT_FOUND for both
      final keyHash = LyricsService.computeLyricsKey(
        filePath: track404.filePath,
        title: track404.title,
        artist: track404.artist,
        durationMs: track404.duration.inMilliseconds,
      );
      final entries = await db.getAllLyricsSourceEntries(keyHash);
      expect(entries[LyricsSource.lrclib]?.state, equals(LyricsSourceState.notFound));
      expect(entries[LyricsSource.lyricsOvh]?.state, equals(LyricsSourceState.notFound));

      // 2. Play another track, then switch BACK to track404
      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/other.mp3', title: 'Other'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      playbackController.setTrack(track404);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Calls for track404 MUST NOT have incremented!
      expect(lrclibCallsByTrack['Non-Existent Song'], equals(1), reason: 'NOT_FOUND cached entry must not trigger new lrclib query');
      expect(ovhCallsByTrack['Non-Existent Song'], equals(1), reason: 'NOT_FOUND cached entry must not trigger new ovh query');

      // 3. User clicks force re-search ("Volver a buscar")
      await controller.forceReSearch();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Calls MUST now increment because forceRefresh: true clears the cache
      expect(lrclibCallsByTrack['Non-Existent Song'], equals(2), reason: 'forceReSearch must clear NOT_FOUND cache and retry');
      expect(ovhCallsByTrack['Non-Existent Song'], equals(2), reason: 'forceReSearch must clear NOT_FOUND cache and retry');
    });

    // -------------------------------------------------------------------------
    // Scenario 8: SQLite Caching: TEMPORARY_ERROR Permits Subsequent Retry
    // -------------------------------------------------------------------------
    test('TEMPORARY_ERROR response is recorded in SQLite but does NOT prevent subsequent retries', () async {
      final lrclibCallsByTrack = <String, int>{};
      bool serverRecovered = false;

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final title = req.url.queryParameters['track_name'] ?? '';
          lrclibCallsByTrack[title] = (lrclibCallsByTrack[title] ?? 0) + 1;
          if (!serverRecovered) {
            return http.Response('Server Error', 500);
          } else {
            return http.Response(
              jsonEncode({
                'trackName': 'Error Song',
                'artistName': 'Test Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }
        }),
        minPacing: Duration.zero,
      );

      final service = LyricsService(
        database: db,
        lrclibClient: lrclibClient,
        lyricsOvhClient: LyricsOvhClient(
          httpClient: MockClient((req) async => http.Response('{}', 404)),
        ),
      );

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      final track500 = createQueueItem(
        uri: 'file:///music/server_error.mp3',
        title: 'Error Song',
      );

      controller.setLyricsViewVisible(true);
      playbackController.setTrack(track500);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lrclibCallsByTrack['Error Song'], equals(1));
      expect(controller.hasLyrics, isFalse);

      // Verify SQLite persisted TEMPORARY_ERROR
      final keyHash = LyricsService.computeLyricsKey(
        filePath: track500.filePath,
        title: track500.title,
        artist: track500.artist,
        durationMs: track500.duration.inMilliseconds,
      );
      final entries = await db.getAllLyricsSourceEntries(keyHash);
      expect(entries[LyricsSource.lrclib]?.state, equals(LyricsSourceState.temporaryError));

      // Server recovers!
      serverRecovered = true;

      // Play track again on normal track transition
      playbackController.setTrack(
        createQueueItem(uri: 'file:///music/temp.mp3', title: 'Temp'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      playbackController.setTrack(track500);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // lrclib MUST be retried because temporaryError does not block queries
      expect(lrclibCallsByTrack['Error Song'], equals(2), reason: 'TEMPORARY_ERROR must allow automatic retry on next play');
      expect(controller.hasLyrics, isTrue);
      expect(controller.currentLyricsSource, equals(LyricsSource.lrclib));

      // SQLite entry should now be updated to FOUND
      final updatedEntries = await db.getAllLyricsSourceEntries(keyHash);
      expect(updatedEntries[LyricsSource.lrclib]?.state, equals(LyricsSourceState.found));
    });

    // -------------------------------------------------------------------------
    // Scenario 9: Rapid Skips with Interspersed Visibility Toggles
    // -------------------------------------------------------------------------
    test('interspersed background skips, view open, skip, close, and re-open', () async {
      final queriedTracks = <String>[];

      final lrclibClient = LrclibClient(
        httpClient: MockClient((req) async {
          final trackName = req.url.queryParameters['track_name'] ?? '';
          queriedTracks.add(trackName);
          return http.Response(
            jsonEncode({
              'trackName': trackName,
              'syncedLyrics': '[00:01.00] $trackName',
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

      final controller = createController(
        lyricsService: service,
        playbackController: playbackController,
      );

      // 1. In background: skip Track 1 -> Track 2 -> Track 3
      playbackController.setTrack(createQueueItem(uri: 'f:///1.mp3', title: 'T1'));
      playbackController.setTrack(createQueueItem(uri: 'f:///2.mp3', title: 'T2'));
      playbackController.setTrack(createQueueItem(uri: 'f:///3.mp3', title: 'T3'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queriedTracks, isEmpty, reason: 'Zero network calls while in background');

      // 2. Open LyricsView on Track 3
      controller.setLyricsViewVisible(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(queriedTracks, equals(['T3']));
      expect(controller.lines.any((l) => l.text.contains('T3')), isTrue);

      // 3. Skip to Track 4, then immediately close LyricsView
      playbackController.setTrack(createQueueItem(uri: 'f:///4.mp3', title: 'T4'));
      controller.setLyricsViewVisible(false);

      // 4. In background, skip to Track 5
      playbackController.setTrack(createQueueItem(uri: 'f:///5.mp3', title: 'T5'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Track 5 should NOT have been queried
      expect(queriedTracks.contains('T5'), isFalse);

      // 5. Open LyricsView on Track 5
      controller.setLyricsViewVisible(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queriedTracks.contains('T5'), isTrue);
      expect(controller.lines.any((l) => l.text.contains('T5')), isTrue);
    });
  });
}
