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
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {
        'np_lyrics_empty': 'No lyrics available',
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

  const sampleTrack = Track(
    uri: 'file:///music/song.mp3',
    title: 'Test Song',
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 60000,
    fileSize: 1000000,
    modifiedAt: 1600000000,
    lyrics: '''
[00:05.00]First line of lyrics
[00:15.00]Second line of lyrics
[00:30.00]Third line of lyrics
''',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();
    await db.insertOrUpdateTrack(sampleTrack);

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

  Widget createTestWidget({ValueChanged<Duration>? onSeek}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LyricsView(onSeek: onSeek),
        ),
      ),
    );
  }

  group('LyricsView Widget Tests', () {
    testWidgets('renders empty state when no lyrics are loaded', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
      expect(find.text('No lyrics available'), findsOneWidget);
    });

    testWidgets('renders list of synchronized lines with active line highlighted', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playTrack(sampleTrack);
        playerA.simulateDuration(const Duration(seconds: 60));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
        playerA.simulatePosition(const Duration(seconds: 16));
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('First line of lyrics'), findsOneWidget);
      expect(find.text('Second line of lyrics'), findsOneWidget);
      expect(find.text('Third line of lyrics'), findsOneWidget);

      // Verify active line (Second line) styling
      final activeText = tester.widget<Text>(find.text('Second line of lyrics'));
      expect(activeText.style?.fontSize, equals(22));
      expect(activeText.style?.fontWeight, equals(FontWeight.w700));

      // Verify inactive line (First line) styling
      final inactiveText = tester.widget<Text>(find.text('First line of lyrics'));
      expect(inactiveText.style?.fontSize, equals(16));
      expect(inactiveText.style?.fontWeight, equals(FontWeight.w400));
    });

    testWidgets('tap on lyric line triggers seek and onSeek callback', (tester) async {
      Duration? soughtDuration;

      await tester.runAsync(() async {
        await playbackController.playTrack(sampleTrack);
        playerA.simulateDuration(const Duration(seconds: 60));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
      });

      await tester.pumpWidget(createTestWidget(
        onSeek: (dur) {
          soughtDuration = dur;
        },
      ));
      await tester.pump();

      // Tap on the third line (timestamp 30s)
      await tester.tap(find.text('Third line of lyrics'));
      await tester.pump();

      expect(soughtDuration, equals(const Duration(seconds: 30)));
      expect(lyricsController.currentIndex, equals(2));
    });

    testWidgets('displays Sync floating action button when user scroll lock is active', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playTrack(sampleTrack);
        playerA.simulateDuration(const Duration(seconds: 60));
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
          if (lyricsController.hasLyrics) break;
        }
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Before scroll lock, sync button is not present
      expect(find.text('Sync'), findsNothing);

      // Simulate user scroll lock
      lyricsController.onUserScroll();
      await tester.pump();

      // Now floating Sync button is visible
      expect(find.text('Sync'), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

      // Tapping Sync button resets scroll lock
      await tester.tap(find.text('Sync'));
      await tester.pump();

      expect(lyricsController.isUserScrollLocked, isFalse);
      expect(find.text('Sync'), findsNothing);
    });
  });
}
