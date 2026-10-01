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
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/library/presentation/tracks_screen.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/waveform_slider.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

/// Fake PlaybackController designed for empirical stress-testing of
/// position decoupling and selective notification routing.
class _FakeChallengerPlaybackController extends ChangeNotifier
    implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(seconds: 100);
  bool _isPlaying = true;
  final bool _isBuffering = false;
  bool _isShuffled = false;
  Loop _loopMode = Loop.off;
  double _volume = 80.0;
  double _rate = 1.0;
  double _pitch = 1.0;
  List<QueueItem> _queue = [];
  int _currentIndex = 0;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);

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
  bool get isCompleted => false;

  @override
  bool get isShuffled => _isShuffled;

  @override
  Loop get loopMode => _loopMode;

  @override
  double get volume => _volume;

  @override
  double get rate => _rate;

  @override
  double get pitch => _pitch;

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
    if (track != null) {
      _queue = [track];
      _currentIndex = 0;
      _duration = track.duration;
    } else {
      _queue = [];
      _currentIndex = 0;
    }
    notifyListeners();
  }

  void setDuration(Duration d) {
    _duration = d;
    notifyListeners();
  }

  /// High-frequency position stream update (pure tick: zero notifyListeners)
  void setPositionTick(Duration pos) {
    _position = pos;
    _positionNotifier.value = pos;
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    notifyListeners();
  }

  @override
  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
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
  Future<void> playTrack(Track track, {List<Track>? contextTracks}) async {
    _currentTrack = QueueItem(
      id: track.id?.toString() ?? track.uri,
      uri: track.uri,
      title: track.title,
      artist: track.artist ?? '',
      album: track.album ?? '',
      duration: Duration(milliseconds: track.durationMs),
    );
    notifyListeners();
  }

  @override
  Future<void> playAll(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    _queue = tracks
        .map(
          (t) => QueueItem(
            id: t.id?.toString() ?? t.uri,
            uri: t.uri,
            title: t.title,
            artist: t.artist ?? '',
            album: t.album ?? '',
            duration: Duration(milliseconds: t.durationMs),
          ),
        )
        .toList();
    if (tracks.isNotEmpty && startIndex < tracks.length) {
      _currentTrack = _queue[startIndex];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocaleRepo implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final map = <String, String>{};
    for (final key in AppStringKey().allKeys) {
      map[key] = key;
    }
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

/// Canvas recording stub for verifying batched paths and geometry caching
class _RecordingCanvas extends Fake implements Canvas {
  final List<Path> recordedPaths = [];
  final List<Paint> recordedPaints = [];
  int drawPathCount = 0;
  int drawCircleCount = 0;

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCount++;
    recordedPaths.add(Path.from(path));
    recordedPaints.add(paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    drawCircleCount++;
  }
}

// -----------------------------------------------------------------------------
// Test helper widgets for tracking rebuilds with selective selectors
// -----------------------------------------------------------------------------
class _TrackUriSelectedWatcher extends StatelessWidget {
  final VoidCallback onBuild;
  const _TrackUriSelectedWatcher({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    final uri = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.uri,
    );
    return Text(uri ?? 'no_track');
  }
}

class _AudioEffectsSelectedWatcher extends StatelessWidget {
  final VoidCallback onBuild;
  const _AudioEffectsSelectedWatcher({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    final rate = context.select<PlaybackController, double>((c) => c.rate);
    final pitch = context.select<PlaybackController, double>((c) => c.pitch);
    final volume = context.select<PlaybackController, double>((c) => c.volume);
    return Text('rate:$rate pitch:$pitch vol:$volume');
  }
}

class _QueueSelectedWatcher extends StatelessWidget {
  final VoidCallback onBuild;
  const _QueueSelectedWatcher({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    final len = context.select<PlaybackController, int>((c) => c.queue.length);
    final idx = context.select<PlaybackController, int>((c) => c.currentIndex);
    final playing = context.select<PlaybackController, bool>((c) => c.isPlaying);
    return Text('len:$len idx:$idx playing:$playing');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChallengerPlaybackController playbackController;
  late LocaleController localeController;
  late Directory tempDir;
  late AppDatabase db;
  late CoverCacheService coverCacheService;
  late MetadataExtractor extractor;
  late LibraryController libraryController;
  late PlaylistsController playlistsController;
  late LyricsController lyricsController;

  const sampleTrack1 = Track(
    id: 1,
    uri: '/music/cyberpunk.mp3',
    title: 'Cyberpunk 2099',
    artist: 'Neon Rider',
    album: 'Night City',
    durationMs: 180000,
    fileSize: 4000000,
    modifiedAt: 1000,
  );

  const sampleTrack2 = Track(
    id: 2,
    uri: '/music/synthwave.mp3',
    title: 'Retro Sunset',
    artist: 'Synth Master',
    album: 'Neon Horizon',
    durationMs: 240000,
    fileSize: 5000000,
    modifiedAt: 1000,
  );

  final sampleQueueItem1 = QueueItem(
    id: '1',
    uri: sampleTrack1.uri,
    title: sampleTrack1.title,
    artist: sampleTrack1.artist ?? '',
    album: sampleTrack1.album ?? '',
    duration: Duration(milliseconds: sampleTrack1.durationMs),
  );

  final sampleQueueItem2 = QueueItem(
    id: '2',
    uri: sampleTrack2.uri,
    title: sampleTrack2.title,
    artist: sampleTrack2.artist ?? '',
    album: sampleTrack2.album ?? '',
    duration: Duration(milliseconds: sampleTrack2.durationMs),
  );

  setUp(() async {
    playbackController = _FakeChallengerPlaybackController();
    localeController = LocaleController(_FakeLocaleRepo(), 'en');
    await localeController.whenReady;

    tempDir = await Directory.systemTemp.createTemp('tachyon_challenger_m2_');
    db = AppDatabase.inMemory();
    coverCacheService = CoverCacheService(cacheDirectory: tempDir);
    await coverCacheService.init();

    extractor = MetadataExtractor(
      database: db,
      coverCacheService: coverCacheService,
    );
    libraryController = LibraryController(
      database: db,
      metadataExtractor: extractor,
      coverCacheService: coverCacheService,
    );
    playlistsController = PlaylistsController(database: db);

    final mockLrclib = LrclibClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
      minPacing: Duration.zero,
    );
    final mockOvh = LyricsOvhClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    final lyricsService = LyricsService(
      database: db,
      cooldownManager: LyricsCooldownManager(),
      lrclibClient: mockLrclib,
      lyricsOvhClient: mockOvh,
    );
    lyricsController = LyricsController(
      lyricsService: lyricsService,
      playbackController: playbackController,
      cooldownManager: LyricsCooldownManager(),
      translationClient: _FakeTranslationClient(),
    );

    // Insert sample tracks into DB and load into library
    await db.batchInsertTracks([sampleTrack1, sampleTrack2]);
    await libraryController.loadLibrary();
  });

  tearDown(() async {
    playbackController.dispose();
    lyricsController.dispose();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    WaveformSlider.clearGeometryCache();
  });

  // ===========================================================================
  // Feature 15: WaveformSlider Painter Optimization & Quantization
  // ===========================================================================
  group('Feature 15 Empirical Verification: WaveformSlider Painter Optimization', () {
    testWidgets('shouldRepaint returns false when position delta is within 50ms bucket and within the same bar', (
      WidgetTester tester,
    ) async {
      final positionNotifier = ValueNotifier<Duration>(const Duration(milliseconds: 1000));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: WaveformSlider(
                position: const Duration(milliseconds: 1000),
                positionListenable: positionNotifier,
                duration: const Duration(seconds: 100),
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint1 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter1 = customPaint1.painter!;

      // Advance by 20ms: 1000ms ~/ 50 == 20, 1020ms ~/ 50 == 20
      // For 100s duration with 55 bars (54 intervals), 1 bar interval = 1851.85ms
      // Both 1000ms and 1020ms map to bar 0 ((1000/100000*54).floor() == 0)
      positionNotifier.value = const Duration(milliseconds: 1020);
      await tester.pump();

      final customPaint2 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter2 = customPaint2.painter!;

      expect(
        painter2.shouldRepaint(painter1),
        isFalse,
        reason: 'Within the same 50ms bucket and same active bar, shouldRepaint MUST return false',
      );

      // Advance by another 15ms (1035ms, still in bucket 20)
      positionNotifier.value = const Duration(milliseconds: 1035);
      await tester.pump();

      final customPaint3 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter3 = customPaint3.painter!;

      expect(
        painter3.shouldRepaint(painter2),
        isFalse,
        reason: 'Delta of 15ms within bucket 20 must not trigger repaint',
      );
    });

    testWidgets('shouldRepaint returns true when crossing 50ms bucket boundary', (
      WidgetTester tester,
    ) async {
      final positionNotifier = ValueNotifier<Duration>(const Duration(milliseconds: 1020));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: WaveformSlider(
                position: const Duration(milliseconds: 1020),
                positionListenable: positionNotifier,
                duration: const Duration(seconds: 100),
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint1 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter1 = customPaint1.painter!;

      // Advance from 1020ms (bucket 20) to 1055ms (bucket 21)
      positionNotifier.value = const Duration(milliseconds: 1055);
      await tester.pump();

      final customPaint2 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter2 = customPaint2.painter!;

      expect(
        painter2.shouldRepaint(painter1),
        isTrue,
        reason: 'Crossing the 50ms bucket boundary (bucket 20 -> 21) MUST return true',
      );
    });

    testWidgets('shouldRepaint returns true when crossing active bar boundary even within same 50ms bucket', (
      WidgetTester tester,
    ) async {
      // Craft duration such that a bar boundary falls inside a single 50ms bucket:
      // Bar count = 55 -> 54 intervals.
      // Let duration = 54 * 1020ms = 55,080ms.
      // Bar 0 -> Bar 1 boundary occurs exactly at 1020.0ms.
      // Bucket 20 covers [1000ms .. 1049ms].
      // At 1015ms: bucket = 20, bar = (1015 / 55080 * 54).floor() = 0.
      // At 1025ms: bucket = 20, bar = (1025 / 55080 * 54).floor() = 1.
      final positionNotifier = ValueNotifier<Duration>(const Duration(milliseconds: 1015));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: WaveformSlider(
                position: const Duration(milliseconds: 1015),
                positionListenable: positionNotifier,
                duration: const Duration(milliseconds: 55080),
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint1 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter1 = customPaint1.painter!;

      // Advance by 10ms from 1015ms to 1025ms (both are within 50ms bucket 20)
      positionNotifier.value = const Duration(milliseconds: 1025);
      await tester.pump();

      final customPaint2 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter2 = customPaint2.painter!;

      expect(
        painter2.shouldRepaint(painter1),
        isTrue,
        reason: 'Active bar transition (bar 0 -> 1) MUST trigger repaint even when within same 50ms bucket',
      );
    });

    testWidgets('shouldRepaint returns true on any position change when isDragging == true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byType(GestureDetector).first;
      final center = tester.getCenter(gestureFinder);

      // Start horizontal drag: move past kTouchSlop (18.0) to activate drag recognizer
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(25.0, 0));
      await tester.pump();

      final customPaintDrag1 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painterDrag1 = customPaintDrag1.painter!;

      // Move by an additional tiny delta (1 pixel horizontally)
      await gesture.moveBy(const Offset(1.0, 0));
      await tester.pump();

      final customPaintDrag2 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painterDrag2 = customPaintDrag2.painter!;

      expect(
        painterDrag2.shouldRepaint(painterDrag1),
        isTrue,
        reason: 'During active dragging, quantization MUST be bypassed to give responsive scrubbing feedback',
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('Cached geometry _cachedBars invariance when size is unchanged', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: WaveformSlider(
                position: const Duration(seconds: 5),
                duration: const Duration(seconds: 100),
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter = customPaint.painter!;

      WaveformSlider.clearGeometryCache();

      final canvas1 = _RecordingCanvas();
      const testSize = Size(400, 38);

      // 1. Initial paint populates _cachedBars
      painter.paint(canvas1, testSize);
      expect(canvas1.drawPathCount, inInclusiveRange(1, 3));
      final initialPathBounds = canvas1.recordedPaths.map((p) => p.getBounds()).toList();

      // 2. Subsequent paints with identical size reuse _cachedBars
      final canvas2 = _RecordingCanvas();
      painter.paint(canvas2, testSize);
      expect(canvas2.drawPathCount, inInclusiveRange(1, 3));
      final secondPathBounds = canvas2.recordedPaths.map((p) => p.getBounds()).toList();

      expect(
        secondPathBounds.length,
        equals(initialPathBounds.length),
        reason: 'Path structure must be identical when size is unchanged',
      );
      for (int i = 0; i < initialPathBounds.length; i++) {
        expect(secondPathBounds[i], equals(initialPathBounds[i]));
      }

      // 3. Size change invalidation: Size(500, 38) alters bar positions and bounds
      final canvas3 = _RecordingCanvas();
      const newSize = Size(500, 38);
      painter.paint(canvas3, newSize);
      final newPathBounds = canvas3.recordedPaths.map((p) => p.getBounds()).toList();

      expect(
        newPathBounds.last.width,
        isNot(equals(initialPathBounds.last.width)),
        reason: 'Altering width must invalidate cached bar geometry and update layout',
      );

      // 4. Batched drawing assertion: Canvas.drawPath called at most 3 times (never 55 times)
      expect(
        canvas1.drawPathCount,
        lessThanOrEqualTo(3),
        reason: 'WaveformSlider MUST batch bar rendering into at most 3 path draw calls',
      );
      expect(
        canvas2.drawPathCount,
        lessThanOrEqualTo(3),
        reason: 'WaveformSlider MUST batch bar rendering into at most 3 path draw calls',
      );
    });

    testWidgets('Microbenchmark: cached geometry paint is significantly faster than uncached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: WaveformSlider(
                position: const Duration(seconds: 10),
                duration: const Duration(seconds: 100),
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter = customPaint.painter!;
      const testSize = Size(400, 38);
      final canvas = _RecordingCanvas();

      // Warmup and seed cache
      WaveformSlider.clearGeometryCache();
      painter.paint(canvas, testSize);

      const iterations = 5000;

      // 1. Benchmark cached paint (zero RRect allocations)
      final swCached = Stopwatch()..start();
      for (int i = 0; i < iterations; i++) {
        painter.paint(canvas, testSize);
      }
      swCached.stop();

      // 2. Benchmark uncached paint (clears cache each time -> forces 55 RRect allocations)
      final swUncached = Stopwatch()..start();
      for (int i = 0; i < iterations; i++) {
        WaveformSlider.clearGeometryCache();
        painter.paint(canvas, testSize);
      }
      swUncached.stop();

      // Empirical proof: cached throughput must outperform uncached allocation loop
      expect(
        swCached.elapsedMicroseconds,
        lessThanOrEqualTo(swUncached.elapsedMicroseconds),
        reason: 'Cached geometry loop must be faster than or equal to continuous RRect generation',
      );
    });
  });

  // ===========================================================================
  // Feature 13: Targeted Library Listeners & Screen Rebuild Suppression
  // ===========================================================================
  group('Feature 13 Empirical Verification: Targeted Library Listeners (context.select)', () {
    testWidgets('Emitting 50 position ticks does NOT cause TracksScreen to rebuild', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleQueueItem1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<LibraryController>.value(value: libraryController),
            ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
          ],
          child: const MaterialApp(
            home: TracksScreen(),
          ),
        ),
      );

      // Verify TracksScreen is mounted and displays track titles
      expect(find.byType(TracksScreen), findsOneWidget);
      expect(find.text('Cyberpunk 2099'), findsOneWidget);
      expect(find.text('Retro Sunset'), findsOneWidget);

      final tracksScreenElement = tester.element(find.byType(TracksScreen));
      expect(tracksScreenElement.dirty, isFalse);

      // 1. Emit 50 rapid position ticks (simulating 1-2 seconds of high-frequency playback)
      for (int i = 1; i <= 50; i++) {
        playbackController.setPositionTick(Duration(milliseconds: i * 25));
      }

      // Assert that position ticks do NOT mark TracksScreen dirty
      expect(
        tracksScreenElement.dirty,
        isFalse,
        reason: 'Position ticks must NOT mark TracksScreen dirty',
      );

      // Pump to ensure no scheduled frames were queued
      await tester.pump();
      expect(
        tracksScreenElement.dirty,
        isFalse,
        reason: 'TracksScreen element must remain clean after pumping position ticks',
      );

      // 2. Adjust volume or playback rate (calls notifyListeners(), but currentTrack.uri is unchanged)
      await playbackController.setRate(1.25);
      await playbackController.setVolume(90.0);

      // Provider's context.select checks (c) => c.currentTrack?.uri; since URI has not changed,
      // TracksScreen must NOT be marked dirty.
      expect(
        tracksScreenElement.dirty,
        isFalse,
        reason: 'Rate and volume adjustments must NOT trigger rebuild of TracksScreen (context.select uri)',
      );

      await tester.pump();
      expect(tracksScreenElement.dirty, isFalse);

      // 3. Transition to a different track (URI changes)
      playbackController.setTrack(sampleQueueItem2);
      await tester.pump();

      // Verify that TrackTile for track 2 now has isPlaying == true and track 1 is false
      final track2Tile = tester.widget<TrackTile>(
        find.byKey(ValueKey(sampleTrack2.uri)),
      );
      expect(track2Tile.isPlaying, isTrue);

      final track1Tile = tester.widget<TrackTile>(
        find.byKey(ValueKey(sampleTrack1.uri)),
      );
      expect(track1Tile.isPlaying, isFalse);
    });

    testWidgets('Comprehensive matrix test: selective listeners decouple position ticks from all screens', (
      WidgetTester tester,
    ) async {
      int uriBuilds = 0;
      int effectsBuilds = 0;
      int queueBuilds = 0;

      playbackController.setTrack(sampleQueueItem1);

      await tester.pumpWidget(
        ChangeNotifierProvider<PlaybackController>.value(
          value: playbackController,
          child: MaterialApp(
            home: Column(
              children: [
                _TrackUriSelectedWatcher(onBuild: () => uriBuilds++),
                _AudioEffectsSelectedWatcher(onBuild: () => effectsBuilds++),
                _QueueSelectedWatcher(onBuild: () => queueBuilds++),
              ],
            ),
          ),
        ),
      );

      // Initial build count is 1 for each
      expect(uriBuilds, equals(1));
      expect(effectsBuilds, equals(1));
      expect(queueBuilds, equals(1));

      // 1. Emit 100 position ticks
      for (int i = 0; i < 100; i++) {
        playbackController.setPositionTick(Duration(milliseconds: i * 20));
      }
      await tester.pump();

      // None of the selective listeners should rebuild on position ticks
      expect(uriBuilds, equals(1), reason: 'Track URI watcher must not rebuild on position ticks');
      expect(effectsBuilds, equals(1), reason: 'Audio effects watcher must not rebuild on position ticks');
      expect(queueBuilds, equals(1), reason: 'Queue watcher must not rebuild on position ticks');

      // 2. Update audio effects (rate/pitch/volume)
      await playbackController.setRate(1.5);
      await tester.pump();

      expect(uriBuilds, equals(1), reason: 'Track URI watcher must not rebuild on rate change');
      expect(effectsBuilds, equals(2), reason: 'Audio effects watcher MUST rebuild on rate change');
      expect(queueBuilds, equals(1), reason: 'Queue watcher must not rebuild on rate change');

      // 3. Update track URI
      playbackController.setTrack(sampleQueueItem2);
      await tester.pump();

      expect(uriBuilds, equals(2), reason: 'Track URI watcher MUST rebuild on track URI change');
      expect(effectsBuilds, equals(2), reason: 'Audio effects watcher must not rebuild on track URI change');
      expect(
        queueBuilds,
        equals(1),
        reason: 'Queue watcher must not rebuild when length, index, and playing status are unchanged',
      );

      // 4. Toggle play/pause (modifies isPlaying)
      await playbackController.playOrPause();
      await tester.pump();

      expect(uriBuilds, equals(2), reason: 'Track URI watcher must not rebuild on play/pause');
      expect(effectsBuilds, equals(2), reason: 'Audio effects watcher must not rebuild on play/pause');
      expect(queueBuilds, equals(2), reason: 'Queue watcher MUST rebuild when isPlaying toggles');
    });
  });

  // ===========================================================================
  // Feature 14: RepaintBoundary Composite Layer Isolation
  // ===========================================================================
  group('Feature 14 Empirical Verification: RepaintBoundary Layer Isolation', () {
    testWidgets('WaveformSlider, _buildAmbientBackdrop, and _buildHeroCoverArt are wrapped in RepaintBoundaries', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleQueueItem1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
          ],
          child: const MaterialApp(
            home: NowPlayingScreen(),
          ),
        ),
      );

      // 1. WaveformSlider RepaintBoundary verification
      final waveformFinder = find.byType(WaveformSlider);
      expect(waveformFinder, findsOneWidget);

      final waveformAncestorRepaint = find.ancestor(
        of: waveformFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        waveformAncestorRepaint,
        findsWidgets,
        reason: 'WaveformSlider MUST be wrapped in a RepaintBoundary in NowPlayingScreen',
      );

      // Internal isolation: WaveformSlider has internal RepaintBoundary around CustomPaint
      final waveformInternalRepaint = find.descendant(
        of: waveformFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        waveformInternalRepaint,
        findsWidgets,
        reason: 'WaveformSlider MUST contain internal RepaintBoundary for painter isolation',
      );

      // 2. Ambient Backdrop RepaintBoundary verification
      final backdropFilterFinder = find.byType(ImageFiltered);
      expect(backdropFilterFinder, findsOneWidget);

      final backdropRepaintAncestor = find.ancestor(
        of: backdropFilterFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        backdropRepaintAncestor,
        findsWidgets,
        reason: 'Ambient backdrop (_buildAmbientBackdrop) MUST be wrapped in a RepaintBoundary',
      );

      // 3. Hero Cover Art RepaintBoundary verification
      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && (w.tag as String).startsWith('now_playing_art_'),
      );
      expect(heroFinder, findsOneWidget);

      final heroAncestorRepaint = find.ancestor(
        of: heroFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        heroAncestorRepaint,
        findsWidgets,
        reason: 'Hero cover art (_buildHeroCoverArt) MUST be wrapped in a RepaintBoundary',
      );
    });

    testWidgets('MiniPlayerBar root and internal progress indicator are wrapped in RepaintBoundaries', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleQueueItem1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: MiniPlayerBar(isDesktop: false),
            ),
          ),
        ),
      );

      final miniPlayerFinder = find.byType(MiniPlayerBar);
      expect(miniPlayerFinder, findsOneWidget);

      // Root RepaintBoundary
      final miniPlayerRootRepaint = find.descendant(
        of: miniPlayerFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        miniPlayerRootRepaint,
        findsWidgets,
        reason: 'MiniPlayerBar MUST contain a RepaintBoundary at root for shell layer isolation',
      );

      // Progress bar RepaintBoundary
      final progressFinder = find.descendant(
        of: miniPlayerFinder,
        matching: find.byType(LinearProgressIndicator),
      );
      expect(progressFinder, findsOneWidget);

      final progressAncestorRepaint = find.ancestor(
        of: progressFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(
        progressAncestorRepaint,
        findsWidgets,
        reason: 'LinearProgressIndicator inside MiniPlayerBar MUST be wrapped in a RepaintBoundary',
      );
    });
  });

  // ===========================================================================
  // Feature 16: Ambient Backdrop Downsampling
  // ===========================================================================
  group('Feature 16 Empirical Verification: Ambient Backdrop Downsampling', () {
    testWidgets('AlbumArtImage in _buildAmbientBackdrop receives cacheWidth: 128 and cacheHeight: 128', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleQueueItem1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
          ],
          child: const MaterialApp(
            home: NowPlayingScreen(),
          ),
        ),
      );

      // Find the AlbumArtImage in the ambient backdrop
      final backdropFilterFinder = find.byType(ImageFiltered);
      expect(backdropFilterFinder, findsOneWidget);

      final backdropStackFinder = find.ancestor(
        of: backdropFilterFinder,
        matching: find.byType(Stack),
      );
      expect(backdropStackFinder, findsWidgets);

      final backdropAlbumArtFinder = find.descendant(
        of: backdropStackFinder.first,
        matching: find.byType(AlbumArtImage),
      );
      expect(backdropAlbumArtFinder, findsOneWidget);

      final backdropAlbumArt = tester.widget<AlbumArtImage>(backdropAlbumArtFinder);
      expect(
        backdropAlbumArt.cacheWidth,
        equals(128),
        reason: 'Ambient backdrop AlbumArtImage MUST set cacheWidth: 128 to minimize decode memory',
      );
      expect(
        backdropAlbumArt.cacheHeight,
        equals(128),
        reason: 'Ambient backdrop AlbumArtImage MUST set cacheHeight: 128 to minimize decode memory',
      );

      // Contrast check: Hero cover art must NOT have hardcoded 128x128 (preserves full resolution)
      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && (w.tag as String).startsWith('now_playing_art_'),
      );
      final heroAlbumArtFinder = find.descendant(
        of: heroFinder,
        matching: find.byType(AlbumArtImage),
      );
      expect(heroAlbumArtFinder, findsOneWidget);

      final heroAlbumArt = tester.widget<AlbumArtImage>(heroAlbumArtFinder);
      expect(
        heroAlbumArt.cacheWidth,
        isNull,
        reason: 'Hero cover art should not be hardcoded to 128x128; it uses DPR scaled default downsampling',
      );
      expect(
        heroAlbumArt.cacheHeight,
        isNull,
        reason: 'Hero cover art should not be hardcoded to 128x128; it uses DPR scaled default downsampling',
      );
    });
  });
}
