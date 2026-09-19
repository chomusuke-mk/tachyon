import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';

/// Controlled mock repository supporting both randomized latency and explicit completer ordering
class ControllableMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> bundles;
  final Duration Function(String localeCode, int callIndex)? delayGenerator;
  final Completer<Map<String, String>> Function(String localeCode, int callIndex)? completerGenerator;
  int _callCount = 0;

  ControllableMockLocaleRepository(
    this.bundles, {
    this.delayGenerator,
    this.completerGenerator,
  });

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final idx = _callCount++;
    if (completerGenerator != null) {
      return completerGenerator!(localeCode, idx).future;
    }
    if (delayGenerator != null) {
      final delay = delayGenerator!(localeCode, idx);
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
    return Map<String, String>.from(bundles[localeCode] ?? <String, String>{});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ==========================================================================
  // EMPIRICAL CHALLENGE 1: Rapid Concurrent Locale Switching (1,000 Calls)
  // ==========================================================================
  group('Empirical Challenge 1: Rapid Concurrent Locale Switching (1,000 Calls)', () {
    final testBundles = <String, Map<String, String>>{
      'en': {
        'np_title': 'Now Playing',
        'np_play': 'Play',
        's_title': 'Settings',
      },
      'es': {
        'np_title': 'Reproduciendo Ahora',
        'np_play': 'Reproducir',
        's_title': 'Ajustes',
      },
      'fr': {
        'np_title': 'Lecture En Cours',
        'np_play': 'Lire',
        's_title': 'Paramètres',
      },
      'de': {
        'np_title': 'Aktuelle Wiedergabe',
        'np_play': 'Abspielen',
        's_title': 'Einstellungen',
      },
      'ja': {
        'np_title': '再生中',
        'np_play': '再生',
        's_title': '設定',
      },
    };

    test('1,000 rapid concurrent calls with randomized delays drops stale completions', () async {
      final random = math.Random(42);
      final languages = ['en', 'es', 'fr', 'de', 'ja'];

      final repo = ControllableMockLocaleRepository(
        testBundles,
        delayGenerator: (code, idx) {
          // Randomized jitter between 1ms and 15ms for non-fallback loads
          return Duration(milliseconds: 1 + random.nextInt(15));
        },
      );

      final controller = LocaleController(repo, 'en');
      await controller.whenReady;

      final futures = <Future<void>>[];
      String expectedFinalLocale = 'en';

      final sw = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        final target = languages[i % languages.length];
        expectedFinalLocale = target;
        futures.add(controller.setLocale(target));
      }

      await Future.wait(futures);
      sw.stop();

      // ignore: avoid_print
      print('1,000 concurrent locale switches completed in ${sw.elapsedMilliseconds}ms');

      final expectedTitle = testBundles[expectedFinalLocale]!['np_title']!;
      final expectedPlay = testBundles[expectedFinalLocale]!['np_play']!;

      expect(controller.currentLocaleCode, equals(expectedFinalLocale),
          reason: 'Active locale code must match the final requested target');
      expect(controller.localeStrings.npTitle, equals(expectedTitle),
          reason: 'Localised string must not be corrupted by stale async responses');
      expect(controller.localeStrings.npPlay, equals(expectedPlay));
    });

    test('Adversarial Inverted Completion: Request 1,000 completes first, Request 1 completes last', () async {
      final completers = List.generate(1000, (_) => Completer<Map<String, String>>());
      int requestCount = 0;

      final repo = ControllableMockLocaleRepository(
        testBundles,
        completerGenerator: (code, idx) {
          // idx == 0 is the controller._init() call loading fallback English
          if (idx == 0) {
            return Completer<Map<String, String>>()..complete(testBundles['en']!);
          }
          final c = completers[requestCount++];
          return c;
        },
      );

      final controller = LocaleController(repo, 'en');
      await controller.whenReady;

      // Queue 1,000 concurrent requests alternating between 'es' and 'fr'
      final futures = <Future<void>>[];
      final requestedCodes = <String>[];
      for (int i = 0; i < 1000; i++) {
        final code = i.isEven ? 'es' : 'fr';
        requestedCodes.add(code);
        futures.add(controller.setLocale(code));
      }

      expect(requestCount, equals(1000));
      final finalRequestedCode = requestedCodes.last; // index 999 is odd -> 'fr'
      expect(finalRequestedCode, equals('fr'));

      // Adversarial completion order:
      // Resolve request 999 FIRST
      completers[999].complete(testBundles['fr']!);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // At this point, request 999 has set the locale to 'fr'
      expect(controller.currentLocaleCode, equals('fr'));
      expect(controller.localeStrings.npTitle, equals('Lecture En Cours'));

      // Now resolve all previous requests (998 down to 0) in reverse order!
      for (int i = 998; i >= 0; i--) {
        final code = requestedCodes[i];
        completers[i].complete(testBundles[code]!);
      }

      await Future.wait(futures);

      // Verify that NONE of the 999 stale earlier completions overwrote 'fr'
      expect(controller.currentLocaleCode, equals('fr'));
      expect(controller.localeStrings.npTitle, equals('Lecture En Cours'),
          reason: 'Stale completions (from 998 down to 0) must be dropped by _loadRequestId');
      expect(controller.localeStrings.npPlay, equals('Lire'));
    });

    test('Alternating non-fallback async and warm synchronous fallback (1,000 calls)', () async {
      final repo = ControllableMockLocaleRepository(
        testBundles,
        delayGenerator: (code, idx) => const Duration(milliseconds: 2),
      );

      final controller = LocaleController(repo, 'en');
      await controller.whenReady;

      final futures = <Future<void>>[];
      // Alternating 'es' (async load) and 'en' (warm fallback cache)
      for (int i = 0; i < 1000; i++) {
        final target = i.isEven ? 'es' : 'en';
        futures.add(controller.setLocale(target));
      }

      await Future.wait(futures);

      // The 1,000th call (index 999) requested 'en'
      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(controller.localeStrings.npPlay, equals('Play'));
      expect(controller.localeStrings.sTitle, equals('Settings'));
    });
  });

  // ==========================================================================
  // EMPIRICAL CHALLENGE 2: LRC Timestamp Minute Range Parsing ([105:30.00], 1-digit)
  // ==========================================================================
  group('Empirical Challenge 2: LRC Parsing on Single-Digit and >= 100 Minutes', () {
    test('Single-digit minute timestamps parse correctly and compute precise millisecond timestamps', () {
      const lrcContent = '''
[0:05.00]Zero minute mark
[1:05.00]One minute five seconds
[2:00.12]Two minute centisecond check
[5:30.500]Five thirty millisecond check
[9:59.99]Nine fifty nine
''';

      final parsed = LyricLine.parseLrc(lrcContent);
      expect(parsed.length, equals(5));

      // 0:05.00 -> 5,000 ms
      expect(parsed[0].text, equals('Zero minute mark'));
      expect(parsed[0].isSynced, isTrue);
      expect(parsed[0].timestampMs, equals(5000));

      // 1:05.00 -> (1 * 60 + 5) * 1000 = 65,000 ms
      expect(parsed[1].text, equals('One minute five seconds'));
      expect(parsed[1].isSynced, isTrue);
      expect(parsed[1].timestampMs, equals(65000));

      // 2:00.12 -> (2 * 60) * 1000 + 120 = 120,120 ms
      expect(parsed[2].text, equals('Two minute centisecond check'));
      expect(parsed[2].isSynced, isTrue);
      expect(parsed[2].timestampMs, equals(120120));

      // 5:30.500 -> (5 * 60 + 30) * 1000 + 500 = 330,500 ms
      expect(parsed[3].text, equals('Five thirty millisecond check'));
      expect(parsed[3].isSynced, isTrue);
      expect(parsed[3].timestampMs, equals(330500));

      // 9:59.99 -> (9 * 60 + 59) * 1000 + 990 = 599,990 ms
      expect(parsed[4].text, equals('Nine fifty nine'));
      expect(parsed[4].isSynced, isTrue);
      expect(parsed[4].timestampMs, equals(599990));
    });

    test('>= 100 minute timestamps (including [105:30.00]) parse as synced lyrics with exact milliseconds', () {
      const lrcLongForm = '''
[100:00.00]One hundred minutes exact
[105:30.00]One hundred five minutes thirty seconds
[120:15.50]Two hours in
[250:45.123]Extended ambient mix
[999:59.99]Three digit limit
[1000:00.00]Four digit marathon
''';

      final parsed = LyricLine.parseLrc(lrcLongForm);
      expect(parsed.length, equals(6));

      // [100:00.00] -> 100 * 60 * 1000 = 6,000,000 ms
      expect(parsed[0].text, equals('One hundred minutes exact'));
      expect(parsed[0].isSynced, isTrue);
      expect(parsed[0].timestampMs, equals(6000000));

      // [105:30.00] -> (105 * 60 + 30) * 1000 = 6,330,000 ms
      expect(parsed[1].text, equals('One hundred five minutes thirty seconds'));
      expect(parsed[1].isSynced, isTrue);
      expect(parsed[1].timestampMs, equals(6330000));

      // [120:15.50] -> (120 * 60 + 15) * 1000 + 500 = 7,215,500 ms
      expect(parsed[2].text, equals('Two hours in'));
      expect(parsed[2].isSynced, isTrue);
      expect(parsed[2].timestampMs, equals(7215500));

      // [250:45.123] -> (250 * 60 + 45) * 1000 + 123 = 15,045,123 ms
      expect(parsed[3].text, equals('Extended ambient mix'));
      expect(parsed[3].isSynced, isTrue);
      expect(parsed[3].timestampMs, equals(15045123));

      // [999:59.99] -> (999 * 60 + 59) * 1000 + 990 = 59,999,990 ms
      expect(parsed[4].text, equals('Three digit limit'));
      expect(parsed[4].isSynced, isTrue);
      expect(parsed[4].timestampMs, equals(59999990));

      // [1000:00.00] -> 1000 * 60 * 1000 = 60,000,000 ms
      expect(parsed[5].text, equals('Four digit marathon'));
      expect(parsed[5].isSynced, isTrue);
      expect(parsed[5].timestampMs, equals(60000000));
    });

    test('Multi-timestamp line combining single-digit and >= 100 minute tags', () {
      const mixedLine = '[1:05.00][105:30.00]Shared recurring refrain';
      final parsed = LyricLine.parseLrc(mixedLine);

      expect(parsed.length, equals(2));
      expect(parsed[0].timestampMs, equals(65000));
      expect(parsed[0].text, equals('Shared recurring refrain'));
      expect(parsed[0].isSynced, isTrue);

      expect(parsed[1].timestampMs, equals(6330000));
      expect(parsed[1].text, equals('Shared recurring refrain'));
      expect(parsed[1].isSynced, isTrue);
    });

    test('SplayTreeMap active index lookup and round-trip formatting for >= 100 minutes', () {
      const lrc = '''
[1:00.00]Intro
[105:30.00]Target 105 minute line
[120:00.00]Outro
''';
      final parsed = LyricLine.parseLrc(lrc);
      final indexMap = LyricLine.buildIndex(parsed);

      // Verify active index queries around 105:30.00 (6,330,000 ms)
      expect(LyricLine.findActiveIndex(indexMap, 60000), equals(0)); // at 1:00.00
      expect(LyricLine.findActiveIndex(indexMap, 6329999), equals(0)); // just before 105:30
      expect(LyricLine.findActiveIndex(indexMap, 6330000), equals(1)); // exactly 105:30
      expect(LyricLine.findActiveIndex(indexMap, 6340000), equals(1)); // during 105:30
      expect(LyricLine.findActiveIndex(indexMap, 7200000), equals(2)); // at 120:00

      // Roundtrip formattedTimestamp check
      final line105 = parsed[1];
      expect(line105.formattedTimestamp, equals('[105:30.00]'));

      final reParsed = LyricLine.parseLrc('${line105.formattedTimestamp} ${line105.text}');
      expect(reParsed.single.timestampMs, equals(6330000));
      expect(reParsed.single.text, equals('Target 105 minute line'));
      expect(reParsed.single.isSynced, isTrue);
    });
  });

  // ==========================================================================
  // EMPIRICAL CHALLENGE 3: SQLite Cascade Protection & Multi-Genre Integrity
  // ==========================================================================
  group('Empirical Challenge 3: SQLite Cascade & Genre Integrity Stress', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabaseImpl.inMemory();
      await db.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('Updating track metadata does NOT trigger CASCADE deletion on playlists or Liked Songs', () async {
      // 1. Insert initial track
      const track1 = Track(
        id: 1,
        uri: '/music/song1.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 240000,
        fileSize: 1024000,
        modifiedAt: 1600000000,
        genres: ['Rock'],
      );
      await db.insertOrUpdateTrack(track1);

      // 2. Add track to a custom playlist and to Liked Songs
      final playlistId = await db.createPlaylist('Favorites');
      const likedPlaylistId = AppConstants.likedSongsPlaylistId;

      await db.addTrackToPlaylist(playlistId, 1);
      await db.addTrackToPlaylist(likedPlaylistId, 1);

      var favTracks = await db.getTracksForPlaylist(playlistId);
      var likedTracks = await db.getTracksForPlaylist(likedPlaylistId);
      expect(favTracks.length, equals(1));
      expect(likedTracks.length, equals(1));

      // 3. Update track via insertOrUpdateTrack (e.g. metadata refresh)
      final updatedTrack1 = track1.copyWith(
        title: 'Updated Title',
        bitrate: 320000,
      );
      await db.insertOrUpdateTrack(updatedTrack1);

      // Verify playlist entries survived
      favTracks = await db.getTracksForPlaylist(playlistId);
      likedTracks = await db.getTracksForPlaylist(likedPlaylistId);
      expect(favTracks.length, equals(1), reason: 'insertOrUpdateTrack must not trigger CASCADE deletion on custom playlist');
      expect(likedTracks.length, equals(1), reason: 'insertOrUpdateTrack must not trigger CASCADE deletion on Liked Songs');
      expect(favTracks.first.title, equals('Updated Title'));

      // 4. Update track via batchInsertTracks
      final batchUpdatedTrack1 = updatedTrack1.copyWith(
        title: 'Batch Updated Title',
      );
      await db.batchInsertTracks([batchUpdatedTrack1]);

      // Verify playlist entries still survive
      favTracks = await db.getTracksForPlaylist(playlistId);
      likedTracks = await db.getTracksForPlaylist(likedPlaylistId);
      expect(favTracks.length, equals(1), reason: 'batchInsertTracks must not trigger CASCADE deletion on custom playlist');
      expect(likedTracks.length, equals(1), reason: 'batchInsertTracks must not trigger CASCADE deletion on Liked Songs');
      expect(favTracks.first.title, equals('Batch Updated Title'));
    });

    test('batchInsertTracks correctly extracts, links, and aggregates multi-genres for 1,000 tracks', () async {
      final tracks = List<Track>.generate(1000, (i) {
        return Track(
          uri: '/music/track_$i.mp3',
          title: 'Track $i',
          artist: 'Artist ${i % 10}',
          album: 'Album ${i % 20}',
          durationMs: 180000,
          fileSize: 2048000,
          modifiedAt: 1600000000 + i,
          genres: <String>[
            'Electronic',
            'Synthwave',
            if (i % 2 == 0) 'Ambient',
            if (i % 5 == 0) 'Cyberpunk',
          ],
        );
      });

      await db.batchInsertTracks(tracks);

      final allGenres = await db.getAllGenres();
      final genreMap = {for (final g in allGenres) g.name: g.trackCount};

      // Electronic and Synthwave: all 1,000 tracks
      expect(genreMap['Electronic'], equals(1000));
      expect(genreMap['Synthwave'], equals(1000));

      // Ambient: even tracks -> 500
      expect(genreMap['Ambient'], equals(500));

      // Cyberpunk: divisible by 5 -> 200
      expect(genreMap['Cyberpunk'], equals(200));
    });
  });
}
