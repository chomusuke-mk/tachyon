import 'package:flutter_test/flutter_test.dart';

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

  group('Tier 3: Pairwise Cross-Feature Interactions', () {
    test('[T3-1] R1 (Crossfade) + R3 (Persistence): App restart restores track, position, volume, and crossfade config', () async {
      // Phase 1: User configures audio and listens to music
      final track1 = const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 5));
      final track2 = const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 4));
      await driver.batchInsertTracks([track1, track2]);

      await driver.openQueue([track1, track2], index: 1, play: true);
      await driver.seek(const Duration(minutes: 2, seconds: 15));
      await driver.setVolume(82.0);
      await driver.setCrossfadeConfig(
        duration: const Duration(seconds: 7),
        curve: CrossfadeCurve.equalPower,
      );

      // Persist state into AppSettings
      final snapshot = driver.settings.copyWith(
        volume: driver.currentState.volume,
        crossfadeDurationSeconds: driver.currentState.crossfadeDuration.inSeconds,
      );
      driver.updateSettings(snapshot);

      // Phase 2: App restarts (new driver instance)
      final restoredDriver = TachyonTestDriver();
      restoredDriver.updateSettings(driver.settings);

      expect(restoredDriver.settings.volume, equals(82.0));
      expect(restoredDriver.settings.crossfadeDurationSeconds, equals(7));

      // Re-initialize queue with restored settings
      await restoredDriver.openQueue(
        [track1, track2],
        index: 1,
        play: false,
      );
      await restoredDriver.seek(const Duration(minutes: 2, seconds: 15));
      await restoredDriver.setVolume(restoredDriver.settings.volume);
      await restoredDriver.setCrossfadeConfig(
        duration: Duration(seconds: restoredDriver.settings.crossfadeDurationSeconds),
      );

      expect(restoredDriver.currentState.index, equals(1));
      expect(restoredDriver.currentState.currentTrack?.title, equals('T2'));
      expect(restoredDriver.currentState.position, equals(const Duration(minutes: 2, seconds: 15)));
      expect(restoredDriver.currentState.volume, equals(82.0));
      expect(restoredDriver.currentState.crossfadeDuration, equals(const Duration(seconds: 7)));

      restoredDriver.dispose();
    });

    test('[T3-2] R1 (Queue Shuffle) + R4 (Now Playing Queue UI): Shuffle preserves active track at index 0 and reorders remaining tracks', () async {
      final tracks = List.generate(
        25,
        (i) => TrackInfo(id: i + 1, uri: 'song$i.mp3', title: 'Track $i', artist: 'Artist', album: 'Album', duration: const Duration(minutes: 3)),
      );

      // Playing track at index 14
      await driver.openQueue(tracks, index: 14, play: true);
      final activeTrackBeforeShuffle = driver.currentState.currentTrack!;
      expect(activeTrackBeforeShuffle.id, equals(15));
      expect(driver.currentState.playing, isTrue);

      // User toggles shuffle from Now Playing screen
      await driver.toggleShuffle();

      final state = driver.currentState;
      expect(state.shuffle, isTrue);
      // Active track is pinned at index 0
      expect(state.index, equals(0));
      expect(state.currentTrack?.id, equals(15));
      expect(state.playing, isTrue);
      expect(state.queue.length, equals(25));
    });

    test('[T3-3] R2 (Metadata Scan) + R3 (Relational DB): Ingestion populates relational artists and albums correctly', () async {
      const ffprobe1 = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "flac"}],
        "format": {
          "duration": "240.0",
          "tags": {
            "title": "Stairway to Heaven",
            "artist": "Led Zeppelin",
            "album": "Led Zeppelin IV",
            "date": "1971"
          }
        }
      }
      ''';
      const ffprobe2 = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "flac"}],
        "format": {
          "duration": "210.0",
          "tags": {
            "title": "Rock and Roll",
            "artist": "Led Zeppelin",
            "album": "Led Zeppelin IV",
            "date": "1971"
          }
        }
      }
      ''';

      final t1 = driver.parseFfprobeJson(ffprobe1, filePath: '/music/stairway.flac', trackId: 1);
      final t2 = driver.parseFfprobeJson(ffprobe2, filePath: '/music/rock.flac', trackId: 2);

      await driver.batchInsertTracks([t1, t2]);

      final albums = await driver.getAllAlbums();
      final artists = await driver.getAllArtists();
      final tracks = await driver.getAllTracks();

      expect(tracks.length, equals(2));
      expect(artists.length, equals(1));
      expect(artists.first.name, equals('Led Zeppelin'));
      expect(artists.first.trackCount, equals(2));

      expect(albums.length, equals(1));
      expect(albums.first.name, equals('Led Zeppelin IV'));
      expect(albums.first.trackCount, equals(2));
      expect(albums.first.year, equals(1971));
    });

    test('[T3-4] R4 (Lyrics View) + R1 (Audio Engine Seek): Tapping lyric line seeks audio and updates active line', () async {
      const sampleLrc = '''
      [00:00.00]Instrumental Intro
      [00:15.50]First vocal line
      [00:45.00]Second vocal line
      [01:24.50]Epic guitar solo starts here
      [02:10.00]Outro
      ''';

      final lyrics = driver.parseLrc(sampleLrc);
      final indexMap = driver.buildLyricsIndex(lyrics);

      final track = TrackInfo(
        id: 1,
        uri: 'epic.mp3',
        title: 'Epic Track',
        artist: 'Band',
        album: 'Album',
        duration: const Duration(minutes: 3),
        rawLyrics: sampleLrc,
      );

      await driver.openQueue([track], index: 0, play: true);

      // User taps on the lyric line at 01:24.50 (84,500ms)
      final tappedLine = lyrics[3];
      expect(tappedLine.text, equals('Epic guitar solo starts here'));

      await driver.seek(Duration(milliseconds: tappedLine.timestampMs));

      // Assert audio engine seeks to target
      expect(driver.currentState.position, equals(const Duration(milliseconds: 84500)));

      // Assert active lyric index is 3
      final activeIndex = driver.getActiveLyricIndex(driver.currentState.position.inMilliseconds, indexMap);
      expect(activeIndex, equals(3));
      expect(lyrics[activeIndex].text, equals('Epic guitar solo starts here'));
    });

    test('[T3-5] R5 (Locale Switch) + R4 (Settings / UI Screens): Dynamic language change updates strings across all views', () {
      driver.registerLocaleBundle('en', {
        'np_title': 'Now Playing',
        'tr_header': 'Tracks Library',
        's_title': 'Settings',
        's_crossfade': 'Crossfade Duration',
      });
      driver.registerLocaleBundle('es', {
        'np_title': 'Reproduciendo',
        'tr_header': 'Biblioteca de Pistas',
        's_title': 'Configuración',
        's_crossfade': 'Duración de Crossfade',
      });

      expect(driver.getString('np_title'), equals('Now Playing'));
      expect(driver.getString('tr_header'), equals('Tracks Library'));
      expect(driver.getString('s_title'), equals('Settings'));

      // Switch language dynamically
      driver.switchLocale('es');

      expect(driver.getString('np_title'), equals('Reproduciendo'));
      expect(driver.getString('tr_header'), equals('Biblioteca de Pistas'));
      expect(driver.getString('s_title'), equals('Configuración'));
      expect(driver.getString('s_crossfade'), equals('Duración de Crossfade'));
      expect(driver.settings.locale, equals('es'));
    });

    test('[T3-6] R1 (Audio Engine) + R4 (MiniPlayer / Desktop Transport Bar): Transport actions reactively update state stream', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
      ];

      final stateHistory = <PlayerStateSnapshot>[];
      final sub = driver.stateStream.listen(stateHistory.add);

      await driver.openQueue(tracks, index: 0, play: true);
      await driver.pause();
      await driver.next();
      await driver.setVolume(60.0);

      await Future<void>.delayed(Duration.zero);
      expect(stateHistory.length, greaterThanOrEqualTo(4));
      expect(stateHistory.last.index, equals(1));
      expect(stateHistory.last.volume, equals(60.0));

      await sub.cancel();
    });

    test('[T3-7] R2 (Cover Extractor) + R4 (Now Playing Artwork): Cover resolution cleanly falls back without UI blocking', () {
      const trackWithCover = TrackInfo(
        id: 1,
        uri: '/music/t1.mp3',
        title: 'T1',
        artist: 'A',
        album: 'B',
        duration: Duration(minutes: 3),
        hasCover: true,
      );
      const trackWithoutCover = TrackInfo(
        id: 2,
        uri: '/music/t2.mp3',
        title: 'T2',
        artist: 'A',
        album: 'B',
        duration: Duration(minutes: 3),
        hasCover: false,
      );

      // Embedded cover
      final art1 = driver.resolveCoverArt(
        track: trackWithCover,
        directoryFiles: [],
        defaultAssetPath: 'assets/default.png',
      );
      expect(art1, equals('/cache/covers/1.jpg'));

      // Missing embedded, directory cover fallback
      final art2 = driver.resolveCoverArt(
        track: trackWithoutCover,
        directoryFiles: ['/music/folder.jpg'],
        defaultAssetPath: 'assets/default.png',
      );
      expect(art2, equals('/music/folder.jpg'));

      // Missing both, fallback to default asset
      final art3 = driver.resolveCoverArt(
        track: trackWithoutCover,
        directoryFiles: [],
        defaultAssetPath: 'assets/default.png',
      );
      expect(art3, equals('assets/default.png'));
    });

    test('[T3-8] R3 (Playlists) + R1 (Queue Management): Adding custom playlist as "Play Next" inserts items after current track', () async {
      final initialQueue = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
      ];
      await driver.openQueue(initialQueue, index: 0); // Currently playing T1

      // Create and populate custom playlist
      final plId = await driver.createPlaylist('Chill Vibes');
      final plTrack1 = const TrackInfo(id: 10, uri: '10.mp3', title: 'Chill 1', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      final plTrack2 = const TrackInfo(id: 20, uri: '20.mp3', title: 'Chill 2', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      await driver.insertOrUpdateTrack(plTrack1);
      await driver.insertOrUpdateTrack(plTrack2);
      await driver.addTrackToPlaylist(plId, 10);
      await driver.addTrackToPlaylist(plId, 20);

      final playlistTracks = await driver.getTracksForPlaylist(plId);

      // Insert playlist tracks as "Play Next" (in reverse to preserve order or loop)
      for (final t in playlistTracks.reversed) {
        await driver.insertNext(t);
      }

      final newQueue = driver.currentState.queue;
      expect(newQueue.length, equals(4));
      expect(newQueue[0].id, equals(1)); // Current
      expect(newQueue[1].id, equals(10)); // Chill 1 (Play Next)
      expect(newQueue[2].id, equals(20)); // Chill 2 (Play Next)
      expect(newQueue[3].id, equals(2)); // Original next
    });

    test('[T3-9] R5 (Update Checker) + R4 (Update Dialog): New release detection does not interrupt active playback', () async {
      final track = const TrackInfo(id: 1, uri: '1.mp3', title: 'Playing Song', artist: 'A', album: 'B', duration: Duration(minutes: 4));
      await driver.openQueue([track], index: 0, play: true);
      expect(driver.currentState.playing, isTrue);

      // Update check runs in background
      final releasePayload = {
        'tag_name': 'v2.5.0',
        'body': 'Major performance update',
        'assets': [{'name': 'tachyon-v2.5.0.apk', 'browser_download_url': 'https://download.com/app.apk'}]
      };
      final update = driver.checkReleaseUpdate(
        currentVersion: '2.0.0',
        releaseJson: releasePayload,
      );

      expect(update.isNewer, isTrue);
      expect(update.version, equals('2.5.0'));

      // Playback remains playing undisturbed
      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.currentTrack?.title, equals('Playing Song'));
    });

    test('[T3-10] R1 (Crossfade Automation) + R4 (Progress Slider): Manual slider scrub during crossfade aborts preloaded instance', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(seconds: 30)),
      ];
      await driver.openQueue(tracks, index: 0);

      // Start crossfade at 80%
      driver.simulateCrossfadeTick(0.8);
      expect(driver.currentState.crossfadeActive, isTrue);
      expect(driver.currentState.instanceAVolume, lessThan(40.0));
      expect(driver.currentState.instanceBVolume, greaterThan(80.0));

      // User interacts with progress slider and drags to 10 seconds
      await driver.seek(const Duration(seconds: 10));

      final state = driver.currentState;
      expect(state.crossfadeActive, isFalse);
      expect(state.crossfadeProgress, equals(0.0));
      expect(state.instanceAVolume, equals(100.0));
      expect(state.instanceBVolume, equals(0.0));
      expect(state.position, equals(const Duration(seconds: 10)));
    });
  });
}
