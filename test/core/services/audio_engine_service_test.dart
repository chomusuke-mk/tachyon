import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/features/playback/domain/behavior_subject.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioEngineService Unit & Crossfade Tests', () {
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late AudioEngineServiceImpl engine;

    final sampleTracks = [
      const QueueItem(
        id: 'track_1',
        uri: '/music/song1.mp3',
        title: 'Song One',
        artist: 'Artist One',
        album: 'Album One',
        duration: Duration(seconds: 30),
      ),
      const QueueItem(
        id: 'track_2',
        uri: '/music/song2.flac',
        title: 'Song Two',
        artist: 'Artist Two',
        album: 'Album Two',
        duration: Duration(seconds: 40),
      ),
      const QueueItem(
        id: 'track_3',
        uri: '/music/song3.wav',
        title: 'Song Three',
        artist: 'Artist Three',
        album: 'Album Three',
        duration: Duration(seconds: 50),
      ),
    ];

    setUp(() {
      playerA = MockAudioPlayerAdapter(id: 'PlayerA');
      playerB = MockAudioPlayerAdapter(id: 'PlayerB');
      engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 10),
        random: math.Random(42),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    // ------------------------------------------------------------------------
    // 1. Crossfade Math Verification
    // ------------------------------------------------------------------------
    test('Equal-power crossfade curve strictly conserves acoustic energy V_A^2 + V_B^2 = V_master^2', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.equalPower);
      const master = 100.0;
      final points = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];

      for (final p in points) {
        final vOut = config.calculateFadeOutVolume(p, master);
        final vIn = config.calculateFadeInVolume(p, master);

        // Acoustic power check
        final sumSquares = (vOut * vOut) + (vIn * vIn);
        expect(
          sumSquares,
          closeTo(master * master, 0.001),
          reason: 'Power conservation failed at progress $p',
        );
      }

      // Midpoint equal-power value check: cos(pi/4) = sin(pi/4) = sqrt(2)/2 * 100 ≈ 70.7106
      final midOut = config.calculateFadeOutVolume(0.5, master);
      final midIn = config.calculateFadeInVolume(0.5, master);
      expect(midOut, closeTo(70.7106, 0.001));
      expect(midIn, closeTo(70.7106, 0.001));
    });

    test('Linear crossfade curve scales linearly without energy conservation', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.linear);
      const master = 100.0;

      expect(config.calculateFadeOutVolume(0.0, master), equals(100.0));
      expect(config.calculateFadeInVolume(0.0, master), equals(0.0));

      expect(config.calculateFadeOutVolume(0.5, master), equals(50.0));
      expect(config.calculateFadeInVolume(0.5, master), equals(50.0));

      expect(config.calculateFadeOutVolume(1.0, master), equals(0.0));
      expect(config.calculateFadeInVolume(1.0, master), equals(100.0));
    });

    // ------------------------------------------------------------------------
    // 2. Dual-Instance Initialization & Queue Opening
    // ------------------------------------------------------------------------
    test('Initializes active player with track 1 at master volume and standby player idle', () async {
      await engine.open(sampleTracks, index: 0, play: true);

      expect(engine.currentState.index, equals(0));
      expect(engine.currentState.currentTrack?.title, equals('Song One'));
      expect(playerA.volume, equals(100.0));
      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 3. Automated Crossfade Triggering & Role Swapping
    // ------------------------------------------------------------------------
    test('Automated crossfade triggers at threshold, fades smoothly, and performs role swap', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
        curve: CrossfadeCurve.equalPower,
      ));
      await engine.open(sampleTracks, index: 0, play: true);

      playerA.simulateDuration(const Duration(seconds: 30));
      // Simulate position before threshold (24s -> remaining 6s > 5s crossfade)
      playerA.simulatePosition(const Duration(seconds: 24));
      expect(playerB.isPlaying, isFalse);

      // Simulate reaching threshold (26s -> remaining 4s <= 5s crossfade)
      playerA.simulatePosition(const Duration(seconds: 26));
      await pumpEventQueue();

      // Standby playerB must be opened with track 2 and volume 0
      expect(playerB.isPlaying, isTrue);
      expect(playerB.volume, equals(0.0));

      // Wait for ticker automation or trigger next to complete
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Simulate next to test instant completion
      await engine.next();
      await pumpEventQueue();

      // After transition completes:
      // Player B is now the active player playing Track 2 at 100% volume
      expect(engine.currentState.index, equals(1));
      expect(engine.currentState.currentTrack?.title, equals('Song Two'));
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 4. Short Track Clamping to trackDuration / 2
    // ------------------------------------------------------------------------
    test('Effective crossfade duration clamps to half of track duration for short tracks', () {
      const config = CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      );

      // 3-second track -> effective crossfade is 1.5s
      final effective1 = config.effectiveDuration(const Duration(seconds: 3));
      expect(effective1, equals(const Duration(milliseconds: 1500)));

      // 10-second track -> effective crossfade is 5s
      final effective2 = config.effectiveDuration(const Duration(seconds: 10));
      expect(effective2, equals(const Duration(seconds: 5)));

      // 0-second track -> 0s
      final effective3 = config.effectiveDuration(Duration.zero);
      expect(effective3, equals(Duration.zero));
    });

    // ------------------------------------------------------------------------
    // 5. Manual Seek during Active Crossfade
    // ------------------------------------------------------------------------
    test('Manual seek during active crossfade aborts standby player and restores master volume', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade at 27s
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(playerB.isPlaying, isTrue);

      // User seeks back to 10 seconds
      await engine.seek(const Duration(seconds: 10));
      await pumpEventQueue();

      // Player B must be stopped, Player A volume restored to 100
      expect(playerB.isPlaying, isFalse);
      expect(playerA.volume, equals(100.0));
      expect(playerA.position, equals(const Duration(seconds: 10)));
    });

    // ------------------------------------------------------------------------
    // 6. Manual Next during Active Crossfade
    // ------------------------------------------------------------------------
    test('Manual next during active crossfade fast-forwards immediately to incoming track', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade at 27s
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(playerB.isPlaying, isTrue);

      // User taps skip to next
      await engine.next();
      await pumpEventQueue();

      // Outgoing Player A terminated immediately, Player B volume at 100, index advanced
      expect(engine.currentState.index, equals(1));
      expect(engine.currentState.currentTrack?.title, equals('Song Two'));
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 7. Single-Track Queue with Loop.one
    // ------------------------------------------------------------------------
    test('Single-track queue with Loop.one loops into itself smoothly', () async {
      final singleTrack = [sampleTracks.first];
      await engine.open(singleTrack, index: 0, play: true);
      await engine.setLoopMode(Loop.one);

      await engine.next();

      expect(engine.currentState.index, equals(0));
      expect(engine.currentState.currentTrack?.title, equals('Song One'));
      expect(playerA.isPlaying, isTrue);
      expect(engine.currentState.completed, isFalse);
    });

    // ------------------------------------------------------------------------
    // 8. Queue End with Loop.off
    // ------------------------------------------------------------------------
    test('End of queue with Loop.off transitions to completed state without crossfading', () async {
      final singleTrack = [sampleTracks.first];
      await engine.open(singleTrack, index: 0, play: true);
      await engine.setLoopMode(Loop.off);

      await engine.next();

      expect(engine.currentState.completed, isTrue);
      expect(engine.currentState.playing, isFalse);
      expect(playerB.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 9. Audio Effects: Rate, Pitch, and Volume Boost
    // ------------------------------------------------------------------------
    test('Audio effects update both players and clamp to specified ranges', () async {
      await engine.open(sampleTracks, index: 0, play: true);

      // Playback speed (0.5x - 1.5x)
      await engine.setRate(1.25);
      expect(engine.currentState.rate, equals(1.25));
      expect(playerA.rate, equals(1.25));
      expect(playerB.rate, equals(1.25));

      await engine.setRate(2.5); // Clamps to 1.5
      expect(engine.currentState.rate, equals(1.5));

      // Pitch shifting (0.5 - 1.5)
      await engine.setPitch(0.85);
      expect(engine.currentState.pitch, equals(0.85));
      expect(playerA.pitch, equals(0.85));
      expect(playerB.pitch, equals(0.85));

      // Volume Boost (0% - 200%)
      await engine.setVolume(175.0);
      expect(engine.currentState.volume, equals(175.0));
      expect(playerA.volume, equals(175.0));

      await engine.setVolume(250.0); // Clamps to 200.0
      expect(engine.currentState.volume, equals(200.0));
    });

    // ------------------------------------------------------------------------
    // 10. ReplayGain Normalization & Preamp Configuration
    // ------------------------------------------------------------------------
    test('ReplayGain modes and preamp dB are passed as mpv properties to both players', () async {
      await engine.open(sampleTracks, index: 0, play: true);

      await engine.setReplayGain(ReplayGainMode.track);
      expect(playerA.properties['replaygain'], equals('track'));
      expect(playerB.properties['replaygain'], equals('track'));

      await engine.setReplayGain(ReplayGainMode.album);
      expect(playerA.properties['replaygain'], equals('album'));
      expect(playerB.properties['replaygain'], equals('album'));

      await engine.setReplayGain(ReplayGainMode.off);
      expect(playerA.properties['replaygain'], equals('no'));
      expect(playerB.properties['replaygain'], equals('no'));

      // Preamp dB setting (-15dB to +15dB)
      await engine.setReplayGainPreamp(4.5);
      expect(playerA.properties['replaygain-preamp'], equals('4.5'));
      expect(playerB.properties['replaygain-preamp'], equals('4.5'));

      await engine.setReplayGainPreamp(-20.0); // Clamped to -15.0
      expect(playerA.properties['replaygain-preamp'], equals('-15.0'));
    });

    // ------------------------------------------------------------------------
    // 11. Windows Exclusive Audio Conflict Prevention
    // ------------------------------------------------------------------------
    test('Enforcing strict mutual exclusion between Windows Exclusive Audio and Crossfade', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));

      // Attempting to enable Exclusive Audio while crossfade is active must throw
      expect(
        () => engine.setExclusiveAudio(true),
        throwsA(isA<ExclusiveAudioCrossfadeException>()),
      );

      // Disable crossfade first
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: false,
        duration: Duration.zero,
      ));

      // Now exclusive audio succeeds
      await engine.setExclusiveAudio(true);
      expect(playerA.properties['audio-exclusive'], equals('yes'));
      expect(playerB.properties['audio-exclusive'], equals('yes'));

      // Attempting to re-enable crossfade while exclusive audio is active must throw
      expect(
        () => engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        )),
        throwsA(isA<ExclusiveAudioCrossfadeException>()),
      );
    });

    // ------------------------------------------------------------------------
    // 12. Raw Custom MPV Properties Propagation
    // ------------------------------------------------------------------------
    test('Arbitrary custom MPV properties propagate cleanly to both player instances', () async {
      await engine.open(sampleTracks, index: 0, play: true);

      await engine.setMpvProperty('audio-buffer', '0.2');
      expect(playerA.properties['audio-buffer'], equals('0.2'));
      expect(playerB.properties['audio-buffer'], equals('0.2'));

      await engine.setMpvProperties({
        'audio-channels': 'stereo',
        'gapless-audio': 'yes',
      });
      expect(playerA.properties['audio-channels'], equals('stereo'));
      expect(playerB.properties['audio-channels'], equals('stereo'));
      expect(playerA.properties['gapless-audio'], equals('yes'));
      expect(playerB.properties['gapless-audio'], equals('yes'));
    });

    // ------------------------------------------------------------------------
    // 13. Pause and Resume during Active Crossfade
    // ------------------------------------------------------------------------
    test('Pause during active crossfade pauses both players; resume resumes both', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade at 27s
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);
      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isTrue);

      // User pauses playback
      await engine.pause();
      await pumpEventQueue();

      expect(playerA.isPlaying, isFalse);
      expect(playerB.isPlaying, isFalse);

      // User resumes playback
      await engine.play();
      await pumpEventQueue();

      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isTrue);
    });

    // ------------------------------------------------------------------------
    // 14. Stop during Active Crossfade Resets Both Players
    // ------------------------------------------------------------------------
    test('Stop during active crossfade terminates both players and clears crossfade state', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Stop
      await engine.stop();
      await pumpEventQueue();

      expect(engine.isCrossfading, isFalse);
      expect(playerA.isPlaying, isFalse);
      expect(playerB.isPlaying, isFalse);
      expect(engine.currentState.playing, isFalse);
    });

    // ------------------------------------------------------------------------
    // 15. Gapless Transition When Crossfade is Disabled
    // ------------------------------------------------------------------------
    test('Gapless transition advances immediately when crossfade is disabled (duration = 0)', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: false,
        duration: Duration.zero,
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Position reaches 29s (no crossfade triggered)
      playerA.simulatePosition(const Duration(seconds: 29));
      await pumpEventQueue();
      expect(engine.isCrossfading, isFalse);
      expect(playerB.isPlaying, isFalse);

      // Track naturally completes
      playerA.simulateCompleted();
      await pumpEventQueue();

      // State immediately advances to Track 2
      expect(engine.currentState.index, equals(1));
      expect(engine.currentState.currentTrack?.title, equals('Song Two'));
    });

    // ------------------------------------------------------------------------
    // 16. Sequential Double Role Swap (Player A -> Player B -> Player A)
    // ------------------------------------------------------------------------
    test('Sequential crossfades execute dual role swaps cleanly: A -> B -> A', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);

      // Initial state: Active is Player A
      expect(engine.activePlayer, equals(playerA));
      expect(engine.standbyPlayer, equals(playerB));

      // 1st Crossfade (Track 1 -> Track 2)
      playerA.simulateDuration(const Duration(seconds: 30));
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Skip forward to complete 1st transition
      await engine.next();
      await pumpEventQueue();

      // Role Swap 1: Active is now Player B, Standby is Player A
      expect(engine.currentState.index, equals(1));
      expect(engine.activePlayer, equals(playerB));
      expect(engine.standbyPlayer, equals(playerA));
      expect(playerB.isPlaying, isTrue);
      expect(playerA.isPlaying, isFalse);

      // 2nd Crossfade (Track 2 -> Track 3)
      playerB.simulateDuration(const Duration(seconds: 40));
      playerB.simulatePosition(const Duration(seconds: 37));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Standby player A is primed with Track 3
      expect(playerA.isPlaying, isTrue);

      // Skip forward to complete 2nd transition
      await engine.next();
      await pumpEventQueue();

      // Role Swap 2: Active is back to Player A, Standby is Player B
      expect(engine.currentState.index, equals(2));
      expect(engine.activePlayer, equals(playerA));
      expect(engine.standbyPlayer, equals(playerB));
      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 17. Queue Manipulation & Fisher-Yates Shuffle Delegation
    // ------------------------------------------------------------------------
    test('Queue operations (insertNext, append, remove, reorder, shuffle) work properly', () async {
      await engine.open([sampleTracks[0], sampleTracks[1]], index: 0, play: true);
      expect(engine.currentState.playables.length, equals(2));

      // Append
      await engine.append([sampleTracks[2]]);
      expect(engine.currentState.playables.length, equals(3));
      expect(engine.currentState.playables[2].title, equals('Song Three'));

      // Insert Next
      const bonusTrack = QueueItem(
        id: 'track_bonus',
        uri: '/music/bonus.mp3',
        title: 'Bonus Track',
        artist: 'Bonus Artist',
        album: 'Bonus Album',
        duration: Duration(seconds: 20),
      );
      await engine.insertNext(bonusTrack);
      expect(engine.currentState.playables.length, equals(4));
      expect(engine.currentState.playables[1].title, equals('Bonus Track'));

      // Reorder: move bonus track from 1 to 3
      await engine.reorder(1, 3);
      expect(engine.currentState.playables[3].title, equals('Bonus Track'));

      // Remove index 3
      await engine.remove(3);
      expect(engine.currentState.playables.length, equals(3));

      // Toggle shuffle on
      await engine.toggleShuffle();
      expect(engine.currentState.shuffle, isTrue);
      // Active playing track (Song One) must remain at index 0
      expect(engine.currentState.currentTrack?.title, equals('Song One'));

      // Toggle shuffle off -> restores original order
      await engine.toggleShuffle();
      expect(engine.currentState.shuffle, isFalse);
      expect(engine.currentState.currentTrack?.title, equals('Song One'));
    });

    // ------------------------------------------------------------------------
    // 18. Pause/Resume during Crossfade Resumes Ticker and Completes Role Swap
    // ------------------------------------------------------------------------
    test('Pause and resume during active crossfade resumes ticker and completes with role swap', () async {
      const shortTrack1 = QueueItem(
        id: 'short_1',
        uri: '/music/short1.mp3',
        title: 'Short 1',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(milliseconds: 200),
      );
      const shortTrack2 = QueueItem(
        id: 'short_2',
        uri: '/music/short2.mp3',
        title: 'Short 2',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(milliseconds: 200),
      );

      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(milliseconds: 200),
      ));
      await engine.open([shortTrack1, shortTrack2], index: 0, play: true);

      playerA.simulateDuration(const Duration(milliseconds: 200));
      // Trigger crossfade (clamped to 100ms; remaining 80ms <= 100ms)
      playerA.simulatePosition(const Duration(milliseconds: 120));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Pause during crossfade
      await engine.pause();
      await pumpEventQueue();
      expect(playerA.isPlaying, isFalse);
      expect(playerB.isPlaying, isFalse);

      final pausedVolumeB = playerB.volume;
      // Volume must not drift while paused
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(playerB.volume, equals(pausedVolumeB));

      // Resume playback
      await engine.play();
      await pumpEventQueue();
      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isTrue);

      // Wait for ticker to complete the remaining progress
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Must have finished cleanly with role swap
      expect(engine.isCrossfading, isFalse);
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
      expect(engine.currentState.index, equals(1));
      expect(engine.currentState.currentTrack?.id, equals('short_2'));
    });

    // ------------------------------------------------------------------------
    // 19. Loop.one Prevents Crossfade Initiation
    // ------------------------------------------------------------------------
    test('Loop.one strictly prevents crossfade initiation and seeks to zero on track completion', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      await engine.setLoopMode(Loop.one);

      playerA.simulateDuration(const Duration(seconds: 30));
      // 27s -> 3s remaining <= 5s crossfade
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();

      // Crossfade MUST NOT trigger
      expect(engine.isCrossfading, isFalse);
      expect(playerB.isPlaying, isFalse);

      // Complete track
      playerA.simulatePosition(const Duration(seconds: 30));
      playerA.simulateCompleted();
      await pumpEventQueue();

      // Should seek to 0 and replay
      expect(playerA.position, equals(Duration.zero));
      expect(playerA.isPlaying, isTrue);
      expect(engine.currentState.index, equals(0));
    });

    // ------------------------------------------------------------------------
    // 20. Queue Mutations During Active Crossfade Abort Crossfade Cleanly
    // ------------------------------------------------------------------------
    test('Queue mutation insertNext during active crossfade aborts crossfade cleanly', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);
      expect(playerB.isPlaying, isTrue);

      const insertedItem = QueueItem(
        id: 'inserted_item',
        uri: '/music/inserted.mp3',
        title: 'Inserted Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 120),
      );

      // Insert next during crossfade
      await engine.insertNext(insertedItem);
      await pumpEventQueue();

      // Crossfade must be aborted
      expect(engine.isCrossfading, isFalse);
      expect(playerA.volume, equals(100.0));
      expect(playerB.isPlaying, isFalse);
      expect(engine.currentState.playables[1].id, equals('inserted_item'));
    });

    test('Queue mutation remove during active crossfade aborts crossfade cleanly', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Remove an item during crossfade
      await engine.remove(2);
      await pumpEventQueue();

      expect(engine.isCrossfading, isFalse);
      expect(playerA.volume, equals(100.0));
      expect(playerB.isPlaying, isFalse);
      expect(engine.currentState.playables.length, equals(2));
    });

    test('Queue mutation reorder during active crossfade aborts crossfade cleanly', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(sampleTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Reorder items during crossfade
      await engine.reorder(1, 2);
      await pumpEventQueue();

      expect(engine.isCrossfading, isFalse);
      expect(playerA.volume, equals(100.0));
      expect(playerB.isPlaying, isFalse);
    });

    // ------------------------------------------------------------------------
    // 21. Symmetric Crossfade Clamping
    // ------------------------------------------------------------------------
    test('Symmetric crossfade clamping clamps against incoming track duration / 2', () async {
      // Outgoing track: 30s duration
      // Incoming track: 4s duration
      const shortNextTrack = QueueItem(
        id: 'short_incoming',
        uri: '/music/short_incoming.mp3',
        title: 'Short Incoming',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 4),
      );

      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open([sampleTracks[0], shortNextTrack], index: 0, play: true);

      playerA.simulateDuration(const Duration(seconds: 30));

      // Half of 30s is 15s; half of 4s is 2s.
      // Symmetrically clamped duration must be min(5s, 2s) = 2s.
      // At 26s (4s remaining > 2s), crossfade must NOT trigger yet.
      playerA.simulatePosition(const Duration(seconds: 26));
      await pumpEventQueue();
      expect(engine.isCrossfading, isFalse);

      // At 28.5s (1.5s remaining <= 2s), crossfade MUST trigger.
      playerA.simulatePosition(const Duration(milliseconds: 28500));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);
    });

    // ------------------------------------------------------------------------
    // 22. BehaviorSubject Immediate Cancellation Guard
    // ------------------------------------------------------------------------
    test('BehaviorSubject.listen does not invoke onData if subscription cancelled synchronously', () async {
      final subject = BehaviorSubject<int>(99);
      bool dataEmitted = false;

      final sub = subject.listen((val) {
        dataEmitted = true;
      });
      await sub.cancel();

      await pumpEventQueue();
      expect(dataEmitted, isFalse, reason: 'onData must not be called after subscription cancellation');

      await subject.close();
    });
  });
}
