import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  QueueItem createItem({
    required String id,
    required String uri,
    required String title,
    Duration duration = const Duration(seconds: 180),
  }) {
    return QueueItem(
      id: id,
      uri: uri,
      title: title,
      artist: 'Challenger Artist',
      album: 'Challenger Album',
      duration: duration,
    );
  }

  group('Challenger V2: High-Intensity Empirical Edge Cases', () {
    // =========================================================================
    // Edge Case 1: Repeated pause/resume cycles during active crossfade
    // =========================================================================
    group('Edge Case 1: Repeated pause/resume during active crossfade', () {
      test('Pause at ~20%, resume, pause at ~60%, resume -> smooth progress accumulation, zero volume pops, clean completion', () async {
        final playerA = MockAudioPlayerAdapter(id: 'A');
        final playerB = MockAudioPlayerAdapter(id: 'B');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 10),
        );

        final track1 = createItem(
          id: '1',
          uri: 'uri:1',
          title: 'Track 1',
          duration: const Duration(milliseconds: 600),
        );
        final track2 = createItem(
          id: '2',
          uri: 'uri:2',
          title: 'Track 2',
          duration: const Duration(milliseconds: 600),
        );

        await engine.open([track1, track2], index: 0, play: true);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 250),
          curve: CrossfadeCurve.linear,
        ));

        playerA.simulateDuration(const Duration(milliseconds: 600));

        // Trigger crossfade (remaining 200ms <= 250ms)
        playerA.simulatePosition(const Duration(milliseconds: 400));
        await pumpEventQueue();

        expect(engine.isCrossfading, isTrue, reason: 'Crossfade should start at 400ms');
        expect(playerB.isPlaying, isTrue);

        final List<double> volumeLogA = [];
        final List<double> volumeLogB = [];

        void sampleVolumes() {
          volumeLogA.add(playerA.volume);
          volumeLogB.add(playerB.volume);
        }

        sampleVolumes();

        // Let it run for ~50ms (~20% of 250ms)
        await Future<void>.delayed(const Duration(milliseconds: 50));
        sampleVolumes();

        // 1st PAUSE (around 20% progress)
        await engine.pause();
        await pumpEventQueue();

        expect(playerA.isPlaying, isFalse, reason: 'Player A must pause');
        expect(playerB.isPlaying, isFalse, reason: 'Player B must pause');

        final volAAtPause1 = playerA.volume;
        final volBAtPause1 = playerB.volume;
        expect(volAAtPause1, lessThan(100.0));
        expect(volBAtPause1, greaterThan(0.0));

        // Verify volume stays completely frozen while paused
        for (int i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(playerA.volume, equals(volAAtPause1), reason: 'Player A volume must remain frozen during pause');
          expect(playerB.volume, equals(volBAtPause1), reason: 'Player B volume must remain frozen during pause');
          sampleVolumes();
        }

        // 1st RESUME
        await engine.play();
        await pumpEventQueue();
        expect(playerA.isPlaying, isTrue, reason: 'Player A resumes');
        expect(playerB.isPlaying, isTrue, reason: 'Player B resumes');

        // Let it run for ~100ms (accumulating to ~150ms / 250ms = ~60% progress)
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          sampleVolumes();
        }

        // 2nd PAUSE (around 60% progress)
        await engine.pause();
        await pumpEventQueue();

        expect(playerA.isPlaying, isFalse);
        expect(playerB.isPlaying, isFalse);

        final volAAtPause2 = playerA.volume;
        final volBAtPause2 = playerB.volume;
        // Volume must have continued advancing smoothly between resumes
        expect(volAAtPause2, lessThan(volAAtPause1), reason: 'Fade-out must have progressed further before 2nd pause');
        expect(volBAtPause2, greaterThan(volBAtPause1), reason: 'Fade-in must have progressed further before 2nd pause');

        // Verify volume stays completely frozen while paused
        for (int i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(playerA.volume, equals(volAAtPause2));
          expect(playerB.volume, equals(volBAtPause2));
          sampleVolumes();
        }

        // 2nd RESUME
        await engine.play();
        await pumpEventQueue();
        expect(playerA.isPlaying, isTrue);
        expect(playerB.isPlaying, isTrue);

        // Let it run to clean completion (~150ms more)
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          sampleVolumes();
          if (!engine.isCrossfading) break;
        }

        // Verification of clean completion & role swap
        expect(engine.isCrossfading, isFalse, reason: 'Crossfade must complete');
        expect(engine.activePlayer, equals(playerB), reason: 'Player B must be the new active player');
        expect(playerB.volume, equals(100.0), reason: 'Player B must end at master volume');
        expect(playerA.isPlaying, isFalse, reason: 'Player A must be stopped');
        expect(engine.currentState.currentTrack?.id, equals('2'), reason: 'Current track must advance to 2');

        // Verification of monotonic volume change (zero volume pops)
        // Discard identical consecutive values caused by sampling while paused
        final distinctA = <double>[];
        for (final v in volumeLogA) {
          if (distinctA.isEmpty || (distinctA.last - v).abs() > 0.001) {
            distinctA.add(v);
          }
        }
        for (int i = 1; i < distinctA.length; i++) {
          expect(distinctA[i], lessThanOrEqualTo(distinctA[i - 1]),
              reason: 'Player A volume must be monotonically decreasing (no volume pops)');
        }

        final distinctB = <double>[];
        for (final v in volumeLogB) {
          if (distinctB.isEmpty || (distinctB.last - v).abs() > 0.001) {
            distinctB.add(v);
          }
        }
        for (int i = 1; i < distinctB.length; i++) {
          expect(distinctB[i], greaterThanOrEqualTo(distinctB[i - 1]),
              reason: 'Player B volume must be monotonically increasing (no volume pops)');
        }

        await engine.dispose();
      });

      test('Rapid pause/resume barrage during active crossfade does not corrupt timer or leak state', () async {
        final playerA = MockAudioPlayerAdapter(id: 'A');
        final playerB = MockAudioPlayerAdapter(id: 'B');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final track1 = createItem(id: '1', uri: 'uri:1', title: 'Track 1', duration: const Duration(milliseconds: 500));
        final track2 = createItem(id: '2', uri: 'uri:2', title: 'Track 2', duration: const Duration(milliseconds: 500));

        await engine.open([track1, track2], index: 0, play: true);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 200),
        ));

        playerA.simulateDuration(const Duration(milliseconds: 500));
        playerA.simulatePosition(const Duration(milliseconds: 350));
        await pumpEventQueue();

        expect(engine.isCrossfading, isTrue);

        // Rapidly toggle pause and play 10 times in quick succession
        for (int i = 0; i < 10; i++) {
          await engine.pause();
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await engine.play();
          await Future<void>.delayed(const Duration(milliseconds: 3));
        }

        // Wait for crossfade to finish
        for (int i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!engine.isCrossfading) break;
        }

        expect(engine.isCrossfading, isFalse, reason: 'Crossfade must cleanly finish despite pause/play barrage');
        expect(engine.activePlayer, equals(playerB));
        expect(playerB.volume, equals(100.0));
        expect(playerA.isPlaying, isFalse);

        await engine.dispose();
      });
    });

    // =========================================================================
    // Edge Case 2: Queue with 10 duplicate tracks
    // =========================================================================
    group('Edge Case 2: Queue with 10 duplicate tracks and shuffle cycling', () {
      test('10 duplicate tracks (same URI): remove 3 items at various positions; toggle shuffle on/off 50x; queues never desynchronize', () {
        final manager = QueueManager();

        // 10 duplicate tracks with identical URI
        final items = List.generate(
          10,
          (i) => createItem(
            id: 'item_$i',
            uri: 'uri:duplicate_track',
            title: 'Duplicate Song $i',
          ),
        );

        manager.setQueue(items, startIndex: 0);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        // Remove 3 items at various positions: index 8, index 4, index 0
        final removed1 = manager.remove(8);
        expect(removed1?.id, equals('item_8'));
        expect(manager.activeQueue.length, equals(9));
        expect(manager.originalQueue.length, equals(9));

        final removed2 = manager.remove(4);
        expect(removed2?.id, equals('item_4'));
        expect(manager.activeQueue.length, equals(8));
        expect(manager.originalQueue.length, equals(8));

        final removed3 = manager.remove(0);
        expect(removed3?.id, equals('item_0'));
        expect(manager.activeQueue.length, equals(7));
        expect(manager.originalQueue.length, equals(7));

        // Toggle shuffle on and off 50 times repeatedly
        for (int cycle = 0; cycle < 50; cycle++) {
          manager.setShuffle(true);
          expect(manager.isShuffled, isTrue);
          expect(manager.activeQueue.length, equals(7), reason: 'Active queue length must remain 7 while shuffled');
          expect(manager.originalQueue.length, equals(7), reason: 'Original queue length must remain 7 while shuffled');

          manager.setShuffle(false);
          expect(manager.isShuffled, isFalse);
          expect(manager.activeQueue.length, equals(7), reason: 'Active queue length must remain 7 while unshuffled');
          expect(manager.originalQueue.length, equals(7), reason: 'Original queue length must remain 7 while unshuffled');

          // Check that un-shuffled active queue matches original queue element for element
          for (int idx = 0; idx < 7; idx++) {
            expect(manager.activeQueue[idx].id, equals(manager.originalQueue[idx].id));
            expect(manager.activeQueue[idx].uri, equals(manager.originalQueue[idx].uri));
          }
        }
      });

      test('10 duplicate tracks: remove 3 items WHILE SHUFFLED; toggle shuffle on/off 50x; queues never desynchronize', () {
        final manager = QueueManager();

        final items = List.generate(
          10,
          (i) => createItem(
            id: 'track_$i',
            uri: 'uri:repeated_song',
            title: 'Track $i',
          ),
        );

        manager.setQueue(items, startIndex: 0, shuffle: true);
        expect(manager.isShuffled, isTrue);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        // Remove 3 items from active queue while shuffled
        manager.remove(5);
        expect(manager.activeQueue.length, equals(9));
        expect(manager.originalQueue.length, equals(9));

        manager.remove(2);
        expect(manager.activeQueue.length, equals(8));
        expect(manager.originalQueue.length, equals(8));

        manager.remove(0);
        expect(manager.activeQueue.length, equals(7));
        expect(manager.originalQueue.length, equals(7));

        // Toggle shuffle 50 times
        for (int cycle = 0; cycle < 50; cycle++) {
          manager.setShuffle(false);
          expect(manager.isShuffled, isFalse);
          expect(manager.activeQueue.length, equals(7));
          expect(manager.originalQueue.length, equals(7));

          // When unshuffled, activeQueue must match originalQueue exactly
          for (int idx = 0; idx < 7; idx++) {
            expect(manager.activeQueue[idx].id, equals(manager.originalQueue[idx].id));
          }

          manager.setShuffle(true);
          expect(manager.isShuffled, isTrue);
          expect(manager.activeQueue.length, equals(7));
          expect(manager.originalQueue.length, equals(7));
        }
      });
    });

    // =========================================================================
    // Edge Case 3: Loop.all vs Loop.off transitions at queue boundaries with infinite mix enabled
    // =========================================================================
    group('Edge Case 3: Loop.all vs Loop.off transitions at queue boundaries with infinite mix', () {
      test('Loop.all wraps without calling infinite mix; switching to Loop.off triggers infinite mix; switching back wraps', () async {
        int mixCallCount = 0;
        final List<Track> generatedTracks = [
          Track(
            id: 101,
            uri: 'uri:mix_1',
            title: 'Mix Track 1',
            artist: 'Mix Artist',
            album: 'Mix Album',
            durationMs: 180000,
            fileSize: 1000,
            modifiedAt: 1,
          ),
          Track(
            id: 102,
            uri: 'uri:mix_2',
            title: 'Mix Track 2',
            artist: 'Mix Artist',
            album: 'Mix Album',
            durationMs: 180000,
            fileSize: 1000,
            modifiedAt: 1,
          ),
        ];

        final manager = QueueManager(
          libraryTrackProvider: (count) async {
            mixCallCount++;
            return generatedTracks;
          },
        );

        final initialTracks = [
          createItem(id: 'q1', uri: 'uri:q1', title: 'Queue 1'),
          createItem(id: 'q2', uri: 'uri:q2', title: 'Queue 2'),
          createItem(id: 'q3', uri: 'uri:q3', title: 'Queue 3'),
        ];

        // Start at last track (index 2)
        manager.setQueue(initialTracks, startIndex: 2);
        manager.setInfiniteMix(true);
        manager.setLoopMode(Loop.all);

        expect(manager.currentIndex, equals(2));
        expect(manager.currentTrack?.id, equals('q3'));

        // 1. In Loop.all, advancing past end MUST wrap around to index 0 and NOT invoke mix provider
        final next1 = await manager.next(isManual: false);
        expect(next1?.id, equals('q1'), reason: 'Under Loop.all, queue must wrap to index 0');
        expect(manager.currentIndex, equals(0));
        expect(mixCallCount, equals(0), reason: 'Infinite mix must not be called when Loop.all is active');

        // Advance back to the last track (index 2)
        await manager.next(isManual: false); // to index 1
        await manager.next(isManual: false); // to index 2
        expect(manager.currentIndex, equals(2));
        expect(manager.currentTrack?.id, equals('q3'));

        // 2. Transition from Loop.all to Loop.off at the boundary
        manager.setLoopMode(Loop.off);
        expect(manager.loopMode, equals(Loop.off));

        // In Loop.off with infinite mix enabled, advancing past end MUST invoke provider and append mix tracks
        final next2 = await manager.next(isManual: false);
        expect(mixCallCount, equals(1), reason: 'Under Loop.off with infinite mix, provider must be called');
        expect(next2?.uri, equals('uri:mix_1'), reason: 'Next track must be the first mix track');
        expect(manager.currentIndex, equals(3));
        expect(manager.activeQueue.length, equals(5), reason: 'Queue must now have 3 initial + 2 mix tracks');

        // 3. Advance to the last mix track (index 4)
        final next3 = await manager.next(isManual: false);
        expect(next3?.uri, equals('uri:mix_2'));
        expect(manager.currentIndex, equals(4));

        // 4. Transition back to Loop.all at the new boundary
        manager.setLoopMode(Loop.all);
        expect(manager.loopMode, equals(Loop.all));

        // Advancing past the new boundary under Loop.all must wrap back to index 0 without calling mix again
        final next4 = await manager.next(isManual: false);
        expect(next4?.id, equals('q1'), reason: 'Under Loop.all, wraps back to start of expanded queue');
        expect(manager.currentIndex, equals(0));
        expect(mixCallCount, equals(1), reason: 'Mix provider must not have been called again under Loop.all');
      });

      test('Transitioning Loop.off with infinite mix disabled at boundary returns null without wrapping', () async {
        final manager = QueueManager(
          libraryTrackProvider: (count) async => [],
        );

        final tracks = [
          createItem(id: '1', uri: 'uri:1', title: 'Song 1'),
          createItem(id: '2', uri: 'uri:2', title: 'Song 2'),
        ];

        manager.setQueue(tracks, startIndex: 1);
        manager.setLoopMode(Loop.off);
        manager.setInfiniteMix(false);

        final next = await manager.next(isManual: false);
        expect(next, isNull, reason: 'End of queue with Loop.off and mix disabled must return null');
        expect(manager.currentIndex, equals(1));
      });
    });

    // =========================================================================
    // Edge Case 4: Loop.one rapid repeat cycles without crossfade
    // =========================================================================
    group('Edge Case 4: Loop.one rapid repeat cycles without crossfade', () {
      test('10 rapid repeat cycles under Loop.one never initiate crossfade, never swap players, and cleanly seek to zero', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final track = createItem(
          id: 'single_loop_track',
          uri: 'uri:single_loop',
          title: 'Single Loop Track',
          duration: const Duration(seconds: 30),
        );

        await engine.open([track], index: 0, play: true);
        await engine.setLoopMode(Loop.one);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5), // 5-second crossfade window
        ));

        // Run 10 rapid complete playback cycles
        for (int cycle = 1; cycle <= 10; cycle++) {
          playerA.simulateDuration(const Duration(seconds: 30));

          // 1. Move into the crossfade threshold (27s -> remaining 3s <= 5s)
          playerA.simulatePosition(const Duration(seconds: 27));
          await pumpEventQueue();

          // Assert crossfade is NOT started
          expect(engine.isCrossfading, isFalse,
              reason: 'Cycle $cycle: Engine must NOT initiate crossfade under Loop.one');
          expect(playerB.isPlaying, isFalse,
              reason: 'Cycle $cycle: Standby player must remain inactive');
          expect(playerA.isPlaying, isTrue,
              reason: 'Cycle $cycle: Active player must continue playing');
          expect(engine.activePlayer, equals(playerA),
              reason: 'Cycle $cycle: Player A must remain the active player');
          expect(playerA.volume, equals(100.0),
              reason: 'Cycle $cycle: Player A volume must not fade');

          // 2. Track reaches end and simulates completion
          playerA.simulatePosition(const Duration(seconds: 30));
          playerA.simulateCompleted();
          await pumpEventQueue();

          // Assert clean seek to zero and replay
          expect(playerA.position, equals(Duration.zero),
              reason: 'Cycle $cycle: Player A must seek to zero upon track completion');
          expect(playerA.isPlaying, isTrue,
              reason: 'Cycle $cycle: Player A must continue playing');
          expect(playerB.isPlaying, isFalse,
              reason: 'Cycle $cycle: Player B must still be idle');
          expect(engine.isCrossfading, isFalse,
              reason: 'Cycle $cycle: Crossfade must still be false');
          expect(engine.currentState.currentTrack?.id, equals('single_loop_track'),
              reason: 'Cycle $cycle: Current track must remain the same track');
          expect(engine.currentState.index, equals(0),
              reason: 'Cycle $cycle: Queue index must remain 0');
        }

        // Verify callLog on playerB: playerB was never opened
        expect(playerB.callLog.where((c) => c.startsWith('open')).isEmpty, isTrue,
            reason: 'Standby player must never have been opened across all 10 Loop.one cycles');

        await engine.dispose();
      });
    });
  });
}
