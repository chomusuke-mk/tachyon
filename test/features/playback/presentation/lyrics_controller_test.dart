import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

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

  const trackWithLyrics = Track(
    id: 1,
    uri: 'file:///music/song_lyrics.mp3',
    title: 'Synced Song',
    artist: 'Lrc Artist',
    album: 'Lrc Album',
    durationMs: 60000,
    fileSize: 1000000,
    modifiedAt: 1600000000,
    lyrics: '''
[00:05.00]First line of song
[00:10.00]Second line of song
[00:20.00]Third line of song
[00:35.00]Fourth line of song
''',
  );

  const trackWithoutLyrics = Track(
    id: 2,
    uri: 'file:///music/instrumental.mp3',
    title: 'Instrumental',
    artist: 'Lrc Artist',
    album: 'Lrc Album',
    durationMs: 40000,
    fileSize: 1000000,
    modifiedAt: 1600000001,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();
    await db.insertOrUpdateTrack(trackWithLyrics);
    await db.insertOrUpdateTrack(trackWithoutLyrics);

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
  });

  
  Future<void> waitForLyrics() async {
    for (int i = 0; i < 50; i++) {
      if (lyricsController.hasLyrics) break;
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  tearDown(() async {
    lyricsController.dispose();
    playbackController.dispose();
    await engine.dispose();
    await db.close();
  });

  group('LyricsController Initialization & Ingestion', () {
    test('initializes with empty state when no track is loaded', () {
      expect(lyricsController.lyrics, isNull);
      expect(lyricsController.lines, isEmpty);
      expect(lyricsController.isSynced, isFalse);
      expect(lyricsController.hasLyrics, isFalse);
      expect(lyricsController.isLoading, isFalse);
      expect(lyricsController.currentIndex, equals(0));
      expect(lyricsController.isUserScrollLocked, isFalse);
    });

    test('automatically loads and parses lyrics when playback begins', () async {
      await playbackController.playTrack(trackWithLyrics);
      await waitForLyrics();

      expect(lyricsController.hasLyrics, isTrue);
      expect(lyricsController.isSynced, isTrue);
      expect(lyricsController.lines.length, equals(4));
      expect(lyricsController.lines[0].text, equals('First line of song'));
      expect(lyricsController.lines[1].text, equals('Second line of song'));
    });

    test('handles tracks without lyrics gracefully', () async {
      await playbackController.playTrack(trackWithoutLyrics);
      await pumpEventQueue(times: 20);

      expect(lyricsController.hasLyrics, isFalse);
      expect(lyricsController.lyrics, isNull);
      expect(lyricsController.lines, isEmpty);
      expect(lyricsController.errorMessage, isNull);
    });
  });

  group('LyricsController Synchronization & Active Line Tracking', () {
    setUp(() async {
      await playbackController.playTrack(trackWithLyrics);
      playerA.simulateDuration(const Duration(seconds: 60));
      await waitForLyrics();
    });

    test('reactively updates active lyric line as playback progresses', () async {
      // Before 5s -> index 0 (initial line)
      playerA.simulatePosition(const Duration(seconds: 2));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(0));

      // At 7s -> first line (timestamp 5s)
      playerA.simulatePosition(const Duration(seconds: 7));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(0));
      expect(lyricsController.currentLine?.text, equals('First line of song'));

      // At 12s -> second line (timestamp 10s)
      playerA.simulatePosition(const Duration(seconds: 12));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(1));
      expect(lyricsController.currentLine?.text, equals('Second line of song'));

      // At 25s -> third line (timestamp 20s)
      playerA.simulatePosition(const Duration(seconds: 25));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(2));
      expect(lyricsController.currentLine?.text, equals('Third line of song'));

      // At 50s -> fourth line (timestamp 35s)
      playerA.simulatePosition(const Duration(seconds: 50));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(3));
      expect(lyricsController.currentLine?.text, equals('Fourth line of song'));
    });

    test('seekToLine jumps playback position to matching line timestamp', () async {
      // Seek to line 2 (timestamp 20s)
      await lyricsController.seekToLine(2);
      await pumpEventQueue(times: 20);

      expect(playerA.position, equals(const Duration(seconds: 20)));
      expect(lyricsController.currentIndex, equals(2));
    });

    test('adjustOffset applies calibration delta and shifts active line', () async {
      // Playback at 9 seconds (normally line 0 since line 1 starts at 10s)
      playerA.simulatePosition(const Duration(seconds: 9));
      await pumpEventQueue(times: 20);
      expect(lyricsController.currentIndex, equals(0));

      // Add +1500ms offset -> effective position is 10.5s -> switches to line 1
      lyricsController.adjustOffset(1500);
      await pumpEventQueue(times: 20);
      expect(lyricsController.userOffsetMs, equals(1500));
      expect(lyricsController.currentIndex, equals(1));

      // Reset offset returns to 0
      lyricsController.resetOffset();
      await pumpEventQueue(times: 20);
      expect(lyricsController.userOffsetMs, equals(0));
      expect(lyricsController.currentIndex, equals(0));
    });
  });

  group('LyricsController Manual Scroll Lock & Auto-Resume', () {
    setUp(() async {
      await playbackController.playTrack(trackWithLyrics);
      playerA.simulateDuration(const Duration(seconds: 60));
      await waitForLyrics();
    });

    testWidgets('onUserScroll activates scroll lock and auto-resumes after 5 seconds', (tester) async {
      expect(lyricsController.isUserScrollLocked, isFalse);

      // User interacts with scroll gesture
      lyricsController.onUserScroll();
      expect(lyricsController.isUserScrollLocked, isTrue);

      // After 3 seconds, lock is still active
      await tester.pump(const Duration(seconds: 3));
      expect(lyricsController.isUserScrollLocked, isTrue);

      // After 2 more seconds (total 5s), lock auto-resumes
      await tester.pump(const Duration(seconds: 2));
      expect(lyricsController.isUserScrollLocked, isFalse);
    });

    testWidgets('resumeAutoScroll cancels scroll lock immediately', (tester) async {
      lyricsController.onUserScroll();
      expect(lyricsController.isUserScrollLocked, isTrue);

      lyricsController.resumeAutoScroll();
      expect(lyricsController.isUserScrollLocked, isFalse);
    });

    test('changing tracks resets scroll lock', () async {
      lyricsController.onUserScroll();
      expect(lyricsController.isUserScrollLocked, isTrue);

      await playbackController.playTrack(trackWithoutLyrics);
      await pumpEventQueue(times: 20);

      expect(lyricsController.isUserScrollLocked, isFalse);
    });
  });
}
