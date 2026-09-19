import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reviewer 2 Empirical Edge-Case Verification & Remediation', () {
    test('Remediation 1: QueueManager duplicate track removal maintains active and original queues synchronization', () {
      final manager = QueueManager();
      const itemA1 = QueueItem(
        id: '1',
        uri: 'uri:A',
        title: 'Song A',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
      );
      const itemB = QueueItem(
        id: '2',
        uri: 'uri:B',
        title: 'Song B',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
      );
      const itemA2 = QueueItem(
        id: '3',
        uri: 'uri:A', // Identical URI
        title: 'Song A',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
      );

      manager.setQueue([itemA1, itemB, itemA2]);
      expect(manager.activeQueue.length, equals(3));
      expect(manager.originalQueue.length, equals(3));

      // Remove the 2nd instance of Song A (at index 2)
      manager.remove(2);

      // Both activeQueue and originalQueue must now have exactly 2 items
      expect(manager.activeQueue.length, equals(2));
      expect(manager.activeQueue.map((it) => it.id), equals(['1', '2']));
      expect(manager.originalQueue.length, equals(2));
      expect(manager.originalQueue.map((it) => it.id), equals(['1', '2']));

      // Un-shuffling must restore the remaining 2 tracks without dropping Song A
      manager.setShuffle(false);
      expect(manager.activeQueue.length, equals(2));
      expect(manager.activeQueue.map((it) => it.id), equals(['1', '2']));
    });

    test('Remediation 2: Infinite Library Mix does not hijack Loop.all at end of queue', () async {
      int mixCalls = 0;
      final manager = QueueManager(
        libraryTrackProvider: (count) async {
          mixCalls++;
          return [
            Track(
              id: 99,
              uri: 'uri:mix',
              title: 'Mix Track',
              artist: 'Mixer',
              album: 'Mix Album',
              durationMs: 120000,
              fileSize: 500,
              modifiedAt: 1,
            ),
          ];
        },
      );

      const item1 = QueueItem(
        id: '1',
        uri: 'uri:1',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
      );
      const item2 = QueueItem(
        id: '2',
        uri: 'uri:2',
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
      );

      manager.setQueue([item1, item2], startIndex: 1);
      manager.setLoopMode(Loop.all);
      manager.setInfiniteMix(true);

      // Current track is the last track (index 1) with Loop.all enabled
      // next() MUST wrap around to index 0 (item1) rather than calling infinite mix
      final nextTrack = await manager.next(isManual: false);

      expect(mixCalls, equals(0), reason: 'Infinite mix must NOT be called when Loop.all is active');
      expect(nextTrack?.uri, equals('uri:1'), reason: 'Queue should wrap around to index 0 under Loop.all');
      expect(manager.currentIndex, equals(0));
    });

    test('Remediation 3: Crossfade does not trigger under Loop.one and repeats without crossfade', () async {
      final playerA = MockAudioPlayerAdapter(id: 'A');
      final playerB = MockAudioPlayerAdapter(id: 'B');
      final engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 10),
      );

      const track = QueueItem(
        id: '1',
        uri: 'uri:1',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 30),
      );

      await engine.open([track], index: 0, play: true);
      await engine.setLoopMode(Loop.one);
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(seconds: 5),
      ));

      playerA.simulateDuration(const Duration(seconds: 30));
      // Position reaches threshold (27s -> 3s remaining <= 5s)
      playerA.simulatePosition(const Duration(seconds: 27));
      await pumpEventQueue();

      // Under Loop.one, crossfade must NOT be started
      expect(engine.isCrossfading, isFalse, reason: 'Engine must NOT start crossfade under Loop.one');

      // When track completes, playerA seeks to zero and replays
      playerA.simulatePosition(const Duration(seconds: 30));
      playerA.simulateCompleted();
      await pumpEventQueue();

      expect(playerA.position, equals(Duration.zero));
      expect(playerA.isPlaying, isTrue);

      await engine.dispose();
    });

    test('Remediation 4: Pause during crossfade pauses ticker, play resumes it and completes role swap', () async {
      final playerA = MockAudioPlayerAdapter(id: 'A');
      final playerB = MockAudioPlayerAdapter(id: 'B');
      final engine = AudioEngineServiceImpl(
        playerA: playerA,
        playerB: playerB,
        tickerInterval: const Duration(milliseconds: 10),
      );

      const track1 = QueueItem(
        id: '1',
        uri: 'uri:1',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(milliseconds: 200),
      );
      const track2 = QueueItem(
        id: '2',
        uri: 'uri:2',
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(milliseconds: 200),
      );

      await engine.open([track1, track2], index: 0, play: true);
      await engine.setCrossfadeConfig(const CrossfadeConfig(
        enabled: true,
        duration: Duration(milliseconds: 200),
      ));

      playerA.simulateDuration(const Duration(milliseconds: 200));
      // Trigger crossfade (half-track clamp = 100ms; remaining 80ms <= 100ms)
      playerA.simulatePosition(const Duration(milliseconds: 120));
      await pumpEventQueue();
      expect(engine.isCrossfading, isTrue);

      // User pauses
      await engine.pause();
      await pumpEventQueue();
      expect(playerA.isPlaying, isFalse);
      expect(playerB.isPlaying, isFalse);

      final pausedVolumeB = playerB.volume;
      // Wait while paused — volume must not change
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(playerB.volume, equals(pausedVolumeB));

      // User resumes
      await engine.play();
      await pumpEventQueue();
      expect(playerA.isPlaying, isTrue);
      expect(playerB.isPlaying, isTrue);

      // Wait 150ms for ticker ticks to advance to completion
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Crossfade must have finished and role swapped
      expect(engine.isCrossfading, isFalse, reason: 'Crossfade must complete after play resumes ticker');
      expect(playerB.volume, equals(100.0));
      expect(playerA.isPlaying, isFalse);
      expect(engine.currentState.currentTrack?.id, equals('2'));

      await engine.dispose();
    });
  });
}
