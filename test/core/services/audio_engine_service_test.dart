import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

/// Testable fake adapter mimicking native audio player events without I/O
class FakeAudioPlayerAdapter implements AudioPlayerAdapter {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _rateController = StreamController<double>.broadcast();
  final _pitchController = StreamController<double>.broadcast();
  final _skipSilenceController = StreamController<bool>.broadcast();
  final _equalizerController = StreamController<Equalizer>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  final bool _isBuffering = false;
  bool _isCompleted = false;
  double _volume = 1.0;
  double _rate = 1.0;
  double _pitch = 1.0;
  Equalizer _equalizer = Equalizer.flat;
  bool _skipSilence = false;
  bool _isDisposed = false;

  String? lastOpenedFilePath;
  String? get lastOpenedUri => lastOpenedFilePath;
  set lastOpenedUri(String? val) => lastOpenedFilePath = val;
  int openCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int seekCount = 0;
  Duration? lastSeekPosition;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isBuffering => _isBuffering;

  @override
  bool get isCompleted => _isCompleted;

  @override
  double get volume => _volume;

  @override
  double get rate => _rate;

  @override
  double get pitch => _pitch;

  @override
  bool get skipSilence => _skipSilence;

  @override
  bool get isDisposed => _isDisposed;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<double> get rateStream => _rateController.stream;

  @override
  Stream<double> get pitchStream => _pitchController.stream;

  @override
  Stream<bool> get skipSilenceStream => _skipSilenceController.stream;

  @override
  Equalizer get equalizer => _equalizer;

  @override
  Stream<Equalizer> get equalizerStream => _equalizerController.stream;

  @override
  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    _equalizerController.add(equalizer);
  }

  @override
  Future<void> open(
    String filePath, {
    bool play = true,
  }) async {
    lastOpenedFilePath = filePath;
    lastOpenedUri = filePath;
    openCount++;
    _isPlaying = play;
    _playingController.add(play);
  }

  @override
  Future<void> play() async {
    playCount++;
    _isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    lastSeekPosition = position;
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    _volumeController.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    _rateController.add(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    _pitchController.add(pitch);
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    _skipSilenceController.add(enabled);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _bufferingController.close();
    await _completedController.close();
    await _volumeController.close();
    await _rateController.close();
    await _pitchController.close();
    await _skipSilenceController.close();
  }

  // Simulation helpers
  void emitPosition(Duration pos) {
    _position = pos;
    _positionController.add(pos);
  }

  void emitDuration(Duration dur) {
    _duration = dur;
    _durationController.add(dur);
  }

  void emitCompleted() {
    _isCompleted = true;
    _completedController.add(true);
  }
}

