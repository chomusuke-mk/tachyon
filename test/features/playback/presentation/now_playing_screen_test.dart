import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/waveform_slider.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {
        'np_queue': 'Play Queue',
        'np_queue_empty': 'Queue is empty',
        'np_queue_clear': 'Clear Queue',
        'np_lyrics': 'Lyrics',
        'np_lyrics_empty': 'No lyrics available',
        'np_speed': 'Playback Speed',
        'np_pitch': 'Pitch Shift',
        'np_volume_boost': 'Volume Boost',
        'np_replay_gain': 'ReplayGain',
        'np_preamp': 'Preamp',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockAudioPlayerAdapter playerA;
  late MockAudioPlayerAdapter playerB;
  late QueueManager queueManager;
  late AudioEngineServiceImpl engine;
  late AppDatabase db;
  late SettingsRepository settingsRepo;
  late PlaybackController playbackController;
  late LyricsService lyricsService;
  late LyricsController lyricsController;
  late LocaleController localeController;

  const testTrack = Track(
    id: 10,
    uri: 'file:///music/test_song.mp3',
    title: 'Starlight Symphony',
    artist: 'Cosmic Orchestra',
    album: 'Galactic Horizons',
    durationMs: 180000,
    fileSize: 5000000,
    modifiedAt: 1600000000,
    lyrics: '[00:10.00]Gazing at the starlight\n[00:20.00]Across the infinite cosmos',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();
    await db.insertOrUpdateTrack(testTrack);

    playerA = MockAudioPlayerAdapter(id: 'PlayerA');
    playerB = MockAudioPlayerAdapter(id: 'PlayerB');
    queueManager = QueueManager();
    engine = AudioEngineServiceImpl(
      playerA: playerA,
      playerB: playerB,
      queueManager: queueManager,
    );

    playbackController = PlaybackController(
      audioEngineService: engine,
      database: db,
      settingsRepository: settingsRepo,
    );

    lyricsService = LyricsServiceImpl(database: db);
    lyricsController = LyricsController(
      lyricsService: lyricsService,
      playbackController: playbackController,
    );

    localeController = LocaleController(StubLocaleRepository(), 'en');
  });

  tearDown(() async {
    lyricsController.dispose();
    playbackController.dispose();
    await engine.dispose();
    await db.close();
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        Provider<AppDatabase>.value(value: db),
        Provider<SettingsRepository>.value(value: settingsRepo),
      ],
      child: const MaterialApp(
        home: NowPlayingScreen(),
      ),
    );
  }

  group('NowPlayingScreen Widget Tests', () {
    testWidgets('renders empty state placeholder when no track is queued', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Queue is empty'), findsOneWidget);
    });

    testWidgets('renders mobile column layout with track metadata and controls (< 720dp)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() async {
        await playbackController.playTrack(testTrack);
        playerA.simulateDuration(const Duration(seconds: 180));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Verify track metadata
      expect(find.text('Starlight Symphony'), findsOneWidget);
      expect(find.text('Cosmic Orchestra'), findsOneWidget);

      // Verify WaveformSlider is present
      expect(find.byType(WaveformSlider), findsOneWidget);

      // Verify primary transport controls
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget); // playing initially
    });

    testWidgets('toggles play and pause on transport control button tap', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() async {
        await playbackController.playTrack(testTrack);
        playerA.simulateDuration(const Duration(seconds: 180));
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Tap pause button
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await Future.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('cycles loop mode on loop button tap', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() async {
        await playbackController.playTrack(testTrack);
        playerA.simulateDuration(const Duration(seconds: 180));
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(playbackController.loopMode, equals(Loop.off));

      // Tap repeat button
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.repeat_rounded));
        await Future.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(playbackController.loopMode, equals(Loop.all));
    });

    testWidgets('flips view to lyrics on mobile when lyrics toggle button is tapped', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() async {
        await playbackController.playTrack(testTrack);
        playerA.simulateDuration(const Duration(seconds: 180));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // LyricsView is not visible before toggle
      expect(find.byType(LyricsView), findsNothing);

      // Tap lyrics button
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pumpAndSettle();

      // Now LyricsView is rendered
      expect(find.byType(LyricsView), findsOneWidget);
      expect(find.text('Gazing at the starlight'), findsOneWidget);
    });

    testWidgets('renders desktop dual-panel layout with both artwork and lyrics (>= 720dp)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() async {
        await playbackController.playTrack(testTrack);
        playerA.simulateDuration(const Duration(seconds: 180));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Desktop layout renders metadata, controls, and LyricsView side-by-side simultaneously
      expect(find.text('Starlight Symphony'), findsOneWidget);
      expect(find.text('Cosmic Orchestra'), findsOneWidget);
      expect(find.byType(LyricsView), findsOneWidget);
    });
  });
}
