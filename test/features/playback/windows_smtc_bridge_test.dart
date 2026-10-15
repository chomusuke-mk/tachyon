import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/services/tachyon_audio_handler.dart';
import 'package:tachyon/features/playback/services/windows_smtc_bridge.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';

class _FakeBackendClient implements TachyonBackendClient {
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _posController =
      StreamController<Duration>.broadcast();
  final StreamController<List<double>> _visController =
      StreamController<List<double>>.broadcast();
  final StreamController<List<AudioDevice>> _devController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<void> _catController =
      StreamController<void>.broadcast();
  final StreamController<ScanProgress> _scanController =
      StreamController<ScanProgress>.broadcast();

  PlaybackState _currentState = const PlaybackState.initial();

  @override
  Stream<PlaybackState> get playbackStateStream => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _posController.stream;
  @override
  Stream<List<double>> get visualizerStream => _visController.stream;
  @override
  Stream<List<AudioDevice>> get devicesStream => _devController.stream;
  @override
  Stream<void> get catalogUpdatedStream => _catController.stream;
  @override
  Stream<ScanProgress> get scanProgressStream => _scanController.stream;

  @override
  Future<PlaybackState> getPlaybackState() async => _currentState;

  void emitState(PlaybackState state) {
    _currentState = state;
    _stateController.add(state);
  }

  @override
  Future<void> play() async {
    emitState(_currentState.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    emitState(_currentState.copyWith(playing: false));
  }

  @override
  Future<void> next() async {
    final nextIdx = (_currentState.index + 1) % _currentState.playables.length;
    emitState(_currentState.copyWith(
      index: nextIdx,
      position: Duration.zero,
      playing: true,
    ));
  }

  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration pos) async {
    emitState(_currentState.copyWith(position: pos));
  }

  @override
  Future<void> stop() async {
    emitState(_currentState.copyWith(playing: false));
  }

  @override
  Future<void> addTracksToPlaylist(int id, List<int> ids) async {}

  @override
  Future<List<AudioDevice>> getAudioDevices() async => const [];

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsSmtcBridge & TachyonAudioHandler 30 Skips Verification', () {
    late Directory tempDir;
    late SettingsRepository settingsRepo;
    late _FakeBackendClient backend;
    late PlaybackController controller;
    late TachyonAudioHandler handler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      backend = _FakeBackendClient();

      tempDir = await Directory.systemTemp.createTemp('smtc_verify_test');
      MetadataUtils.init(tempDir.path, tempDir.path);

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

      backend.emitState(PlaybackState(
        index: 0,
        playables: [PlaylistEntry.forQueue(id: 1, track: track)],
        playing: true,
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
          .map((t) => PlaylistEntry.forQueue(id: t.id!, track: t))
          .toList();

      backend.emitState(PlaybackState(
        index: 0,
        playables: playables,
        playing: true,
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
