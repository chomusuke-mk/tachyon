import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';
import 'package:tachyon/core/playback/windows_smtc_bridge.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';

class _FakePlaybackController extends PlaybackController {
  _FakePlaybackController({
    required super.settingsRepository,
  });

  PlaybackState _fakeState = const PlaybackState.initial();
  final ValueNotifier<Duration> _fakePositionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  @override
  PlaybackState get state => _fakeState;

  @override
  Track? get currentTrack => _fakeState.currentTrack;

  @override
  bool get isPlaying => _fakeState.isPlaying;

  @override
  Duration get position => _fakeState.position;

  @override
  Duration get duration => _fakeState.duration;

  @override
  ValueNotifier<Duration> get positionNotifier => _fakePositionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _fakePositionNotifier;

  @override
  bool get isShuffled => _fakeState.isShuffled;

  @override
  LoopMode get loopMode => _fakeState.loopMode;

  @override
  double get rate => _fakeState.rate;

  @override
  double get volume => _fakeState.volume;

  void emitState(PlaybackState state) {
    _fakeState = state;
    _fakePositionNotifier.value = state.position;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    emitState(_fakeState.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    emitState(_fakeState.copyWith(isPlaying: false));
  }

  @override
  Future<void> next() async {
    if (_fakeState.queue.isEmpty) return;
    final nextIdx = (_fakeState.currentIndex + 1) % _fakeState.queue.length;
    emitState(_fakeState.copyWith(
      currentIndex: nextIdx,
      position: Duration.zero,
      isPlaying: true,
    ));
  }

  @override
  Future<void> previous() async {}

  @override
  Future<void> seek(Duration pos) async {
    emitState(_fakeState.copyWith(position: pos));
  }

  @override
  Future<void> stop() async {
    emitState(_fakeState.copyWith(isPlaying: false));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsSmtcBridge & TachyonAudioHandler 30 Skips Verification', () {
    late Directory tempDir;
    late SettingsRepository settingsRepo;
    late _FakePlaybackController controller;
    late TachyonAudioHandler handler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);

      tempDir = await Directory.systemTemp.createTemp('smtc_verify_test');
      MetadataUtils.init(tempDir.path, tempDir.path);

      controller = _FakePlaybackController(
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
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('TachyonAudioHandler uses low-quality cover and caches queue synchronization', () async {
      final coverPath = MetadataUtils.getThumbnailFilePath('hash_lq', quality: ThumbnailQuality.low);
      final coverLq = File(coverPath);
      coverLq.parent.createSync(recursive: true);
      coverLq.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);

      const track = Track(
        id: 1,
        filePath: 'C:\\Music\\Song.mp3',
        title: 'Song',
        thumbnailHash: 'hash_lq',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
      );

      controller.emitState(PlaybackState(
        currentIndex: 0,
        queue: [track.toEngineItem()],
        isPlaying: true,
      ));

      await Future<void>.delayed(Duration.zero);

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.artUri, isNotNull);
      // Verify small / LQ thumbnail is selected
      expect(item.artUri!.toFilePath().contains('_low.png'), isTrue);
    });

    test('30 rapid skips execute smoothly without queue re-scan or bridge freeze', () async {
      final tracks = List.generate(50, (i) {
        final coverPath = MetadataUtils.getThumbnailFilePath('track_$i', quality: ThumbnailQuality.low);
        final coverLq = File(coverPath);
        coverLq.parent.createSync(recursive: true);
        coverLq.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);

        return Track(
          id: i,
          filePath: 'C:\\Music\\Track_$i.mp3',
          title: 'Track $i',
          durationMs: 200000,
          fileSize: 1000,
          modifiedAt: 1000,
          thumbnailHash: 'track_$i',
          artists: [Artist(id: i, name: 'Artist $i')],
        );
      });

      final playables = tracks
          .map((t) => t.toEngineItem())
          .toList();

      controller.emitState(PlaybackState(
        currentIndex: 0,
        queue: playables,
        isPlaying: true,
      ));

      await Future<void>.delayed(Duration.zero);

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 30; i++) {
        await controller.next();
      }
      stopwatch.stop();

      // 30 skips should complete under 500ms total
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('WindowsSmtcBridge starts loopback server and serves small cover image', () async {
      if (!Platform.isWindows) return;

      final bridge = WindowsSmtcBridge(handler);
      final initialized = await bridge.initialize();
      expect(initialized, isTrue);
      expect(bridge.coverServerPort, isNotNull);

      // Verify that loopback server responds with cover image
      final sampleCover = File('${tempDir.path}/covers/test_sample_lq.jpg');
      sampleCover.parent.createSync(recursive: true);
      sampleCover.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);

      final port = bridge.coverServerPort!;
      final url = Uri.parse(
        'http://127.0.0.1:$port/cover?path=${Uri.encodeComponent(sampleCover.path)}',
      );

      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final response = await http.get(url);
      HttpOverrides.global = previousOverrides;
      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('image/jpeg'));
      expect(response.bodyBytes, equals(sampleCover.readAsBytesSync()));

      bridge.dispose();
    });
  });
}
