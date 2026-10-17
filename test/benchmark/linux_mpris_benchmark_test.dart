import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/services/linux_mpris_bridge.dart';
import 'package:tachyon/features/playback/services/tachyon_audio_handler.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';

class _BenchmarkBackendClient implements TachyonBackendClient {
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

  void emitPosition(Duration pos) {
    _posController.add(pos);
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
    if (_currentState.playables.isEmpty) return;
    final nextIdx = (_currentState.index + 1) % _currentState.playables.length;
    emitState(
      _currentState.copyWith(
        index: nextIdx,
        position: Duration.zero,
        playing: true,
      ),
    );
  }

  @override
  Future<void> previous() async {
    if (_currentState.playables.isEmpty) return;
    final prevIdx =
        (_currentState.index - 1 + _currentState.playables.length) %
        _currentState.playables.length;
    emitState(
      _currentState.copyWith(
        index: prevIdx,
        position: Duration.zero,
        playing: true,
      ),
    );
  }

  @override
  Future<void> skipToIndex(int index) async {
    emitState(
      _currentState.copyWith(
        index: index,
        position: Duration.zero,
        playing: true,
      ),
    );
  }

  @override
  Future<void> seek(Duration pos) async {
    emitState(_currentState.copyWith(position: pos));
  }

  @override
  Future<void> stop() async {
    emitState(_currentState.copyWith(playing: false));
  }

  @override
  Future<void> setVolume(double volume) async {
    emitState(_currentState.copyWith(volume: volume));
  }

  @override
  Future<void> setLoopMode(Loop loop) async {
    emitState(_currentState.copyWith(loop: loop));
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    emitState(_currentState.copyWith(shuffle: shuffle));
  }

  @override
  Future<void> setRate(double rate) async {
    emitState(_currentState.copyWith(rate: rate));
  }

  @override
  Future<void> addTracksToPlaylist(int id, List<int> ids) async {}

