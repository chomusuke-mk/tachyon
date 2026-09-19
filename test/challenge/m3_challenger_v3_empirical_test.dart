import 'dart:math' as math;
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
      artist: 'Adversarial Artist',
      album: 'Adversarial Album',
      duration: duration,
    );
  }

  group('Milestone 3 Challenger V3: Adversarial Empirical Verification Suite', () {
    // =========================================================================
    // Scope 1: Rapid pause/resume during crossfade
    // =========================================================================
    group('Scope 1: Rapid Pause/Resume During Crossfade', () {
      test('1.1: 20 rapid pause/play toggles during crossfade with boosted master volume (160%)', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final track1 = createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(milliseconds: 600));
        final track2 = createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(milliseconds: 600));

        await engine.setVolume(160.0);
        await engine.open([track1, track2], index: 0, play: true);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 300),
          curve: CrossfadeCurve.equalPower,
        ));

        playerA.simulateDuration(const Duration(milliseconds: 600));
        // Crossfade threshold: remaining 200ms <= 300ms
        playerA.simulatePosition(const Duration(milliseconds: 400));
        await pumpEventQueue();

        expect(engine.isCrossfading, isTrue, reason: 'Crossfade must be active');
        expect(playerB.isPlaying, isTrue);

        // Execute 20 rapid pause/play cycles with jittered delays
        for (int i = 0; i < 20; i++) {
          await engine.pause();
          expect(playerA.isPlaying, isFalse);
          expect(playerB.isPlaying, isFalse);

          // Small random sleep to vary pause interval
          await Future<void>.delayed(Duration(milliseconds: 1 + (i % 3)));

          await engine.play();
          expect(playerA.isPlaying, isTrue);
          expect(playerB.isPlaying, isTrue);
          await Future<void>.delayed(Duration(milliseconds: 1 + ((i + 1) % 4)));
        }

        // Ticker must remain alive and running until crossfade finishes
        for (int attempt = 0; attempt < 50; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          if (!engine.isCrossfading) break;
        }

        expect(engine.isCrossfading, isFalse, reason: 'Crossfade must finish after resumes');
        expect(engine.activePlayer, equals(playerB), reason: 'Role swap to Player B');
        expect(playerB.volume, equals(160.0), reason: 'Player B reaches boosted master volume');
        expect(playerA.isPlaying, isFalse, reason: 'Player A terminated');
        expect(engine.currentState.currentTrack?.id, equals('t2'));

        await engine.dispose();
      });

      test('1.2: Volume continuity across prolonged pause during crossfade (no wall-clock skip)', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final track1 = createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(milliseconds: 500));
        final track2 = createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(milliseconds: 500));

        await engine.open([track1, track2], index: 0, play: true);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 200),
          curve: CrossfadeCurve.linear,
        ));

        playerA.simulateDuration(const Duration(milliseconds: 500));
        // Trigger at 350ms (remaining 150ms <= 200ms)
        playerA.simulatePosition(const Duration(milliseconds: 350));
        await pumpEventQueue();
        expect(engine.isCrossfading, isTrue);

        // Let ticker tick for ~40ms (~20% progress)
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await engine.pause();
        await pumpEventQueue();

        final volAAtPause = playerA.volume;
        final volBAtPause = playerB.volume;
        expect(volAAtPause, inExclusiveRange(0.0, 100.0));
        expect(volBAtPause, inExclusiveRange(0.0, 100.0));

        // Sleep for 300ms (longer than the total 200ms crossfade duration!)
        // If bug existed (using wall-clock now.difference(startTime)), resume would snap straight to 100%
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(playerA.volume, equals(volAAtPause));
        expect(playerB.volume, equals(volBAtPause));

        // Resume playback
        await engine.play();
        await pumpEventQueue();

        // Immediately after resume (one tick ~5ms), volume must NOT have jumped to 100%
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(engine.isCrossfading, isTrue, reason: 'Crossfade must NOT instantly finish due to elapsed wall time');
        expect(playerB.volume, lessThan(85.0), reason: 'Volume must continue progressively, not jump past 85%');

        // Let it finish naturally
        for (int i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!engine.isCrossfading) break;
        }

        expect(engine.isCrossfading, isFalse);
        expect(engine.activePlayer, equals(playerB));
        expect(playerB.volume, equals(100.0));

        await engine.dispose();
      });

      test('1.3: Seek while paused during active crossfade cleanly aborts crossfade and restores active player', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final tracks = [
          createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(seconds: 30)),
          createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(seconds: 30)),
        ];

        await engine.open(tracks, index: 0, play: true);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ));

        playerA.simulateDuration(const Duration(seconds: 30));
        playerA.simulatePosition(const Duration(seconds: 27)); // trigger crossfade
        await pumpEventQueue();
        expect(engine.isCrossfading, isTrue);

        // Pause while crossfading
        await engine.pause();
        await pumpEventQueue();

        // User seeks back to 5s while paused
        await engine.seek(const Duration(seconds: 5));
        await pumpEventQueue();

        // Invariants:
        // 1. Crossfade aborted
        expect(engine.isCrossfading, isFalse);
        // 2. Standby player B stopped
        expect(playerB.isPlaying, isFalse);
        // 3. Player A volume restored to master (100.0)
        expect(playerA.volume, equals(100.0));
        // 4. Player A remains paused (seeking preserves paused state)
        expect(playerA.isPlaying, isFalse);

        // Resume play -> should play Player A from 5s without crossfade
        await engine.play();
        await pumpEventQueue();
        expect(playerA.isPlaying, isTrue);
        expect(playerB.isPlaying, isFalse);
        expect(engine.isCrossfading, isFalse);

        await engine.dispose();
      });
    });

    // =========================================================================
    // Scope 2: Queue operations with duplicate items
    // =========================================================================
    group('Scope 2: Queue Operations with Duplicate Items', () {
      test('2.1: Interleaved duplicate items: activeQueue.length == originalQueue.length after every removal', () {
        final manager = QueueManager();

        // 20 tracks alternating between URI:Alpha and URI:Beta
        final items = List.generate(
          20,
          (i) => createItem(
            id: 'id_$i',
            uri: i.isEven ? 'uri:Alpha' : 'uri:Beta',
            title: 'Track $i',
          ),
        );

        manager.setQueue(items, startIndex: 5);
        expect(manager.activeQueue.length, equals(20));
        expect(manager.originalQueue.length, equals(20));

        // Sequentially remove 10 tracks from various positions (head, tail, middle, current)
        final removeIndices = [0, 18, 5, 2, 10, 0, 7, 3, 1, 4];
        for (final idx in removeIndices) {
          final activeLenBefore = manager.activeQueue.length;
          final removed = manager.remove(idx);
          expect(removed, isNotNull);

          expect(
            manager.activeQueue.length,
            equals(activeLenBefore - 1),
            reason: 'Active queue length must decrease by exactly 1',
          );
          expect(
            manager.originalQueue.length,
            equals(manager.activeQueue.length),
            reason: 'Strict invariant: originalQueue.length == activeQueue.length',
          );
        }

        // Remaining 10 tracks: verify unshuffle preserves exact counts
        manager.setShuffle(true);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        manager.setShuffle(false);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        // Count occurrences of Alpha and Beta
        final alphaCount = manager.activeQueue.where((t) => t.uri == 'uri:Alpha').length;
        final betaCount = manager.activeQueue.where((t) => t.uri == 'uri:Beta').length;
        expect(alphaCount + betaCount, equals(10));
      });

      test('2.2: Removal of duplicate items while shuffled preserves accurate unshuffle reconstruction', () {
        final manager = QueueManager(random: math.Random(12345));

        // 12 tracks: 4 of Song A, 4 of Song B, 4 of Song C
        final items = <QueueItem>[];
        for (int i = 0; i < 4; i++) {
          items.add(createItem(id: 'A_$i', uri: 'uri:A', title: 'Song A'));
          items.add(createItem(id: 'B_$i', uri: 'uri:B', title: 'Song B'));
          items.add(createItem(id: 'C_$i', uri: 'uri:C', title: 'Song C'));
        }

        manager.setQueue(items, startIndex: 0, shuffle: true);
        expect(manager.isShuffled, isTrue);
        expect(manager.activeQueue.length, equals(12));
        expect(manager.originalQueue.length, equals(12));

        // Remove 2 items from active queue while shuffled
        final removed1 = manager.remove(11);
        final removed2 = manager.remove(0);
        expect(removed1, isNotNull);
        expect(removed2, isNotNull);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        // Turn shuffle off
        manager.setShuffle(false);
        expect(manager.isShuffled, isFalse);
        expect(manager.activeQueue.length, equals(10));
        expect(manager.originalQueue.length, equals(10));

        // Ensure removed items are not present in either queue
        final activeIds = manager.activeQueue.map((t) => t.id).toSet();
        final originalIds = manager.originalQueue.map((t) => t.id).toSet();
        expect(activeIds.contains(removed1!.id), isFalse);
        expect(activeIds.contains(removed2!.id), isFalse);
        expect(originalIds.contains(removed1.id), isFalse);
        expect(originalIds.contains(removed2.id), isFalse);

        // Turn shuffle on and off 10 times in a row
        for (int i = 0; i < 10; i++) {
          manager.toggleShuffle();
          expect(manager.activeQueue.length, equals(10));
          expect(manager.originalQueue.length, equals(10));
        }
      });

      test('2.3: Removing currentTrack when identical duplicate is also in queue does not corrupt pointer', () {
        final manager = QueueManager();
        final item1 = createItem(id: 'copy1', uri: 'uri:same', title: 'Same Song');
        final item2 = createItem(id: 'other', uri: 'uri:other', title: 'Other Song');
        final item3 = createItem(id: 'copy2', uri: 'uri:same', title: 'Same Song');

        manager.setQueue([item1, item2, item3], startIndex: 0);
        expect(manager.currentTrack?.id, equals('copy1'));

        // Remove copy1 (index 0)
        final removed = manager.remove(0);
        expect(removed?.id, equals('copy1'));
        expect(manager.activeQueue.length, equals(2));
        expect(manager.originalQueue.length, equals(2));

        // Pointer shifts to remaining track at index 0 (which is now item2)
        expect(manager.currentIndex, equals(0));
        expect(manager.currentTrack?.id, equals('other'));

        // Advance to next -> copy2
        manager.next();
        expect(manager.currentIndex, equals(1));
        expect(manager.currentTrack?.id, equals('copy2'));
      });
    });

    // =========================================================================
    // Scope 3: Loop.all vs Infinite Library Mix
    // =========================================================================
    group('Scope 3: Loop.all vs Infinite Library Mix Precedence', () {
      test('3.1: Single-track queue under Loop.all NEVER calls Infinite Library Mix across 10 iterations', () async {
        int mixCallCount = 0;
        final manager = QueueManager(
          libraryTrackProvider: (count) async {
            mixCallCount++;
            return [
              Track(
                id: 999,
                uri: 'uri:infinite_track',
                title: 'Infinite Track',
                artist: 'Infinite Artist',
                album: 'Infinite Album',
                durationMs: 150000,
                fileSize: 1024,
                modifiedAt: 1,
              ),
            ];
          },
        );

        final singleTrack = createItem(id: 'solo', uri: 'uri:solo', title: 'Solo Track');
        manager.setQueue([singleTrack], startIndex: 0);
        manager.setLoopMode(Loop.all);
        manager.setInfiniteMix(true);

        for (int i = 0; i < 10; i++) {
          final isManual = i.isEven;
          final result = await manager.next(isManual: isManual);
          expect(result?.id, equals('solo'), reason: 'Under Loop.all, single-track queue must continually return itself');
          expect(manager.currentIndex, equals(0));
          expect(mixCallCount, equals(0), reason: 'Iteration $i: Infinite Mix must NEVER trigger under Loop.all');
          expect(manager.activeQueue.length, equals(1), reason: 'Queue length must remain 1');
        }
      });

      test('3.2: Multi-track queue under Loop.all: end of queue wraps to 0 without invoking Infinite Mix', () async {
        int mixCallCount = 0;
        final manager = QueueManager(
          libraryTrackProvider: (count) async {
            mixCallCount++;
            return [
              Track(
                id: 888,
                uri: 'uri:mix888',
                title: 'Mix 888',
                artist: 'Mixer',
                album: 'Mix Album',
                durationMs: 120000,
                fileSize: 1024,
                modifiedAt: 1,
              ),
            ];
          },
        );

        final tracks = [
          createItem(id: 't1', uri: 'uri:t1', title: 'Track 1'),
          createItem(id: 't2', uri: 'uri:t2', title: 'Track 2'),
          createItem(id: 't3', uri: 'uri:t3', title: 'Track 3'),
        ];

        manager.setQueue(tracks, startIndex: 2); // Start at last track
        manager.setLoopMode(Loop.all);
        manager.setInfiniteMix(true);

        // Next automatic advance past end
        final wrapped1 = await manager.next(isManual: false);
        expect(wrapped1?.id, equals('t1'), reason: 'Auto advance wraps to index 0');
        expect(manager.currentIndex, equals(0));
        expect(mixCallCount, equals(0));

        // Advance to end again
        await manager.next(isManual: true); // t2
        await manager.next(isManual: true); // t3
        expect(manager.currentIndex, equals(2));

        // Manual advance past end
        final wrapped2 = await manager.next(isManual: true);
        expect(wrapped2?.id, equals('t1'), reason: 'Manual advance wraps to index 0');
        expect(manager.currentIndex, equals(0));
        expect(mixCallCount, equals(0));
      });

      test('3.3: Toggling Loop.off triggers infinite mix; subsequent toggle to Loop.all wraps expanded queue', () async {
        int mixCallCount = 0;
        final manager = QueueManager(
          libraryTrackProvider: (count) async {
            mixCallCount++;
            return [
              Track(
                id: 111,
                uri: 'uri:injected_1',
                title: 'Injected 1',
                artist: 'AI',
                album: 'Mix',
                durationMs: 100000,
                fileSize: 100,
                modifiedAt: 1,
              ),
            ];
          },
        );

        manager.setQueue([createItem(id: 'x', uri: 'uri:x', title: 'Track X')], startIndex: 0);
        manager.setInfiniteMix(true);
        manager.setLoopMode(Loop.off);

        // In Loop.off, reaching end triggers Infinite Mix
        final mixedItem = await manager.next(isManual: false);
        expect(mixCallCount, equals(1));
        expect(mixedItem?.uri, equals('uri:injected_1'));
        expect(manager.activeQueue.length, equals(2));
        expect(manager.currentIndex, equals(1));

        // Switch to Loop.all at end of the newly expanded queue
        manager.setLoopMode(Loop.all);

        // Next advance must wrap back to Track X (index 0) without calling mix again
        final loopItem = await manager.next(isManual: false);
        expect(loopItem?.id, equals('x'));
        expect(manager.currentIndex, equals(0));
        expect(mixCallCount, equals(1), reason: 'Provider must not be called again under Loop.all');
      });
    });

    // =========================================================================
    // Scope 4: Loop.one
    // =========================================================================
    group('Scope 4: Loop.one Semantics & Crossfade Suppression', () {
      test('4.1: Multi-track queue under Loop.one never initiates crossfade into next track or itself', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final tracks = [
          createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(seconds: 40)),
          createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(seconds: 40)),
          createItem(id: 't3', uri: 'uri:t3', title: 'Track 3', duration: const Duration(seconds: 40)),
        ];

        // Open at index 1 (Track 2)
        await engine.open(tracks, index: 1, play: true);
        await engine.setLoopMode(Loop.one);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 8), // 8 second crossfade window
        ));

        playerA.simulateDuration(const Duration(seconds: 40));

        // Simulate advancing near track end: 35s, 38s, 39s (all within the 8s crossfade window)
        for (final posSec in [35, 38, 39]) {
          playerA.simulatePosition(Duration(seconds: posSec));
          await pumpEventQueue();

          expect(engine.isCrossfading, isFalse, reason: 'Crossfade must NEVER start under Loop.one at pos ${posSec}s');
          expect(playerB.isPlaying, isFalse, reason: 'Standby player must not play');
          expect(engine.activePlayer, equals(playerA));
          expect(playerA.volume, equals(100.0), reason: 'Volume must stay 100%');
        }

        // Simulate track completion
        playerA.simulatePosition(const Duration(seconds: 40));
        playerA.simulateCompleted();
        await pumpEventQueue();

        // Invariants:
        // 1. Player seeks to Duration.zero and remains playing
        expect(playerA.position, equals(Duration.zero));
        expect(playerA.isPlaying, isTrue);
        // 2. Queue index does NOT advance to Track 3
        expect(engine.currentState.index, equals(1));
        expect(engine.currentState.currentTrack?.id, equals('t2'));
        // 3. Standby player was never touched
        expect(playerB.callLog.where((c) => c.startsWith('open')), isEmpty);

        await engine.dispose();
      });

      test('4.2: Manual next() under Loop.one restarts current track without advancing or crossfading', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final tracks = [
          createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(seconds: 30)),
          createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(seconds: 30)),
        ];

        await engine.open(tracks, index: 0, play: true);
        await engine.setLoopMode(Loop.one);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ));

        playerA.simulateDuration(const Duration(seconds: 30));
        playerA.simulatePosition(const Duration(seconds: 15));
        await pumpEventQueue();

        // Calling next() manually while Loop.one is active
        await engine.next();
        await pumpEventQueue();

        // Current track remains t1, seeks to zero, plays
        expect(engine.currentState.index, equals(0));
        expect(engine.currentState.currentTrack?.id, equals('t1'));
        expect(playerA.position, equals(Duration.zero));
        expect(playerA.isPlaying, isTrue);
        expect(engine.isCrossfading, isFalse);
        expect(playerB.isPlaying, isFalse);

        await engine.dispose();
      });

      test('4.3: Switching from Loop.all to Loop.one during pre-crossfade window cancels next track expectation', () async {
        final playerA = MockAudioPlayerAdapter(id: 'PlayerA');
        final playerB = MockAudioPlayerAdapter(id: 'PlayerB');
        final engine = AudioEngineServiceImpl(
          playerA: playerA,
          playerB: playerB,
          tickerInterval: const Duration(milliseconds: 5),
        );

        final tracks = [
          createItem(id: 't1', uri: 'uri:t1', title: 'Track 1', duration: const Duration(seconds: 30)),
          createItem(id: 't2', uri: 'uri:t2', title: 'Track 2', duration: const Duration(seconds: 30)),
        ];

        await engine.open(tracks, index: 0, play: true);
        await engine.setLoopMode(Loop.all);
        await engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ));

        playerA.simulateDuration(const Duration(seconds: 30));
        playerA.simulatePosition(const Duration(seconds: 20)); // not in window yet

        // Switch loop mode to Loop.one
        await engine.setLoopMode(Loop.one);

        // Move into window: 27s
        playerA.simulatePosition(const Duration(seconds: 27));
        await pumpEventQueue();

        // Crossfade must NOT trigger because mode is now Loop.one
        expect(engine.isCrossfading, isFalse);
        expect(playerB.isPlaying, isFalse);

        await engine.dispose();
      });
    });
  });
}
