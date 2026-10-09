import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, CrossfeedMode, Equalizer, ReplayGainConfig, VisualizerData;
import 'package:tachyon/core/backend/services/audio_player_adapter.dart';
import 'package:tachyon/core/backend/services/crossfade_manager.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart' show CrossfadeCurve;

class MockAudioPlayerAdapter implements AudioPlayerAdapter {
  double currentVolume = 100.0;
  bool isPlayingState = false;
  bool isStopped = false;
  bool isPaused = false;
  bool isCompletedFlag = false;
  double currentRate = 1.0;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = const Duration(minutes: 3);

  final List<Duration> seekHistory = [];
  final List<double> volumeHistory = [];
  int openCount = 0;

  final StreamController<Duration> _posController = StreamController.broadcast();
  final StreamController<Duration> _durController = StreamController.broadcast();
  final StreamController<bool> _playingController = StreamController.broadcast();
  final StreamController<bool> _bufferingController = StreamController.broadcast();
  final StreamController<bool> _completedController = StreamController.broadcast();

  @override
  Future<void> open(String filePath, {bool play = true}) async {
    openCount++;
    isPlayingState = play;
    isStopped = false;
    isPaused = false;
    _playingController.add(play);
  }

  @override
  Future<void> play() async {
    isPlayingState = true;
    isStopped = false;
    isPaused = false;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    isPlayingState = false;
    isPaused = true;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    isPlayingState = false;
    isStopped = true;
    _playingController.add(false);
  }

  void emitCompleted([bool completed = true]) {
    _completedController.add(completed);
  }

  @override
  Future<void> seek(Duration position) async {
    currentPosition = position;
    seekHistory.add(position);
    _posController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    currentVolume = volume;
    volumeHistory.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    currentRate = rate;
  }

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setEqualizer(Equalizer equalizer) async {}

  @override
  Future<bool> setDevice(AudioDevice device) async => true;

  @override
  Future<List<AudioDevice>> getAudioDevices() async => [];

  @override
  List<AudioDevice> getAudioDevicesSync() => [];

  @override
  Stream<List<AudioDevice>> get devicesStream => const Stream.empty();

  ReplayGainConfig currentReplayGain = const ReplayGainConfig();
  double currentPreamp = 0.0;
  double currentBalance = 0.0;
  bool currentMono = false;
  CrossfeedMode currentCrossfeed = CrossfeedMode.off;
  double currentSpatializerWidth = 1.0;
  bool currentLimiterEnabled = true;

  @override
  Future<void> setReplayGain({
    double? gainDb,
    double? peak,
    double? preampDb,
    bool? preventClipping,
  }) async {
    currentReplayGain = ReplayGainConfig(
      enabled: true,
      gainDb: gainDb ?? 0.0,
      peak: peak ?? 0.0,
      preampDb: preampDb ?? 0.0,
      preventClipping: preventClipping ?? true,
    );
  }

  @override
  Future<void> clearReplayGain() async {
    currentReplayGain = const ReplayGainConfig();
  }

  @override
  Future<void> setPreamp(double preampDb) async {
    currentPreamp = preampDb;
  }

  @override
  Future<void> setBalance(double balance) async {
    currentBalance = balance;
  }

  @override
  Future<void> setMono(bool enabled) async {
    currentMono = enabled;
  }

  @override
  Future<void> setCrossfeed(CrossfeedMode mode) async {
    currentCrossfeed = mode;
  }

  @override
  Future<void> setSpatializer(double width) async {
    currentSpatializerWidth = width;
  }

  @override
  Future<void> setLimiter(bool enabled) async {
    currentLimiterEnabled = enabled;
  }

  @override
  ReplayGainConfig get replayGain => currentReplayGain;

  @override
  double get preampDb => currentPreamp;

  @override
  double get balance => currentBalance;

  @override
  bool get mono => currentMono;

  @override
  CrossfeedMode get crossfeed => currentCrossfeed;

  @override
  double get spatializerWidth => currentSpatializerWidth;

  @override
  bool get limiterEnabled => currentLimiterEnabled;

  @override
  Future<void> setSkipSilence(bool enabled) async {}

  @override
  Future<void> dispose() async {
    await _posController.close();
    await _durController.close();
    await _playingController.close();
    await _bufferingController.close();
    await _completedController.close();
  }

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => totalDuration;

