import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/linux_mpris_bridge.dart';
import 'package:tachyon/core/playback/system_media_service.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';

class FakePlaybackController extends PlaybackController {
  FakePlaybackController({
    required super.settingsRepository,
  });

  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeekPosition;
  LoopMode? lastSetLoop;
  bool? lastShuffle;
  void Function(bool)? onSetMinimized;

  PlaybackState _fakeState = const PlaybackState.initial();
  final ValueNotifier<Duration> _fakePositionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  @override
  PlaybackState get state => _fakeState;

  @override
  Track? get currentTrack => _fakeState.currentTrack;

  @override
  bool get isPlaying => _fakeState.playing;

  @override
  Duration get position => _fakeState.position;

  @override
  Duration get duration => _fakeState.duration;

  @override
  ValueNotifier<Duration> get positionNotifier => _fakePositionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _fakePositionNotifier;

  @override
  bool get isShuffled => _fakeState.shuffle;

  @override
  LoopMode get loopMode => _fakeState.loop;

  @override
  double get rate => _fakeState.rate;

  @override
  double get volume => _fakeState.volume;

  void emitPlaybackState(PlaybackState state) {
    _fakeState = state;
    _fakePositionNotifier.value = state.position;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCount++;
    emitPlaybackState(_fakeState.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPlaybackState(_fakeState.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    pauseCount++;
    emitPlaybackState(_fakeState.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
    emitPlaybackState(_fakeState.copyWith(position: position));
  }

  @override
  Future<void> setLoopMode(LoopMode loop) async {
    lastSetLoop = loop;
    emitPlaybackState(_fakeState.copyWith(loop: loop));
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    lastShuffle = shuffle;
    emitPlaybackState(_fakeState.copyWith(shuffle: shuffle));
  }

  @override
  void setMinimized(bool minimized) {
    super.setMinimized(minimized);
    onSetMinimized?.call(minimized);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TachyonAudioHandler & System Media Service Unit Tests', () {
    late SettingsRepository settingsRepo;
    late FakePlaybackController controller;
    late TachyonAudioHandler handler;
    late Directory tempCacheDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      tempCacheDir = await Directory.systemTemp.createTemp('tachyon_cover_test');
      MetadataUtils.init(tempCacheDir.path, tempCacheDir.path);

      controller = FakePlaybackController(
        settingsRepository: settingsRepo,
      );

      handler = TachyonAudioHandler(
        playbackController: controller,
      );
    });

    tearDown(() async {
      handler.dispose();
      controller.dispose();
      try {
        if (tempCacheDir.existsSync()) {
          tempCacheDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Initial mediaItem is null and playbackState is idle', () {
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        equals(as_lib.AudioProcessingState.idle),
      );
    });

    test('Syncs mediaItem and playbackState when current track is updated', () async {
      const artist = Artist(id: 1, name: 'Tachyon Artist');
      const track = Track(
        id: 10,
        filePath: '/music/song.mp3',
        title: 'Song Title',
        durationMs: 240000,
        fileSize: 5000000,
        modifiedAt: 123456789,
        artists: [artist],
      );

      controller.emitPlaybackState(
        PlaybackState(
          index: 0,
          playables: [
            track.toEngineItem(),
          ],
          playing: true,
          position: const Duration(seconds: 42),
          duration: const Duration(milliseconds: 240000),
          loop: LoopMode.all,
          shuffle: true,
        ),
      );

      // Wait a microtask for controller listener to execute
      await Future<void>.delayed(Duration.zero);

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.id, equals('/music/song.mp3'));
      expect(item.title, equals('Song Title'));
      expect(item.artist, equals('Tachyon Artist'));
      expect(item.duration, equals(const Duration(milliseconds: 240000)));

      final pbState = handler.playbackState.value;
      expect(pbState.playing, isTrue);
      expect(pbState.processingState, equals(as_lib.AudioProcessingState.ready));
      expect(pbState.updatePosition, equals(const Duration(seconds: 42)));
      expect(pbState.repeatMode, equals(as_lib.AudioServiceRepeatMode.all));
      expect(pbState.shuffleMode, equals(as_lib.AudioServiceShuffleMode.all));
    });

    test('Handler play, pause, seek, and loop calls delegate to controller', () async {
      await handler.play();
      expect(controller.playCount, equals(1));

      await handler.pause();
      expect(controller.pauseCount, equals(1));

      await handler.seek(const Duration(seconds: 90));
      expect(controller.lastSeekPosition, equals(const Duration(seconds: 90)));

      await handler.setRepeatMode(as_lib.AudioServiceRepeatMode.one);
      expect(controller.lastSetLoop, equals(LoopMode.one));
    });

    test('onTaskRemoved stops playback only when not playing', () async {
      // 1. When not playing: onTaskRemoved should call stop
      controller.emitPlaybackState(const PlaybackState(playing: false));
      await Future<void>.delayed(Duration.zero);

      await handler.onTaskRemoved();
      expect(
        handler.playbackState.value.processingState,
        equals(as_lib.AudioProcessingState.idle),
      );

      // 2. When playing: onTaskRemoved preserves playing state for headless mode
      controller.emitPlaybackState(const PlaybackState(playing: true));
      await Future<void>.delayed(Duration.zero);

      await handler.onTaskRemoved();
      // Should remain playing (no stop executed)
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('LinuxMprisBridge accurately maps playback status, volume, and metadata', () async {
      final mpris = LinuxMprisBridge(
        handler: handler,
        playbackController: controller,
      );

      const artist = Artist(id: 1, name: 'MPRIS Artist');
      const track = Track(
        id: 10,
        filePath: '/music/mpris.mp3',
        title: 'MPRIS Song',
        durationMs: 180000,
        fileSize: 3000000,
        modifiedAt: 123456789,
        artists: [artist],
      );

      controller.emitPlaybackState(
        PlaybackState(
          index: 0,
          playables: [
            track.toEngineItem(),
          ],
          playing: true,
          position: const Duration(seconds: 15),
          duration: const Duration(milliseconds: 180000),
          volume: 0.75,
          loop: LoopMode.all,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mpris.playbackStatus, equals('Playing'));
      expect(mpris.volume, closeTo(0.75, 0.001));
      expect(mpris.loopStatus, equals('Playlist'));
      expect(mpris.metadata, isNotNull);

      await mpris.pause();
      expect(controller.pauseCount, equals(1));
    });

    test('TachyonMprisObject returns full property maps via getAllProperties', () async {
      final mpris = LinuxMprisBridge(
        handler: handler,
        playbackController: controller,
      );
      final mprisObject = TachyonMprisObject(mpris);

      final rootProps = await mprisObject.getAllProperties('org.mpris.MediaPlayer2');
      expect(rootProps, isA<DBusGetAllPropertiesResponse>());
      final rootMap = (rootProps as DBusGetAllPropertiesResponse).values[0].asStringVariantDict();
      expect(rootMap['Identity']?.asString(), equals('Tachyon'));
      expect(rootMap['DesktopEntry']?.asString(), equals(''));

      final playerProps = await mprisObject.getAllProperties('org.mpris.MediaPlayer2.Player');
      expect(playerProps, isA<DBusGetAllPropertiesResponse>());
      final playerMap = (playerProps as DBusGetAllPropertiesResponse).values[0].asStringVariantDict();
      expect(playerMap['CanPlay']?.asBoolean(), isTrue);
      expect(playerMap['CanControl']?.asBoolean(), isTrue);
      expect(playerMap['PlaybackStatus'], isNotNull);
      expect(playerMap['Metadata'], isNotNull);
    });

    test('Minimized Mode updates isMinimizedListenable and notifies playback controller', () async {
      bool? lastMinimizedSentToController;
      controller.onSetMinimized = (minimized) {
        lastMinimizedSentToController = minimized;
      };

      expect(SystemMediaService.isMinimized, isFalse);

      SystemMediaService.updateMinimizedState(true, playbackController: controller);
      expect(SystemMediaService.isMinimized, isTrue);
      expect(SystemMediaService.isMinimizedListenable.value, isTrue);
      expect(lastMinimizedSentToController, isTrue);

      SystemMediaService.updateMinimizedState(false, playbackController: controller);
      expect(SystemMediaService.isMinimized, isFalse);
      expect(SystemMediaService.isMinimizedListenable.value, isFalse);
      expect(lastMinimizedSentToController, isFalse);
    });
  });
}
