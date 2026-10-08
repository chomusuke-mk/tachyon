import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';

void main() {
  group('QueueManager Proactive Lookahead Prefetch Tests', () {
    late List<Track> testTracks;

    setUp(() {
      testTracks = [
        const Track(
          id: 1,
          filePath: '/music/track_1.mp3',
          title: 'Track 1',
          durationMs: 180000,
          fileSize: 1024,
          modifiedAt: 1000,
        ),
        const Track(
          id: 2,
          filePath: '/music/track_2.mp3',
          title: 'Track 2',
          durationMs: 190000,
          fileSize: 1024,
          modifiedAt: 1000,
        ),
      ];
    });

    test('Prefetch triggers proactively when reaching last track in Loop.off with Infinite Mix enabled', () async {
      int providerCallCount = 0;
      final mixTracks = [
        const Track(
          id: 10,
          filePath: '/music/mix_10.mp3',
          title: 'Mix 10',
          durationMs: 200000,
          fileSize: 1024,
          modifiedAt: 1000,
        ),
      ];

      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          providerCallCount++;
          return mixTracks;
        },
      );

      bool mutationNotified = false;
      queueManager.onQueueMutated = () {
        mutationNotified = true;
      };

      queueManager.setTracks(testTracks, startIndex: 0);
      queueManager.setLoopMode(Loop.off);
      queueManager.setInfiniteMix(true);

      // On track 0 of 2: Not yet on the last track, so prefetch does NOT trigger
      expect(providerCallCount, equals(0));
      expect(queueManager.length, equals(2));
      expect(queueManager.currentIndex, equals(0));

      // Advance to track 1 (the last track): Prefetch triggers proactively!
      await queueManager.next(isManual: true);
      expect(queueManager.currentIndex, equals(1));
      expect(providerCallCount, equals(1));
      expect(queueManager.length, equals(3));
      expect(queueManager.peekNext(distinct: true)?.track?.filePath, equals('/music/mix_10.mp3'));
      expect(mutationNotified, isTrue);
      expect(queueManager.hasNext, isTrue);
    });

    test('Loop.one does NOT prefetch and preserves repeat of current track', () async {
      int providerCallCount = 0;
      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          providerCallCount++;
          return [
            const Track(
              id: 99,
              filePath: '/music/mix.mp3',
              title: 'Mix',
              durationMs: 1000,
              fileSize: 100,
              modifiedAt: 100,
            ),
          ];
        },
      );

      queueManager.setLoopMode(Loop.one);
      queueManager.setInfiniteMix(true);
      queueManager.setTracks(testTracks, startIndex: 1); // on last track

      // Provider should NOT be called in Loop.one
      expect(providerCallCount, equals(0));
      expect(queueManager.length, equals(2));

      // Auto-advance in Loop.one returns the same track
      final nextTrack = await queueManager.next(isManual: false);
      expect(nextTrack?.track?.filePath, equals(testTracks[1].filePath));
      expect(providerCallCount, equals(0));
      expect(queueManager.length, equals(2));
    });

    test('Loop.all does NOT prefetch and loops back to track 0 with crossfade candidate', () async {
      int providerCallCount = 0;
      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          providerCallCount++;
          return [
            const Track(
              id: 99,
              filePath: '/music/mix.mp3',
              title: 'Mix',
              durationMs: 1000,
              fileSize: 100,
              modifiedAt: 100,
            ),
          ];
        },
      );

      queueManager.setLoopMode(Loop.all);
      queueManager.setInfiniteMix(true);
      queueManager.setTracks(testTracks, startIndex: 1); // on last track

      // Provider should NOT be called in Loop.all
      expect(providerCallCount, equals(0));
      expect(queueManager.length, equals(2));

      // peekNext in Loop.all returns track 0
      expect(queueManager.peekNext(distinct: true)?.track?.filePath, equals(testTracks[0].filePath));

      // Advance in Loop.all loops back to index 0
      final nextTrack = await queueManager.next(isManual: true);
      expect(queueManager.currentIndex, equals(0));
      expect(nextTrack?.track?.filePath, equals(testTracks[0].filePath));
      expect(providerCallCount, equals(0));
    });

    test('Switching from Loop.all to Loop.off on last track triggers prefetch immediately', () async {
      int providerCallCount = 0;
      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          providerCallCount++;
          return [
            const Track(
              id: 50,
              filePath: '/music/mix_50.mp3',
              title: 'Mix 50',
              durationMs: 1000,
              fileSize: 100,
              modifiedAt: 100,
            ),
          ];
        },
      );

      queueManager.setLoopMode(Loop.all);
      queueManager.setInfiniteMix(true);
      queueManager.setTracks(testTracks, startIndex: 1); // on last track

      expect(providerCallCount, equals(0));
      expect(queueManager.length, equals(2));

      // Switch to Loop.off: now it immediately triggers prefetch!
      queueManager.setLoopMode(Loop.off);
      // Wait for async fetch
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(providerCallCount, equals(1));
      expect(queueManager.length, equals(3));
      expect(queueManager.peekNext(distinct: true)?.track?.filePath, equals('/music/mix_50.mp3'));
    });

    test('Empty provider marks prefetchExhausted and does not loop forever', () async {
      int providerCallCount = 0;
      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          providerCallCount++;
          return <Track>[]; // Empty library
        },
      );

      queueManager.setTracks(testTracks.take(1).toList(), startIndex: 0);
      queueManager.setLoopMode(Loop.off);
      queueManager.setInfiniteMix(true);

      // Wait for initial prefetch to finish and mark exhausted
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(providerCallCount, equals(1));
      expect(queueManager.length, equals(1));
      expect(queueManager.hasNext, isFalse);

      // Subsequent next() call should NOT call provider again
      final result = await queueManager.next(isManual: true);
      expect(result, isNull);
      expect(providerCallCount, equals(1)); // Stays at 1, no spinning loop
    });

    test('Concurrent manual skip while prefetch is in flight awaits fetch and transitions smoothly', () async {
      final queueManager = QueueManager(
        libraryTrackProvider: (count) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return [
            const Track(
              id: 88,
              filePath: '/music/delayed_mix.mp3',
              title: 'Delayed Mix',
              durationMs: 1000,
              fileSize: 100,
              modifiedAt: 100,
            ),
          ];
        },
      );

      queueManager.setTracks(testTracks.take(1).toList(), startIndex: 0);
      queueManager.setLoopMode(Loop.off);
      queueManager.setInfiniteMix(true); // prefetch started in background

      // User immediately clicks next() while fetch is still in flight (50ms delay)
      final nextTrack = await queueManager.next(isManual: true);
      expect(nextTrack?.track?.filePath, equals('/music/delayed_mix.mp3'));
      expect(queueManager.currentIndex, equals(1));
      expect(queueManager.length, equals(2));
    });
  });

  group('PlaybackState hasNext with isInfiniteMixEnabled', () {
    test('hasNext is true when on last track in Loop.off if isInfiniteMixEnabled is true', () {
      const dummyTrack = Track(
        id: 1,
        filePath: '/music/t1.mp3',
        title: 'T1',
        durationMs: 1000,
        fileSize: 100,
        modifiedAt: 100,
      );
      final stateWithMix = PlaybackState(
        index: 2,
        playables: [
          PlaylistEntry.forQueue(id: 0, position: 0, track: dummyTrack),
          PlaylistEntry.forQueue(id: 1, position: 1, track: dummyTrack),
          PlaylistEntry.forQueue(id: 2, position: 2, track: dummyTrack),
        ],
        loop: Loop.off,
        isInfiniteMixEnabled: true,
      );
      expect(stateWithMix.hasNext, isTrue);

      final stateWithoutMix = stateWithMix.copyWith(isInfiniteMixEnabled: false);
      expect(stateWithoutMix.hasNext, isFalse);
    });

    test('hasNext is false if playables is empty even if isInfiniteMixEnabled is true', () {
      const emptyState = PlaybackState(
        index: 0,
        playables: [],
        loop: Loop.off,
        isInfiniteMixEnabled: true,
      );
      expect(emptyState.hasNext, isFalse);
    });
  });
}