  @override
  bool get isPlaying => isPlayingState;

  @override
  bool get isBuffering => false;

  @override
  bool get isCompleted => isCompletedFlag || isStopped;

  @override
  double get volume => currentVolume;

  @override
  double get rate => currentRate;

  @override
  double get pitch => 1.0;

  @override
  Equalizer get equalizer => Equalizer.flat;

  @override
  AudioDevice get audioDevice => const AudioDevice(id: 'default', name: 'Default');

  @override
  bool get skipSilence => false;

  @override
  int get audioBitrate => 0;

  @override
  Stream<int> get audioBitrateStream => const Stream.empty();

  @override
  bool get isDisposed => false;

  @override
  Stream<Duration> get positionStream => _posController.stream;

  @override
  Stream<Duration> get durationStream => _durController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<double> get volumeStream => Stream.value(currentVolume);

  @override
  Stream<double> get rateStream => Stream.value(1.0);

  @override
  Stream<double> get pitchStream => Stream.value(1.0);

  @override
  Stream<Equalizer> get equalizerStream => Stream.value(Equalizer.flat);

  @override
  Stream<AudioDevice> get audioDeviceStream => Stream.value(audioDevice);

  @override
  Stream<bool> get skipSilenceStream => Stream.value(false);

  @override
  Stream<VisualizerData> get visualizerStream => const Stream.empty();

  @override
  VisualizerData get visualizer => VisualizerData.empty();

  @override
  void setVisualizerEnabled(bool enabled) {}
}

