import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class FakeAudioEngineService extends Fake implements AudioEngineService {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _currentState = const PlaybackState.initial();

  @override
  Stream<PlaybackState> get stateStream => _controller.stream;

  @override
  PlaybackState get currentState => _currentState;

  @override
  PlaybackState get state => _currentState;

  void emitState(PlaybackState state) {
    _currentState = state;
    _controller.add(state);
  }

  void close() {
    _controller.close();
  }
}

class FakeAppDatabase extends Fake implements AppDatabase {
  final List<String> addedTracks = [];

  @override
  Future<void> addTrackToPlaylist(int playlistId, int trackId, [String? filePath]) async {
    addedTracks.add('$playlistId:$trackId');
  }
}

class FakeSettingsRepository extends Fake implements SettingsRepository {
  final List<({String uri, int positionMs})> lastPlayedWrites = [];

  @override
  Future<void> setLastPlayed({
    String? filePath,
    required int positionMs,
    String? uri,
  }) async {
    final effective = filePath ?? uri ?? '';
    lastPlayedWrites.add((uri: effective, positionMs: positionMs));
  }
}

void main() {
  late FakeAudioEngineService fakeEngine;
  late FakeAppDatabase fakeDatabase;
  late FakeSettingsRepository fakeSettings;
  late PlaybackController controller;

  const track1 = QueueItem(
    id: 'track_1',
    filePath: '/storage/music/song1.mp3',
    title: 'Song One',
    artist: 'Artist A',
    album: 'Album A',
    duration: Duration(seconds: 180),
  );

  const track2 = QueueItem(
    id: 'track_2',
    filePath: '/storage/music/song2.mp3',
    title: 'Song Two',
    artist: 'Artist B',
    album: 'Album B',
    duration: Duration(seconds: 240),
  );

  setUp(() {
    fakeEngine = FakeAudioEngineService();
    fakeDatabase = FakeAppDatabase();
    fakeSettings = FakeSettingsRepository();
    final backend = DirectTachyonBackendClient(
      audioEngine: fakeEngine,
      database: fakeDatabase,
    );
    controller = PlaybackController(
      backend: backend,
      settingsRepository: fakeSettings,
    );
  });

  tearDown(() {
    fakeEngine.close();
  });

  group('Feature 11: Position Stream Decoupling', () {
    test('High-frequency position ticks advance positionNotifier without firing notifyListeners()', () async {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      int positionNotifierCount = 0;
      controller.positionListenable.addListener(() => positionNotifierCount++);

      // Emit initial playing state
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration.zero,
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);

      // Discrete change occurred (initial -> playing track1)
      expect(notifyCount, equals(1));
      expect(positionNotifierCount, equals(0)); // Was Duration.zero

      // Simulate 50 high-frequency position ticks (20ms intervals) during smooth playback
      for (int i = 1; i <= 50; i++) {
        fakeEngine.emitState(PlaybackState(
          playing: true,
          playables: const [track1],
          index: 0,
          position: Duration(milliseconds: i * 20),
          duration: const Duration(seconds: 180),
        ));
      }
      await Future<void>.delayed(Duration.zero);

      // Verify positionNotifier advanced to 1000ms
      expect(controller.position, equals(const Duration(milliseconds: 1000)));
      expect(controller.positionNotifier.value, equals(const Duration(milliseconds: 1000)));
      expect(positionNotifierCount, equals(50));

      // CRITICAL: PlaybackController notifyListeners() must NOT have fired during continuous ticks!
      expect(notifyCount, equals(1), reason: 'notifyListeners() must not fire on pure position ticks');
    });

    test('Discrete state changes (play, pause, track transition, buffering) fire notifyListeners()', () async {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // 1. Start playback
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 10),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(1));

      // 2. Pause
      fakeEngine.emitState(const PlaybackState(
        playing: false,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 10),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(2));

      // 3. Track transition
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1, track2],
        index: 1,
        position: Duration.zero,
        duration: Duration(seconds: 240),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(3));

      // 4. Buffering state toggle
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        buffering: true,
        playables: [track1, track2],
        index: 1,
        position: Duration.zero,
        duration: Duration(seconds: 240),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(4));

      // 5. Completion
      fakeEngine.emitState(const PlaybackState(
        playing: false,
        completed: true,
        playables: [track1, track2],
        index: 1,
        position: Duration(seconds: 240),
        duration: Duration(seconds: 240),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifyCount, equals(5));
    });
  });

  group('Feature 12: Throttled SharedPreferences Disk Writes', () {
    test('Continuous playback position writes are throttled to once per 5 seconds', () async {
      // Start track
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration.zero,
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(fakeSettings.lastPlayedWrites.length, equals(1));
      expect(fakeSettings.lastPlayedWrites.first.uri, equals(track1.filePath));
      expect(fakeSettings.lastPlayedWrites.first.positionMs, equals(0));

      // Ticks at 1s, 2s, 3s, 4s should be throttled and NOT write to disk
      for (int sec = 1; sec <= 4; sec++) {
        fakeEngine.emitState(PlaybackState(
          playing: true,
          playables: const [track1],
          index: 0,
          position: Duration(seconds: sec),
          duration: const Duration(seconds: 180),
        ));
        await Future<void>.delayed(Duration.zero);
      }
      expect(fakeSettings.lastPlayedWrites.length, equals(1),
          reason: 'Writes under 5s throttle window must be suppressed');

      // Now force persistence via flushStatePersistence
      await controller.flushStatePersistence();
      expect(fakeSettings.lastPlayedWrites.length, equals(2));
      expect(fakeSettings.lastPlayedWrites.last.positionMs, equals(4000));
    });

    test('Pausing forces immediate persistence write', () async {
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 1),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      final countBeforePause = fakeSettings.lastPlayedWrites.length;

      // Pause at 2 seconds
      fakeEngine.emitState(const PlaybackState(
        playing: false,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 2),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(fakeSettings.lastPlayedWrites.length, equals(countBeforePause + 1));
      expect(fakeSettings.lastPlayedWrites.last.positionMs, equals(2000));
    });

    test('Seek with delta > 2000ms forces immediate persistence write', () async {
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 5),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      final initialCount = fakeSettings.lastPlayedWrites.length;

      // Jump 50 seconds forward (> 2000ms delta)
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 55),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(fakeSettings.lastPlayedWrites.length, equals(initialCount + 1));
      expect(fakeSettings.lastPlayedWrites.last.positionMs, equals(55000));
    });

    test('Track transition immediately flushes old track state and records new track', () async {
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 30),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);

      // Switch to track2
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1, track2],
        index: 1,
        position: Duration.zero,
        duration: Duration(seconds: 240),
      ));
      await Future<void>.delayed(Duration.zero);

      final uris = fakeSettings.lastPlayedWrites.map((w) => w.uri).toList();
      expect(uris.contains(track1.filePath), isTrue);
      expect(uris.contains(track2.filePath), isTrue);
    });

    test('Controller dispose() flushes final state immediately', () async {
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 12),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      final countBeforeDispose = fakeSettings.lastPlayedWrites.length;

      // Advance position within throttle window
      fakeEngine.emitState(const PlaybackState(
        playing: true,
        playables: [track1],
        index: 0,
        position: Duration(seconds: 14),
        duration: Duration(seconds: 180),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(fakeSettings.lastPlayedWrites.length, equals(countBeforeDispose));

      // Dispose controller
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(fakeSettings.lastPlayedWrites.length, equals(countBeforeDispose + 1));
      expect(fakeSettings.lastPlayedWrites.last.positionMs, equals(14000));
    });
  });
}
