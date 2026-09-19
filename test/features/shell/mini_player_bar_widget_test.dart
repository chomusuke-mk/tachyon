import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {};
}

class MockAudioEngineService implements AudioEngineService {
  final StreamController<MediaPlayerState> _controller =
      StreamController<MediaPlayerState>.broadcast(sync: true);
  MediaPlayerState _state = const MediaPlayerState.initial();

  @override
  Stream<MediaPlayerState> get stateStream => _controller.stream;

  @override
  MediaPlayerState get currentState => _state;

  void emitState(MediaPlayerState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> open(
    List<Playable> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    _state = _state.copyWith(
      playables: playables,
      index: index,
      playing: play,
      duration: playables.isNotEmpty ? playables[index].duration : Duration.zero,
    );
    _controller.add(_state);
  }

  @override
  Future<void> play() async {
    _state = _state.copyWith(playing: true);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
    _controller.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = _state.copyWith(playing: false, position: Duration.zero);
    _controller.add(_state);
  }

  @override
  Future<void> next() async {
    if (_state.index < _state.playables.length - 1) {
      _state = _state.copyWith(index: _state.index + 1);
      _controller.add(_state);
    }
  }

  @override
  Future<void> previous() async {
    if (_state.index > 0) {
      _state = _state.copyWith(index: _state.index - 1);
      _controller.add(_state);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    _controller.add(_state);
  }

  @override
  Future<void> setVolume(double volume) async =>
      emitState(_state.copyWith(volume: volume));

  @override
  Future<void> setRate(double rate) async =>
      emitState(_state.copyWith(rate: rate));

  @override
  Future<void> setPitch(double pitch) async =>
      emitState(_state.copyWith(pitch: pitch));

  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async =>
      emitState(_state.copyWith(crossfadeConfig: config));

  @override
  Future<void> setLoopMode(Loop loop) async =>
      emitState(_state.copyWith(loop: loop));

  @override
  Future<void> toggleShuffle() async =>
      emitState(_state.copyWith(shuffle: !_state.shuffle));

  @override
  Future<void> insertNext(Playable playable) async {}

  @override
  Future<void> append(List<Playable> playables) async {}

  @override
  Future<void> remove(int index) async {}

  @override
  Future<void> reorder(int from, int to) async {}

  @override
  Future<void> setReplayGain(ReplayGainMode mode) async =>
      emitState(_state.copyWith(replayGain: mode));

  @override
  Future<void> setReplayGainPreamp(double preamp) async =>
      emitState(_state.copyWith(replayGainPreamp: preamp));

  @override
  Future<void> setExclusiveAudio(bool exclusive) async =>
      emitState(_state.copyWith(exclusiveAudio: exclusive));

  @override
  Future<void> setMpvProperty(String property, String value) async {}

  @override
  Future<void> setMpvProperties(Map<String, String> properties) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockAudioEngineService mockEngine;
  late AppDatabase db;
  late SettingsRepository settingsRepo;
  late LocaleController localeController;
  late PlaybackController playbackController;

  const testTrack = Track(
    uri: 'file:///music/song.mp3',
    title: 'Test Song Title',
    artist: 'Test Artist Name',
    durationMs: 60000,
    fileSize: 1000000,
    modifiedAt: 1600000000,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();

    mockEngine = MockAudioEngineService();

    localeController = LocaleController(StubLocaleRepository(), 'en');
    playbackController = PlaybackController(
      audioEngineService: mockEngine,
      database: db,
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    await mockEngine.dispose();
    await db.close();
  });

  Widget buildTestWidget({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ],
      child: MaterialApp(
        theme: TachyonTheme.darkTheme,
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  testWidgets('renders empty SizedBox when currentTrack is null', (tester) async {
    await tester.pumpWidget(buildTestWidget(child: const MiniPlayerBar(isDesktop: false)));
    await tester.pump();

    expect(find.text('Test Song Title'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('displays title, artist, progress indicator, and controls when track is playing', (tester) async {
    await playbackController.playTrack(testTrack);
    await tester.pumpWidget(buildTestWidget(child: const MiniPlayerBar(isDesktop: false)));
    await tester.pump();

    expect(find.text('Test Song Title'), findsOneWidget);
    expect(find.text('Test Artist Name'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('tap on play/pause pauses and plays track', (tester) async {
    await playbackController.playTrack(testTrack);

    await tester.pumpWidget(buildTestWidget(child: const MiniPlayerBar(isDesktop: false)));
    await tester.pump();

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Tap pause
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    expect(playbackController.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Tap play
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(playbackController.isPlaying, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('renders desktop controls when isDesktop is true', (tester) async {
    await playbackController.playTrack(testTrack);
    mockEngine.seek(const Duration(seconds: 15));

    await tester.pumpWidget(buildTestWidget(child: const MiniPlayerBar(isDesktop: true)));
    await tester.pump();

    expect(find.text('00:15 / 01:00'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
  });

  testWidgets('tap on mini player triggers onTap callback', (tester) async {
    var tapped = false;
    await playbackController.playTrack(testTrack);

    await tester.pumpWidget(
      buildTestWidget(
        child: MiniPlayerBar(
          isDesktop: false,
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Test Song Title'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
