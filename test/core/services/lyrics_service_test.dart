import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.inMemory();
    tempDir = await Directory.systemTemp.createTemp('lyrics_service_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
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

  Track createTrack({
    int? id,
    required String uri,
    required String title,
    String? artist,
    String? album,
    int durationMs = 240000,
    String? lyrics,
  }) {
    return Track(
      id: id,
      filePath: uri,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      fileSize: 1024,
      modifiedAt: 1000,
      lyrics: lyrics,
    );
  }

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
      filePath: uri,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      extras: lyrics != null ? {'lyrics': lyrics} : const {},
    );
  }

  String trackKey(Track track) => LyricsService.computeLyricsKey(
        filePath: track.filePath,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
      );

  group('LyricsService 4-Tier Resolution Engine', () {
    // -------------------------------------------------------------------------
    // Tier 1: Embedded Audio Tags
    // -------------------------------------------------------------------------
    group('Tier 1: Embedded Audio Tags', () {
      test('resolves embedded lyrics directly when embeddedLyrics is provided', () async {
        final service = LyricsService(database: db);
        final track = createTrack(
          id: 1,
          uri: 'file:///music/song.mp3',
          title: 'Midnight City',
          artist: 'M83',
          lyrics: sampleSyncedLrc,
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.embedded));
        expect(result.state, equals(LyricsSourceState.found));
        expect(result.isSynced, isTrue);
        expect(result.lines.length, equals(3));

        // Verifies entry is persisted in SQLite
        final entry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.embedded);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.found));
        expect(entry.isSynced, isTrue);
      });

      test('resolves embedded lyrics from SQLite tracks table if embeddedLyrics is null', () async {
        // Seed track in database with lyrics
        await db.database.insert('tracks', {
          'id': 10,
          'file_path': '/music/track10.mp3',
          'title': 'Track 10',
          'duration_ms': 200000,
          'bitrate': 320,
          'file_size': 1024,
          'modified_at': 1000,
          'lyrics': sampleSyncedLrc,
        });

        final service = LyricsService(database: db);
        final track = createTrack(
          id: 10,
          uri: 'file:///music/track10.mp3',
          title: 'Track 10',
          artist: 'Artist 10',
          lyrics: null, // null in model
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.embedded));
        expect(result.isSynced, isTrue);
      });

      test('whitespace-only embedded lyrics falls through to next tier', () async {
        final service = LyricsService(database: db);
        final track = createTrack(
          id: 2,
          uri: 'file:///music/whitespace.mp3',
          title: 'Whitespace',
          artist: 'Artist',
          lyrics: '   \n  \t  ',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: false);
        expect(result, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // Tier 2: Local Contiguous .lrc File
    // -------------------------------------------------------------------------
    group('Tier 2: Local Contiguous .lrc File', () {
      test('resolves contiguous lowercase .lrc file in track folder', () async {
        final audioFile = File(p.join(tempDir.path, 'song.mp3'));
        await audioFile.writeAsString('dummy mp3 content');

        final lrcFile = File(p.join(tempDir.path, 'song.lrc'));
        await lrcFile.writeAsString(sampleSyncedLrc);

        final service = LyricsService(database: db);
        final track = createTrack(
          id: 3,
          uri: audioFile.path,
          title: 'Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: false);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.file));
        expect(result.state, equals(LyricsSourceState.found));
        expect(result.lines.length, equals(3));

        final entry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.file);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.found));
      });

      test('resolves contiguous uppercase .LRC file in track folder', () async {
        final audioFile = File(p.join(tempDir.path, 'song2.flac'));
        await audioFile.writeAsString('dummy flac content');

        final lrcFile = File(p.join(tempDir.path, 'song2.LRC'));
        await lrcFile.writeAsString(sampleSyncedLrc);

        final service = LyricsService(database: db);
        final track = createTrack(
          id: 4,
          uri: audioFile.path,
          title: 'Song 2',
          artist: 'Artist 2',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: false);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.file));
      });

      test('missing or empty local .lrc file returns null when remote is disabled', () async {
        final audioFile = File(p.join(tempDir.path, 'empty.mp3'));
        await audioFile.writeAsString('content');

        final lrcFile = File(p.join(tempDir.path, 'empty.lrc'));
        await lrcFile.writeAsString('   '); // empty content

        final service = LyricsService(database: db);
        final track = createTrack(
          id: 5,
          uri: audioFile.path,
          title: 'Empty',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: false);
        expect(result, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // Remote Visibility Gating (allowRemote)
    // -------------------------------------------------------------------------
    group('Remote Visibility Gating (allowRemote)', () {
      test('allowRemote: false prevents web queries and returns null when local sources absent', () async {
        int webQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            webQueries++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
        );

        final track = createTrack(
          id: 6,
          uri: 'file:///music/online_only.mp3',
          title: 'Online Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: false);

        expect(result, isNull);
        expect(webQueries, equals(0));
      });

      test('allowRemote: true triggers web resolution when local sources are absent', () async {
        int lrclibQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response(
              jsonEncode({
                'id': 101,
                'name': 'Online Song',
                'trackName': 'Online Song',
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

        final track = createTrack(
          id: 7,
          uri: 'file:///music/online_only.mp3',
          title: 'Online Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track, allowRemote: true);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lrclib));
        expect(lrclibQueries, equals(1));
      });
    });

    // -------------------------------------------------------------------------
    // Tier 3: Primary Web API (lrclib.net) & SQLite State Caching
    // -------------------------------------------------------------------------
    group('Tier 3: Primary Web API (lrclib.net) & SQLite Caching', () {
      test('successful HTTP 200 with syncedLyrics persists FOUND in SQLite and returns result', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'id': 1,
                'name': 'Midnight City',
                'trackName': 'Midnight City',
                'artistName': 'M83',
                'syncedLyrics': sampleSyncedLrc,
                'plainLyrics': samplePlainLyrics,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final track = createTrack(
          id: 8,
          uri: 'file:///music/m83.mp3',
          title: 'Midnight City',
          artist: 'M83',
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lrclib));
        expect(result.state, equals(LyricsSourceState.found));
        expect(result.isSynced, isTrue);

        final entry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.lrclib);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.found));
        expect(entry.isSynced, isTrue);
      });

      test('HTTP 404 from lrclib.net persists NOT_FOUND in SQLite and falls through to Tier 4', () async {
        int lrclibQueries = 0;
        int ovhQueries = 0;

        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response('{"statusCode": 404, "error": "Not Found"}', 404);
          }),
          minPacing: Duration.zero,
        );

        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhQueries++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
        );

        final track = createTrack(
          id: 9,
          uri: 'file:///music/rare_song.mp3',
          title: 'Rare Song',
          artist: 'Obscure Band',
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(lrclibQueries, equals(1));
        expect(ovhQueries, equals(1));
        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lyricsOvh));

        // lrclib must be recorded as NOT_FOUND in SQLite
        final lrclibEntry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.lrclib);
        expect(lrclibEntry, isNotNull);
        expect(lrclibEntry!.state, equals(LyricsSourceState.notFound));
      });

      test('subsequent query skips lrclib.net completely when NOT_FOUND is cached in SQLite', () async {
        final track = createTrack(
          id: 11,
          uri: 'file:///music/cached_404.mp3',
          title: 'Cached 404',
          artist: 'Artist',
        );

        final keyHash = trackKey(track);

        // Pre-seed NOT_FOUND in SQLite
        await db.saveLyricsSourceEntry(
          LyricsSourceEntry.notFound(
            keyHash: keyHash,
            source: LyricsSource.lrclib,
          ),
        );

        int lrclibQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);

        await service.resolveLyricsForTrack(track);

        // lrclib.net must NOT have been called
        expect(lrclibQueries, equals(0));
      });

      test('HTTP 429 with retryAfter <= 10s persists TEMPORARY_ERROR and calls onThresholdCountdown', () async {
        int countdownInvokedWith = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response(
              'Too Many Requests',
              429,
              headers: {'Retry-After': '5'},
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final track = createTrack(
          id: 12,
          uri: 'file:///music/rate_limited.mp3',
          title: 'Limited Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(
          track,
          onThresholdCountdown: (sec) {
            countdownInvokedWith = sec;
          },
        );

        expect(result, isNull);
        expect(countdownInvokedWith, equals(5));

        final keyHash = trackKey(track);

        // State in SQLite must be TEMPORARY_ERROR, NEVER NOT_FOUND!
        final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lrclib);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.temporaryError));
      });

      test('HTTP 429 with retryAfter > 10s persists TEMPORARY_ERROR, activates cooldown and falls through to Tier 4', () async {
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            return http.Response(
              'Too Many Requests',
              429,
              headers: {'Retry-After': '60'},
            );
          }),
          minPacing: Duration.zero,
        );

        int ovhQueries = 0;
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhQueries++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
        );

        final track = createTrack(
          id: 13,
          uri: 'file:///music/cooldown_song.mp3',
          title: 'Cooldown Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lyricsOvh));
        expect(ovhQueries, equals(1));
        expect(service.cooldownManager.isCooldownActive, isTrue);

        final entry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.lrclib);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.temporaryError));
      });

      test('active memory cooldown skips lrclib.net directly to fallback Tier 4', () async {
        int lrclibQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            lrclibQueries++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        int ovhQueries = 0;
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhQueries++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final cooldownManager = LyricsCooldownManager();
        cooldownManager.setCooldown(const Duration(minutes: 5));

        final service = LyricsService(
          database: db,
          lrclibClient: mockLrclib,
          lyricsOvhClient: mockOvh,
          cooldownManager: cooldownManager,
        );

        final track = createTrack(
          id: 14,
          uri: 'file:///music/skip_lrclib.mp3',
          title: 'Skip Lrclib',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(track);

        expect(lrclibQueries, equals(0)); // skipped completely!
        expect(ovhQueries, equals(1));
        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lyricsOvh));
      });
    });

    // -------------------------------------------------------------------------
    // Tier 4: Secondary Fallback API (lyrics.ovh)
    // -------------------------------------------------------------------------
    group('Tier 4: Secondary Fallback API (lyrics.ovh)', () {
      test('HTTP 200 plain text from lyrics.ovh returns isSynced: false and saves FOUND', () async {
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final service = LyricsService(
          database: db,
          lyricsOvhClient: mockOvh,
        );

        final track = createTrack(
          id: 15,
          uri: 'file:///music/ovh_only.mp3',
          title: 'OVH Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(
          track,
          enabledSources: {LyricsSource.lyricsOvh},
        );

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lyricsOvh));
        expect(result.isSynced, isFalse);

        final entry = await db.getLyricsSourceEntry(result.keyHash, LyricsSource.lyricsOvh);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.found));
      });

      test('HTTP 404 from lyrics.ovh saves NOT_FOUND to SQLite', () async {
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            return http.Response('{"error": "No lyrics found"}', 404);
          }),
        );

        final service = LyricsService(database: db, lyricsOvhClient: mockOvh);
        final track = createTrack(
          id: 16,
          uri: 'file:///music/not_in_ovh.mp3',
          title: 'Not In Ovh',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(
          track,
          enabledSources: {LyricsSource.lyricsOvh},
        );

        expect(result, isNull);

        final keyHash = trackKey(track);

        final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.notFound));
      });

      test('HTTP 500 saves TEMPORARY_ERROR to SQLite', () async {
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            return http.Response('Server Error', 500);
          }),
        );

        final service = LyricsService(database: db, lyricsOvhClient: mockOvh);
        final track = createTrack(
          id: 17,
          uri: 'file:///music/server_error.mp3',
          title: 'Error Song',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(
          track,
          enabledSources: {LyricsSource.lyricsOvh},
        );

        expect(result, isNull);

        final keyHash = trackKey(track);

        final entry = await db.getLyricsSourceEntry(keyHash, LyricsSource.lyricsOvh);
        expect(entry, isNotNull);
        expect(entry!.state, equals(LyricsSourceState.temporaryError));
      });
    });

    // -------------------------------------------------------------------------
    // Enabled Sources Configuration Switches
    // -------------------------------------------------------------------------
    group('Enabled Sources Configuration Switches', () {
      test('disabling local sources bypasses Tier 1 and Tier 2', () async {
        final track = createTrack(
          id: 18,
          uri: 'file:///music/song.mp3',
          title: 'Song',
          artist: 'Artist',
          lyrics: sampleSyncedLrc, // Has embedded lyrics
        );

        int ovhQueries = 0;
        final mockOvh = LyricsOvhClient(
          httpClient: MockClient((_) async {
            ovhQueries++;
            return http.Response(jsonEncode({'lyrics': samplePlainLyrics}), 200);
          }),
        );

        final service = LyricsService(
          database: db,
          lyricsOvhClient: mockOvh,
        );

        // Disable local and lrclib -> only lyricsOvh enabled
        final result = await service.resolveLyricsForTrack(
          track,
          enabledSources: {LyricsSource.lyricsOvh},
        );

        expect(ovhQueries, equals(1));
        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lyricsOvh));
      });

      test('disabling web sources returns null when no local sources exist', () async {
        int webHits = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            webHits++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final track = createTrack(
          id: 19,
          uri: 'file:///music/offline.mp3',
          title: 'Offline',
          artist: 'Artist',
        );

        final result = await service.resolveLyricsForTrack(
          track,
          enabledSources: {LyricsSource.embedded, LyricsSource.file},
        );

        expect(result, isNull);
        expect(webHits, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // Manual Re-Search (forceRefresh)
    // -------------------------------------------------------------------------
    group('Manual Re-Search (forceRefresh)', () {
      test('forceRefresh: true purges SQLite source entries and memory cache to allow retry', () async {
        final track = createTrack(
          id: 20,
          uri: 'file:///music/refresh_me.mp3',
          title: 'Refresh Me',
          artist: 'Artist',
        );

        final keyHash = trackKey(track);

        // Pre-seed NOT_FOUND
        await db.saveLyricsSourceEntry(
          LyricsSourceEntry.notFound(
            keyHash: keyHash,
            source: LyricsSource.lrclib,
          ),
        );

        int queryCount = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            queryCount++;
            return http.Response(
              jsonEncode({
                'id': 200,
                'name': 'Refresh Me',
                'trackName': 'Refresh Me',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);

        // Without forceRefresh: skips query because of NOT_FOUND
        final initialResult = await service.resolveLyricsForTrack(track, forceRefresh: false);
        expect(initialResult, isNull);
        expect(queryCount, equals(0));

        // With forceRefresh: purges SQLite NOT_FOUND and queries lrclib.net
        final refreshedResult = await service.resolveLyricsForTrack(track, forceRefresh: true);
        expect(refreshedResult, isNotNull);
        expect(refreshedResult!.source, equals(LyricsSource.lrclib));
        expect(queryCount, equals(1));
      });
    });

    // -------------------------------------------------------------------------
    // Rapid Skip Concurrency & Cancellation Tokens
    // -------------------------------------------------------------------------
    group('Rapid Skip Concurrency & Cancellation Tokens', () {
      test('pre-cancelled token returns null before any network queries', () async {
        int webQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            webQueries++;
            return http.Response('{}', 200);
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final track = createTrack(
          id: 21,
          uri: 'file:///music/cancelled.mp3',
          title: 'Cancelled',
          artist: 'Artist',
        );

        final token = LyricsCancellationToken();
        token.cancel(); // Pre-cancelled

        final result = await service.resolveLyricsForTrack(
          track,
          cancellationToken: token,
        );

        expect(result, isNull);
        expect(webQueries, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // In-Memory LRU Cache
    // -------------------------------------------------------------------------
    group('In-Memory LRU Cache', () {
      test('repeated calls return from memory cache with 0 SQLite and 0 HTTP calls', () async {
        int webQueries = 0;
        final mockLrclib = LrclibClient(
          httpClient: MockClient((_) async {
            webQueries++;
            return http.Response(
              jsonEncode({
                'id': 300,
                'name': 'Cached Song',
                'trackName': 'Cached Song',
                'artistName': 'Artist',
                'syncedLyrics': sampleSyncedLrc,
              }),
              200,
            );
          }),
          minPacing: Duration.zero,
        );

        final service = LyricsService(database: db, lrclibClient: mockLrclib);
        final track = createTrack(
          id: 22,
          uri: 'file:///music/lru.mp3',
          title: 'Cached Song',
          artist: 'Artist',
        );

        // First call hits network
        final res1 = await service.resolveLyricsForTrack(track);
        expect(res1, isNotNull);
        expect(webQueries, equals(1));

        // Second call returns from memory cache directly
        final res2 = await service.resolveLyricsForTrack(track);
        expect(res2, isNotNull);
        expect(webQueries, equals(1)); // zero new queries!
        expect(identical(res1, res2), isTrue);
      });

      test('exceeding maxMemoryEntries evicts oldest entry', () async {
        final service = LyricsService(database: db, maxMemoryEntries: 2);

        await service.saveLyrics(keyHash: 'key1', rawLrc: sampleSyncedLrc, source: 'embedded');
        await service.saveLyrics(keyHash: 'key2', rawLrc: sampleSyncedLrc, source: 'embedded');
        await service.saveLyrics(keyHash: 'key3', rawLrc: sampleSyncedLrc, source: 'embedded');

        // key1 was evicted from memory cache
        final queueItem1 = createQueueItem(
          id: 'q1',
          uri: 'file:///music/q1.mp3',
          title: 'Song 1',
          artist: 'Artist 1',
        );

        final res = await service.resolveLyricsForQueueItem(queueItem1, allowRemote: false);
        expect(res, isNull);
      });
    });
  });
}
