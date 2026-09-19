import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_session_manager.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSessionManager Unit Tests', () {
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

    test('initial state has inactive session and no pending interruption resume', () {
      expect(sessionManager.isSessionActive, isFalse);
      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
    });

    test('activates and deactivates session properly', () async {
      await sessionManager.activateSession();
      expect(sessionManager.isSessionActive, isTrue);

      await sessionManager.deactivateSession();
      expect(sessionManager.isSessionActive, isFalse);
    });

    test('interruption begin auto-pauses when playing and sets resume flag', () async {
      delegate.isPlaying = true;

      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);

      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);
      expect(delegate.isPlaying, isFalse);
      expect(delegate.callLog, contains('delegate.pause()'));
    });

    test('interruption begin when already paused does not set resume flag', () async {
      delegate.isPlaying = false;

      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);

      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.callLog, isEmpty);
    });

    test('interruption end auto-resumes if playing prior to interruption', () async {
      delegate.isPlaying = true;

      // Call begins
      interruptionController.add(const AudioInterruptionEvent(begin: true));
      await Future<void>.delayed(Duration.zero);
      expect(sessionManager.wasPlayingBeforeInterruption, isTrue);

      // Call ends
      interruptionController.add(const AudioInterruptionEvent(begin: false));
      await Future<void>.delayed(Duration.zero);

      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.isPlaying, isTrue);
      expect(delegate.callLog, containsAllInOrder(['delegate.pause()', 'delegate.play()']));
    });

    test('interruption end does nothing if was not playing prior', () async {
      delegate.isPlaying = false;

      interruptionController.add(const AudioInterruptionEvent(begin: false));
      await Future<void>.delayed(Duration.zero);

      expect(sessionManager.wasPlayingBeforeInterruption, isFalse);
      expect(delegate.callLog, isEmpty);
    });

    test('becoming noisy immediately pauses if playing', () async {
      delegate.isPlaying = true;

      becomingNoisyController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(delegate.isPlaying, isFalse);
      expect(delegate.callLog, contains('delegate.pause()'));
    });

    test('becoming noisy does nothing if already paused', () async {
      delegate.isPlaying = false;

      becomingNoisyController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(delegate.callLog, isEmpty);
    });
  });
}
