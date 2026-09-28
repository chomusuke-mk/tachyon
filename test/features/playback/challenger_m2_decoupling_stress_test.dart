import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class MockAudioEngineService extends Fake implements AudioEngineService {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _currentState = const PlaybackState.initial();

  @override
  Stream<PlaybackState> get stateStream => _controller.stream;

  @override
  PlaybackState get currentState => _currentState;

  void emitState(PlaybackState state) {
    _currentState = state;
    _controller.add(state);
  }

  void close() {
    _controller.close();
  }
}

class MockAppDatabase extends Fake implements AppDatabase {
  final List<String> historyPlaylistLogs = [];

  @override
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    historyPlaylistLogs.add('$playlistId:$trackId');
  }
}

class RecordedWrite {
  final String uri;
  final int positionMs;
  final DateTime timestamp;

  RecordedWrite({
    required this.uri,
    required this.positionMs,
    required this.timestamp,
  });
}

class MockSettingsRepository extends Fake implements SettingsRepository {
  final List<RecordedWrite> writes = [];

  @override
  Future<void> setLastPlayed({
    required String uri,
    required int positionMs,
  }) async {
    writes.add(
      RecordedWrite(
        uri: uri,
        positionMs: positionMs,
        timestamp: DateTime.now(),
      ),
    );
  }
}