void main() {
  group('CrossfadeManager Unit Tests', () {
    late CrossfadeManager manager;
    late MockAudioPlayerAdapter playerOut;
    late MockAudioPlayerAdapter playerIn;

    setUp(() {
      manager = CrossfadeManager(
        tickerInterval: const Duration(milliseconds: 10),
      );
      playerOut = MockAudioPlayerAdapter()..isPlayingState = true;
      playerIn = MockAudioPlayerAdapter();
    });

    tearDown(() {
      manager.dispose();
    });

    test('Direct cut executes immediately for duration <= 100ms', () async {
      bool endCalled = false;

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 50),
        curve: CrossfadeCurve.linear,
        masterVolume: 80.0,
        onCrossEnd: () => endCalled = true,
      );

      expect(manager.isActive, isFalse);
      expect(playerOut.currentVolume, equals(0.0));
      expect(playerOut.isStopped, isTrue);
      expect(playerIn.currentVolume, equals(80.0));
      expect(playerIn.seekHistory, contains(Duration.zero));
      expect(playerIn.isPlaying, isTrue);
      expect(endCalled, isTrue);
    });

    test('Crossfade initializes volumes and seeks playerIn to 0:00', () async {
      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 200),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
      );

      expect(manager.isActive, isTrue);
      expect(playerIn.seekHistory, contains(Duration.zero));
      expect(playerIn.isPlaying, isTrue);

      // Initial linear volumes: out = 100, in = 0
      expect(playerOut.currentVolume, closeTo(100.0, 0.01));
      expect(playerIn.currentVolume, closeTo(0.0, 0.01));
    });

    test('Equal-Power curve preserves energy at midpoint', () async {
      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 300),
        curve: CrossfadeCurve.equalPower,
        masterVolume: 100.0,
      );

      // Wait 150ms for midpoint tick
      await Future.delayed(const Duration(milliseconds: 150));

      expect(manager.isActive, isTrue);
      // At roughly halfway (pi/4), volume is ~70.71%
      expect(playerOut.currentVolume, lessThan(100.0));
      expect(playerOut.currentVolume, greaterThan(40.0));
      expect(playerIn.currentVolume, greaterThan(40.0));
      expect(playerIn.currentVolume, lessThan(100.0));
    });

    test('Cancel is synchronous, stops ticker and leaves players unmanaged', () async {
      bool endCalled = false;

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 500),
        curve: CrossfadeCurve.linear,
        masterVolume: 90.0,
        onCrossEnd: () => endCalled = true,
      );

      expect(manager.isActive, isTrue);

      // Cancel mid-flight
      manager.cancel();

      expect(manager.isActive, isFalse);
      expect(endCalled, isFalse, reason: 'onCrossEnd must not fire on cancel');

      // Verify no subsequent ticks touch players
      final outHistoryLen = playerOut.volumeHistory.length;
      final inHistoryLen = playerIn.volumeHistory.length;

      await Future.delayed(const Duration(milliseconds: 50));
      expect(playerOut.volumeHistory.length, equals(outHistoryLen));
      expect(playerIn.volumeHistory.length, equals(inHistoryLen));
    });

    test('Dynamic master volume update scales volume during crossfade', () async {
      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 300),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
      );

      // User changes volume to 40% mid-fade
      manager.setMasterVolume(40.0);

      // Allow tick
      await Future.delayed(const Duration(milliseconds: 30));

      expect(playerOut.currentVolume, lessThanOrEqualTo(40.0));
      expect(playerIn.currentVolume, lessThanOrEqualTo(40.0));
    });

    test('Crossfade natural completion invokes onCrossEnd and shuts playerOut', () async {
      bool endCalled = false;

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 150),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
        onCrossEnd: () => endCalled = true,
      );

      // Wait for complete duration plus tick margin
      await Future.delayed(const Duration(milliseconds: 250));

      expect(manager.isActive, isFalse);
      expect(playerOut.currentVolume, equals(0.0));
      expect(playerOut.isStopped, isTrue);
      expect(playerIn.currentVolume, equals(100.0));
      expect(endCalled, isTrue);
    });

    test('Pause and resume freezes and restores ticker and players', () async {
      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 300),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
      );

      await manager.pause();
      expect(manager.isPaused, isTrue);
      expect(playerOut.isPaused, isTrue);
      expect(playerIn.isPaused, isTrue);

      final outVol = playerOut.currentVolume;
      await Future.delayed(const Duration(milliseconds: 50));
      expect(playerOut.currentVolume, equals(outVol), reason: 'Volumes frozen while paused');

      await manager.resume();
      expect(manager.isPaused, isFalse);
      expect(playerOut.isPlaying, isTrue);
      expect(playerIn.isPlaying, isTrue);
    });

    test('Crossfade with playbackRate = 2.0 advances at double rate and finishes early', () async {
      bool endCalled = false;

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 200),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
        playbackRate: 2.0,
        onCrossEnd: () => endCalled = true,
      );

      expect(manager.isActive, isTrue);
      expect(manager.playbackRate, equals(2.0));

      // With 2x speed, 200ms target finishes in ~100ms wall-clock time.
      // Wait 135ms (enough for 200ms media at 2x rate plus tick margin, but far less than 200ms)
      await Future.delayed(const Duration(milliseconds: 135));

      expect(manager.isActive, isFalse);
      expect(endCalled, isTrue);
      expect(playerOut.currentVolume, equals(0.0));
      expect(playerIn.currentVolume, equals(100.0));
    });

    test('Dynamic setPlaybackRate updates active crossfade rate', () async {
      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(milliseconds: 500),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
        playbackRate: 1.0,
      );

      expect(manager.playbackRate, equals(1.0));

      manager.setPlaybackRate(2.0);
      expect(manager.playbackRate, equals(2.0));

      manager.cancel();
    });

    test('Crossfade completes immediately when playerOut reaches EOF / isCompleted', () async {
      bool endCalled = false;

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(seconds: 5),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
        onCrossEnd: () => endCalled = true,
      );

      expect(manager.isActive, isTrue);
      expect(endCalled, isFalse);

      // Trigger EOF on outgoing player
      playerOut.isCompletedFlag = true;

      // Wait 1-2 ticks
      await Future.delayed(const Duration(milliseconds: 60));

      expect(manager.isActive, isFalse);
      expect(endCalled, isTrue);
      expect(playerOut.currentVolume, equals(0.0));
      expect(playerIn.currentVolume, equals(100.0));
    });

    test('Position advances track media progress faster than wall-clock time', () async {
      playerOut.currentPosition = const Duration(seconds: 10);

      await manager.cross(
        playerOut: playerOut,
        playerIn: playerIn,
        targetDuration: const Duration(seconds: 1),
        curve: CrossfadeCurve.linear,
        masterVolume: 100.0,
      );

      // Player position jumped 500ms forward
      playerOut.currentPosition = const Duration(seconds: 10, milliseconds: 500);

      expect(manager.progress, greaterThanOrEqualTo(0.5));
      manager.cancel();
    });
  });
}
