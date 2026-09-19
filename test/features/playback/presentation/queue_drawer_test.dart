import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/queue_drawer.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {
        'np_queue': 'Play Queue',
        'np_queue_empty': 'Queue is empty',
        'np_queue_clear': 'Clear Queue',
        'pl_cancel_button': 'Cancel',
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
  late LocaleController localeController;

  const trackA = Track(
    uri: 'file:///music/songA.mp3',
    title: 'Song Alpha',
    artist: 'Artist One',
    album: 'Album One',
    durationMs: 45000,
    fileSize: 1000000,
    modifiedAt: 1600000000,
  );

  const trackB = Track(
    uri: 'file:///music/songB.mp3',
    title: 'Song Beta',
    artist: 'Artist Two',
    album: 'Album Two',
    durationMs: 55000,
    fileSize: 1000000,
    modifiedAt: 1600000001,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();

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

    localeController = LocaleController(StubLocaleRepository(), 'en');
  });

  tearDown(() async {
    playbackController.dispose();
    await engine.dispose();
    await db.close();
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: QueueView(),
        ),
      ),
    );
  }

  group('QueueView Widget Tests', () {
    testWidgets('renders empty queue state when no tracks are queued', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Queue is empty'), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    });

    testWidgets('renders list of queued tracks with current track playing badge', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playAll([trackA, trackB], startIndex: 0);
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Song Alpha'), findsOneWidget);
      expect(find.text('Song Beta'), findsOneWidget);

      // Verify active playing equalizer icon on active track 0
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('tapping track tile switches active playback index', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playAll([trackA, trackB], startIndex: 0);
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(playbackController.currentIndex, equals(0));

      // Tap second track (Song Beta)
      await tester.runAsync(() async {
        await tester.tap(find.text('Song Beta'));
        await Future.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(playbackController.currentIndex, equals(1));
    });

    testWidgets('toggles infinite library mix setting', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playTrack(trackA);
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(playbackController.isInfiniteMixEnabled, isFalse);

      // Tap Infinite Mix icon
      await tester.tap(find.byIcon(Icons.all_inclusive_rounded));
      await tester.pump();

      expect(playbackController.isInfiniteMixEnabled, isTrue);
    });

    testWidgets('clear queue button displays confirmation dialog and clears queue', (tester) async {
      await tester.runAsync(() async {
        await playbackController.playAll([trackA, trackB], startIndex: 0);
        await Future.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(playbackController.queue.length, equals(2));

      // Tap Clear Queue icon in header
      await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
      await tester.pumpAndSettle();

      // Verify confirmation dialog appeared
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap the confirm button in the dialog (which has np_queue_clear text)
      final confirmButtons = find.widgetWithText(FilledButton, 'Clear Queue');
      expect(confirmButtons, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(confirmButtons);
        await Future.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      // Queue is now empty
      expect(playbackController.queue, isEmpty);
      expect(find.text('Queue is empty'), findsOneWidget);
    });
  });
}
