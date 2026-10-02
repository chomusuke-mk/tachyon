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
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

class _FakePlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = const Duration(seconds: 40);
  final Duration _duration = const Duration(seconds: 200);
  bool _isPlaying = true;
  final bool _isBuffering = false;
  bool _isShuffled = false;
  Loop _loopMode = Loop.off;
  double _volume = 80.0;
  double _rate = 1.0;
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
    } else {
      _queue = [];
      _currentIndex = 0;
    }
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

  void setPositionTick(Duration pos) {
    _position = pos;
    _positionNotifier.value = pos;
    // Pure position tick: do NOT call notifyListeners()
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
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
  Future<void> setVolume(double val) async {
    _volume = val;
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
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
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

class _TargetedTrackUriWidget extends StatelessWidget {
  static int buildCount = 0;

  const _TargetedTrackUriWidget();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final trackUri = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.uri,
    );
    return Text(trackUri ?? 'No Track');
  }
}

class _TargetedRateWidget extends StatelessWidget {
  static int buildCount = 0;

  const _TargetedRateWidget();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final rate = context.select<PlaybackController, double>((c) => c.rate);
    return Text('Rate: $rate');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlaybackController playbackController;
  late LocaleController localeController;
  late AppDatabase db;
  late LyricsController lyricsController;

  const sampleTrack = QueueItem(
    id: 'track_1',
    uri: '/music/synthwave.mp3',
    title: 'Neon Horizon',
    artist: 'Future City',
    album: 'Odyssey',
    duration: Duration(seconds: 180),
  );

  setUp(() async {
    playbackController = _FakePlaybackController();
    localeController = LocaleController(_FakeLocaleRepository(), 'en');
    await localeController.whenReady;
    db = AppDatabase.inMemory();

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
  });

  tearDown(() async {
    playbackController.dispose();
    lyricsController.dispose();
    await db.close();
  });

  group('Feature 13: Targeted Library Listeners (context.select)', () {
    testWidgets('Widget with context.select(uri) does NOT rebuild on positionNotifier ticks or rate changes', (
      WidgetTester tester,
    ) async {
      _TargetedTrackUriWidget.buildCount = 0;
      _TargetedRateWidget.buildCount = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<PlaybackController>.value(
          value: playbackController,
          child: const MaterialApp(
            home: Column(
              children: [
                _TargetedTrackUriWidget(),
                _TargetedRateWidget(),
              ],
            ),
          ),
        ),
      );

      expect(_TargetedTrackUriWidget.buildCount, equals(1));
      expect(_TargetedRateWidget.buildCount, equals(1));
      expect(find.text('No Track'), findsOneWidget);
      expect(find.text('Rate: 1.0'), findsOneWidget);

      // 1. Advance positionNotifier (high-frequency ticks)
      playbackController.setPositionTick(const Duration(seconds: 15));
      await tester.pump();

      // Neither widget should rebuild
      expect(_TargetedTrackUriWidget.buildCount, equals(1));
      expect(_TargetedRateWidget.buildCount, equals(1));

      // 2. Change rate: only _TargetedRateWidget should rebuild
      await playbackController.setRate(1.25);
      await tester.pump();

      expect(_TargetedTrackUriWidget.buildCount, equals(1),
          reason: 'Track URI widget must not rebuild when rate changes');
      expect(_TargetedRateWidget.buildCount, equals(2));
      expect(find.text('Rate: 1.25'), findsOneWidget);

      // 3. Set track: only _TargetedTrackUriWidget should rebuild
      playbackController.setTrack(sampleTrack);
      await tester.pump();

      expect(_TargetedTrackUriWidget.buildCount, equals(2));
      expect(_TargetedRateWidget.buildCount, equals(2),
          reason: 'Rate widget must not rebuild when track URI changes');
      expect(find.text('/music/synthwave.mp3'), findsOneWidget);
    });
  });

  group('Feature 14 & 16: Layer Isolation & Downsampled Backdrop in NowPlayingScreen', () {
    testWidgets('NowPlayingScreen isolates backdrop and hero art with RepaintBoundary and specifies 128x128 cache', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

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

      // Check for RepaintBoundary widgets in tree
      final repaintBoundaries = find.byType(RepaintBoundary);
      expect(repaintBoundaries, findsWidgets);

      // Verify downsampled AlbumArtImage in ambient backdrop (cacheWidth: 128, cacheHeight: 128)
      final albumArtImages = tester.widgetList<AlbumArtImage>(find.byType(AlbumArtImage));
      expect(albumArtImages, isNotEmpty);

      // At least one AlbumArtImage (the ambient backdrop) has cacheWidth: 128 and cacheHeight: 128
      final hasDownsampledBackdrop = albumArtImages.any(
        (img) => img.cacheWidth == 128 && img.cacheHeight == 128,
      );
      expect(hasDownsampledBackdrop, isTrue,
          reason: 'Ambient backdrop must downsample album art to 128x128 for GPU fill rate optimization');
    });
  });

  group('Feature 14: MiniPlayerBar Layer Isolation & Progress Decoupling', () {
    testWidgets('MiniPlayerBar root is wrapped in RepaintBoundary and contains internal RepaintBoundary for progress', (
      WidgetTester tester,
    ) async {
      playbackController.setTrack(sampleTrack);

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

      // Verify MiniPlayerBar widget is present
      final miniPlayerFinder = find.byType(MiniPlayerBar);
      expect(miniPlayerFinder, findsOneWidget);

      // Verify RepaintBoundary is used for composite layer isolation
      final repaints = find.descendant(
        of: miniPlayerFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaints, findsWidgets);

      // Verify LinearProgressIndicator is present and wrapped in RepaintBoundary
      final progressIndicatorFinder = find.byType(LinearProgressIndicator);
      expect(progressIndicatorFinder, findsOneWidget);

      final progressAncestorRepaint = find.ancestor(
        of: progressIndicatorFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(progressAncestorRepaint, findsWidgets);

      // Verify progress indicator updates when positionNotifier updates
      playbackController.setPositionTick(const Duration(seconds: 100));
      await tester.pump();

      final indicator = tester.widget<LinearProgressIndicator>(progressIndicatorFinder);
      expect(indicator.value, closeTo(0.5, 0.01));
    });
  });
}
