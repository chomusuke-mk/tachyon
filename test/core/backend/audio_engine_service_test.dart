import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/crossfade_manager.dart';
import 'package:tachyon/core/backend/services/queue_manager.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart' show CrossfadeCurve;

import 'crossfade_manager_test.dart';

void main() {
  group('AudioEngineService Anti-Regression & Concurrency Tests', () {
    late AudioEngineService service;
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late QueueManager queueManager;
    late CrossfadeManager crossfadeManager;

    final List<QueueItem> testItems = List.generate(
      6,
      (i) => QueueItem(
        id: '${i + 1}',
        filePath: '/music/track_${i + 1}.mp3',
        title: 'Track ${i + 1}',
        artist: 'Artist ${i + 1}',
        album: 'Album 1',
        duration: const Duration(seconds: 180),
      ),
    );

    setUp(() {
      playerA = MockAudioPlayerAdapter();
      playerB = MockAudioPlayerAdapter();
      queueManager = QueueManager();
      crossfadeManager = CrossfadeManager(
        tickerInterval: const Duration(milliseconds: 10),
      );

      service = AudioEngineService(
        playerA: playerA,
        playerB: playerB,
        queueManager: queueManager,
        crossfadeManager: crossfadeManager,
        tickerInterval: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('Open queue initializes active player with first track at volume 100', () async {
      await service.open(testItems, index: 0, play: true);

      expect(service.queueManager.currentIndex, equals(0));
      expect(service.activePlayer.isPlaying, isTrue);
      expect(service.standbyPlayer.isPlaying, isFalse);
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
      expect((service.activePlayer as MockAudioPlayerAdapter).seekHistory, contains(Duration.zero));
    });

    test('Anti-Zombie Test: Rapid clicking next during crossfade leaves 0 zombie players', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 300),
          manualDuration: Duration(milliseconds: 200),
          curve: CrossfadeCurve.linear,
        ),
      );

      // Rapidly skip 1 -> 2 -> 3 -> 4 -> 5 in <50ms
      await service.next();
      await Future.delayed(const Duration(milliseconds: 10));
      await service.next();
      await Future.delayed(const Duration(milliseconds: 10));
      await service.next();
      await Future.delayed(const Duration(milliseconds: 10));
      await service.next();

      // Current index should be 4 (track 5)
      expect(service.queueManager.currentIndex, equals(4));

      // Wait for any final transition to settle
      await Future.delayed(const Duration(milliseconds: 250));

      // Hard Gate: exactly one player active and playing, standby is stopped and silenced
      expect(service.activePlayer.isPlaying, isTrue);
      expect(service.standbyPlayer.isPlaying, isFalse, reason: 'Standby player must never be playing');
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0), reason: 'Standby player volume must be 0');
    });

    test('Anti-Freeze Test: Simultaneous completedStream and auto-crossfade ticker does NOT double-swap', () async {
      await service.open(testItems, index: 4, play: true); // Start at track 5
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 100),
          manualDuration: Duration(milliseconds: 100),
        ),
      );

      final initialActive = service.activePlayer;
      final initialStandby = service.standbyPlayer;

      final initialActiveMock = initialActive as MockAudioPlayerAdapter;
      initialActiveMock.totalDuration = const Duration(seconds: 180);

      // Trigger crossfade transition to test exact completion concurrency
      await service.next();

      // Simulate completed stream firing on the outgoing player concurrently
      initialActiveMock.stop();

      // Wait for crossfade to complete
      await Future.delayed(const Duration(milliseconds: 150));

      // Verification: Queue index must be 5 (track 6), exactly 1 advance
      expect(service.queueManager.currentIndex, equals(5));

      // Player roles swapped exactly ONCE:
      // Active player is now initialStandby (playing track 6)
      expect(identical(service.activePlayer, initialStandby), isTrue);
      // Standby player is initialActive (stopped)
      expect(identical(service.standbyPlayer, initialActive), isTrue);
      expect((service.standbyPlayer as MockAudioPlayerAdapter).isStopped, isTrue);
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
      expect(service.activePlayer.isPlaying, isTrue);
    });

    test('Volume update mid-crossfade dynamically updates CrossfadeManager', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          manualDuration: Duration(milliseconds: 300),
        ),
      );

      await service.next();
      expect(service.isCrossfading, isTrue);

      // Change volume mid-crossfade
      await service.setVolume(50.0);

      await Future.delayed(const Duration(milliseconds: 40));

      expect(service.currentState.volume, equals(50.0));
      expect(service.activePlayer.volume, lessThanOrEqualTo(50.0));
      expect(service.standbyPlayer.volume, lessThanOrEqualTo(50.0));
    });

    test('Seek during active manual crossfade cleanly cancels crossfade and keeps position', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          manualDuration: Duration(milliseconds: 400),
        ),
      );

      await service.next();
      expect(service.isCrossfading, isTrue);

      // Seek to 1:00
      await service.seek(const Duration(minutes: 1));

      expect(service.isCrossfading, isFalse, reason: 'Seek must cancel crossfade');
      expect(service.activePlayer.isPlaying, isTrue);
      expect(service.activePlayer.position, equals(const Duration(minutes: 1)));
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
      expect((service.standbyPlayer as MockAudioPlayerAdapter).isStopped, isTrue);
    });

    test('Seek during active auto-crossfade reverts transition, keeps active player playing and silences standby', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 500),
          manualDuration: Duration(milliseconds: 200),
        ),
      );

      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      activeMock.totalDuration = const Duration(seconds: 180);

      // Trigger auto-crossfade by simulating position in trigger zone (remaining = 200ms < 500ms)
      await activeMock.seek(const Duration(seconds: 179, milliseconds: 800));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.isCrossfading, isTrue, reason: 'Auto-crossfade should be active');
      expect(service.standbyPlayer.isPlaying, isTrue, reason: 'Standby player should be fading in');

      // User seeks to 1:00 (before the crossfade zone)
      await service.seek(const Duration(minutes: 1));

      // Verification:
      expect(service.isCrossfading, isFalse, reason: 'Crossfade must be cancelled');
      expect(service.activePlayer.isPlaying, isTrue, reason: 'Active player must keep playing');
      expect(service.currentState.playing, isTrue, reason: 'UI state must be playing');
      expect((service.activePlayer as MockAudioPlayerAdapter).currentVolume, equals(100.0), reason: 'Active player volume must be restored to 100');
      expect(service.activePlayer.position, equals(const Duration(minutes: 1)));
      expect(service.standbyPlayer.isPlaying, isFalse, reason: 'Standby player must be stopped');
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0), reason: 'Standby player volume must be 0');
    });

    test('Previous track restarts current track if played > 3 seconds', () async {
      await service.open(testItems, index: 2, play: true);
      final currentMock = service.activePlayer as MockAudioPlayerAdapter;
      currentMock.currentPosition = const Duration(seconds: 10);

      await service.previous();

      // Current track restarted (seek 0), index remains 2
      expect(service.queueManager.currentIndex, equals(2));
      expect(currentMock.seekHistory, contains(Duration.zero));
    });

    test('Previous track moves to track 2 if current track played <= 3 seconds', () async {
      await service.open(testItems, index: 2, play: true);
      final currentMock = service.activePlayer as MockAudioPlayerAdapter;
      currentMock.currentPosition = const Duration(seconds: 1);

      await service.previous();

      // Moves to index 1
      expect(service.queueManager.currentIndex, equals(1));
    });

    test('Auto-crossfade in flight + user switches to Loop.one cancels crossfade and repeats track on completion', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 500),
          manualDuration: Duration(milliseconds: 200),
          curve: CrossfadeCurve.linear,
        ),
      );

      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      activeMock.totalDuration = const Duration(seconds: 180);

      // Trigger auto-crossfade
      await activeMock.seek(const Duration(seconds: 179, milliseconds: 800));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.isCrossfading, isTrue, reason: 'Auto-crossfade should be active');
      expect(service.standbyPlayer.isPlaying, isTrue);

      // User sets Loop.one mid-crossfade
      await service.setLoopMode(Loop.one);

      // Verification: Crossfade cancelled immediately, standby stopped, active player restored
      expect(service.isCrossfading, isFalse, reason: 'Crossfade must be cancelled on Loop.one');
      expect(service.standbyPlayer.isPlaying, isFalse, reason: 'Standby player must be stopped');
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
      expect(service.activePlayer.isPlaying, isTrue, reason: 'Active player must keep playing');
      expect((service.activePlayer as MockAudioPlayerAdapter).currentVolume, equals(100.0));
      expect(service.queueManager.currentIndex, equals(0));

      // Active track completes naturally
      activeMock.emitCompleted();
      await Future.delayed(const Duration(milliseconds: 20));

      // Track repeats itself at index 0
      expect(service.queueManager.currentIndex, equals(0), reason: 'Track must repeat at index 0');
      expect(activeMock.seekHistory, contains(Duration.zero));
    });

    test('Auto-crossfade in flight + user toggles shuffle cancels crossfade and restores volume', () async {
      await service.open(testItems, index: 0, play: true);
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 500),
          manualDuration: Duration(milliseconds: 200),
          curve: CrossfadeCurve.linear,
        ),
      );

      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      activeMock.totalDuration = const Duration(seconds: 180);

      // Trigger auto-crossfade
      await activeMock.seek(const Duration(seconds: 179, milliseconds: 800));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.isCrossfading, isTrue, reason: 'Auto-crossfade should be active');

      // User toggles shuffle mid-crossfade
      await service.toggleShuffle();

      // Verification: Crossfade cancelled, standby stopped, active player restored
      expect(service.isCrossfading, isFalse, reason: 'Crossfade must be cancelled on toggleShuffle');
      expect(service.standbyPlayer.isPlaying, isFalse);
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
      expect(service.activePlayer.isPlaying, isTrue);
    });
  });

  group('QueueManager peekNext & hasNextDifferent Tests', () {
    late QueueManager qm;
    final itemA = QueueItem(id: '1', filePath: '/a.mp3', title: 'A', artist: 'A', album: 'A', duration: const Duration(seconds: 100));
    final itemB = QueueItem(id: '2', filePath: '/b.mp3', title: 'B', artist: 'B', album: 'B', duration: const Duration(seconds: 100));
    final itemADup = QueueItem(id: '3', filePath: '/a.mp3', title: 'A Duplicate', artist: 'A', album: 'A', duration: const Duration(seconds: 100));

    setUp(() {
      qm = QueueManager();
    });

    test('Standard queue returns next track and hasNextDifferent is true', () {
      qm.setQueue([itemA, itemB], startIndex: 0);

      expect(qm.hasNextDifferent, isTrue);
      expect(qm.peekNext(distinct: true), equals(itemB));
    });

    test('End of queue in Loop.off returns null and hasNextDifferent is false', () {
      qm.setQueue([itemA, itemB], startIndex: 1);
      qm.setLoopMode(Loop.off);

      expect(qm.hasNextDifferent, isFalse);
      expect(qm.peekNext(distinct: true), isNull);
    });

    test('End of queue in Loop.all returns first track if different', () {
      qm.setQueue([itemA, itemB], startIndex: 1);
      qm.setLoopMode(Loop.all);

      expect(qm.hasNextDifferent, isTrue);
      expect(qm.peekNext(distinct: true), equals(itemA));
    });

    test('Loop.one always returns null for peekNext(distinct: true)', () {
      qm.setQueue([itemA, itemB], startIndex: 0);
      qm.setLoopMode(Loop.one);

      expect(qm.hasNextDifferent, isFalse);
      expect(qm.peekNext(distinct: true), isNull);
      expect(qm.peekNext(distinct: false), equals(itemA));
    });

    test('Single-track queue in Loop.all returns null because next is not distinct', () {
      qm.setQueue([itemA], startIndex: 0);
      qm.setLoopMode(Loop.all);

      expect(qm.hasNextDifferent, isFalse);
      expect(qm.peekNext(distinct: true), isNull);
    });

    test('Adjacent identical tracks return null for peekNext(distinct: true)', () {
      qm.setQueue([itemA, itemADup], startIndex: 0);

      expect(qm.hasNextDifferent, isFalse);
      expect(qm.peekNext(distinct: true), isNull);
    });
  });

  group('Reactive Crossfade & Queue Mutation Tests', () {
    late AudioEngineService service;
    late MockAudioPlayerAdapter playerA;
    late MockAudioPlayerAdapter playerB;
    late QueueManager queueManager;
    late CrossfadeManager crossfadeManager;

    final List<QueueItem> testItems = List.generate(
      6,
      (i) => QueueItem(
        id: '${i + 1}',
        filePath: '/music/track_${i + 1}.mp3',
        title: 'Track ${i + 1}',
        artist: 'Artist ${i + 1}',
        album: 'Album 1',
        duration: const Duration(seconds: 180),
      ),
    );

    setUp(() {
      playerA = MockAudioPlayerAdapter();
      playerB = MockAudioPlayerAdapter();
      queueManager = QueueManager();
      crossfadeManager = CrossfadeManager(
        tickerInterval: const Duration(milliseconds: 10),
      );

      service = AudioEngineService(
        playerA: playerA,
        playerB: playerB,
        queueManager: queueManager,
        crossfadeManager: crossfadeManager,
        tickerInterval: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    Future<void> triggerCrossfade(AudioEngineService svc, MockAudioPlayerAdapter activeMock) async {
      await svc.open(testItems, index: 0, play: true);
      await svc.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 500),
          manualDuration: Duration(milliseconds: 200),
          curve: CrossfadeCurve.linear,
        ),
      );
      activeMock.totalDuration = const Duration(seconds: 180);
      await activeMock.seek(const Duration(seconds: 179, milliseconds: 800));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(svc.isCrossfading, isTrue, reason: 'Crossfade must be active');
    }

    test('Reordering distant tracks mid-crossfade PRESERVES crossfade without interruption', () async {
      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      await triggerCrossfade(service, activeMock);

      // Reorder tracks at index 4 and 5 (distant from active 0 and candidate 1)
      await service.reorder(4, 5);

      // Crossfade remains active because next candidate track did not change
      expect(service.isCrossfading, isTrue, reason: 'Distant reorder must NOT cancel crossfade');
      expect(service.standbyPlayer.isPlaying, isTrue);
    });

    test('Reordering candidate next track mid-crossfade CANCELS crossfade immediately', () async {
      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      await triggerCrossfade(service, activeMock);

      // Move track at index 1 (the one being faded into) to the end (index 5)
      await service.reorder(1, 5);

      // Crossfade must be cancelled because candidate next track changed
      expect(service.isCrossfading, isFalse, reason: 'Moving next track must cancel crossfade');
      expect(service.standbyPlayer.isPlaying, isFalse);
      expect((service.standbyPlayer as MockAudioPlayerAdapter).currentVolume, equals(0.0));
    });

    test('Inserting a track next mid-crossfade CANCELS crossfade', () async {
      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      await triggerCrossfade(service, activeMock);

      final newItem = QueueItem(
        id: 'new_99',
        filePath: '/music/new_99.mp3',
        title: 'New Track',
        artist: 'New Artist',
        album: 'Album 1',
        duration: const Duration(seconds: 180),
      );

      // Insert new item right after current playing track
      await service.insertNext(newItem);

      // Crossfade must be cancelled because candidate next track changed to new item
      expect(service.isCrossfading, isFalse, reason: 'insertNext must cancel crossfade to previous track');
      expect(service.standbyPlayer.isPlaying, isFalse);
    });

    test('Removing distant track mid-crossfade PRESERVES crossfade', () async {
      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      await triggerCrossfade(service, activeMock);

      // Remove distant track at index 4
      await service.remove(4);

      expect(service.isCrossfading, isTrue, reason: 'Removing distant track must NOT cancel crossfade');
      expect(service.standbyPlayer.isPlaying, isTrue);
    });

    test('Removing candidate next track mid-crossfade CANCELS crossfade', () async {
      final activeMock = service.activePlayer as MockAudioPlayerAdapter;
      await triggerCrossfade(service, activeMock);

      // Remove candidate next track at index 1
      await service.remove(1);

      expect(service.isCrossfading, isFalse, reason: 'Removing next track must cancel crossfade');
      expect(service.standbyPlayer.isPlaying, isFalse);
    });
  });
}
