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
  // Requirement R1: Playback & Crossfade Engine
  // ==========================================================================
  group('[R1] Playback & Crossfade Engine - Feature Coverage', () {
    test('[R1-1] Multi-format queue ingestion (MP3, FLAC, WAV, AAC, OGG, M4A)', () async {
      final tracks = [
        const TrackInfo(
          id: 1,
          uri: '/music/song1.mp3',
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          duration: Duration(minutes: 3),
          format: AudioFormat.mp3,
        ),
        const TrackInfo(
          id: 2,
          uri: '/music/song2.flac',
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          duration: Duration(minutes: 4),
          format: AudioFormat.flac,
        ),
        const TrackInfo(
          id: 3,
          uri: '/music/song3.wav',
          title: 'Song 3',
          artist: 'Artist 3',
          album: 'Album 3',
          duration: Duration(minutes: 2),
          format: AudioFormat.wav,
        ),
        const TrackInfo(
          id: 4,
          uri: '/music/song4.aac',
          title: 'Song 4',
          artist: 'Artist 4',
          album: 'Album 4',
          duration: Duration(minutes: 5),
          format: AudioFormat.aac,
        ),
        const TrackInfo(
          id: 5,
          uri: '/music/song5.ogg',
          title: 'Song 5',
          artist: 'Artist 5',
          album: 'Album 5',
          duration: Duration(minutes: 3, seconds: 30),
          format: AudioFormat.ogg,
        ),
        const TrackInfo(
          id: 6,
          uri: '/music/song6.m4a',
          title: 'Song 6',
          artist: 'Artist 6',
          album: 'Album 6',
          duration: Duration(minutes: 4, seconds: 15),
          format: AudioFormat.m4a,
        ),
      ];

      await driver.openQueue(tracks, index: 0, play: true);
      final state = driver.currentState;

      expect(state.queue.length, equals(6));
      expect(state.index, equals(0));
      expect(state.playing, isTrue);
      expect(state.currentTrack?.format, equals(AudioFormat.mp3));
      expect(state.queue[1].format, equals(AudioFormat.flac));
      expect(state.queue[2].format, equals(AudioFormat.wav));
      expect(state.queue[3].format, equals(AudioFormat.aac));
      expect(state.queue[4].format, equals(AudioFormat.ogg));
      expect(state.queue[5].format, equals(AudioFormat.m4a));
    });

    test('[R1-2] Basic transport state transitions (play, pause, stop, seek)', () async {
      final tracks = [
        const TrackInfo(
          id: 1,
          uri: '/music/test.mp3',
          title: 'Test Song',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 3),
        ),
      ];

      await driver.openQueue(tracks, index: 0, play: false);
      expect(driver.currentState.playing, isFalse);

      await driver.play();
      expect(driver.currentState.playing, isTrue);

      await driver.pause();
      expect(driver.currentState.playing, isFalse);

      await driver.seek(const Duration(seconds: 45));
      expect(driver.currentState.position, equals(const Duration(seconds: 45)));

      await driver.stop();
      expect(driver.currentState.playing, isFalse);
      expect(driver.currentState.position, equals(Duration.zero));
    });

    test('[R1-3] Fisher-Yates shuffle retains current playing track at index 0', () async {
      final tracks = List.generate(
        10,
        (i) => TrackInfo(
          id: i + 1,
          uri: '/music/song$i.mp3',
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
        ),
      );

      // Open at index 3
      await driver.openQueue(tracks, index: 3, play: true, shuffle: false);
      final playingTrack = driver.currentState.currentTrack;
      expect(playingTrack?.title, equals('Song 3'));

      await driver.toggleShuffle();
      final state = driver.currentState;

      expect(state.shuffle, isTrue);
      expect(state.index, equals(0));
      expect(state.currentTrack?.title, equals('Song 3'));
      expect(state.queue.length, equals(10));

      // Check remaining tracks were permuted
      final originalIdsExcept3 = tracks.where((t) => t.id != 4).map((t) => t.id).toList();
      final shuffledRemainingIds = state.queue.sublist(1).map((t) => t.id).toList();
      expect(shuffledRemainingIds.toSet(), equals(originalIdsExcept3.toSet()));
    });

    test('[R1-4] Repeat modes (LoopMode.off completes queue, LoopMode.one loops track, LoopMode.all loops queue)', () async {
      final tracks = [
        const TrackInfo(
          id: 1,
          uri: '/music/song1.mp3',
          title: 'Song 1',
          artist: 'A',
          album: 'B',
          duration: Duration(minutes: 3),
        ),
        const TrackInfo(
          id: 2,
          uri: '/music/song2.mp3',
          title: 'Song 2',
          artist: 'A',
          album: 'B',
          duration: Duration(minutes: 4),
        ),
      ];

      // LoopMode.off: next from last track completes
      await driver.openQueue(tracks, index: 1, play: true);
      await driver.setLoopMode(LoopMode.off);
      await driver.next();
      expect(driver.currentState.completed, isTrue);
      expect(driver.currentState.playing, isFalse);

      // LoopMode.one: next from any track restarts track
      await driver.openQueue(tracks, index: 0, play: true);
      await driver.setLoopMode(LoopMode.one);
      driver.simulatePositionTick(const Duration(seconds: 40));
      await driver.next();
      expect(driver.currentState.index, equals(0));
      expect(driver.currentState.position, equals(Duration.zero));
      expect(driver.currentState.playing, isTrue);

      // LoopMode.all: next from last track wraps to first track
      await driver.openQueue(tracks, index: 1, play: true);
      await driver.setLoopMode(LoopMode.all);
      await driver.next();
      expect(driver.currentState.index, equals(0));
      expect(driver.currentState.playing, isTrue);
      expect(driver.currentState.completed, isFalse);
    });

    test('[R1-5] Equal-power crossfade curve preserves acoustic power at all progress points', () async {
      const masterVolume = 100.0;
      await driver.setVolume(masterVolume);
      await driver.setCrossfadeConfig(
        duration: const Duration(seconds: 5),
        curve: CrossfadeCurve.equalPower,
      );

      final testPoints = [0.0, 0.25, 0.5, 0.75, 1.0];
      for (final p in testPoints) {
        final res = CrossfadeMath.calculateEqualPower(
          progress: p,
          masterVolume: masterVolume,
        );

        // Acoustic power conservation check: V_A^2 + V_B^2 == V_master^2
        final isConserved = CrossfadeMath.verifyEnergyConservation(
          volumeA: res.volumeA,
          volumeB: res.volumeB,
          masterVolume: masterVolume,
        );
        expect(isConserved, isTrue, reason: 'Acoustic power must be conserved at p=$p');
      }

      // Midpoint equal-power check: V_A(0.5) == V_B(0.5) == masterVol * sqrt(2)/2
      final midRes = CrossfadeMath.calculateEqualPower(
        progress: 0.5,
        masterVolume: masterVolume,
      );
      expect(midRes.volumeA, closeTo(70.7106, 0.001));
      expect(midRes.volumeB, closeTo(70.7106, 0.001));
    });

    test('[R1-6] Reactive state stream broadcasts position, volume, and playback state updates', () async {
      final tracks = [
        const TrackInfo(
          id: 1,
          uri: '/music/song1.mp3',
          title: 'Song 1',
          artist: 'A',
          album: 'B',
          duration: Duration(minutes: 3),
        ),
      ];

      final emissions = <PlayerStateSnapshot>[];
      final subscription = driver.stateStream.listen(emissions.add);

      await driver.openQueue(tracks, index: 0, play: true);
      await driver.setVolume(85.0);
      await driver.pause();
      await driver.play();

      // Allow microtasks to complete
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, greaterThanOrEqualTo(4));
      expect(emissions.last.playing, isTrue);
      expect(emissions.last.volume, equals(85.0));

      await subscription.cancel();
    });
  });

  // ==========================================================================
  // Requirement R2: ffprobe Metadata & Cover Art Extraction
  // ==========================================================================
  group('[R2] ffprobe Metadata Extraction & Cover Art - Feature Coverage', () {
    test('[R2-1] Standard ffprobe JSON output parsing for title, artist, album, track, year, and duration', () {
      const mockJson = '''
      {
        "streams": [
          {
            "codec_type": "audio",
            "codec_name": "flac",
            "sample_rate": "48000",
            "bit_rate": "960000"
          }
        ],
        "format": {
          "duration": "184.500000",
          "size": "22140000",
          "bit_rate": "960000",
          "tags": {
            "title": "Cosmic Voyager",
            "artist": "Starlight Ensemble",
            "album": "Nebula Dreams",
            "track": "4/10",
            "disc": "1/2",
            "date": "2024"
          }
        }
      }
      ''';

      final track = driver.parseFfprobeJson(mockJson, filePath: '/music/cosmic.flac');

      expect(track.title, equals('Cosmic Voyager'));
      expect(track.artist, equals('Starlight Ensemble'));
      expect(track.album, equals('Nebula Dreams'));
      expect(track.trackNumber, equals(4));
      expect(track.discNumber, equals(1));
      expect(track.year, equals(2024));
      expect(track.duration.inSeconds, equals(184));
      expect(track.codec, equals('flac'));
      expect(track.sampleRate, equals(48000));
      expect(track.format, equals(AudioFormat.flac));
    });

    test('[R2-2] Case-insensitive tag key normalization (TITLE vs title vs Title)', () {
      const mockJsonUpper = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "mp3"}],
        "format": {
          "duration": "120.0",
          "tags": {
            "TITLE": "Uppercase Song",
            "ARTIST": "Uppercase Artist",
            "ALBUM": "Uppercase Album",
            "YEAR": "2023"
          }
        }
      }
      ''';

      final track = driver.parseFfprobeJson(mockJsonUpper, filePath: '/music/upper.mp3');
      expect(track.title, equals('Uppercase Song'));
      expect(track.artist, equals('Uppercase Artist'));
      expect(track.album, equals('Uppercase Album'));
      expect(track.year, equals(2023));
    });

    test('[R2-3] Multi-artist delimiter parsing into individual artist entities', () {
      final res1 = driver.normalizeArtists('Daft Punk / Pharrell Williams / Nile Rodgers');
      expect(res1, equals(['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']));

      final res2 = driver.normalizeArtists('Queen; David Bowie');
      expect(res2, equals(['Queen', 'David Bowie']));

      final res3 = driver.normalizeArtists('Kendrick Lamar feat. Rihanna');
      expect(res3, equals(['Kendrick Lamar', 'Rihanna']));

      final res4 = driver.normalizeArtists('Clean Artist');
      expect(res4, equals(['Clean Artist']));
    });

    test('[R2-4] Embedded cover art detection from video stream with attached_pic == 1', () {
      const mockJsonCover = '''
      {
        "streams": [
          {"codec_type": "audio", "codec_name": "mp3"},
          {
            "codec_type": "video",
            "codec_name": "mjpeg",
            "disposition": {
              "attached_pic": 1
            }
          }
        ],
        "format": {
          "duration": "200.0",
          "tags": {"title": "Art Song"}
        }
      }
      ''';

      final track = driver.parseFfprobeJson(mockJsonCover, filePath: '/music/art.mp3');
      expect(track.hasCover, isTrue);

      final coverUrl = driver.resolveCoverArt(
        track: track,
        directoryFiles: ['/music/cover.jpg'],
        defaultAssetPath: 'assets/images/default.png',
      );
      expect(coverUrl, equals('/cache/covers/${track.id}.jpg'));
    });

    test('[R2-5] Directory artwork fallback priority (cover.jpg > folder.jpg > default asset)', () {
      const noCoverTrack = TrackInfo(
        id: 1,
        uri: '/music/song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 3),
        hasCover: false,
      );

      // Has cover.jpg
      final art1 = driver.resolveCoverArt(
        track: noCoverTrack,
        directoryFiles: ['/music/folder.jpg', '/music/cover.jpg'],
        defaultAssetPath: 'assets/images/default.png',
      );
      expect(art1, equals('/music/cover.jpg'));

      // No cover.jpg, has folder.jpg
      final art2 = driver.resolveCoverArt(
        track: noCoverTrack,
        directoryFiles: ['/music/folder.jpg', '/music/other.png'],
        defaultAssetPath: 'assets/images/default.png',
      );
      expect(art2, equals('/music/folder.jpg'));

      // Empty directory, falls back to default
      final art3 = driver.resolveCoverArt(
        track: noCoverTrack,
        directoryFiles: [],
        defaultAssetPath: 'assets/images/default.png',
      );
      expect(art3, equals('assets/images/default.png'));
    });

    test('[R2-6] Fallback to filename when title tag is missing or empty', () {
      const mockJsonEmptyTitle = '''
      {
        "streams": [{"codec_type": "audio", "codec_name": "mp3"}],
        "format": {
          "duration": "150.0",
          "tags": {
            "artist": "Known Artist"
          }
        }
      }
      ''';

      final track = driver.parseFfprobeJson(
        mockJsonEmptyTitle,
        filePath: '/music/MyFavoriteJam.mp3',
      );
      expect(track.title, equals('MyFavoriteJam'));
      expect(track.artist, equals('Known Artist'));
    });
  });

  // ==========================================================================
  // Requirement R3: Local Library Persistence & Preferences
  // ==========================================================================
  group('[R3] Local Library Persistence & Preferences - Feature Coverage', () {
    test('[R3-1] Relational insertion of tracks with automatic artist and album link creation', () async {
      final t1 = const TrackInfo(
        id: 1,
        uri: '/music/track1.mp3',
        title: 'Track 1',
        artist: 'Pink Floyd',
        album: 'The Dark Side of the Moon',
        year: 1973,
        duration: Duration(minutes: 4),
      );
      final t2 = const TrackInfo(
        id: 2,
        uri: '/music/track2.mp3',
        title: 'Track 2',
        artist: 'Pink Floyd',
        album: 'The Dark Side of the Moon',
        year: 1973,
        duration: Duration(minutes: 6),
      );

      await driver.batchInsertTracks([t1, t2]);

      final tracks = await driver.getAllTracks();
      final albums = await driver.getAllAlbums();
      final artists = await driver.getAllArtists();

      expect(tracks.length, equals(2));
      expect(albums.length, equals(1));
      expect(albums.first.name, equals('The Dark Side of the Moon'));
      expect(albums.first.trackCount, equals(2));
      expect(artists.length, equals(1));
      expect(artists.first.name, equals('Pink Floyd'));
      expect(artists.first.trackCount, equals(2));
    });

    test('[R3-2] Track sorting by title, duration, and year', () async {
      final t1 = const TrackInfo(
        id: 1,
        uri: '/music/c.mp3',
        title: 'Charlie',
        artist: 'A',
        album: 'B',
        year: 2020,
        duration: Duration(minutes: 5),
      );
      final t2 = const TrackInfo(
        id: 2,
        uri: '/music/a.mp3',
        title: 'Alpha',
        artist: 'A',
        album: 'B',
        year: 2010,
        duration: Duration(minutes: 2),
      );
      final t3 = const TrackInfo(
        id: 3,
        uri: '/music/b.mp3',
        title: 'Bravo',
        artist: 'A',
        album: 'B',
        year: 2015,
        duration: Duration(minutes: 4),
      );

      await driver.batchInsertTracks([t1, t2, t3]);

      final sortedByTitle = await driver.getAllTracks(sortBy: 'title', ascending: true);
      expect(sortedByTitle.map((t) => t.title).toList(), equals(['Alpha', 'Bravo', 'Charlie']));

      final sortedByDuration = await driver.getAllTracks(sortBy: 'duration', ascending: true);
      expect(sortedByDuration.map((t) => t.title).toList(), equals(['Alpha', 'Bravo', 'Charlie']));

      final sortedByYearDesc = await driver.getAllTracks(sortBy: 'year', ascending: false);
      expect(sortedByYearDesc.map((t) => t.title).toList(), equals(['Charlie', 'Bravo', 'Alpha']));
    });

    test('[R3-3] Custom playlist creation, track addition, and ordered retrieval', () async {
      final t1 = const TrackInfo(
        id: 10,
        uri: '/music/t10.mp3',
        title: 'Track 10',
        artist: 'A',
        album: 'B',
        duration: Duration(minutes: 3),
      );
      final t2 = const TrackInfo(
        id: 20,
        uri: '/music/t20.mp3',
        title: 'Track 20',
        artist: 'A',
        album: 'B',
        duration: Duration(minutes: 4),
      );
      await driver.batchInsertTracks([t1, t2]);

      final playlistId = await driver.createPlaylist('Road Trip');
      await driver.addTrackToPlaylist(playlistId, 10);
      await driver.addTrackToPlaylist(playlistId, 20);

      final playlistTracks = await driver.getTracksForPlaylist(playlistId);
      expect(playlistTracks.length, equals(2));
      expect(playlistTracks[0].id, equals(10));
      expect(playlistTracks[1].id, equals(20));
    });

    test('[R3-4] Playlist entry drag-and-drop reordering updates positions sequentially', () async {
      final t1 = const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 1));
      final t2 = const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 1));
      final t3 = const TrackInfo(id: 3, uri: '3.mp3', title: 'T3', artist: 'A', album: 'B', duration: Duration(minutes: 1));
      await driver.batchInsertTracks([t1, t2, t3]);

      final playlistId = await driver.createPlaylist('Favorites');
      await driver.addTrackToPlaylist(playlistId, 1);
      await driver.addTrackToPlaylist(playlistId, 2);
      await driver.addTrackToPlaylist(playlistId, 3);

      // Reorder: move item at index 0 (T1) to index 2
      await driver.reorderPlaylistEntries(playlistId, 0, 2);

      final reordered = await driver.getTracksForPlaylist(playlistId);
      expect(reordered.map((t) => t.id).toList(), equals([2, 3, 1]));
    });

    test('[R3-5] Auto-managed special playlists (Liked Songs id=1, History id=2) initialization', () async {
      final playlists = await driver.getAllPlaylists();

      final likedSongs = playlists.firstWhere((p) => p.isSpecial == 1);
      final history = playlists.firstWhere((p) => p.isSpecial == 2);

      expect(likedSongs.id, equals(1));
      expect(likedSongs.name, equals('Liked Songs'));
      expect(history.id, equals(2));
      expect(history.name, equals('History'));
    });

    test('[R3-6] App settings persistence for audio preferences, theme, and language', () {
      final initialSettings = driver.settings;
      expect(initialSettings.crossfadeEnabled, isTrue);
      expect(initialSettings.crossfadeDurationSeconds, equals(5));
      expect(initialSettings.volume, equals(100.0));

      final updated = initialSettings.copyWith(
        crossfadeDurationSeconds: 8,
        volume: 75.0,
        themeMode: 'oled',
        locale: 'es',
        musicDirectories: ['/home/user/Music'],
      );
      driver.updateSettings(updated);

      final current = driver.settings;
      expect(current.crossfadeDurationSeconds, equals(8));
      expect(current.volume, equals(75.0));
      expect(current.themeMode, equals('oled'));
      expect(current.locale, equals('es'));
      expect(current.musicDirectories, equals(['/home/user/Music']));
    });
  });

  // ==========================================================================
  // Requirement R4: Modern Adaptive UI & Navigation Shell
  // ==========================================================================
  group('[R4] Modern Adaptive UI & Navigation Shell - Feature Coverage', () {
    test('[R4-1] Synchronized LRC parser extracts timestamped lines and text', () {
      const mockLrc = '''
      [ti:Song Title]
      [ar:Artist Name]
      [00:10.50]Line 1 lyrics
      [00:20.00]Line 2 lyrics
      [01:05.25]Line 3 lyrics
      ''';

      final lyrics = driver.parseLrc(mockLrc);
      expect(lyrics.length, equals(3));
      expect(lyrics[0].timestampMs, equals(10500));
      expect(lyrics[0].text, equals('Line 1 lyrics'));
      expect(lyrics[1].timestampMs, equals(20000));
      expect(lyrics[1].text, equals('Line 2 lyrics'));
      expect(lyrics[2].timestampMs, equals(65250));
      expect(lyrics[2].text, equals('Line 3 lyrics'));
    });

    test('[R4-2] O(log n) active lyric line lookup using SplayTreeMap during playback position advancement', () {
      const mockLrc = '''
      [00:05.00]Intro
      [00:15.00]Verse 1
      [00:30.00]Chorus
      [01:00.00]Outro
      ''';

      final lyrics = driver.parseLrc(mockLrc);
      final indexMap = driver.buildLyricsIndex(lyrics);

      // At 0ms (before first line) -> returns index 0
      expect(driver.getActiveLyricIndex(0, indexMap), equals(0));

      // At 10,000ms (between Intro and Verse 1) -> returns index 0 (Intro)
      expect(driver.getActiveLyricIndex(10000, indexMap), equals(0));

      // At 15,000ms -> returns index 1 (Verse 1)
      expect(driver.getActiveLyricIndex(15000, indexMap), equals(1));

      // At 45,000ms (between Chorus and Outro) -> returns index 2 (Chorus)
      expect(driver.getActiveLyricIndex(45000, indexMap), equals(2));

      // At 65,000ms (after Outro) -> returns index 3 (Outro)
      expect(driver.getActiveLyricIndex(65000, indexMap), equals(3));
    });

    test('[R4-3] Interactive queue insertion ("Play Next" and "Add to Queue")', () async {
      final initialTracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
      ];
      await driver.openQueue(initialTracks, index: 0);

      // Play Next
      const nextTrack = TrackInfo(id: 99, uri: '99.mp3', title: 'Next Up', artist: 'A', album: 'B', duration: Duration(minutes: 2));
      await driver.insertNext(nextTrack);

      expect(driver.currentState.queue.length, equals(3));
      expect(driver.currentState.queue[1].title, equals('Next Up'));

      // Add to Queue (Append)
      const appendedTrack = TrackInfo(id: 100, uri: '100.mp3', title: 'Last', artist: 'A', album: 'B', duration: Duration(minutes: 4));
      await driver.append([appendedTrack]);

      expect(driver.currentState.queue.length, equals(4));
      expect(driver.currentState.queue.last.title, equals('Last'));
    });

    test('[R4-4] Real-time multi-field search across title, artist, and album', () async {
      final t1 = const TrackInfo(id: 1, uri: '1.mp3', title: 'Bohemian Rhapsody', artist: 'Queen', album: 'A Night at the Opera', duration: Duration(minutes: 6));
      final t2 = const TrackInfo(id: 2, uri: '2.mp3', title: 'Hotel California', artist: 'Eagles', album: 'Hotel California', duration: Duration(minutes: 6));
      final t3 = const TrackInfo(id: 3, uri: '3.mp3', title: 'Under Pressure', artist: 'Queen & David Bowie', album: 'Hot Space', duration: Duration(minutes: 4));
      await driver.batchInsertTracks([t1, t2, t3]);

      // Search by title
      final r1 = await driver.searchTracks('Bohemian');
      expect(r1.length, equals(1));
      expect(r1.first.id, equals(1));

      // Search by artist
      final r2 = await driver.searchTracks('Queen');
      expect(r2.length, equals(2));

      // Search by album
      final r3 = await driver.searchTracks('Opera');
      expect(r3.length, equals(1));

      // Case-insensitive check
      final r4 = await driver.searchTracks('eAgLeS');
      expect(r4.length, equals(1));
    });

    test('[R4-5] Audio effects controls (playback rate 0.5x-1.5x and pitch 0.5-1.5)', () async {
      await driver.setRate(1.25);
      expect(driver.currentState.rate, equals(1.25));

      // Out-of-bounds rate clamps to [0.5, 1.5]
      await driver.setRate(2.5);
      expect(driver.currentState.rate, equals(1.5));
      await driver.setRate(0.2);
      expect(driver.currentState.rate, equals(0.5));

      await driver.setPitch(0.9);
      expect(driver.currentState.pitch, equals(0.9));

      // Out-of-bounds pitch clamps to [0.5, 1.5]
      await driver.setPitch(3.0);
      expect(driver.currentState.pitch, equals(1.5));
    });

    test('[R4-6] Queue item removal advances playback if active item is deleted', () async {
      final tracks = [
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
        const TrackInfo(id: 2, uri: '2.mp3', title: 'T2', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
        const TrackInfo(id: 3, uri: '3.mp3', title: 'T3', artist: 'A', album: 'B', duration: Duration(minutes: 3)),
      ];
      await driver.openQueue(tracks, index: 1); // Playing T2

      // Remove currently playing item (index 1)
      await driver.removeQueueItem(1);

      expect(driver.currentState.queue.length, equals(2));
      // Advances to what was T3, now at index 1
      expect(driver.currentState.currentTrack?.title, equals('T3'));
    });
  });

  // ==========================================================================
  // Requirement R5: Localization (i18n) & GitHub Updates
  // ==========================================================================
  group('[R5] Localization (i18n) & GitHub Updates - Feature Coverage', () {
    test('[R5-1] JSONC locale bundle registration and typed key lookup', () {
      driver.registerLocaleBundle('en', {
        'np_title': 'Now Playing',
        'tr_tracks': 'Tracks',
        's_crossfade': 'Crossfade Duration',
      });

      expect(driver.getString('np_title'), equals('Now Playing'));
      expect(driver.getString('tr_tracks'), equals('Tracks'));
      expect(driver.getString('s_crossfade'), equals('Crossfade Duration'));
    });

    test('[R5-2] Dynamic language switching updates localized strings without app restart', () {
      driver.registerLocaleBundle('en', {'np_title': 'Now Playing'});
      driver.registerLocaleBundle('es', {'np_title': 'Reproduciendo'});

      expect(driver.getString('np_title'), equals('Now Playing'));

      driver.switchLocale('es');
      expect(driver.getString('np_title'), equals('Reproduciendo'));
      expect(driver.settings.locale, equals('es'));
    });

    test('[R5-3] Missing translation keys fallback seamlessly to English bundle', () {
      driver.registerLocaleBundle('en', {
        'np_title': 'Now Playing',
        'tr_untranslated': 'Untranslated String',
      });
      driver.registerLocaleBundle('es', {
        'np_title': 'Reproduciendo',
        // 'tr_untranslated' missing in Spanish
      });

      driver.switchLocale('es');
      expect(driver.getString('np_title'), equals('Reproduciendo'));
      // Falls back to English
      expect(driver.getString('tr_untranslated'), equals('Untranslated String'));
    });

    test('[R5-4] GitHub release payload parsing for version, changelog, and asset download URL', () {
      final mockRelease = {
        'tag_name': 'v1.4.0',
        'body': '## What is New\n- Added equal power crossfade\n- Improved ffprobe speed',
        'assets': [
          {
            'name': 'tachyon-v1.4.0-linux.tar.gz',
            'browser_download_url': 'https://github.com/tachyon/releases/v1.4.0/linux.tar.gz',
          },
          {
            'name': 'tachyon-v1.4.0-android.apk',
            'browser_download_url': 'https://github.com/tachyon/releases/v1.4.0/android.apk',
          }
        ]
      };

      final update = driver.checkReleaseUpdate(
        currentVersion: '1.2.0',
        releaseJson: mockRelease,
      );

      expect(update.version, equals('1.4.0'));
      expect(update.isNewer, isTrue);
      expect(update.changelog, contains('equal power crossfade'));
      expect(update.assetUrl, isNotEmpty);
    });

    test('[R5-5] Semver version comparison detects newer releases (2.1.0 > 2.0.0)', () {
      expect(driver.isVersionNewer('1.0.0', '1.0.1'), isTrue);
      expect(driver.isVersionNewer('1.0.0', '1.1.0'), isTrue);
      expect(driver.isVersionNewer('1.0.0', '2.0.0'), isTrue);
    });

    test('[R5-6] Release checker marks equal or older versions as up to date (2.0.0 vs 2.0.0)', () {
      expect(driver.isVersionNewer('2.0.0', '2.0.0'), isFalse);
      expect(driver.isVersionNewer('2.1.0', '2.0.0'), isFalse);
      expect(driver.isVersionNewer('2.0.1', '2.0.0'), isFalse);
    });
  });

  // ==========================================================================
  // Requirement R6: Automated Testing & CI Harness
  // ==========================================================================
  group('[R6] Automated Testing & CI Harness - Feature Coverage', () {
    test('[R6-1] Test driver state isolation between test instances', () {
      final freshDriver = TachyonTestDriver();
      expect(freshDriver.currentState.queue, isEmpty);
      expect(freshDriver.currentState.playing, isFalse);
      expect(freshDriver.currentState.index, equals(0));
      expect(freshDriver.currentState.volume, equals(100.0));
      freshDriver.dispose();
    });

    test('[R6-2] Deterministic test random seeds produce repeatable shuffle orders', () async {
      final tracks = List.generate(
        8,
        (i) => TrackInfo(id: i + 1, uri: 'uri$i', title: 'T$i', artist: 'A', album: 'B', duration: const Duration(minutes: 2)),
      );

      final d1 = TachyonTestDriver();
      await d1.openQueue(tracks, index: 0, shuffle: true);
      final d1Order = d1.currentState.queue.map((t) => t.id).toList();

      final d2 = TachyonTestDriver();
      await d2.openQueue(tracks, index: 0, shuffle: true);
      final d2Order = d2.currentState.queue.map((t) => t.id).toList();

      expect(d1Order, equals(d2Order));
      d1.dispose();
      d2.dispose();
    });

    test('[R6-3] Asynchronous operations complete within bounded timeout', () async {
      final tracks = List.generate(
        100,
        (i) => TrackInfo(id: i + 1, uri: 'uri$i', title: 'T$i', artist: 'A$i', album: 'B$i', duration: const Duration(minutes: 3)),
      );

      final stopwatch = Stopwatch()..start();
      await driver.batchInsertTracks(tracks);
      final retrieved = await driver.getAllTracks();
      stopwatch.stop();

      expect(retrieved.length, equals(100));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('[R6-4] Stream subscription cleanup on driver disposal', () async {
      final tempDriver = TachyonTestDriver();
      bool isDone = false;

      tempDriver.stateStream.listen(
        (_) {},
        onDone: () => isDone = true,
      );

      tempDriver.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(isDone, isTrue);
    });

    test('[R6-5] Database reset clears all relational entities and resets auto-increment IDs', () async {
      await driver.batchInsertTracks([
        const TrackInfo(id: 1, uri: '1.mp3', title: 'T1', artist: 'A1', album: 'B1', duration: Duration(minutes: 3)),
      ]);
      expect((await driver.getAllTracks()).length, equals(1));

      driver.resetDatabase();
      expect((await driver.getAllTracks()).length, equals(0));
      expect((await driver.getAllArtists()).length, equals(0));
      expect((await driver.getAllAlbums()).length, equals(0));
      // Special playlists are re-created
      expect((await driver.getAllPlaylists()).length, equals(2));
    });

    test('[R6-6] Math utilities verify linear vs equal-power crossfade midpoint characteristics', () {
      const master = 100.0;
      final eqMid = CrossfadeMath.calculateEqualPower(progress: 0.5, masterVolume: master);
      final linMid = CrossfadeMath.calculateLinear(progress: 0.5, masterVolume: master);

      // Linear midpoint is exactly 50%
      expect(linMid.volumeA, equals(50.0));
      expect(linMid.volumeB, equals(50.0));
      // Linear power drops to 0.5 * master^2 (a 3dB drop)
      final linPower = (linMid.volumeA * linMid.volumeA) + (linMid.volumeB * linMid.volumeB);
      expect(linPower, equals(5000.0));

      // Equal power midpoint is ~70.71%
      expect(eqMid.volumeA, closeTo(70.71, 0.01));
      expect(eqMid.volumeB, closeTo(70.71, 0.01));
      // Equal power maintains 1.0 * master^2 (constant acoustic energy)
      final eqPower = (eqMid.volumeA * eqMid.volumeA) + (eqMid.volumeB * eqMid.volumeB);
      expect(eqPower, closeTo(10000.0, 0.01));
    });
  });
}