void main() {
  late MockAudioEngineService mockEngine;
  late MockAppDatabase mockDatabase;
  late MockSettingsRepository mockSettings;
  late PlaybackController controller;

  const track1 = QueueItem(
    id: 'track_1',
    uri: '/storage/music/track1.flac',
    title: 'Track One',
    artist: 'Artist A',
    album: 'Album A',
    duration: Duration(seconds: 300),
    trackId: 101,
  );

  const track2 = QueueItem(
    id: 'track_2',
    uri: '/storage/music/track2.flac',
    title: 'Track Two',
    artist: 'Artist B',
    album: 'Album B',
    duration: Duration(seconds: 240),
    trackId: 102,
  );

  const track3 = QueueItem(
    id: 'track_3',
    uri: '/storage/music/track3.flac',
    title: 'Track Three',
    artist: 'Artist C',
    album: 'Album C',
    duration: Duration(seconds: 180),
    trackId: 103,
  );

  setUp(() {
    mockEngine = MockAudioEngineService();
    mockDatabase = MockAppDatabase();
    mockSettings = MockSettingsRepository();
    controller = PlaybackController(
      audioEngineService: mockEngine,
      database: mockDatabase,
      settingsRepository: mockSettings,
    );
  });

  tearDown(() {
    mockEngine.close();
  });

  group('Adversarial Challenge 1: High-Frequency Position Stream Decoupling', () {
    test(
      'Emits 500 position ticks at 50Hz: notifyListeners() call count is strictly ZERO while positionListenable updates 500 times',
      () async {
        // Initial setup: start playback of track1 at steady-state position (5 seconds)
        // (At position >= 3s, hasPrevious is already true and invariant)
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 5),
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        int notifyListenersCount = 0;
        controller.addListener(() {
          notifyListenersCount++;
        });

        int listenableUpdateCount = 0;
        Duration lastObservedPosition = Duration.zero;
        controller.positionListenable.addListener(() {
          listenableUpdateCount++;
          lastObservedPosition = controller.positionListenable.value;
        });

        // Emit 500 consecutive position ticks (every 20ms = 50Hz streaming, from 5,020ms to 15,000ms)
        const int tickCount = 500;
        const int stepMs = 20;

        for (int i = 1; i <= tickCount; i++) {
          mockEngine.emitState(
            PlaybackState(
              playing: true,
              playables: const [track1],
              index: 0,
              position: Duration(milliseconds: 5000 + i * stepMs),
              duration: const Duration(seconds: 300),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);

        // STRESS ASSERTION 1: PlaybackController.notifyListeners() MUST be strictly 0
        expect(
          notifyListenersCount,
          equals(0),
          reason:
              'High-frequency position ticks must never trigger PlaybackController.notifyListeners()',
        );

        // STRESS ASSERTION 2: positionListenable and positionNotifier MUST have updated exactly 500 times
        expect(
          listenableUpdateCount,
          equals(tickCount),
          reason:
              'positionListenable must notify subscribers for every single position tick',
        );

        // STRESS ASSERTION 3: Final values must accurately reflect 15,000ms
        const expectedFinalPos = Duration(
          milliseconds: 5000 + tickCount * stepMs,
        );
        expect(lastObservedPosition, equals(expectedFinalPos));
        expect(controller.positionNotifier.value, equals(expectedFinalPos));
        expect(controller.position, equals(expectedFinalPos));
      },
    );

    test(
      'Track start at 0s: crossing the 3s threshold fires notifyListeners() exactly once for discrete hasPrevious transition',
      () async {
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration.zero,
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        int notifyListenersCount = 0;
        controller.addListener(() {
          notifyListenersCount++;
        });

        // Emit 250 ticks from 0 to 5,000ms
        for (int i = 1; i <= 250; i++) {
          mockEngine.emitState(
            PlaybackState(
              playing: true,
              playables: const [track1],
              index: 0,
              position: Duration(milliseconds: i * 20),
              duration: const Duration(seconds: 300),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);

        // Exactly 1 notification fired: when position crossed 3.0s (hasPrevious false -> true)
        expect(
          notifyListenersCount,
          equals(1),
          reason:
              'Crossing the 3-second mark represents a legitimate discrete state transition (hasPrevious)',
        );
        expect(controller.hasPrevious, isTrue);
      },
    );

    test('Identical position ticks do NOT re-trigger positionListenable listeners', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 5),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      int listenableUpdateCount = 0;
      controller.positionListenable.addListener(() {
        listenableUpdateCount++;
      });

      // Emit 10 identical states with the same position
      for (int i = 0; i < 10; i++) {
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 5),
            duration: Duration(seconds: 300),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        listenableUpdateCount,
        equals(0),
        reason:
            'Unchanged position ticks must be deduplicated by ValueNotifier',
      );
    });
  });

  group('Adversarial Challenge 2: SharedPreferences Write Throttling Stress Tests', () {
    test(
      'Simulate 15 seconds of rapid continuous playback ticks: setLastPlayed called at most once without real-time delay',
      () async {
        // Start track1 playback
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration.zero,
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Initial track start wrote 1 entry
        expect(mockSettings.writes.length, equals(1));
        expect(mockSettings.writes.first.uri, equals(track1.uri));
        expect(mockSettings.writes.first.positionMs, equals(0));

        // Simulate 15 seconds of audio playback ticks (750 ticks at 50Hz = 15,000ms)
        const int totalTicks = 750;
        for (int i = 1; i <= totalTicks; i++) {
          mockEngine.emitState(
            PlaybackState(
              playing: true,
              playables: const [track1],
              index: 0,
              position: Duration(milliseconds: i * 20),
              duration: const Duration(seconds: 300),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);

        // STRESS ASSERTION: Out of 750 position updates within the burst, exactly 1 initial write was recorded
        // (suppressing 749 redundant writes to flash storage)
        expect(
          mockSettings.writes.length,
          equals(1),
          reason:
              'Writes within the 5-second throttle window must be completely suppressed',
        );
      },
    );

    test(
      'Throttling over 10-15 seconds of elapsed time triggers setLastPlayed at most 3-4 times (~once per 5s)',
      () async {
        // Start track1
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration.zero,
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(mockSettings.writes.length, equals(1)); // Write #1 (t=0)

        // Rapid ticks for 1 second of audio
        for (int i = 1; i <= 50; i++) {
          mockEngine.emitState(
            PlaybackState(
              playing: true,
              playables: const [track1],
              index: 0,
              position: Duration(milliseconds: i * 20),
              duration: const Duration(seconds: 300),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(mockSettings.writes.length, equals(1)); // Still suppressed

        // Wait 5.1 seconds for the throttle window to elapse
        await Future<void>.delayed(const Duration(milliseconds: 5100));

        // Emit tick at 6 seconds
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 6),
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Write #2 triggered because >= 5s elapsed
        expect(mockSettings.writes.length, equals(2));
        expect(mockSettings.writes.last.positionMs, equals(6000));

        // Ticks within next second (7s) suppressed
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 7),
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(mockSettings.writes.length, equals(2));

        // Wait another 5.1 seconds
        await Future<void>.delayed(const Duration(milliseconds: 5100));

        // Emit tick at 12 seconds
        mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 12),
            duration: Duration(seconds: 300),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Write #3 triggered
        expect(mockSettings.writes.length, equals(3));
        expect(mockSettings.writes.last.positionMs, equals(12000));

        // Total writes over ~12s simulated playback with realistic delays is exactly 3 (at most 3-4 times)
        expect(mockSettings.writes.length, inInclusiveRange(3, 4));

        // Verify write interval spacing >= 5000ms
        final timeDelta1 = mockSettings.writes[1].timestamp.difference(
          mockSettings.writes[0].timestamp,
        );
        final timeDelta2 = mockSettings.writes[2].timestamp.difference(
          mockSettings.writes[1].timestamp,
        );
        expect(timeDelta1.inMilliseconds, greaterThanOrEqualTo(5000));
        expect(timeDelta2.inMilliseconds, greaterThanOrEqualTo(5000));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Adversarial Challenge 3: Invariant Gating (Immediate Forced Writes)', () {
    test('Pause immediately forces setLastPlayed without waiting for 5s throttle', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration.zero,
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockSettings.writes.length, equals(1));

      // Continuous tick at 2 seconds (well within the 5s window)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 2),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockSettings.writes.length, equals(1)); // Suppressed

      // Now pause playback at 2.5 seconds (only 50ms later)
      mockEngine.emitState(
        const PlaybackState(
          playing: false,
          playables: [track1],
          index: 0,
          position: Duration(milliseconds: 2500),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Invariant: MUST immediately force write on pause!
      expect(mockSettings.writes.length, equals(2));
      expect(mockSettings.writes.last.uri, equals(track1.uri));
      expect(mockSettings.writes.last.positionMs, equals(2500));
    });

    test('Stop / track completion immediately forces setLastPlayed', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 290),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final writesCount = mockSettings.writes.length;

      // Track completed
      mockEngine.emitState(
        const PlaybackState(
          playing: false,
          completed: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 300),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockSettings.writes.length, equals(writesCount + 1));
      expect(mockSettings.writes.last.positionMs, equals(300000));
    });

    test('Track jump immediately flushes new track state without throttle delay', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1, track2],
          index: 0,
          position: Duration(seconds: 15),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final writesCount = mockSettings.writes.length;

      // Jump to track2 immediately (position 0)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1, track2],
          index: 1,
          position: Duration.zero,
          duration: Duration(seconds: 240),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockSettings.writes.length, equals(writesCount + 1));
      expect(mockSettings.writes.last.uri, equals(track2.uri));
      expect(mockSettings.writes.last.positionMs, equals(0));
    });

    test('Major seek (>2s delta) immediately forces setLastPlayed', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 10),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final writesCount = mockSettings.writes.length;

      // Forward seek: 10s -> 50s (delta = 40s > 2s)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 50),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockSettings.writes.length, equals(writesCount + 1));
      expect(mockSettings.writes.last.positionMs, equals(50000));

      // Backward seek: 50s -> 5s (delta = 45s > 2s)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 5),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockSettings.writes.length, equals(writesCount + 2));
      expect(mockSettings.writes.last.positionMs, equals(5000));
    });

    test('Minor seek (<=2s delta) within throttle window is suppressed', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 10),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final writesCount = mockSettings.writes.length;

      // Small seek: 10s -> 11.5s (delta = 1.5s <= 2s)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(milliseconds: 11500),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        mockSettings.writes.length,
        equals(writesCount),
        reason: 'Minor seek under 2s within throttle window must be suppressed',
      );
    });

    test('Controller dispose() immediately flushes latest position to SharedPreferences', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 20),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final writesBeforeDispose = mockSettings.writes.length;

      // Advance position to 22 seconds (suppressed by throttle)
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 22),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockSettings.writes.length, equals(writesBeforeDispose));

      // Call dispose() on controller
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      // STRESS ASSERTION: dispose MUST have flushed position 22000ms immediately!
      expect(mockSettings.writes.length, equals(writesBeforeDispose + 1));
      expect(mockSettings.writes.last.uri, equals(track1.uri));
      expect(mockSettings.writes.last.positionMs, equals(22000));
    });

    test('Post-dispose ticks are safely ignored and do not throw exceptions', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1],
          index: 0,
          position: Duration(seconds: 1),
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      controller.dispose();

      // Emitting after dispose should not crash or call notifyListeners
      expect(
        () => mockEngine.emitState(
          const PlaybackState(
            playing: true,
            playables: [track1],
            index: 0,
            position: Duration(seconds: 2),
            duration: Duration(seconds: 300),
          ),
        ),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('Adversarial Challenge 4: Discrete State Transitions (notifyListeners Coverage)', () {
    test('Reliably fires notifyListeners() on all discrete property transitions', () async {
      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      var currentState = const PlaybackState(
        playing: false,
        playables: [track1, track2],
        index: 0,
        position: Duration.zero,
        duration: Duration(seconds: 300),
      );

      // 1. Initial emission
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(1), reason: 'Transition: initial load');

      // 2. Play transition
      currentState = currentState.copyWith(playing: true);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(2), reason: 'Transition: play');

      // 3. Pause transition
      currentState = currentState.copyWith(playing: false);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(3), reason: 'Transition: pause');

      // 4. Buffering toggle
      currentState = currentState.copyWith(buffering: true);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(4), reason: 'Transition: buffering true');

      currentState = currentState.copyWith(buffering: false);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(5), reason: 'Transition: buffering false');

      // 5. Track change (index + currentTrack)
      currentState = currentState.copyWith(index: 1);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(6), reason: 'Transition: track index change');

      // 6. Queue reorder without current track change
      // Reordering playables to [track2, track1] while index becomes 0 (so currentTrack remains track2)
      currentState = currentState.copyWith(
        playables: [track2, track1],
        index: 0,
      );
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(7), reason: 'Transition: queue reorder');

      // 7. Volume change
      currentState = currentState.copyWith(volume: 75.0);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(8), reason: 'Transition: volume change');

      // 8. Rate change
      currentState = currentState.copyWith(rate: 1.25);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(9), reason: 'Transition: rate change');

      // 9. Pitch change
      currentState = currentState.copyWith(pitch: 1.1);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(10), reason: 'Transition: pitch change');

      // 10. Shuffle toggle
      currentState = currentState.copyWith(shuffle: true);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(11), reason: 'Transition: shuffle toggle');

      // 11. Loop mode transition (off -> one -> all)
      currentState = currentState.copyWith(loop: Loop.one);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(12), reason: 'Transition: loop one');

      currentState = currentState.copyWith(loop: Loop.all);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(13), reason: 'Transition: loop all');

      // 12. Skip silence toggle
      currentState = currentState.copyWith(skipSilence: true);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(14), reason: 'Transition: skipSilence');

      // 13. Crossfade duration change
      currentState = currentState.copyWith(
        crossfadeDuration: const Duration(seconds: 8),
      );
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(15), reason: 'Transition: crossfadeDuration');

      // 14. Completed toggle
      currentState = currentState.copyWith(completed: true);
      mockEngine.emitState(currentState);
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(16), reason: 'Transition: completed');
    });
  });

  group('Adversarial Challenge 5: Rapid Track Skips and Concurrency', () {
    test('Rapid consecutive track skips preserve persistence integrity', () async {
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1, track2, track3],
          index: 0,
          position: Duration.zero,
          duration: Duration(seconds: 300),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockSettings.writes.first.uri, equals(track1.uri));

      // Rapidly skip 1 -> 2 -> 3 without waiting
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1, track2, track3],
          index: 1,
          position: Duration.zero,
          duration: Duration(seconds: 240),
        ),
      );
      mockEngine.emitState(
        const PlaybackState(
          playing: true,
          playables: [track1, track2, track3],
          index: 2,
          position: Duration.zero,
          duration: Duration(seconds: 180),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final uris = mockSettings.writes.map((w) => w.uri).toList();
      expect(uris, contains(track1.uri));
      expect(uris, contains(track2.uri));
      expect(uris, contains(track3.uri));
      expect(mockSettings.writes.last.uri, equals(track3.uri));
    });
  });
}
