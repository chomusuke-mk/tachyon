import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/audio_session_manager.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  QueueItem createItem(String id, String uri, String title, {Duration? duration}) {
    return QueueItem(
      id: id,
      uri: uri,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      duration: duration ?? const Duration(seconds: 180),
    );
  }

  group('Empirical Challenge 1: Rapid Seek Stress During Active Crossfade', () {
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late AudioEngineServiceImpl engine;

    final testTracks = [
      createItem('t1', '/music/track1.mp3', 'Track 1', duration: const Duration(seconds: 30)),
      createItem('t2', '/music/track2.mp3', 'Track 2', duration: const Duration(seconds: 30)),
      createItem('t3', '/music/track3.mp3', 'Track 3', duration: const Duration(seconds: 30)),
    ];

    setUp(() {
      playerA = MockAudioPlayerAdapter(id: 'PlayerA');
      playerB = MockAudioPlayerAdapter(id: 'PlayerB');
      engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 5), // Ultra-fast ticker
        random: math.Random(101),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('50 rapid seeks while crossfade automation ticker is actively running', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
        curve: CrossfadeCurve.equalPower,
      ));
      await engine.open(testTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade (27s -> remaining 3s <= 5s)
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();

      expect(engine.isCrossfading, isTrue);
      expect(playerB.isPlaying, isTrue);

      // Perform 50 rapid seeks while the ticker is actively calculating volume curves
      final seekTargets = [
        const Duration(seconds: 5),
        const Duration(seconds: 12),
        const Duration(seconds: 2),
        const Duration(seconds: 22),
        const Duration(seconds: 8),
        const Duration(seconds: 15),
        const Duration(seconds: 3),
        const Duration(seconds: 18),
        const Duration(seconds: 1),
        const Duration(seconds: 10),
      ];

      for (int i = 0; i < 50; i++) {
        final target = seekTargets[i % seekTargets.length];
        await engine.seek(target);
        // Small microtask yield to allow ticker ticks to interleave
        if (i % 5 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }
      await pumpEventQueue();

      // Final seek to a known non-crossfade position (10s)
      await engine.seek(const Duration(seconds: 10));
      await pumpEventQueue();

      // Assertions:
      // 1. Crossfade must be completely aborted
      expect(engine.isCrossfading, isFalse);
      // 2. Standby player must be stopped
      expect(playerB.isPlaying, isFalse);
      // 3. Active player volume must NOT be stuck at intermediate curve value
      expect(engine.activePlayer.volume, equals(100.0));
      expect(playerA.volume, equals(100.0));
      // 4. Current position reflects the final seek target
      expect(playerA.position, equals(const Duration(seconds: 10)));
    });

    test('Rapid seeks oscillating across the crossfade boundary (24s <-> 28s)', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(testTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      for (int i = 0; i < 20; i++) {
        // Cross into crossfade zone (28s -> remaining 2s <= 5s)
        await engine.seek(const Duration(seconds: 28));
        await pumpEventQueue();
        expect(engine.isCrossfading, isTrue);
        expect(playerB.isPlaying, isTrue);

        // Immediately seek out of crossfade zone (15s -> remaining 15s > 5s)
        await engine.seek(const Duration(seconds: 15));
        await pumpEventQueue();
        expect(engine.isCrossfading, isFalse);
        expect(playerB.isPlaying, isFalse);
        expect(playerA.volume, equals(100.0));
      }
    });

    test('Rapid seek during crossfade restores boosted master volume (180%) without clipping', () async {
      await engine.setVolume(180.0);
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(testTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 30));

      // Trigger crossfade at 27s
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Seek back to 10s
      await engine.seek(const Duration(seconds: 10));
      await pumpEventQueue();

      // Master volume must be restored to 180.0, NOT hardcoded 100.0
      expect(playerA.volume, equals(180.0));
      expect(playerB.isPlaying, isFalse);
      expect(engine.isCrossfading, isFalse);
    });
  });

  group('Empirical Challenge 2: Extreme Short Track Crossfade Clamping & Transitions', () {
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late AudioEngineServiceImpl engine;

    setUp(() {
      playerA = MockAudioPlayerAdapter(id: 'PlayerA');
      playerB = MockAudioPlayerAdapter(id: 'PlayerB');
      engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 5),
        random: math.Random(202),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('CrossfadeConfig clamps effective duration to trackDuration / 2 for extreme short tracks', () {
      const config = CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 10),
      );

      // 500ms track with 10s crossfade -> clamps to 250ms
      expect(
        config.effectiveDuration(const Duration(milliseconds: 500)),
        equals(const Duration(milliseconds: 250)),
      );

      // 1000ms (1s) track with 10s crossfade -> clamps to 500ms
      expect(
        config.effectiveDuration(const Duration(seconds: 1)),
        equals(const Duration(milliseconds: 500)),
      );

      // 200ms track with 10s crossfade -> clamps to 100ms
      expect(
        config.effectiveDuration(const Duration(milliseconds: 200)),
        equals(const Duration(milliseconds: 100)),
      );

      // 0ms track -> 0ms
      expect(
        config.effectiveDuration(Duration.zero),
        equals(Duration.zero),
      );

      // Negative duration track -> 0ms
      expect(
        config.effectiveDuration(const Duration(milliseconds: -500)),
        equals(Duration.zero),
      );
    });

    test('Live crossfade on a 1-second track triggers at 500ms threshold and completes cleanly', () async {
      final microTracks = [
        createItem('m1', '/music/micro1.mp3', 'Micro 1', duration: const Duration(seconds: 1)),
        createItem('m2', '/music/micro2.mp3', 'Micro 2', duration: const Duration(seconds: 1)),
      ];

      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 10), // 10s config, but track is 1s -> effective is 500ms
      ));
      await engine.open(microTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(seconds: 1));

      // At 400ms: remaining 600ms > 500ms -> no crossfade yet
      playerA.simulatePosition(const Duration(milliseconds: 400));
      await pumpEventQueue();
      expect(engine.isCrossfading, isFalse);
      expect(playerB.isPlaying, isFalse);

      // At 600ms: remaining 400ms <= 500ms -> crossfade triggered
      playerA.simulatePosition(const Duration(milliseconds: 600));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);
      expect(playerB.isPlaying, isTrue);
      expect(playerB.volume, equals(0.0));

      // Fast forward crossfade to completion via next()
      await engine.next();
      await pumpEventQueue();

      // Role swap: Player B is now active with Micro 2 at 100% volume
      expect(engine.currentState.index, equals(1));
      expect(engine.currentState.currentTrack?.title, equals('Micro 2'));
      expect(engine.activePlayer, equals(playerB));
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
    });

    test('Live crossfade on a 500ms track transitions cleanly without arithmetic errors', () async {
      final microTracks = [
        createItem('m1', '/music/halfsec1.mp3', 'HalfSec 1', duration: const Duration(milliseconds: 500)),
        createItem('m2', '/music/halfsec2.mp3', 'HalfSec 2', duration: const Duration(milliseconds: 500)),
      ];

      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5), // effective will be 250ms
      ));
      await engine.open(microTracks, index: 0, play: true);
      playerA.simulateDuration(const Duration(milliseconds: 500));

      // Trigger crossfade at 300ms (remaining 200ms <= 250ms)
      playerA.simulatePosition(const Duration(milliseconds: 300));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Complete crossfade
      await engine.next();
      await pumpEventQueue();

      expect(engine.currentState.index, equals(1));
      expect(engine.activePlayer, equals(playerB));
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
    });

    test('Zero-duration track does not trigger crossfade and avoids division by zero', () async {
      final zeroTrack = [
        createItem('z1', '/music/zero.mp3', 'Zero Track', duration: Duration.zero),
        createItem('z2', '/music/next.mp3', 'Next Track', duration: const Duration(seconds: 10)),
      ];

      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(zeroTrack, index: 0, play: true);
      playerA.simulateDuration(Duration.zero);
      playerA.simulatePosition(Duration.zero);
      await pumpEventQueue();

      expect(engine.isCrossfading, isFalse);
      expect(playerB.isPlaying, isFalse);
    });
  });

  group('Empirical Challenge 3: Rapid Track Skipping & Role Swap Stress During Crossfade', () {
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late AudioEngineServiceImpl engine;

    final testTracks = List.generate(
      20,
      (i) => createItem('t_$i', '/music/track_$i.mp3', 'Track $i', duration: const Duration(seconds: 30)),
    );

    setUp(() {
      playerA = MockAudioPlayerAdapter(id: 'PlayerA');
      playerB = MockAudioPlayerAdapter(id: 'PlayerB');
      engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 5),
        random: math.Random(303),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('Rapid consecutive next() calls during crossfade fast-forward and swap roles cleanly', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(testTracks, index: 0, play: true);

      // Perform 10 iterations of triggering crossfade and immediately calling next()
      for (int i = 0; i < 10; i++) {
        final active = engine.activePlayer as MockAudioPlayerAdapter;
        active.simulateDuration(const Duration(seconds: 30));
        active.simulatePosition(const Duration(seconds: 27)); // triggers crossfade
        await pumpEventQueue();
        expect(engine.isCrossfading, isTrue);

        // Immediate skip to fast-forward crossfade
        await engine.next();
        await pumpEventQueue();

        // Crossfade completed, exactly one player active
        expect(engine.isCrossfading, isFalse);
        expect(engine.activePlayer.isPlaying, isTrue);
        expect(engine.standbyPlayer.isPlaying, isFalse);
        expect(engine.activePlayer.volume, equals(100.0));
      }

      expect(engine.currentState.index, equals(10));
    });

    test('Rapid consecutive previous() calls during crossfade cleanly abort and restore active player', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(testTracks, index: 5, play: true);

      final active = engine.activePlayer as MockAudioPlayerAdapter;
      active.simulateDuration(const Duration(seconds: 30));
      active.simulatePosition(const Duration(seconds: 27)); // triggers crossfade
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // Call previous() during crossfade
      await engine.previous();
      await pumpEventQueue();

      // Standby player stopped, active player restored to master volume
      expect(engine.isCrossfading, isFalse);
      expect(engine.standbyPlayer.isPlaying, isFalse);
      expect(engine.activePlayer.volume, equals(100.0));
    });

    test('Chaotic interleaved next() and previous() calls do not leak timers or produce overlapping audio', () async {
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));
      await engine.open(testTracks, index: 2, play: true);

      final actions = ['next', 'next', 'prev', 'next', 'prev', 'prev', 'next', 'next'];

      for (final action in actions) {
        final active = engine.activePlayer as MockAudioPlayerAdapter;
        active.simulateDuration(const Duration(seconds: 30));
        active.simulatePosition(const Duration(seconds: 28)); // trigger crossfade
        await pumpEventQueue();

        if (action == 'next') {
          await engine.next();
        } else {
          await engine.previous();
        }
        await pumpEventQueue();

        // Verify mutual exclusion invariant: players are never both playing as active outputs
        expect(engine.isCrossfading, isFalse);
        expect(engine.activePlayer.volume, equals(100.0));
        expect(engine.standbyPlayer.isPlaying, isFalse);
        expect(engine.currentState.index, inInclusiveRange(0, testTracks.length - 1));
      }
    });
  });

  group('Empirical Challenge 4: Queue Mutation Stress & Pointer Integrity', () {
    late QueueManager queueManager;
    late List<QueueItem> initialTracks;

    setUp(() {
      initialTracks = List.generate(
        10,
        (i) => createItem('id_$i', '/music/song_$i.mp3', 'Song $i'),
      );
      queueManager = QueueManager(random: math.Random(404));
      queueManager.setQueue(initialTracks, startIndex: 3);
    });

    test('200 rapid and interleaved mutations preserve index pointer integrity with zero RangeErrors', () {
      final rng = math.Random(777);

      for (int step = 0; step < 200; step++) {
        final op = rng.nextInt(5);
        final len = queueManager.activeQueue.length;

        switch (op) {
          case 0: // insertNext
            final newItem = createItem('dyn_$step', '/music/dyn_$step.mp3', 'Dyn $step');
            queueManager.insertNext(newItem);
            break;

          case 1: // append
            final appended = [
              createItem('app_a_$step', '/music/app_a_$step.mp3', 'App A $step'),
              createItem('app_b_$step', '/music/app_b_$step.mp3', 'App B $step'),
            ];
            queueManager.append(appended);
            break;

          case 2: // remove
            if (len > 0) {
              final removeIdx = rng.nextInt(len);
              queueManager.remove(removeIdx);
            }
            break;

          case 3: // reorder
            if (len > 1) {
              final from = rng.nextInt(len);
              final to = rng.nextInt(len);
              queueManager.reorder(from, to);
            }
            break;

          case 4: // toggleShuffle
            queueManager.toggleShuffle();
            break;
        }

        // Invariants after EVERY single operation:
        if (queueManager.activeQueue.isEmpty) {
          expect(queueManager.currentIndex, equals(-1));
          expect(queueManager.currentTrack, isNull);
        } else {
          expect(
            queueManager.currentIndex,
            inInclusiveRange(0, queueManager.activeQueue.length - 1),
            reason: 'currentIndex out of bounds at step $step (op=$op, len=${queueManager.activeQueue.length})',
          );
          expect(
            queueManager.currentTrack,
            isNotNull,
            reason: 'currentTrack should not be null when queue is non-empty at step $step',
          );
          expect(
            queueManager.currentTrack,
            equals(queueManager.activeQueue[queueManager.currentIndex]),
            reason: 'currentTrack must match activeQueue[currentIndex] at step $step',
          );
        }
      }
    });

    test('Removing current track safely resolves to next track or closes gracefully', () {
      expect(queueManager.currentIndex, equals(3));
      final trackToRemove = queueManager.currentTrack!;

      final removed = queueManager.remove(3);
      expect(removed?.id, equals(trackToRemove.id));

      // Pointer remains valid and points to the shifted element
      expect(queueManager.currentIndex, equals(3));
      expect(queueManager.currentTrack?.id, equals('id_4'));
      expect(queueManager.activeQueue.length, equals(9));
    });

    test('Removing all tracks sequentially until empty causes no RangeErrors', () {
      while (queueManager.activeQueue.isNotEmpty) {
        queueManager.remove(0);
      }

      expect(queueManager.activeQueue, isEmpty);
      expect(queueManager.currentIndex, equals(-1));
      expect(queueManager.currentTrack, isNull);

      // Safe against further operations
      expect(queueManager.remove(0), isNull);
      expect(queueManager.remove(-1), isNull);
      queueManager.reorder(0, 1); // No throw
      expect(queueManager.currentIndex, equals(-1));
    });

    test('Boundary mutation arguments are safely rejected without throwing RangeError', () {
      // Out of bounds remove
      expect(queueManager.remove(-1), isNull);
      expect(queueManager.remove(100), isNull);

      // Out of bounds reorder
      queueManager.reorder(-1, 5);
      queueManager.reorder(2, 50);
      queueManager.reorder(5, -2);
      queueManager.reorder(20, 30);

      // Out of bounds jumpTo
      expect(queueManager.jumpTo(-5), isNull);
      expect(queueManager.jumpTo(100), isNull);

      // Pointer still intact at index 3
      expect(queueManager.currentIndex, equals(3));
      expect(queueManager.currentTrack?.id, equals('id_3'));
    });
  });

  group('Empirical Challenge 5: Fisher-Yates Distribution & Non-Repetition Stress (1,000 Cycles)', () {
    late List<QueueItem> largeQueue;

    setUp(() {
      largeQueue = List.generate(
        50,
        (i) => createItem('track_$i', 'file:///music/song_$i.mp3', 'Track $i'),
      );
    });

    test('1,000 shuffle cycles strictly satisfy current-track pinning, non-repetition, and item conservation', () {
      final rng = math.Random(505);
      final itemPositionHistogram = <int, Map<int, int>>{};

      for (int i = 0; i < 50; i++) {
        itemPositionHistogram[i] = {};
      }

      for (int cycle = 0; cycle < 1000; cycle++) {
        final startIndex = rng.nextInt(50);
        final manager = QueueManager(random: math.Random(cycle + 1000));
        manager.setQueue(largeQueue, startIndex: startIndex, shuffle: true);

        // 1. Index 0 MUST be the selected current track
        expect(
          manager.currentIndex,
          equals(0),
          reason: 'Cycle $cycle: currentIndex must be 0 upon shuffle',
        );
        expect(
          manager.activeQueue.first.id,
          equals('track_$startIndex'),
          reason: 'Cycle $cycle: selected track at index $startIndex must be pinned to index 0',
        );
        expect(
          manager.currentTrack?.id,
          equals('track_$startIndex'),
        );

        // 2. No immediate consecutive duplicate at index 1
        expect(
          manager.activeQueue[1].uri,
          isNot(equals(manager.activeQueue[0].uri)),
          reason: 'Cycle $cycle: track at index 1 must not duplicate index 0 uri',
        );

        // 3. Exactly 50 elements preserved (no drops, no duplicates)
        expect(
          manager.activeQueue.length,
          equals(50),
          reason: 'Cycle $cycle: activeQueue length must remain 50',
        );
        final uniqueIds = manager.activeQueue.map((it) => it.id).toSet();
        expect(
          uniqueIds.length,
          equals(50),
          reason: 'Cycle $cycle: all 50 track IDs must be uniquely preserved',
        );

        // Record positions of items for distribution check
        for (int pos = 1; pos < manager.activeQueue.length; pos++) {
          final trackNum = int.parse(manager.activeQueue[pos].id.split('_')[1]);
          itemPositionHistogram[trackNum]![pos] =
              (itemPositionHistogram[trackNum]![pos] ?? 0) + 1;
        }
      }

      // Statistical spread verification: verify that items spread across multiple positions
      // (not stuck in single deterministic slots)
      for (int trackId = 0; trackId < 50; trackId++) {
        final distinctPositionsVisited = itemPositionHistogram[trackId]!.keys.length;
        // Each track should have landed in at least 30 different positions out of 49 over 1000 cycles
        expect(
          distinctPositionsVisited,
          greaterThanOrEqualTo(30),
          reason: 'Track $trackId visited only $distinctPositionsVisited distinct positions (poor entropy)',
        );
      }
    });

    test('Consecutive duplicates prevention when duplicate tracks exist in source playlist', () {
      // Source playlist with 4 identical tracks
      final duplicateList = [
        createItem('dup_0', 'file:///music/same.mp3', 'Same Song 0'),
        createItem('dup_1', 'file:///music/same.mp3', 'Same Song 1'),
        createItem('other_a', 'file:///music/other_a.mp3', 'Other A'),
        createItem('other_b', 'file:///music/other_b.mp3', 'Other B'),
      ];

      final manager = QueueManager(random: math.Random(999));
      manager.setQueue(duplicateList, startIndex: 0, shuffle: true);

      // Pinned to index 0
      expect(manager.activeQueue[0].id, equals('dup_0'));
      // Index 1 must not have uri matching index 0 because non-matching tracks exist
      expect(manager.activeQueue[1].uri, isNot(equals('file:///music/same.mp3')));
    });
  });

  group('Empirical Challenge 6: Audio Effects Limits & Windows Exclusive Audio Conflict', () {
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late AudioEngineServiceImpl engine;

    setUp(() {
      playerA = MockAudioPlayerAdapter(id: 'PlayerA');
      playerB = MockAudioPlayerAdapter(id: 'PlayerB');
      engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        random: math.Random(606),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('Volume boost supports amplification up to 200.0% and clamps extremes', () async {
      // Boost to 150%
      await engine.setVolume(150.0);
      expect(engine.currentState.volume, equals(150.0));
      expect(playerA.volume, equals(150.0));

      // Boost to 200% (max limit)
      await engine.setVolume(200.0);
      expect(engine.currentState.volume, equals(200.0));
      expect(playerA.volume, equals(200.0));

      // Over boost (280%) clamps to 200.0%
      await engine.setVolume(280.0);
      expect(engine.currentState.volume, equals(200.0));
      expect(playerA.volume, equals(200.0));

      // Negative volume clamps to 0.0%
      await engine.setVolume(-35.0);
      expect(engine.currentState.volume, equals(0.0));
      expect(playerA.volume, equals(0.0));
    });

    test('Playback rate clamps to specified limits [0.5, 1.5]', () async {
      await engine.setRate(0.5);
      expect(engine.currentState.rate, equals(0.5));
      expect(playerA.rate, equals(0.5));
      expect(playerB.rate, equals(0.5));

      await engine.setRate(1.5);
      expect(engine.currentState.rate, equals(1.5));

      // Sub-minimum clamps to 0.5
      await engine.setRate(0.1);
      expect(engine.currentState.rate, equals(0.5));

      // Super-maximum clamps to 1.5
      await engine.setRate(3.0);
      expect(engine.currentState.rate, equals(1.5));
    });

    test('Pitch shifting clamps to specified limits [0.5, 1.5]', () async {
      await engine.setPitch(0.5);
      expect(engine.currentState.pitch, equals(0.5));
      expect(playerA.pitch, equals(0.5));
      expect(playerB.pitch, equals(0.5));

      await engine.setPitch(1.5);
      expect(engine.currentState.pitch, equals(1.5));

      // Sub-minimum clamps to 0.5
      await engine.setPitch(0.2);
      expect(engine.currentState.pitch, equals(0.5));

      // Super-maximum clamps to 1.5
      await engine.setPitch(4.0);
      expect(engine.currentState.pitch, equals(1.5));
    });

    test('ReplayGain preamp clamps to [-15.0 dB, +15.0 dB]', () async {
      await engine.setReplayGainPreamp(15.0);
      expect(playerA.properties['replaygain-preamp'], equals('15.0'));

      await engine.setReplayGainPreamp(-15.0);
      expect(playerA.properties['replaygain-preamp'], equals('-15.0'));

      // Overflow clamps
      await engine.setReplayGainPreamp(30.0);
      expect(playerA.properties['replaygain-preamp'], equals('15.0'));

      await engine.setReplayGainPreamp(-45.0);
      expect(playerA.properties['replaygain-preamp'], equals('-15.0'));
    });

    test('ExclusiveAudioCrossfadeException is thrown when Windows Exclusive Audio conflicts with Crossfade', () async {
      // 1. Crossfade is active -> enabling exclusive audio must throw
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 4),
      ));

      expect(
        () => engine.setExclusiveAudio(true),
        throwsA(
          isA<ExclusiveAudioCrossfadeException>().having(
            (e) => e.toString(),
            'toString',
            contains('Windows Exclusive Audio cannot be enabled while crossfade is active'),
          ),
        ),
      );

      // 2. Disable crossfade -> exclusive audio can now be enabled
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: false,
        duration: Duration.zero,
      ));
      await engine.setExclusiveAudio(true);
      expect(engine.currentState.exclusiveAudio, isTrue);

      // 3. Exclusive audio is active -> re-enabling crossfade must throw
      expect(
        () => engine.setCrossfadeConfig(const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 4),
        )),
        throwsA(
          isA<ExclusiveAudioCrossfadeException>().having(
            (e) => e.toString(),
            'toString',
            contains('Cannot enable crossfade when Windows Exclusive Audio is active'),
          ),
        ),
      );

      // 4. Setting crossfade with duration zero while exclusive audio is active is permitted
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration.zero,
      ));
      expect(engine.currentState.crossfadeDuration, equals(Duration.zero));
    });
  });

  group('Empirical Challenge 7: Audio Focus Interruption & Multi-Event State Restoration', () {
    late MockAudioSessionPlayerDelegate delegate;
    late AudioSessionManager sessionManager;
    late StreamController<AudioInterruptionEvent> interruptionController;
    late StreamController<void> becomingNoisyController;

    setUp(() async {
      delegate = MockAudioSessionPlayerDelegate();
      sessionManager = AudioSessionManager(delegate: delegate);
      interruptionController = StreamController<AudioInterruptionEvent>.broadcast();
      becomingNoisyController = StreamController<void>.broadcast();

      await sessionManager.init(
        mockInterruptionStream: interruptionController.stream,
        mockBecomingNoisyStream: becomingNoisyController.stream,
      );
    });

    tearDown(() async {
      await sessionManager.dispose();
      await interruptionController.close();
      await becomingNoisyController.close();
    });

    test('Multi-event sequence 1: Playing -> Call interruption begin -> Call end -> Resumes', () async {
      delegate.isPlaying = true;

      // Phone call rings and begins
      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);

      // User finishes call
      interruptionController.add(const AudioInterruptionEvent(begin: false));
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isTrue);
      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.callLog, equals(['delegate.pause()', 'delegate.play()']));
    });

    test('Multi-event sequence 2: Paused -> Call interruption begin -> Call end -> Stays paused', () async {
      delegate.isPlaying = false;

      // Interruption starts while already paused
      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);

      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.callLog, isEmpty);

      // Interruption ends
      interruptionController.add(const AudioInterruptionEvent(begin: false));
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.callLog, isEmpty);
    });

    test('Multi-event sequence 3: Nested/repeated interruption begins do not overwrite wasPlaying flag', () async {
      delegate.isPlaying = true;

      // First interruption begins (e.g. navigation prompt)
      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);
      expect(delegate.isPlaying, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);

      // Second overlapping interruption begins (e.g. phone call)
      // Since isPlaying is now false, it must not corrupt or clear wasPlayingBeforeInterruption
      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);
      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);

      // Second interruption ends
      interruptionController.add(const AudioInterruptionEvent(begin: false));
      await Future<void>.delayed(Duration.zero);
      expect(delegate.isPlaying, isTrue);
      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
    });

    test('Multi-event sequence 4: Headphone unplug ("becoming noisy") immediately pauses playback', () async {
      delegate.isPlaying = true;

      becomingNoisyController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isFalse);
      expect(delegate.callLog, equals(['delegate.pause()']));
    });

    test('Multi-event sequence 5: Headphone unplug while paused causes no redundant delegate actions', () async {
      delegate.isPlaying = false;

      becomingNoisyController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isFalse);
      expect(delegate.callLog, isEmpty);
    });

    test('Multi-event sequence 6: Interruption ducking type does not auto-play on end', () async {
      delegate.isPlaying = true;

      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);
      expect(delegate.isPlaying, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);

      // End event with duck type (not pause type)
      interruptionController.add(const AudioInterruptionEvent(
        begin: false,
        type: AudioInterruptionType.duck,
      ));
      await Future<void>.delayed(Duration.zero);

      // Did not call play because type was not pause
      expect(delegate.isPlaying, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
    });

    test('Multi-event sequence 7: Session activation, deactivation, and disposal idempotency', () async {
      expect(sessionManager.isSessionActive, isFalse);

      await sessionManager.activateSession();
      expect(sessionManager.isSessionActive, isTrue);

      // Redundant activation is no-op
      await sessionManager.activateSession();
      expect(sessionManager.isSessionActive, isTrue);

      await sessionManager.deactivateSession();
      expect(sessionManager.isSessionActive, isFalse);

      // Redundant deactivation is no-op
      await sessionManager.deactivateSession();
      expect(sessionManager.isSessionActive, isFalse);

      // Dispose deactivates session
      await sessionManager.activateSession();
      await sessionManager.dispose();
      expect(sessionManager.isSessionActive, isFalse);
    });
  });
}

class MockAudioSessionPlayerDelegate implements AudioSessionPlayerDelegate {
  bool _playing = false;
  double _volume = 100.0;
  final List<String> callLog = [];

  double get volume => _volume;

  @override
  bool get isPlaying => _playing;

  set isPlaying(bool val) => _playing = val;

  @override
  Future<void> play() async {
    _playing = true;
    callLog.add('delegate.play()');
  }

  @override
  Future<void> pause() async {
    _playing = false;
    callLog.add('delegate.pause()');
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    callLog.add('delegate.setVolume($volume)');
  }
}
