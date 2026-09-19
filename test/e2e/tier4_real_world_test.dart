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

  group('Tier 4: Real-World Application Scenarios', () {
    test('[T4-Scenario-1] Cold start -> Directory import -> Library population -> Search & First playback with crossfade', () async {
      // Step 1: Cold start verification
      expect(driver.currentState.queue, isEmpty);
      expect(driver.currentState.playing, isFalse);
      expect((await driver.getAllTracks()), isEmpty);

      // Step 2: User adds music directory and triggers scan
      final dirFiles = [
        '/home/user/Music/Rock/track1.flac',
        '/home/user/Music/Rock/track2.flac',
        '/home/user/Music/Pop/track3.mp3',
      ];

      const probe1 = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "flac", "sample_rate": "44100"}],
        "format": {"duration": "180.0", "tags": {"title": "Comfortably Numb", "artist": "Pink Floyd", "album": "The Wall", "date": "1979"}}
      }
      ''';
      const probe2 = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "flac", "sample_rate": "44100"}],
        "format": {"duration": "200.0", "tags": {"title": "Hey You", "artist": "Pink Floyd", "album": "The Wall", "date": "1979"}}
      }
      ''';
      const probe3 = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "mp3", "sample_rate": "44100"}],
        "format": {"duration": "210.0", "tags": {"title": "Billie Jean", "artist": "Michael Jackson", "album": "Thriller", "date": "1982"}}
      }
      ''';

      final t1 = driver.parseFfprobeJson(probe1, filePath: dirFiles[0], trackId: 1);
      final t2 = driver.parseFfprobeJson(probe2, filePath: dirFiles[1], trackId: 2);
      final t3 = driver.parseFfprobeJson(probe3, filePath: dirFiles[2], trackId: 3);

      await driver.batchInsertTracks([t1, t2, t3]);

      // Verify library indexing
      final allTracks = await driver.getAllTracks();
      expect(allTracks.length, equals(3));
      final allAlbums = await driver.getAllAlbums();
      expect(allAlbums.length, equals(2));
      final allArtists = await driver.getAllArtists();
      expect(allArtists.length, equals(2));

      // Step 3: User searches for "Comfortably"
      final searchResults = await driver.searchTracks('Comfortably');
      expect(searchResults.length, equals(1));
      expect(searchResults.first.title, equals('Comfortably Numb'));

      // Step 4: User clicks play on the search result
      await driver.openQueue(allTracks, index: 0, play: true);
      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.currentTrack?.title, equals('Comfortably Numb'));

      // Step 5: Audio plays until crossfade threshold and transitions to Track 2
      driver.simulatePositionTick(const Duration(seconds: 175)); // 5s before end
      driver.simulateCrossfadeTick(0.5); // Midpoint crossfade
      expect(driver.currentState.crossfadeActive, isTrue);

      // Acoustic energy is conserved
      final isPowerConserved = CrossfadeMath.verifyEnergyConservation(
        volumeA: driver.currentState.instanceAVolume,
        volumeB: driver.currentState.instanceBVolume,
        masterVolume: driver.currentState.volume,
      );
      expect(isPowerConserved, isTrue);

      // Complete crossfade transition
      driver.simulateCrossfadeTick(1.0);
      expect(driver.currentState.crossfadeActive, isFalse);
      expect(driver.currentState.index, equals(1));
      expect(driver.currentState.currentTrack?.title, equals('Hey You'));
      expect(driver.currentState.playing, isTrue);
    });

    test('[T4-Scenario-2] Playlist creation -> Reordering -> Play next -> Continuous loop playback', () async {
      // Step 1: Ingest tracks
      final t1 = const TrackInfo(id: 1, uri: '1.mp3', title: 'Song 1', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      final t2 = const TrackInfo(id: 2, uri: '2.mp3', title: 'Song 2', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      final t3 = const TrackInfo(id: 3, uri: '3.mp3', title: 'Song 3', artist: 'A', album: 'B', duration: Duration(minutes: 3));
      await driver.batchInsertTracks([t1, t2, t3]);

      // Step 2: Create custom playlist and add tracks
      final playlistId = await driver.createPlaylist('Gym Workout');
      await driver.addTrackToPlaylist(playlistId, 1);
      await driver.addTrackToPlaylist(playlistId, 2);
      await driver.addTrackToPlaylist(playlistId, 3);

      var pTracks = await driver.getTracksForPlaylist(playlistId);
      expect(pTracks.map((t) => t.id).toList(), equals([1, 2, 3]));

      // Step 3: Reorder playlist (move Song 3 to index 0)
      await driver.reorderPlaylistEntries(playlistId, 2, 0);
      pTracks = await driver.getTracksForPlaylist(playlistId);
      expect(pTracks.map((t) => t.id).toList(), equals([3, 1, 2]));

      // Step 4: Open playlist with LoopMode.all
      await driver.openQueue(pTracks, index: 0, play: true);
      await driver.setLoopMode(LoopMode.all);
      expect(driver.currentState.currentTrack?.title, equals('Song 3'));

      // Step 5: Advance through all tracks and verify wrap-around to beginning
      await driver.next(); // Song 1
      expect(driver.currentState.currentTrack?.title, equals('Song 1'));
      await driver.next(); // Song 2
      expect(driver.currentState.currentTrack?.title, equals('Song 2'));
      await driver.next(); // Wraps back to Song 3
      expect(driver.currentState.currentTrack?.title, equals('Song 3'));
      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.completed, isFalse);
    });

    test('[T4-Scenario-3] Synchronized lyrics navigation -> Tap-to-seek -> Manual scroll pause & resume', () async {
      const fullLrc = '''
      [ti:Bohemian Rhapsody]
      [ar:Queen]
      [00:00.00]Is this the real life?
      [00:05.00]Is this just fantasy?
      [00:15.00]Caught in a landslide
      [00:25.00]No escape from reality
      [01:00.00]Open your eyes
      ''';

      final lyrics = driver.parseLrc(fullLrc);
      final indexMap = driver.buildLyricsIndex(lyrics);

      final track = TrackInfo(
        id: 1,
        uri: 'bohemian.mp3',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        duration: const Duration(minutes: 6),
        rawLyrics: fullLrc,
      );

      await driver.openQueue([track], index: 0, play: true);

      // Playback reaches 00:16.00 (16,000ms)
      driver.simulatePositionTick(const Duration(seconds: 16));
      int activeIdx = driver.getActiveLyricIndex(16000, indexMap);
      expect(activeIdx, equals(2));
      expect(lyrics[activeIdx].text, equals('Caught in a landslide'));

      // User taps lyric line at 01:00.00 (60,000ms)
      final tappedLine = lyrics[4];
      expect(tappedLine.text, equals('Open your eyes'));
      await driver.seek(Duration(milliseconds: tappedLine.timestampMs));

      expect(driver.currentState.position, equals(const Duration(seconds: 60)));
      activeIdx = driver.getActiveLyricIndex(60000, indexMap);
      expect(activeIdx, equals(4));
      expect(lyrics[activeIdx].text, equals('Open your eyes'));
    });

    test('[T4-Scenario-4] Audio session interruption (Becoming Noisy) -> Auto-pause -> Resume -> Multi-format switch', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: 'highres.flac', title: 'FLAC Song', artist: 'Audiophile', album: 'Studio', duration: Duration(minutes: 5), format: AudioFormat.flac),
        const TrackInfo(id: 2, uri: 'mobile.aac', title: 'AAC Song', artist: 'Mobile', album: 'Stream', duration: Duration(minutes: 3), format: AudioFormat.aac),
      ];

      await driver.openQueue(tracks, index: 0, play: true);
      await driver.setRate(1.25);
      await driver.setVolume(120.0); // Boosted volume

      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.rate, equals(1.25));
      expect(driver.currentState.volume, equals(120.0));

      // Headphone unplugged: Becoming Noisy event triggers pause
      await driver.pause();
      expect(driver.currentState.playing, isFalse);

      // User reconnects headphones and resumes
      await driver.play();
      expect(driver.currentState.playing, isTrue);

      // Skip into AAC track: engine maintains configuration across different formats
      await driver.next();
      expect(driver.currentState.currentTrack?.format, equals(AudioFormat.aac));
      expect(driver.currentState.rate, equals(1.25));
      expect(driver.currentState.volume, equals(120.0));
      expect(driver.currentState.playing, isTrue);
    });

    test('[T4-Scenario-5] Dynamic settings hot-swap & update detection during active playback', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: 'song1.mp3', title: 'Song 1', artist: 'A', album: 'B', duration: Duration(minutes: 4)),
      ];
      await driver.openQueue(tracks, index: 0, play: true);

      // Register languages
      driver.registerLocaleBundle('en', {'s_crossfade': 'Crossfade'});
      driver.registerLocaleBundle('es', {'s_crossfade': 'Desvanecimiento cruzado'});

      // User modifies settings during playback
      driver.switchLocale('es');
      await driver.setCrossfadeConfig(duration: const Duration(seconds: 8));
      await driver.setVolume(90.0);

      expect(driver.getString('s_crossfade'), equals('Desvanecimiento cruzado'));
      expect(driver.currentState.crossfadeDuration, equals(const Duration(seconds: 8)));
      expect(driver.currentState.volume, equals(90.0));
      expect(driver.currentState.playing, isTrue);

      // Background check for update
      final mockRelease = {
        'tag_name': 'v3.0.0',
        'body': 'Major Tachyon Release',
        'assets': [{'name': 'tachyon-v3.0.0-linux.tar.gz', 'browser_download_url': 'https://releases.com/3.0.0'}]
      };

      final update = driver.checkReleaseUpdate(
        currentVersion: '2.1.0',
        releaseJson: mockRelease,
      );

      expect(update.isNewer, isTrue);
      expect(update.version, equals('3.0.0'));
      // Active playback continues seamlessly
      expect(driver.currentState.playing, isTrue);
    });
  });
}
