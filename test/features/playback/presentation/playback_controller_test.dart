import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/constants/app_constants.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
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
  late PlaybackController controller;

  const track1 = Track(
    id: 1,
    uri: 'file:///music/song1.mp3',
    title: 'Song One',
    artist: 'Artist One',
    album: 'Album One',
    durationMs: 30000,
    fileSize: 1000000,
    modifiedAt: 1600000000,
  );

  const track2 = Track(
    id: 2,
    uri: 'file:///music/song2.mp3',
    title: 'Song Two',
    artist: 'Artist Two',
    album: 'Album Two',
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
    await db.insertOrUpdateTrack(track1);
    await db.insertOrUpdateTrack(track2);

    playerA = MockAudioPlayerAdapter(id: 'PlayerA');
    playerB = MockAudioPlayerAdapter(id: 'PlayerB');
    queueManager = QueueManager();
    engine = AudioEngineServiceImpl(
      playerA: playerA,
      playerB: playerB,
      queueManager: queueManager,
    );

    controller = PlaybackController(
      audioEngineService: engine,
      database: db,
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    controller.dispose();
    await engine.dispose();
    await db.close();
  });

  group('PlaybackController Initialization', () {
    test('initializes with default playback state', () {
      expect(controller.isPlaying, isFalse);
      expect(controller.currentTrack, isNull);
      expect(controller.queue, isEmpty);
      expect(controller.volume, equals(100.0));
      expect(controller.rate, equals(1.0));
      expect(controller.pitch, equals(1.0));
      expect(controller.loopMode, equals(Loop.off));
    });
  });

  group('PlaybackController Track Selection & Queueing', () {
    test('playTrack opens queue and initiates playback', () async {
      await controller.playTrack(track1);
      await pumpEventQueue();

      expect(controller.currentTrack?.uri, equals(track1.uri));
      expect(controller.queue.length, equals(1));
      expect(playerA.isPlaying, isTrue);
    });

    test('playAll loads multiple tracks into queue', () async {
      await controller.playAll([track1, track2], startIndex: 1);
      await pumpEventQueue();

      expect(controller.queue.length, equals(2));
      expect(controller.currentTrack?.uri, equals(track2.uri));
      expect(controller.currentIndex, equals(1));
    });

    test('playNext and addToQueue modify upcoming queue', () async {
      await controller.playTrack(track1);
      await pumpEventQueue();

      await controller.playNext(track2);
      await pumpEventQueue();

      expect(controller.queue.length, equals(2));
      expect(controller.queue[1].uri, equals(track2.uri));
    });
  });

  group('PlaybackController Transport Controls', () {
    setUp(() async {
      await controller.playTrack(track1);
      await pumpEventQueue();
    });

    test('playOrPause toggles pause and play states', () async {
      expect(controller.isPlaying, isTrue);

      await controller.playOrPause();
      await pumpEventQueue();
      expect(controller.isPlaying, isFalse);

      await controller.playOrPause();
      await pumpEventQueue();
      expect(controller.isPlaying, isTrue);
    });

    test('seek updates position', () async {
      await controller.seek(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(playerA.position, equals(const Duration(seconds: 10)));
    });

    test('setVolume, setRate, and setPitch delegate to audio engine', () async {
      await controller.setVolume(75.0);
      await controller.setRate(1.25);
      await controller.setPitch(0.9);
      await pumpEventQueue();

      expect(playerA.volume, equals(75.0));
      expect(playerA.rate, equals(1.25));
      expect(playerA.pitch, equals(0.9));
    });

    test('cycleLoopMode rotates through off -> all -> one -> off', () async {
      expect(controller.loopMode, equals(Loop.off));

      await controller.cycleLoopMode();
      await pumpEventQueue();
      expect(controller.loopMode, equals(Loop.all));

      await controller.cycleLoopMode();
      await pumpEventQueue();
      expect(controller.loopMode, equals(Loop.one));

      await controller.cycleLoopMode();
      await pumpEventQueue();
      expect(controller.loopMode, equals(Loop.off));
    });
  });

  group('PlaybackController History & Persistence', () {
    test('logs history to database when progress reaches 50%', () async {
      await controller.playTrack(track1);
      playerA.simulateDuration(const Duration(seconds: 30));
      await pumpEventQueue();

      final historyBefore = await db.getTracksForPlaylist(AppConstants.historyPlaylistId);
      expect(historyBefore, isEmpty);

      // Simulate playing past 50% (16 seconds of 30 seconds)
      playerA.simulatePosition(const Duration(seconds: 16));
      await pumpEventQueue();

      final historyAfter = await db.getTracksForPlaylist(AppConstants.historyPlaylistId);
      expect(historyAfter.length, equals(1));
      expect(historyAfter.first.title, equals('Song One'));
    });

    test('persists last played track URI and position to settings repository', () async {
      await controller.playTrack(track1);
      playerA.simulateDuration(const Duration(seconds: 30));
      playerA.simulatePosition(const Duration(seconds: 12));
      await pumpEventQueue();

      final settings = settingsRepo.getSettings();
      expect(settings.lastPlayedUri, equals(track1.uri));
      expect(settings.lastPlayedPositionMs, equals(12000));
    });
  });
}
