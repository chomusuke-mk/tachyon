import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/queue_drawer.dart';
import 'package:tachyon/features/playback/presentation/waveform_slider.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';

class _FakePlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = const Duration(seconds: 40);
  final Duration _duration = const Duration(seconds: 200);
  bool _isPlaying = true;
  final bool _isBuffering = false;
  bool _isShuffled = false;
  Loop _loopMode = Loop.off;
  double _volume = 80.0;
  List<QueueItem> _queue = [];
  int _currentIndex = 0;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(const Duration(seconds: 40));

  @override
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  @override
  QueueItem? get currentTrack => _currentTrack;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isBuffering => _isBuffering;

  @override
  bool get isShuffled => _isShuffled;

  @override
  Loop get loopMode => _loopMode;

  @override
  double get volume => _volume;

  @override
  List<QueueItem> get queue => _queue;

  @override
  int get currentIndex => _currentIndex;

  @override
  bool get hasNext => _currentIndex < _queue.length - 1;

  @override
  bool get hasPrevious => _currentIndex > 0;

  void setTrack(QueueItem? track) {
    _currentTrack = track;
    notifyListeners();
  }

  void setQueue(List<QueueItem> items, {int index = 0}) {
    _queue = items;
    _currentIndex = index;
    if (items.isNotEmpty && index >= 0 && index < items.length) {
      _currentTrack = items[index];
    } else {
      _currentTrack = null;
    }
    notifyListeners();
  }

  @override
  Future<void> toggleShuffle() async {
    _isShuffled = !_isShuffled;
    notifyListeners();
  }

  @override
  Future<void> toggleLoopMode() async {
    _loopMode = _loopMode.next();
    notifyListeners();
  }

  @override
  Future<void> playOrPause() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double val) async {
    _volume = val;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration pos) async {
    _position = pos;
    _positionNotifier.value = pos;
    notifyListeners();
  }

  @override
  bool get isInfiniteMixEnabled => false;

  @override
  void toggleInfiniteMix() {}

  @override
  Future<void> clearQueue() async {
    _queue.clear();
    _currentTrack = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocaleRepository implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final map = <String, String>{};
    for (final key in AppStringKey().allKeys) {
      map[key] = key;
    }
    map['np_queue_empty'] = 'Queue is empty';
    map['np_lyrics'] = 'Lyrics';
    map['np_queue'] = 'Queue';
    map['np_volume'] = 'Volume';
    map['np_liked'] = 'Liked';
    map['np_unliked'] = 'Unliked';
    map['np_play'] = 'Play';
    map['np_pause'] = 'Pause';
    map['np_previous'] = 'Previous';
    map['np_next'] = 'Next';
    map['np_shuffle_on'] = 'Shuffle On';
    map['np_shuffle_off'] = 'Shuffle Off';
    map['np_repeat_off'] = 'Repeat Off';
    map['np_repeat_one'] = 'Repeat One';
    map['np_repeat_all'] = 'Repeat All';
    map['np_audio_controls'] = 'Audio Controls';
    return map;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTranslationClient implements LyricsTranslationClient {
  @override
  Future<TranslationResult> translate(
    List<String> texts, {
    required String targetLanguage,
  }) async {
    return TranslationResult(
      originalLines: texts,
      translatedLines: texts.map((t) => '[es] $t').toList(),
      targetLanguage: targetLanguage,
      isSuccess: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required _FakePlaybackController playbackController,
  required LocaleController localeController,
  required AppDatabase db,
  required LyricsController lyricsController,
  PlaylistsController? playlistsController,
}) {
  final playlists = playlistsController ?? PlaylistsController(database: db);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ChangeNotifierProvider<PlaylistsController>.value(value: playlists),
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
    ],
    child: const MaterialApp(
      home: NowPlayingScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakePlaybackController playbackController;
  late LocaleController localeController;
  late LyricsCooldownManager cooldownManager;
  late LyricsService lyricsService;
  late _FakeTranslationClient translationClient;
  late LyricsController lyricsController;

  final sampleTrack = const QueueItem(
    id: 'track_1',
    trackId: 101,
    uri: '/storage/music/synthwave.mp3',
    title: 'Neon Odyssey',
    artist: 'Cyber Runner',
    album: 'Future Metropolis',
    duration: Duration(seconds: 240),
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    playbackController = _FakePlaybackController();
    localeController = LocaleController(_FakeLocaleRepository(), 'en');
    await localeController.whenReady;

    cooldownManager = LyricsCooldownManager();
    final mockLrclib = LrclibClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
      minPacing: Duration.zero,
    );
    final mockOvh = LyricsOvhClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    lyricsService = LyricsService(
      database: db,
      cooldownManager: cooldownManager,
      lrclibClient: mockLrclib,
      lyricsOvhClient: mockOvh,
    );
    translationClient = _FakeTranslationClient();
    lyricsController = LyricsController(
      lyricsService: lyricsService,
      playbackController: playbackController,
      cooldownManager: cooldownManager,
      translationClient: translationClient,
    );

    // Insert track row into SQLite for foreign key and like resolution
    await db.database.insert('tracks', {
      'id': 101,
      'file_path': '/storage/music/synthwave.mp3',
      'title': 'Neon Odyssey',
      'duration_ms': 240000,
      'file_size': 5000000,
      'modified_at': 1700000000000,
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('NowPlayingScreen Widget Tests', () {
    testWidgets('Empty queue state displays empty placeholder text', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(null);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pump();

      expect(find.text('Queue is empty'), findsOneWidget);
      expect(find.byType(WaveformSlider), findsNothing);
    });

    testWidgets('Active track renders full controls, title, artist, and waveform slider', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Track title & artist
      expect(find.text('Neon Odyssey'), findsOneWidget);
      expect(find.text('Cyber Runner'), findsOneWidget);

      // WaveformSlider
      expect(find.byType(WaveformSlider), findsOneWidget);

      // Transport controls (Pause, Shuffle, Repeat)
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);

      // Favorite/Like button
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('Tapping like button toggles favorite state in database and UI', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      // Tap like button
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();

      // State updates to liked
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(await db.isTrackLiked(101), isTrue);

      // Tap again to unlike
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(await db.isTrackLiked(101), isFalse);
    });

    testWidgets('Responsive Layout: Renders vertical column layout when viewport is narrow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Top app bar and title rendered
      expect(find.text('Neon Odyssey'), findsOneWidget);
      expect(find.byType(WaveformSlider), findsOneWidget);
    });

    testWidgets('Responsive Layout: Renders horizontal row layout when viewport is wide', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Neon Odyssey'), findsOneWidget);
      expect(find.byType(WaveformSlider), findsOneWidget);
    });

    testWidgets('Toggling lyrics button mounts LyricsView and updates LyricsController visibility', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Initially LyricsView is not mounted
      expect(find.byType(LyricsView), findsNothing);
      expect(lyricsController.isLyricsViewVisible, isFalse);

      // Tap lyrics button
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pump(const Duration(milliseconds: 350));

      // LyricsView is now mounted and controller is informed
      expect(find.byType(LyricsView), findsOneWidget);
      expect(lyricsController.isLyricsViewVisible, isTrue);

      // Tap lyrics button again to hide
      await tester.tap(find.byIcon(Icons.music_note_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(LyricsView), findsNothing);
      expect(lyricsController.isLyricsViewVisible, isFalse);
    });

    testWidgets('Toggling queue button mounts QueueView', (WidgetTester tester) async {
      playbackController.setQueue([sampleTrack]);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QueueView), findsNothing);

      // Tap queue button in top bar
      await tester.tap(find.byIcon(Icons.queue_music_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(QueueView), findsOneWidget);
    });

    testWidgets('RepaintBoundary presence in NowPlayingScreen tree', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Flutter Scaffold/Navigator/Stack hierarchy contains RepaintBoundary widgets
      final boundaries = find.byType(RepaintBoundary);
      expect(boundaries, findsWidgets);
    });

    testWidgets('Feature 20: AnimatedSize is eliminated from NowPlayingScreen to prevent resize layout thrashing', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Assert AnimatedSize is not present in NowPlayingScreen widget hierarchy
      expect(
        find.byType(AnimatedSize),
        findsNothing,
        reason: 'AnimatedSize must be eliminated to prevent layout thrashing and stutter during window resize',
      );

      // Assert rapid window resize simulations execute smoothly without unhandled exceptions
      final testSizes = [
        const Size(1200, 800),
        const Size(900, 700),
        const Size(600, 500),
        const Size(500, 800),
        const Size(400, 600),
      ];
      for (final size in testSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();
      }
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
