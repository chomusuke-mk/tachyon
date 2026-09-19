import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

class StubMetadataExtractor implements MetadataExtractor {
  @override
  Future<Track?> extractMetadata(String filePath) async => null;

  @override
  Stream<ScanProgress> scanDirectories(List<String> directories, {CancellationToken? cancellationToken}) =>
      const Stream.empty();

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async => null;
}

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
    _state = _state.copyWith(playing: false);
    _controller.add(_state);
  }

  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {}
  @override
  Future<void> setLoopMode(Loop loop) async {}
  @override
  Future<void> toggleShuffle() async {}
  @override
  Future<void> insertNext(Playable playable) async {}
  @override
  Future<void> append(List<Playable> playables) async {}
  @override
  Future<void> remove(int index) async {}
  @override
  Future<void> reorder(int from, int to) async {}
  @override
  Future<void> setReplayGain(ReplayGainMode mode) async {}
  @override
  Future<void> setReplayGainPreamp(double preamp) async {}
  @override
  Future<void> setExclusiveAudio(bool exclusive) async {}
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

  late AppDatabase db;
  late MockAudioEngineService mockEngine;
  late SettingsRepository settingsRepo;
  late LocaleController localeController;
  late LibraryController libraryController;
  late PlaylistsController playlistsController;
  late PlaybackController playbackController;

  const testTrack1 = Track(
    id: 1,
    uri: 'file:///music/song1.mp3',
    title: 'Alpha Song',
    artist: 'Artist B',
    album: 'Album X',
    durationMs: 180000,
    fileSize: 5000000,
    modifiedAt: 1600000000,
  );

  const testTrack2 = Track(
    id: 2,
    uri: 'file:///music/song2.mp3',
    title: 'Beta Song',
    artist: 'Artist A',
    album: 'Album Y',
    durationMs: 240000,
    fileSize: 7000000,
    modifiedAt: 1600000001,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();

    mockEngine = MockAudioEngineService();

    localeController = LocaleController(StubLocaleRepository(), 'en');
    libraryController = LibraryController(
      database: db,
      metadataExtractor: StubMetadataExtractor(),
    );
    playlistsController = PlaylistsController(database: db);
    playbackController = PlaybackController(
      audioEngineService: mockEngine,
      database: db,
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    libraryController.dispose();
    playlistsController.dispose();
    await mockEngine.dispose();
    await db.close();
  });

  Widget buildTestWidget({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ],
      child: MaterialApp(
        theme: TachyonTheme.darkTheme,
        home: child,
      ),
    );
  }

  testWidgets('renders empty state when library has no tracks', (tester) async {
    await tester.runAsync(() async {
      await libraryController.loadLibrary();
    });

    await tester.pumpWidget(buildTestWidget(child: const TracksScreen()));
    await tester.pump();

    expect(find.byIcon(Icons.music_off_rounded), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('renders list of tracks using TrackTile with itemExtent 72.0', (tester) async {
    await tester.runAsync(() async {
      await db.insertOrUpdateTrack(testTrack1);
      await db.insertOrUpdateTrack(testTrack2);
      await libraryController.loadLibrary();
    });

    await tester.pumpWidget(buildTestWidget(child: const TracksScreen()));
    await tester.pump();

    final listViewFinder = find.byType(ListView);
    expect(listViewFinder, findsOneWidget);

    final listView = tester.widget<ListView>(listViewFinder);
    expect(listView.itemExtent, equals(72.0));

    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.text('Alpha Song'), findsOneWidget);
    expect(find.text('Beta Song'), findsOneWidget);
  });

  testWidgets('tapping a track tile initiates playback via PlaybackController', (tester) async {
    await tester.runAsync(() async {
      await db.insertOrUpdateTrack(testTrack1);
      await db.insertOrUpdateTrack(testTrack2);
      await libraryController.loadLibrary();
    });

    await tester.pumpWidget(buildTestWidget(child: const TracksScreen()));
    await tester.pump();

    await tester.tap(find.text('Alpha Song'));
    await tester.pump();

    expect(playbackController.currentTrack?.title, equals('Alpha Song'));
    expect(playbackController.isPlaying, isTrue);
  });

  testWidgets('sort menu changes sort option on LibraryController', (tester) async {
    await tester.runAsync(() async {
      await db.insertOrUpdateTrack(testTrack1);
      await db.insertOrUpdateTrack(testTrack2);
      await libraryController.loadLibrary();
    });

    await tester.pumpWidget(buildTestWidget(child: const TracksScreen()));
    await tester.pump();

    // Open sort menu
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();

    // Select artist sort
    final artistSortFinder = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<TrackSortOption> && widget.value == TrackSortOption.artist,
    );
    expect(artistSortFinder, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(artistSortFinder);
    });
    await tester.pumpAndSettle();

    expect(libraryController.sortOption, equals(TrackSortOption.artist));
  });

  testWidgets('selection mode toggles on checklist button press', (tester) async {
    await tester.runAsync(() async {
      await db.insertOrUpdateTrack(testTrack1);
      await db.insertOrUpdateTrack(testTrack2);
      await libraryController.loadLibrary();
    });

    await tester.pumpWidget(buildTestWidget(child: const TracksScreen()));
    await tester.pump();

    // Enter selection mode
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Tap close button to exit selection mode
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
  });
}