void main() {
  group('AudioEngineService Unit Tests', () {
    late FakeAudioPlayerAdapter playerA;
    late FakeAudioPlayerAdapter playerB;
    late QueueManager queueManager;
    late AudioEngineService service;

    final testTracks = [
      const QueueItem(
        id: 'track_1',
        uri: '/music/song1.mp3',
        title: 'Song One',
        artist: 'Artist A',
        album: 'Album X',
        duration: Duration(seconds: 180),
      ),
      const QueueItem(
        id: 'track_2',
        uri: '/music/song2.mp3',
        title: 'Song Two',
        artist: 'Artist B',
        album: 'Album Y',
        duration: Duration(seconds: 200),
      ),
      const QueueItem(
        id: 'track_3',
        uri: '/music/song3.mp3',
        title: 'Song Three',
        artist: 'Artist C',
        album: 'Album Z',
        duration: Duration(seconds: 120),
      ),
    ];

    setUp(() {
      playerA = FakeAudioPlayerAdapter();
      playerB = FakeAudioPlayerAdapter();
      queueManager = QueueManager();
      service = AudioEngineService(
        playerA: playerA,
        playerB: playerB,
        queueManager: queueManager,
        tickerInterval: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('Initial state assigns Player A as active and Player B as standby', () {
      expect(identical(service.activePlayer, playerA), isTrue);
      expect(identical(service.standbyPlayer, playerB), isTrue);
      expect(service.isCrossfading, isFalse);
      expect(service.isPlaying, isFalse);
    });

    test('open() initializes active player with master volume, rate, and pitch', () async {
      await service.setVolume(80.0);
      await service.setRate(1.25);
      await service.setPitch(1.1);

      await service.open(testTracks, index: 0, play: true);

      expect(playerA.lastOpenedUri, equals('/music/song1.mp3'));
      expect(playerA.isPlaying, isTrue);
      expect(playerA.volume, equals(80.0));
      expect(playerA.rate, equals(1.25));
      expect(playerA.pitch, equals(1.1));
      expect(service.currentState.playables.length, equals(3));
      expect(service.currentState.index, equals(0));
    });

    test('Equal-Power crossfade curve formula calculates cosine / sine values accurately', () {
      const config = CrossfadeConfig(
        curve: CrossfadeCurve.equalPower,
        duration: Duration(seconds: 5),
      );
      const masterVol = 100.0;

      // At start (progress 0.0): V_out = 100%, V_in = 0%
      expect(config.calculateFadeOutVolume(0.0, masterVol), closeTo(100.0, 0.001));
      expect(config.calculateFadeInVolume(0.0, masterVol), closeTo(0.0, 0.001));

      // At midpoint (progress 0.5): cos(pi/4) = sin(pi/4) = ~0.7071
      final expectedMid = masterVol * math.sqrt(0.5);
      expect(config.calculateFadeOutVolume(0.5, masterVol), closeTo(expectedMid, 0.001));
      expect(config.calculateFadeInVolume(0.5, masterVol), closeTo(expectedMid, 0.001));

      // Constant power sum of squares: V_out^2 + V_in^2 == masterVol^2
      final vOut = config.calculateFadeOutVolume(0.5, masterVol);
      final vIn = config.calculateFadeInVolume(0.5, masterVol);
      expect(vOut * vOut + vIn * vIn, closeTo(masterVol * masterVol, 0.01));

      // At end (progress 1.0): V_out = 0%, V_in = 100%
      expect(config.calculateFadeOutVolume(1.0, masterVol), closeTo(0.0, 0.001));
      expect(config.calculateFadeInVolume(1.0, masterVol), closeTo(100.0, 0.001));
    });

    test('Linear crossfade curve formula calculates linear progression accurately', () {
      const config = CrossfadeConfig(
        curve: CrossfadeCurve.linear,
        duration: Duration(seconds: 4),
      );
      const masterVol = 80.0;

      // At start (progress 0.0): V_out = 80, V_in = 0
      expect(config.calculateFadeOutVolume(0.0, masterVol), closeTo(80.0, 0.001));
      expect(config.calculateFadeInVolume(0.0, masterVol), closeTo(0.0, 0.001));

      // At midpoint (progress 0.5): V_out = 40, V_in = 40
      expect(config.calculateFadeOutVolume(0.5, masterVol), closeTo(40.0, 0.001));
      expect(config.calculateFadeInVolume(0.5, masterVol), closeTo(40.0, 0.001));

      // Linear sum: V_out + V_in == masterVol
      final vOut = config.calculateFadeOutVolume(0.5, masterVol);
      final vIn = config.calculateFadeInVolume(0.5, masterVol);
      expect(vOut + vIn, closeTo(masterVol, 0.001));

      // At end (progress 1.0): V_out = 0, V_in = 80
      expect(config.calculateFadeOutVolume(1.0, masterVol), closeTo(0.0, 0.001));
      expect(config.calculateFadeInVolume(1.0, masterVol), closeTo(80.0, 0.001));
    });

    test('Crossfade duration symmetric clamping respects shorter tracks', () {
      const config = CrossfadeConfig(
        duration: Duration(seconds: 10),
      );
      // Track length 6 seconds: half track is 3 seconds -> effective duration is clamped to 3s
      final effective = config.effectiveDuration(const Duration(seconds: 6));
      expect(effective, equals(const Duration(seconds: 3)));

      // Track length 60 seconds: 10s is less than half track (30s) -> effective duration is 10s
      final effectiveLong = config.effectiveDuration(const Duration(seconds: 60));
      expect(effectiveLong, equals(const Duration(seconds: 10)));
    });

    test('Crossfade triggers when remaining duration <= effective crossfade duration', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
          curve: CrossfadeCurve.linear,
        ),
      );

      await service.open(testTracks, index: 0, play: true);
      playerA.emitDuration(const Duration(seconds: 180));
      await pumpEventQueue();

      // Position before crossfade window: 170s (remaining 10s > 5s crossfade)
      playerA.emitPosition(const Duration(seconds: 170));
      await pumpEventQueue();
      expect(service.isCrossfading, isFalse);
      expect(playerB.openCount, equals(0));

      // Position enters crossfade window: 176s (remaining 4s <= 5s crossfade)
      playerA.emitPosition(const Duration(seconds: 176));
      await pumpEventQueue();

      expect(service.isCrossfading, isTrue);
      // Standby player opens next track at volume 0.0
      expect(playerB.lastOpenedUri, equals('/music/song2.mp3'));
      expect(playerB.volume, equals(0.0));
      expect(playerB.isPlaying, isTrue);
    });

    test('Completed crossfade swaps player roles and terminates outgoing player', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(milliseconds: 30),
          curve: CrossfadeCurve.linear,
        ),
      );
      await service.setVolume(90.0);
      await service.open(testTracks, index: 0, play: true);
      playerA.emitDuration(const Duration(seconds: 180));
      await pumpEventQueue();

      // Trigger crossfade
      playerA.emitPosition(const Duration(milliseconds: 179980));
      await pumpEventQueue();
      expect(service.isCrossfading, isTrue);
      expect(identical(service.activePlayer, playerA), isTrue);

      // Wait for ticker to complete the 30ms crossfade
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // After crossfade completes:
      // 1. Roles swap: Player B is now active, Player A is standby
      expect(identical(service.activePlayer, playerB), isTrue);
      expect(identical(service.standbyPlayer, playerA), isTrue);
      expect(service.isCrossfading, isFalse);

      // 2. Player A stopped, Player B receives full master volume
      expect(playerA.stopCount, greaterThanOrEqualTo(1));
      expect(playerB.volume, equals(90.0));

      // 3. Queue advanced to track 1
      expect(queueManager.currentIndex, equals(1));
      expect(queueManager.currentTrack?.title, equals('Song Two'));
    });

    test('Seeking during active crossfade aborts crossfade and restores master volume', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ),
      );
      await service.setVolume(100.0);
      await service.open(testTracks, index: 0, play: true);
      playerA.emitDuration(const Duration(seconds: 180));
      await pumpEventQueue();

      // Trigger crossfade
      playerA.emitPosition(const Duration(seconds: 177));
      await pumpEventQueue();
      expect(service.isCrossfading, isTrue);

      // User seeks backward away from crossfade boundary
      await service.seek(const Duration(seconds: 30));
      await pumpEventQueue();

      expect(service.isCrossfading, isFalse);
      expect(playerA.volume, equals(100.0));
      expect(playerB.stopCount, greaterThanOrEqualTo(1));
      expect(playerA.lastSeekPosition, equals(const Duration(seconds: 30)));
    });

    test('next() during active crossfade fast-forwards immediately', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ),
      );
      await service.open(testTracks, index: 0, play: true);
      playerA.emitDuration(const Duration(seconds: 180));
      await pumpEventQueue();

      // Trigger crossfade
      playerA.emitPosition(const Duration(seconds: 178));
      await pumpEventQueue();
      expect(service.isCrossfading, isTrue);

      // User presses Next during fade
      await service.next();
      await pumpEventQueue();

      expect(service.isCrossfading, isFalse);
      expect(identical(service.activePlayer, playerB), isTrue);
      expect(queueManager.currentIndex, equals(1));
      expect(playerA.stopCount, greaterThanOrEqualTo(1));
    });

    test('Loop.one does not trigger crossfade to next track', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ),
      );
      await service.setLoopMode(Loop.one);
      await service.open(testTracks, index: 0, play: true);
      playerA.emitDuration(const Duration(seconds: 180));
      await pumpEventQueue();

      // Position in crossfade window
      playerA.emitPosition(const Duration(seconds: 178));
      await pumpEventQueue();

      // Must not trigger crossfade because Loop.one repeats current track
      expect(service.isCrossfading, isFalse);
      expect(playerB.openCount, equals(0));
    });

    test('End of queue with Loop.off does not trigger crossfade', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ),
      );
      await service.setLoopMode(Loop.off);
      // Open on the last track
      await service.open(testTracks, index: 2, play: true);
      playerA.emitDuration(const Duration(seconds: 120));
      await pumpEventQueue();

      playerA.emitPosition(const Duration(seconds: 118));
      await pumpEventQueue();

      // Last track with Loop.off: no next track -> no crossfade
      expect(service.isCrossfading, isFalse);
      expect(playerB.openCount, equals(0));
    });

    test('End of queue with Loop.all wraps around and crossfades to first track', () async {
      await service.setCrossfadeConfig(
        const CrossfadeConfig(
          enabled: true,
          duration: Duration(seconds: 5),
        ),
      );
      await service.setLoopMode(Loop.all);
      // Open on the last track
      await service.open(testTracks, index: 2, play: true);
      playerA.emitDuration(const Duration(seconds: 120));
      await pumpEventQueue();

      playerA.emitPosition(const Duration(seconds: 118));
      await pumpEventQueue();

      // Loop.all wraps around: should preload track 0
      expect(service.isCrossfading, isTrue);
      expect(playerB.lastOpenedUri, equals('/music/song1.mp3'));
    });
  });
}
