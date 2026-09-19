import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/features/playback/domain/behavior_subject.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MockAudioPlayerAdapter Unit Tests', () {
    late MockAudioPlayerAdapter player;

    setUp(() {
      player = MockAudioPlayerAdapter(id: 'test_player');
    });

    tearDown(() async {
      if (!player.isDisposed) {
        await player.dispose();
      }
    });

    test('initial state conforms to audio defaults', () {
      expect(player.id, equals('test_player'));
      expect(player.position, equals(Duration.zero));
      expect(player.duration, equals(Duration.zero));
      expect(player.isPlaying, isFalse);
      expect(player.isBuffering, isFalse);
      expect(player.isCompleted, isFalse);
      expect(player.volume, equals(100.0));
      expect(player.rate, equals(1.0));
      expect(player.pitch, equals(1.0));
      expect(player.isDisposed, isFalse);
      expect(player.callLog, isEmpty);
      expect(player.properties, isEmpty);
    });

    test('open sets uri, updates position, playing state, and logs call', () async {
      final positions = <Duration>[];
      final playingStates = <bool>[];
      final subPos = player.positionStream.listen(positions.add);
      final subPlay = player.playingStream.listen(playingStates.add);

      await player.open('file:///music/song.mp3', play: true, startPosition: const Duration(seconds: 10));

      expect(player.position, equals(const Duration(seconds: 10)));
      expect(player.isPlaying, isTrue);
      expect(player.isCompleted, isFalse);
      expect(player.callLog, contains('test_player.open(file:///music/song.mp3, play: true, start: 0:00:10.000000)'));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(positions, contains(const Duration(seconds: 10)));
      expect(playingStates, contains(true));

      await subPos.cancel();
      await subPlay.cancel();
    });

    test('play, pause, and stop update state and emit to broadcast streams', () async {
      final playingHistory = <bool>[];
      final subPlay = player.playingStream.listen(playingHistory.add);

      await player.play();
      expect(player.isPlaying, isTrue);
      expect(player.isCompleted, isFalse);

      await player.pause();
      expect(player.isPlaying, isFalse);

      player.simulatePosition(const Duration(seconds: 45));
      expect(player.position, equals(const Duration(seconds: 45)));

      await player.stop();
      expect(player.isPlaying, isFalse);
      expect(player.position, equals(Duration.zero));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playingHistory, containsAllInOrder([true, false, false]));
      expect(player.callLog, containsAllInOrder([
        'test_player.play()',
        'test_player.pause()',
        'test_player.stop()',
      ]));

      await subPlay.cancel();
    });

    test('seek updates position and logs call', () async {
      final positions = <Duration>[];
      final sub = player.positionStream.listen(positions.add);

      await player.seek(const Duration(seconds: 120));
      expect(player.position, equals(const Duration(seconds: 120)));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(positions, contains(const Duration(seconds: 120)));
      expect(player.callLog, contains('test_player.seek(0:02:00.000000)'));

      await sub.cancel();
    });

    test('setVolume, setRate, setPitch, and setProperty modify state and logs', () async {
      await player.setVolume(150.0);
      expect(player.volume, equals(150.0));

      await player.setRate(1.25);
      expect(player.rate, equals(1.25));

      await player.setPitch(0.9);
      expect(player.pitch, equals(0.9));

      await player.setProperty('replaygain', 'track');
      expect(player.properties['replaygain'], equals('track'));

      expect(player.callLog, containsAllInOrder([
        'test_player.setVolume(150.0)',
        'test_player.setRate(1.25)',
        'test_player.setPitch(0.9)',
        'test_player.setProperty(replaygain, track)',
      ]));
    });

    test('simulation helpers dispatch accurately to streams and state', () async {
      Duration? receivedDuration;
      bool? receivedBuffering;
      bool? receivedCompleted;
      double? receivedBitrate;
      bool? receivedPlaying;

      final subDur = player.durationStream.listen((d) => receivedDuration = d);
      final subBuf = player.bufferingStream.listen((b) => receivedBuffering = b);
      final subComp = player.completedStream.listen((c) => receivedCompleted = c);
      final subBit = player.bitrateStream.listen((b) => receivedBitrate = b);
      final subPlay = player.playingStream.listen((p) => receivedPlaying = p);

      player.simulateDuration(const Duration(minutes: 4));
      player.simulateBuffering(true);
      player.simulateBitrate(1411.0);
      player.simulatePlaying(true);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedDuration, equals(const Duration(minutes: 4)));
      expect(receivedBuffering, isTrue);
      expect(receivedBitrate, equals(1411.0));
      expect(receivedPlaying, isTrue);

      player.simulateCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(player.isCompleted, isTrue);
      expect(player.isPlaying, isFalse);
      expect(receivedCompleted, isTrue);

      await subDur.cancel();
      await subBuf.cancel();
      await subComp.cancel();
      await subBit.cancel();
      await subPlay.cancel();
    });

    test('dispose closes all streams and sets isDisposed', () async {
      await player.dispose();
      expect(player.isDisposed, isTrue);
      expect(player.callLog, contains('test_player.dispose()'));
    });
  });

  group('BehaviorSubject Unit Tests', () {
    test('initializes with initial value and provides synchronous getter', () {
      final subject = BehaviorSubject<int>(42);
      expect(subject.value, equals(42));
      expect(subject.isClosed, isFalse);
    });

    test('delivers cached value immediately to new listeners upon subscription (Replay-1)', () async {
      final subject = BehaviorSubject<String>('initial_state');
      subject.add('updated_state');

      final deliveredEvents = <String>[];
      final subscription = subject.listen(deliveredEvents.add);

      // Yield microtasks to allow scheduled initial delivery
      await Future<void>.delayed(Duration.zero);

      expect(deliveredEvents, equals(['updated_state']));
      await subscription.cancel();
      await subject.close();
    });

    test('emits successive values to multiple active broadcast listeners', () async {
      final subject = BehaviorSubject<int>(1);
      final listener1Events = <int>[];
      final listener2Events = <int>[];

      final sub1 = subject.listen(listener1Events.add);
      final sub2 = subject.listen(listener2Events.add);

      await Future<void>.delayed(Duration.zero);

      subject.add(2);
      subject.add(3);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(listener1Events, equals([1, 2, 3]));
      expect(listener2Events, equals([1, 2, 3]));

      await sub1.cancel();
      await sub2.cancel();
      await subject.close();
    });

    test('close marks subject closed and ignores further additions', () async {
      final subject = BehaviorSubject<int>(10);
      await subject.close();

      expect(subject.isClosed, isTrue);
      subject.add(20); // Should be ignored gracefully without error
      expect(subject.value, equals(10));
    });
  });
}