  @override
  Future<List<AudioDevice>> getAudioDevices() async => const [];

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _posController.close();
    await _visController.close();
    await _devController.close();
    await _catController.close();
    await _scanController.close();
  }

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Linux MPRIS Bridge Performance & Coalescing Benchmarks', () {
    late Directory tempDir;
    late SettingsRepository settingsRepo;
    late _BenchmarkBackendClient backend;
    late PlaybackController controller;
    late TachyonAudioHandler handler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      backend = _BenchmarkBackendClient();

      tempDir = await Directory.systemTemp.createTemp('linux_mpris_bench');
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
      await backend.dispose();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test(
      'O(1) hydrated metadata resolves _low.png artUrl without disk existence checks',
      () async {
        final mpris = LinuxMprisBridge(
          handler: handler,
          playbackController: controller,
        );

        const artist = Artist(id: 7, name: 'Benchmark Artist');
        final album = Album(
          id: 3,
          name: 'Benchmark Album',
          thumbnailHash: 'album_hash_without_file_on_disk',
        );
        final track = Track(
          id: 42,
          filePath: '/music/bench_song.flac',
          title: 'Benchmark Song',
          durationMs: 215000,
          fileSize: 12000000,
          modifiedAt: 1700000000,
          thumbnailHash: 'track_hash_without_file_on_disk',
          artists: const [artist],
          album: album,
        );

        backend.emitState(
          PlaybackState(
            index: 0,
            playables: [PlaylistEntry.forQueue(id: 1, track: track)],
            playing: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final meta = mpris.metadata.asStringVariantDict();
        expect(
          meta['mpris:trackid']?.asObjectPath().value,
          equals('/org/mpris/MediaPlayer2/Track/t_42'),
        );
        expect(meta['xesam:title']?.asString(), equals('Benchmark Song'));
        expect(
          meta['xesam:artist']?.asStringArray(),
          equals(['Benchmark Artist']),
        );
        expect(meta['xesam:album']?.asString(), equals('Benchmark Album'));

        final artUrl = meta['mpris:artUrl']?.asString();
        expect(artUrl, isNotNull);
        expect(artUrl, startsWith('file://'));
        expect(
          artUrl,
          endsWith('track_hash_without_file_on_disk_low.png'),
          reason:
              'MPRIS must always use ThumbnailQuality.low (_low.png) in O(1) without disk validation',
        );

        final mprisObj = TachyonMprisObject(mpris);
        final playerProps = await mprisObj.getAllProperties(
          'org.mpris.MediaPlayer2.Player',
        );
        expect(playerProps, isA<DBusGetAllPropertiesResponse>());
        final propMap = (playerProps as DBusGetAllPropertiesResponse)
            .values[0]
            .asStringVariantDict();
        expect(propMap['Shuffle'], equals(const DBusBoolean(false)));
      },
    );

    test(
      'Linux D-Bus MPRIS: 60 rapid consecutive track changes coalesce without blocking or flooding D-Bus',
      () async {
        if (!Platform.isLinux) return;

        final mpris = LinuxMprisBridge(
          handler: handler,
          playbackController: controller,
          metadataDebounceDuration: const Duration(milliseconds: 50),
          stateCoalesceDuration: const Duration(milliseconds: 10),
        );
        await mpris.initialize();
        expect(mpris.registeredBusName, isNotNull);

        // Startup must NOT emit any redundant PropertiesChanged signals.
        expect(mpris.emittedSignalCount, equals(0));

        // Build 60 hydrated tracks in memory (simulating LibraryStore O(1) graph).
        const artist = Artist(id: 1, name: 'Stress Test Artist');
        final album = Album(
          id: 1,
          name: 'Stress Test Album',
          thumbnailHash: 'stress_album_hash',
        );
        final tracks = List.generate(
          60,
          (i) => Track(
            id: i + 1,
            filePath: '/music/track_$i.mp3',
            title: 'Track Number $i',
            durationMs: 180000 + (i * 1000),
            fileSize: 4000000,
            modifiedAt: 1700000000 + i,
            thumbnailHash: 'hash_track_$i',
            artists: const [artist],
            album: album,
          ),
        );
        final playables = tracks
            .map((t) => PlaylistEntry.forQueue(id: t.id!, track: t))
            .toList(growable: false);

        // 1. Start playback on Track 0 (NoTrack -> Track 0, Stopped -> Playing).
        backend.emitState(
          PlaybackState(
            index: 0,
            playables: playables,
            playing: true,
            position: Duration.zero,
            duration: const Duration(milliseconds: 180000),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await mpris.flushPendingSignalsForTest();

        // Starting the queue from idle must emit exactly 1 combined PropertiesChanged signal.
        expect(mpris.emittedSignalCount, equals(1));

        // 2. Simulate 25Hz position stream updates for 1 second: must emit 0 MPRIS signals.
        final signalsBeforePositionTicks = mpris.emittedSignalCount;
        for (int tick = 1; tick <= 25; tick++) {
          backend.emitPosition(Duration(milliseconds: tick * 40));
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(
          mpris.emittedSignalCount,
          equals(signalsBeforePositionTicks),
          reason: 'High-frequency position ticks must never emit MPRIS PropertiesChanged signals',
        );

        // 3. Benchmark 60 rapid consecutive track changes (next() 60 times).
        final signalsBeforeBurst = mpris.emittedSignalCount;
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 60; i++) {
          await controller.next();
        }
        // Allow microtasks on the UI isolate to process all 60 state transitions.
        await Future<void>.delayed(Duration.zero);
        stopwatch.stop();

        // All 60 rapid skips on the UI isolate must complete in < 100ms (zero freeze).
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(100),
          reason:
              '60 consecutive track skips must execute in O(1) without blocking the UI isolate',
        );

        // Flush the debounce window and verify that all 60 rapid track changes
        // coalesced into AT MOST 1 single D-Bus PropertiesChanged signal!
        await mpris.flushPendingSignalsForTest();
        final emittedDuringBurst =
            mpris.emittedSignalCount - signalsBeforeBurst;
        expect(
          emittedDuringBurst,
          lessThanOrEqualTo(1),
          reason:
              '60 rapid skips must coalesce into at most 1 D-Bus PropertiesChanged signal instead of flooding GNOME Shell / GSConnect',
        );

        // 4. Verify single track skip (Track 0 -> Track 1) emits exactly 1 signal.
        final signalsBeforeSingleSkip = mpris.emittedSignalCount;
        await controller.next();
        await Future<void>.delayed(Duration.zero);
        await mpris.flushPendingSignalsForTest();
        expect(
          mpris.emittedSignalCount - signalsBeforeSingleSkip,
          equals(1),
          reason: 'A single track change must emit exactly 1 coalesced PropertiesChanged signal',
        );

        final currentMeta = mpris.metadata.asStringVariantDict();
        expect(
          currentMeta['xesam:title']?.asString(),
          equals('Track Number 1'),
        );
        expect(
          currentMeta['mpris:artUrl']?.asString(),
          endsWith('hash_track_1_low.png'),
        );

        mpris.dispose();
      },
    );
  });
}
