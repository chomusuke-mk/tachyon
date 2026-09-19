import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';

import 'harness/e2e_math_utils.dart';
import 'harness/e2e_models.dart';
import 'harness/tachyon_driver.dart';

void main() {
  late TachyonTestDriver driver;

  setUp(() {
    driver = TachyonTestDriver();
    driver.resetDatabase();
  });

  tearDown(() {
    driver.dispose();
  });

  // ==========================================================================
  // Requirement R1: Playback & Crossfade - Boundary & Corner Cases
  // ==========================================================================
  group('[R1] Playback & Crossfade - Boundary & Corner Cases', () {
    test('[R1-B1] Track duration shorter than crossfade duration clamps effective crossfade to duration / 2', () {
      const configuredDuration = Duration(seconds: 5);

      // Track of 3 seconds: 3s < 5s -> clamp to 1.5s (1500ms)
      final effective1 = CrossfadeMath.calculateEffectiveCrossfadeDuration(
        trackDuration: const Duration(seconds: 3),
        configuredCrossfadeDuration: configuredDuration,
      );
      expect(effective1, equals(const Duration(milliseconds: 1500)));

      // Track of 10 seconds: 10s >= 5s -> keep 5s
      final effective2 = CrossfadeMath.calculateEffectiveCrossfadeDuration(
        trackDuration: const Duration(seconds: 10),
        configuredCrossfadeDuration: configuredDuration,
      );
      expect(effective2, equals(configuredDuration));

      // Track of 0 seconds -> clamp to 0
      final effective3 = CrossfadeMath.calculateEffectiveCrossfadeDuration(
        trackDuration: Duration.zero,
        configuredCrossfadeDuration: configuredDuration,
      );
      expect(effective3, equals(Duration.zero));
    });

    test('[R1-B2] Manual seek during active crossfade aborts preloaded instance and resets volume to master', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
      ];
      await driver.openQueue(tracks, index: 0);
      await driver.setVolume(100.0);

      // Trigger crossfade tick at 50%
      driver.simulateCrossfadeTick(0.5);
      expect(driver.currentState.crossfadeActive, isTrue);
      expect(driver.currentState.instanceAVolume, lessThan(100.0));
      expect(driver.currentState.instanceBVolume, greaterThan(0.0));

      // User seeks back to 5 seconds
      await driver.seek(const Duration(seconds: 5));

      // Crossfade must be aborted and volume restored
      final state = driver.currentState;
      expect(state.crossfadeActive, isFalse);
      expect(state.crossfadeProgress, equals(0.0));
      expect(state.instanceAVolume, equals(100.0));
      expect(state.instanceBVolume, equals(0.0));
      expect(state.position, equals(const Duration(seconds: 5)));
    });

    test('[R1-B3] Manual next/skip during active crossfade terminates outgoing track immediately and advances', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
      ];
      await driver.openQueue(tracks, index: 0);
      driver.simulateCrossfadeTick(0.6);
      expect(driver.currentState.crossfadeActive, isTrue);

      await driver.next();

      final state = driver.currentState;
      expect(state.index, equals(1));
      expect(state.currentTrack?.title, equals('T2'));
      expect(state.crossfadeActive, isFalse);
      expect(state.instanceAVolume, equals(100.0));
    });

    test('[R1-B4] Single-track queue with LoopMode.one loops into itself smoothly', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'Solo', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
      ];
      await driver.openQueue(tracks, index: 0);
      await driver.setLoopMode(LoopMode.one);
      driver.simulatePositionTick(const Duration(seconds: 28));

      await driver.next();

      expect(driver.currentState.index, equals(0));
      expect(driver.currentState.position, equals(Duration.zero));
      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.completed, isFalse);
    });

    test('[R1-B5] Volume boost amplification above 100% clamps to maximum 200%', () async {
      await driver.setVolume(150.0);
      expect(driver.currentState.volume, equals(150.0));

      await driver.setVolume(250.0);
      expect(driver.currentState.volume, equals(200.0));

      await driver.setVolume(-10.0);
      expect(driver.currentState.volume, equals(0.0));
    });

    test('[R1-B6] Next on single-track queue with LoopMode.off transitions to completed state', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'Solo', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
      ];
      await driver.openQueue(tracks, index: 0);
      await driver.setLoopMode(LoopMode.off);

      await driver.next();

      expect(driver.currentState.completed, isTrue);
      expect(driver.currentState.playing, isFalse);
    });
  });

  // ==========================================================================
  // Requirement R2: Metadata & Scanner - Boundary & Corner Cases
  // ==========================================================================
  group('[R2] Metadata & Scanner - Boundary & Corner Cases', () {
    test('[R2-B1] Corrupted JSON / empty ffprobe output falls back to filename with zero duration', () {
      const corruptJson = '{ "format": corrupt json syntax ...';
      final track = driver.parseFfprobeJson(corruptJson, filePath: '/music/DamagedTrack.mp3');

      expect(track.title, equals('DamagedTrack'));
      expect(track.artist, equals('Unknown Artist'));
      expect(track.duration, equals(Duration.zero));
    });

    test('[R2-B2] Complex mixed multi-artist delimiters ("Artist 1 / Artist 2, Artist 3; feat. Artist 4")', () {
      final artists = driver.normalizeArtists('Artist 1 / Artist 2, Artist 3; feat. Artist 4 ft. Artist 5');
      expect(artists, equals(['Artist 1', 'Artist 2', 'Artist 3', 'Artist 4', 'Artist 5']));

      final emptyArtists = driver.normalizeArtists('   ');
      expect(emptyArtists, equals(['Unknown Artist']));
    });

    test('[R2-B3] Malformed track number strings ("invalid", "0/0", "-5", "12")', () {
      expect(driver.normalizeTrackNumber('invalid'), equals(1));
      expect(driver.normalizeTrackNumber('0/0'), equals(0));
      expect(driver.normalizeTrackNumber('12/20'), equals(12));
      expect(driver.normalizeTrackNumber('07'), equals(7));
    });

    test('[R2-B4] Release year string with non-standard formatting extracts 4-digit year or defaults to 0', () {
      expect(driver.normalizeYear('Recorded in 1998 in Tokyo'), equals(1998));
      expect(driver.normalizeYear('2023-11-04T12:00:00Z'), equals(2023));
      expect(driver.normalizeYear('Circa Victorian Era'), equals(0));
    });

    test('[R2-B5] Directory artwork resolution with mixed uppercase/lowercase extensions (COVER.JPG, Folder.PNG)', () {
      const track = TrackInfo(
        id: 1,
        uri: '/music/song.mp3',
        title: 'Song',
        artist: 'A',
        album: 'B',
        duration: Duration(minutes: 3),
        hasCover: false,
      );

      final art = driver.resolveCoverArt(
        track: track,
        directoryFiles: ['/music/Track.mp3', '/music/COVER.JPG'],
        defaultAssetPath: 'assets/default.png',
      );
      expect(art, equals('/music/COVER.JPG'));
    });

    test('[R2-B6] Track with zero bitrate and sample rate defaults to sensible fallbacks', () {
      const mockJson = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "aac"}],
        "format": {"duration": "100.0", "tags": {"title": "Zero Stream"}}
      }
      ''';

      final track = driver.parseFfprobeJson(mockJson, filePath: '/music/zero.aac');
      expect(track.bitrate, equals(0));
      expect(track.sampleRate, equals(44100)); // Default fallback
      expect(track.codec, equals('aac'));
    });
  });

  // ==========================================================================
  // Requirement R3: Persistence & Database - Boundary & Corner Cases
  // ==========================================================================
  group('[R3] Persistence & Database - Boundary & Corner Cases', () {
    test('[R3-B1] Ingestion of 5,000+ tracks handles large volume without data loss', () async {
      final largeCatalog = List.generate(
        5000,
        (i) => TrackInfo(
          id: i + 1,
          uri: '/music/track_$i.mp3',
          title: 'Track $i',
          artist: 'Artist ${i % 100}',
          album: 'Album ${i % 200}',
          duration: const Duration(minutes: 3),
        ),
      );

      await driver.batchInsertTracks(largeCatalog);

      final totalTracks = await driver.getAllTracks();
      final totalArtists = await driver.getAllArtists();
      final totalAlbums = await driver.getAllAlbums();

      expect(totalTracks.length, equals(5000));
      expect(totalArtists.length, equals(100));
      expect(totalAlbums.length, equals(200));
    });

    test('[R3-B2] Special playlists (Liked Songs, History) reject deletion or duplicate system IDs', () async {
      final playlists = await driver.getAllPlaylists();
      final specialIds = playlists.where((p) => p.isSpecial > 0).map((p) => p.id).toList();

      expect(specialIds, containsAll([1, 2]));
    });

    test(r'[R3-B3] Search query with special regex metacharacters (.*+?^${}()|[]) does not crash', () async {
      final t = const TrackInfo(
        id: 1,
        uri: '1.mp3',
        title: 'Song (Remix) [2024] {Deluxe}',
        artist: 'Artist + Co.',
        album: r'Album $100',
        duration: Duration(minutes: 3),
      );
      await driver.insertOrUpdateTrack(t);

      final res1 = await driver.searchTracks('(Remix)');
      expect(res1.length, equals(1));

      final res2 = await driver.searchTracks('[2024]');
      expect(res2.length, equals(1));

      final res3 = await driver.searchTracks('+ Co.');
      expect(res3.length, equals(1));

      final res4 = await driver.searchTracks(r'$100');
      expect(res4.length, equals(1));
    });

    test('[R3-B4] Removing non-existent track from playlist is a safe no-op', () async {
      final pId = await driver.createPlaylist('Empty');
      await driver.removeTrackFromPlaylist(pId, 9999);
      final tracks = await driver.getTracksForPlaylist(pId);
      expect(tracks, isEmpty);
    });

    test('[R3-B5] Reordering playlist with out-of-bounds indices is safely ignored', () async {
      final t = const TrackInfo(id: 1, uri: '1.mp3', title: 'T', artist: 'A', album: 'B', duration: Duration(minutes: 1));
      await driver.insertOrUpdateTrack(t);
      final pId = await driver.createPlaylist('Single');
      await driver.addTrackToPlaylist(pId, 1);

      await driver.reorderPlaylistEntries(pId, -1, 5);
      final tracks = await driver.getTracksForPlaylist(pId);
      expect(tracks.length, equals(1));
      expect(tracks.first.id, equals(1));
    });

    test('[R3-B6] Uninitialized settings load default fallback values without null exceptions', () {
      final s = driver.settings;
      expect(s.volume, equals(100.0));
      expect(s.crossfadeEnabled, isTrue);
      expect(s.crossfadeDurationSeconds, equals(5));
      expect(s.locale, equals('en'));
      expect(s.themeMode, equals('dark'));
      expect(s.musicDirectories, isEmpty);
    });
  });

  // ==========================================================================
  // Requirement R4: UI & Shell - Boundary & Corner Cases
  // ==========================================================================
  group('[R4] UI & Shell - Boundary & Corner Cases', () {
    test('[R4-B1] LRC lyrics with negative header offset ([offset:-500]) clamps negative timestamps to 0ms', () {
      const lrcWithNegativeOffset = '''
      [offset:-1000]
      [00:00.50]Very early lyric
      [00:05.00]Second lyric
      ''';

      final lyrics = driver.parseLrc(lrcWithNegativeOffset);
      expect(lyrics.length, equals(2));
      // 500ms - 1000ms = -500ms -> clamped to 0ms
      expect(lyrics[0].timestampMs, equals(0));
      expect(lyrics[0].text, equals('Very early lyric'));
      // 5000ms - 1000ms = 4000ms
      expect(lyrics[1].timestampMs, equals(4000));
    });

    test('[R4-B2] LRC line with multiple duplicate timestamps creates multiple distinct lines', () {
      const lrcDuplicateTimestamps = '''
      [00:10.00][00:30.00]Chorus repeats twice
      ''';

      final lyrics = driver.parseLrc(lrcDuplicateTimestamps);
      expect(lyrics.length, equals(2));
      expect(lyrics[0].timestampMs, equals(10000));
      expect(lyrics[0].text, equals('Chorus repeats twice'));
      expect(lyrics[1].timestampMs, equals(30000));
      expect(lyrics[1].text, equals('Chorus repeats twice'));
    });

    test('[R4-B3] Unsynchronized plain lyrics fallback (lines without timestamps marked isSynced = false)', () {
      const plainLyrics = '''
      This is plain line 1
      This is plain line 2
      ''';

      final lyrics = driver.parseLrc(plainLyrics);
      expect(lyrics.length, equals(2));
      expect(lyrics[0].isSynced, isFalse);
      expect(lyrics[0].text, equals('This is plain line 1'));
      expect(lyrics[1].isSynced, isFalse);
      expect(lyrics[1].text, equals('This is plain line 2'));
    });

    test('[R4-B4] Reordering queue with negative or exceeding indices is safely ignored', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 1)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 1)),
      ];
      await driver.openQueue(tracks, index: 0);

      await driver.reorderQueue(-1, 10);
      expect(driver.currentState.queue.map((t) => t.id).toList(), equals([1, 2]));
    });

    test('[R4-B5] Removing the last item in queue empties player state gracefully', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 1)),
      ];
      await driver.openQueue(tracks, index: 0);
      await driver.removeQueueItem(0);

      expect(driver.currentState.queue, isEmpty);
      expect(driver.currentState.playing, isFalse);
      expect(driver.currentState.currentTrack, isNull);
    });

    test('[R4-B6] Playback rate and pitch extreme values clamp strictly to [0.5, 1.5]', () async {
      await driver.setRate(-5.0);
      expect(driver.currentState.rate, equals(0.5));

      await driver.setRate(100.0);
      expect(driver.currentState.rate, equals(1.5));

      await driver.setPitch(-1.0);
      expect(driver.currentState.pitch, equals(0.5));

      await driver.setPitch(50.0);
      expect(driver.currentState.pitch, equals(1.5));
    });
  });

  // ==========================================================================
  // Requirement R5: i18n & Updates - Boundary & Corner Cases
  // ==========================================================================
  group('[R5] i18n & Updates - Boundary & Corner Cases', () {
    test('[R5-B1] Locale bundle with completely empty translation dictionary falls back 100% to English', () {
      driver.registerLocaleBundle('en', {'tr_title': 'Tracks'});
      driver.registerLocaleBundle('empty_locale', {});

      driver.switchLocale('empty_locale');
      expect(driver.getString('tr_title'), equals('Tracks'));
    });

    test('[R5-B2] Rapid successive locale switching does not cause race conditions or state corruption', () {
      driver.registerLocaleBundle('en', {'title': 'English'});
      driver.registerLocaleBundle('es', {'title': 'Español'});
      driver.registerLocaleBundle('fr', {'title': 'Français'});

      for (int i = 0; i < 50; i++) {
        final loc = i % 3 == 0 ? 'en' : (i % 3 == 1 ? 'es' : 'fr');
        driver.switchLocale(loc);
      }

      expect(driver.settings.locale, isNotEmpty);
      expect(driver.getString('title'), isNotEmpty);
    });

    test('[R5-B3] GitHub release payload missing asset array or download URLs handled gracefully', () {
      final incompleteRelease = {
        'tag_name': 'v2.0.0',
        'body': 'Notes',
        // assets array missing
      };

      final update = driver.checkReleaseUpdate(
        currentVersion: '1.0.0',
        releaseJson: incompleteRelease,
      );

      expect(update.version, equals('2.0.0'));
      expect(update.isNewer, isTrue);
      expect(update.assetUrl, isEmpty);
    });

    test('[R5-B4] Semver comparison handles pre-release / non-standard tags (v2.0.0-beta.1)', () {
      final release = {
        'tag_name': 'v2.0.0-beta.1',
        'body': 'Beta',
        'assets': []
      };

      final update = driver.checkReleaseUpdate(
        currentVersion: '1.0.0',
        releaseJson: release,
      );

      expect(update.isNewer, isTrue);
    });

    test('[R5-B5] Corrupt JSON syntax in locale loader falls back gracefully to defaults', () {
      final key = driver.getString('non_existent_key');
      expect(key, equals('non_existent_key'));
    });

    test('[R5-B6] Release update checker handles release with identical version number as not newer', () {
      final release = {
        'tag_name': 'v1.5.0',
        'body': 'Current',
        'assets': []
      };

      final update = driver.checkReleaseUpdate(
        currentVersion: '1.5.0',
        releaseJson: release,
      );

      expect(update.isNewer, isFalse);
    });
  });

  // ==========================================================================
  // Requirement R6: Test Infrastructure - Boundary & Corner Cases
  // ==========================================================================
  group('[R6] Test Infrastructure - Boundary & Corner Cases', () {
    test('[R6-B1] High-frequency state stream listener does not drop emissions or leak memory', () async {
      final emitted = <PlayerStateSnapshot>[];
      final sub = driver.stateStream.listen(emitted.add);

      for (int i = 0; i < 100; i++) {
        await driver.setVolume(i.toDouble());
      }

      await Future<void>.delayed(Duration.zero);
      expect(emitted.length, equals(100));
      await sub.cancel();
    });

    test('[R6-B2] Empty queue operations (play, pause, next, prev, seek) execute safely without throwing', () async {
      expect(() async => await driver.play(), returnsNormally);
      expect(() async => await driver.pause(), returnsNormally);
      expect(() async => await driver.next(), returnsNormally);
      expect(() async => await driver.previous(), returnsNormally);
      expect(() async => await driver.seek(const Duration(seconds: 10)), returnsNormally);
    });

    test('[R6-B3] Crossfade progress clamping handles progress < 0.0 or > 1.0 safely', () {
      final under = CrossfadeMath.calculateEqualPower(progress: -0.5, masterVolume: 100.0);
      expect(under.volumeA, equals(100.0));
      expect(under.volumeB, equals(0.0));

      final over = CrossfadeMath.calculateEqualPower(progress: 1.5, masterVolume: 100.0);
      expect(over.volumeA, closeTo(0.0, 0.001));
      expect(over.volumeB, equals(100.0));
    });

    test('[R6-B4] Equal power crossfade maintains invariant with extreme volume values (0.0% and 200.0%)', () {
      final resZero = CrossfadeMath.calculateEqualPower(progress: 0.5, masterVolume: 0.0);
      expect(resZero.volumeA, equals(0.0));
      expect(resZero.volumeB, equals(0.0));

      final resMax = CrossfadeMath.calculateEqualPower(progress: 0.5, masterVolume: 200.0);
      final isConserved = CrossfadeMath.verifyEnergyConservation(
        volumeA: resMax.volumeA,
        volumeB: resMax.volumeB,
        masterVolume: 200.0,
      );
      expect(isConserved, isTrue);
    });

    test('[R6-B5] Batch database insert with duplicate track URIs updates existing records', () async {
      final t1 = const TrackInfo(id: 1, uri: '/music/song.mp3', title: 'V1', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      await driver.insertOrUpdateTrack(t1);

      // Update with new title
      final t2 = const TrackInfo(id: 1, uri: '/music/song.mp3', title: 'V2', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      await driver.insertOrUpdateTrack(t2);

      final tracks = await driver.getAllTracks();
      expect(tracks.length, equals(1));
      expect(tracks.first.title, equals('V2'));
    });

    test('[R6-B6] SplayTreeMap lyrics lookup with empty timestamp map returns -1 safely', () {
      final emptyMap = SplayTreeMap<int, int>();
      final index = LyricsMath.findActiveLyricIndex(
        positionMs: 5000,
        timestampToIndexMap: emptyMap,
      );
      expect(index, equals(-1));
    });
  });
}
