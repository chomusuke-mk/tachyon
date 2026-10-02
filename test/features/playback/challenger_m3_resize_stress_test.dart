import 'dart:io';

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
  Future<void> next() async {
    if (hasNext) {
      _currentIndex++;
      _currentTrack = _queue[_currentIndex];
      notifyListeners();
    }
  }

  @override
  Future<void> previous() async {
    if (hasPrevious) {
      _currentIndex--;
      _currentTrack = _queue[_currentIndex];
      notifyListeners();
    }
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
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
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

  final sampleTrack1 = const QueueItem(
    id: 'track_1',
    trackId: 101,
    uri: '/storage/music/synthwave.mp3',
    title: 'Neon Odyssey',
    artist: 'Cyber Runner',
    album: 'Future Metropolis',
    duration: Duration(seconds: 240),
  );

  final sampleTrack2 = const QueueItem(
    id: 'track_2',
    trackId: 102,
    uri: '/storage/music/retrowave.mp3',
    title: 'Digital Sunset',
    artist: 'Laser Velocity',
    album: 'Grid Horizon',
    duration: Duration(seconds: 195),
  );

  final sampleTrack3 = const QueueItem(
    id: 'track_3',
    trackId: 103,
    uri: '/storage/music/ambient.mp3',
    title: 'Starlight Echoes',
    artist: 'Nebula Dreamer',
    album: 'Deep Cosmos',
    duration: Duration(seconds: 310),
  );

  // 26 arbitrary real-world & boundary viewports (480x360 min constraint up to 4K UHD)
  final testDimensions = [
    const Size(480, 360),   // GTK minimum geometry hint boundary
    const Size(500, 380),   // Just above minimum
    const Size(580, 360),   // Horizontal boundary check
    const Size(587, 360),   // 1px below 588 breakpoint
    const Size(588, 360),   // Exact 588 split layout breakpoint
    const Size(589, 400),   // Near horizontal / vertical thresholds
    const Size(590, 400),   // Exact boundary (canFitHorizontally > 590, canFitVertically > 400)
    const Size(591, 401),   // 1px above both thresholds
    const Size(480, 800),   // Narrow vertical phone / split tiling
    const Size(480, 1080),  // Ultra-tall vertical split window
    const Size(640, 480),   // Classic VGA
    const Size(720, 480),   // NTSC 480p
    const Size(800, 600),   // SVGA
    const Size(1024, 768),  // XGA standard desktop
    const Size(1280, 720),  // 720p HD default window size
    const Size(1280, 800),  // WXGA 16:10
    const Size(1366, 768),  // FWXGA common laptop
    const Size(1440, 900),  // MacBook WXGA+
    const Size(1600, 900),  // HD+
    const Size(1680, 1050), // WSXGA+
    const Size(1920, 1080), // 1080p FHD
    const Size(1920, 1200), // WUXGA
    const Size(2560, 1440), // 2K QHD
    const Size(2560, 1600), // WQXGA
    const Size(3440, 1440), // UWQHD Ultrawide
    const Size(3840, 2160), // 4K UHD
  ];

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

    // Populate SQLite test rows
    for (final track in [sampleTrack1, sampleTrack2, sampleTrack3]) {
      await db.database.insert('tracks', {
        'id': track.trackId,
        'file_path': track.filePath,
        'title': track.title,
        'duration_ms': track.duration.inMilliseconds,
        'file_size': 5000000,
        'modified_at': 1700000000000,
      });
    }

    playbackController.setQueue([sampleTrack1, sampleTrack2, sampleTrack3], index: 0);
  });

  tearDown(() async {
    await db.close();
  });

  group('Milestone 3 / Feature 20 Empirical Stress Tests', () {
    test('AST & Source Inspection: AnimatedSize is 100% eliminated from NowPlayingScreen and related files', () {
      final file = File('lib/features/playback/presentation/now_playing_screen.dart');
      expect(file.existsSync(), isTrue, reason: 'now_playing_screen.dart must exist');
      final source = file.readAsStringSync();
      expect(
        source.contains('AnimatedSize'),
        isFalse,
        reason: 'now_playing_screen.dart must not contain AnimatedSize references to avoid layout thrashing during resize',
      );
    });

    testWidgets('Widget Tree Assertion: AnimatedSize is 0 in all modes (Cover, Lyrics, Queue, Empty)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Cover Art View (Wide)
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in Cover Art view');

      // 2. Lyrics View (Wide)
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(LyricsView), findsOneWidget);
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in Lyrics view');

      // 3. Queue View (Wide)
      await tester.tap(find.byIcon(Icons.queue_music_rounded));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(QueueView), findsOneWidget);
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in Queue view');

      // 4. Narrow Viewport (480x800)
      tester.view.physicalSize = const Size(480, 800);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in narrow viewport');

      // 5. Minimal Fallback Viewport (480x360)
      tester.view.physicalSize = const Size(480, 360);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in fallback compact viewport');

      // 6. Empty Queue State
      playbackController.setTrack(null);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AnimatedSize), findsNothing, reason: 'AnimatedSize must not exist in empty queue state');

      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('Aggressive Viewport Resizing: 26 arbitrary resolutions in rapid succession (Ascending, Descending, Chaotic)', (
      WidgetTester tester,
    ) async {
      final List<FlutterErrorDetails> caughtErrors = [];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtErrors.add(details);
      };

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Pass 1: Ascending sweep through all 26 dimensions with rapid 16ms animation frame ticks
      for (final dim in testDimensions) {
        tester.view.physicalSize = dim;
        tester.view.devicePixelRatio = 1.0;
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'Failed during ascending resize to ${dim.width}x${dim.height}');
      }
      await tester.pumpAndSettle();

      // Pass 2: Descending sweep through all 26 dimensions
      for (final dim in testDimensions.reversed) {
        tester.view.physicalSize = dim;
        tester.view.devicePixelRatio = 1.0;
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'Failed during descending resize to ${dim.width}x${dim.height}');
      }
      await tester.pumpAndSettle();

      // Pass 3: High-entropy chaotic jumps across contrasting aspect ratios and extremes
      final chaoticSequence = [
        const Size(3840, 2160), // 4K UHD
        const Size(480, 360),   // Min GTK
        const Size(3440, 1440), // 21:9 Ultrawide
        const Size(587, 360),   // Sub-split
        const Size(1920, 1080), // 1080p
        const Size(480, 1080),  // Ultra-tall vertical
        const Size(590, 400),   // Boundary
        const Size(2560, 1440), // 2K QHD
        const Size(588, 360),   // Exact split
        const Size(1280, 720),  // Default HD
        const Size(591, 401),   // Above boundary
        const Size(800, 600),   // 4:3 SVGA
      ];

      for (final dim in chaoticSequence) {
        tester.view.physicalSize = dim;
        tester.view.devicePixelRatio = 1.0;
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'Failed during chaotic resize jump to ${dim.width}x${dim.height}');
      }
      await tester.pumpAndSettle();

      FlutterError.onError = oldOnError;
      expect(caughtErrors, isEmpty, reason: 'RenderFlex or layout errors caught during rapid resizing: $caughtErrors');

      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('Device Pixel Ratio / HiDPI Scaling resilience across resolutions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Logical sizes >= 480x360 scaled by DPR to test layout rendering
      final dpiTestMatrix = [
        (const Size(480, 360), 1.0),
        (const Size(600, 450), 1.25), // 480x360 logical @ 1.25 DPR
        (const Size(720, 540), 1.5),  // 480x360 logical @ 1.5 DPR
        (const Size(1280, 720), 1.0),
        (const Size(1600, 900), 1.25),
        (const Size(1920, 1080), 1.5),
        (const Size(2560, 1440), 2.0),
        (const Size(3840, 2160), 2.0),
      ];

      for (final (size, dpr) in dpiTestMatrix) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = dpr;
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'DPI scaling failure at $size with dpr=$dpr');
      }
      await tester.pumpAndSettle();

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('Sub-300px logical height failure probe: exposes RenderFlex overflow boundary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Physical size 480x360 with DPR 1.25 yields logical height of 288px.
      // This test isolates and empirically records whether RenderFlex overflows at sub-300px logical height.
      final List<FlutterErrorDetails> overflowErrors = [];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        overflowErrors.add(details);
      };

      tester.view.physicalSize = const Size(480, 360);
      tester.view.devicePixelRatio = 1.25; // Logical: 384x288
      await tester.pump(const Duration(milliseconds: 32));

      FlutterError.onError = oldOnError;

      // Document whether overflow occurs when window logical height drops below content intrinsic height
      final hasOverflow = overflowErrors.any((e) => e.toString().contains('RenderFlex overflowed'));
      expect(
        hasOverflow,
        isTrue,
        reason: 'Empirical confirmation: NowPlayingScreen lacks a vertical scrollable fallback when logical height < 300px, overflowing by ~14px',
      );

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('View switching under AnimatedSwitcher maintains clean transitions without infinite loop', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: Cover art displayed
      expect(find.byKey(const ValueKey('cover_art_view')), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);
      expect(find.byType(QueueView), findsNothing);
      expect(lyricsController.isLyricsViewVisible, isFalse);

      // Switch to Lyrics
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(LyricsView), findsOneWidget);
      expect(lyricsController.isLyricsViewVisible, isTrue);

      // Switch to Queue
      await tester.tap(find.byIcon(Icons.queue_music_rounded));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(QueueView), findsOneWidget);

      // Toggle Queue off -> returns to Lyrics
      await tester.tap(find.byIcon(Icons.queue_music_rounded));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(LyricsView), findsOneWidget);
      expect(lyricsController.isLyricsViewVisible, isTrue);

      // Toggle Lyrics off -> returns to Cover Art
      await tester.tap(find.byIcon(Icons.music_note_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('cover_art_view')), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);
      expect(lyricsController.isLyricsViewVisible, isFalse);
    });

    testWidgets('CRITICAL BUG REPRODUCTION: Duplicate key crash in AnimatedSwitcher during in-flight resize across 588px breakpoint', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      final List<FlutterErrorDetails> duplicateKeyErrors = [];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        duplicateKeyErrors.add(details);
      };

      // 1. User starts on wide viewport with cover art (outer AnimatedSwitcher has child key: 'player_only')
      expect(find.byKey(const ValueKey('cover_art_view')), findsOneWidget);

      // 2. User taps Lyrics: transition begins from 'player_only' (outgoing) to 'lyrics_and_player' (incoming)
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pump(const Duration(milliseconds: 50)); // 50ms into 300ms transition

      // 3. User resizes window across 588px breakpoint to narrow (500x700).
      // NowPlayingScreen's build method evaluates `currentWidth >= 588 && _showLyrics` to FALSE,
      // and falls back to `_buildPlayer(key: const ValueKey('player_only'))`.
      // AnimatedSwitcher's Stack now receives incoming 'player_only' while outgoing 'player_only' is still animating!
      tester.view.physicalSize = const Size(500, 700);
      await tester.pump(const Duration(milliseconds: 50));

      // 4. User resizes back to wide (1280x720) while animations are still in flight
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pump(const Duration(milliseconds: 50));

      FlutterError.onError = oldOnError;

      // Assert that AnimatedSwitcher does NOT crash with duplicate keys during in-flight resize
      final hasDuplicateKeyCrash = duplicateKeyErrors.any(
        (e) => e.toString().contains('Duplicate keys found') && e.toString().contains('player_only'),
      );

      expect(
        hasDuplicateKeyCrash,
        isFalse,
        reason: 'AnimatedSwitcher must not crash with duplicate key [player_only] '
            'when resizing across the 588px breakpoint during an in-flight view transition.',
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Playback state events during window resizing at fixed layout modes', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          playbackController: playbackController,
          localeController: localeController,
          db: db,
          lyricsController: lyricsController,
        ),
      );
      await tester.pumpAndSettle();

      final sizes = [
        const Size(1920, 1080),
        const Size(1366, 768),
        const Size(1280, 720),
        const Size(1024, 768),
        const Size(800, 600),
        const Size(640, 480),
      ];

      for (var i = 0; i < sizes.length; i++) {
        tester.view.physicalSize = sizes[i];
        if (i % 2 == 0) {
          await playbackController.playOrPause();
        }
        await playbackController.seek(Duration(seconds: 10 * (i + 1)));
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(WaveformSlider), findsOneWidget);
    });
  });
}
