import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/services/linux_mpris_bridge.dart';
import 'package:tachyon/features/playback/services/tachyon_audio_handler.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';

class FakeTachyonBackendClient implements TachyonBackendClient {
  final StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<List<double>> _visualizerController =
      StreamController<List<double>>.broadcast();
  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<void> _catalogUpdatedController =
      StreamController<void>.broadcast();
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();

  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeekPosition;
  Loop? lastSetLoop;
  bool? lastShuffle;

  PlaybackState _currentState = const PlaybackState.initial();

  @override
  Stream<PlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<List<double>> get visualizerStream => _visualizerController.stream;

  @override
  Stream<List<AudioDevice>> get devicesStream => _devicesController.stream;

  @override
  Stream<void> get catalogUpdatedStream => _catalogUpdatedController.stream;

  @override
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  void emitPlaybackState(PlaybackState state) {
    _currentState = state;
    _playbackStateController.add(state);
  }

  @override
  Future<PlaybackState> getPlaybackState() async => _currentState;

  @override
  Future<void> play() async {
    playCount++;
    emitPlaybackState(_currentState.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPlaybackState(_currentState.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
    emitPlaybackState(_currentState.copyWith(position: position));
  }

  @override
  Future<void> setLoopMode(Loop loop) async {
    lastSetLoop = loop;
    emitPlaybackState(_currentState.copyWith(loop: loop));
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    lastShuffle = shuffle;
    emitPlaybackState(_currentState.copyWith(shuffle: shuffle));
  }

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {}

  Future<void> saveLastPlaybackState({
    required String filePath,
    required int positionMs,
  }) async {}

  @override
  Future<List<AudioDevice>> getAudioDevices() async => const [];

  @override
  Future<void> stop() async {
    pauseCount++;
    emitPlaybackState(_currentState.copyWith(playing: false));
  }

  Future<void> initialize({
    required String dbPath,
    required String cacheDirPath,
  }) async {}

  @override
  Future<void> dispose() async {
    await _playbackStateController.close();
    await _positionController.close();
    await _visualizerController.close();
    await _devicesController.close();
    await _catalogUpdatedController.close();
    await _scanProgressController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TachyonAudioHandler & System Media Service Unit Tests', () {
    late SettingsRepository settingsRepo;
    late FakeTachyonBackendClient backend;
    late PlaybackController controller;
    late TachyonAudioHandler handler;
    late Directory tempCacheDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      backend = FakeTachyonBackendClient();
      tempCacheDir = await Directory.systemTemp.createTemp('tachyon_cover_test');
      CoverUtils.init(tempCacheDir);

      controller = PlaybackController(
        backend: backend,
        settingsRepository: settingsRepo,
      );

      handler = TachyonAudioHandler(
        backend: backend,
        playbackController: controller,
      );
    });

    tearDown(() async {
      handler.dispose();
      controller.dispose();
      await backend.dispose();
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

      backend.emitPlaybackState(
        PlaybackState(
          index: 0,
          playables: [
            PlaylistEntry.forQueue(id: 1, track: track),
          ],
          playing: true,
          position: const Duration(seconds: 42),
          duration: const Duration(milliseconds: 240000),
          loop: Loop.all,
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

    test('Handler play, pause, seek, and loop calls delegate to backend/controller', () async {
      await handler.play();
      expect(backend.playCount, equals(1));

      await handler.pause();
      expect(backend.pauseCount, equals(1));

      await handler.seek(const Duration(seconds: 90));
      expect(backend.lastSeekPosition, equals(const Duration(seconds: 90)));

      await handler.setRepeatMode(as_lib.AudioServiceRepeatMode.one);
      expect(backend.lastSetLoop, equals(Loop.one));
    });

    test('onTaskRemoved stops playback only when not playing', () async {
      // 1. When not playing: onTaskRemoved should call stop
      backend.emitPlaybackState(const PlaybackState(playing: false));
      await Future<void>.delayed(Duration.zero);

      await handler.onTaskRemoved();
      expect(
        handler.playbackState.value.processingState,
        equals(as_lib.AudioProcessingState.idle),
      );

      // 2. When playing: onTaskRemoved preserves playing state for headless mode
      backend.emitPlaybackState(const PlaybackState(playing: true));
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

      backend.emitPlaybackState(
        PlaybackState(
          index: 0,
          playables: [
            PlaylistEntry.forQueue(id: 1, track: track),
          ],
          playing: true,
          position: const Duration(seconds: 15),
          duration: const Duration(milliseconds: 180000),
          volume: 75.0,
          loop: Loop.all,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mpris.playbackStatus, equals('Playing'));
      expect(mpris.volume, closeTo(0.75, 0.001));
      expect(mpris.loopStatus, equals('Playlist'));
      expect(mpris.metadata, isNotNull);

      await mpris.pause();
      expect(backend.pauseCount, equals(1));
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
  });
}
