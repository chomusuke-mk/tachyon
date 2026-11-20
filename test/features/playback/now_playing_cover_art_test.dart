import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/audio_effects_sheet.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/now_playing_cover_art.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_mode.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_renderer.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/reactive_circle_visualizer.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/spectrum_bars_visualizer.dart';
import 'package:tachyon/features/playback/presentation/widgets/wave_visualizer.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

class _MockLocaleRepo extends LocaleRepository {
  final Map<String, String> strings;
  _MockLocaleRepo(this.strings);

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => strings;
}

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({
    required super.settingsRepository,
  });

  Track? _mockTrack;
  double _mockAmplitude = 0.0;
  bool _mockIsPlaying = false;
  bool mockHasNext = true;
  bool mockHasPrevious = true;
  int nextCallCount = 0;
  int previousCallCount = 0;
  int seekCallCount = 0;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  @override
  bool get isPlaying => _mockTrack != null ? _mockIsPlaying : super.isPlaying;

  @override
  double get currentVisualAmplitude => _mockAmplitude;

  @override
  bool get hasNext => mockHasNext;

  @override
  bool get hasPrevious => mockHasPrevious;

  @override
  Future<void> next() async {
    nextCallCount++;
  }

  @override
  Future<void> previous() async {
    previousCallCount++;
  }

  @override
  Future<void> seek(Duration pos) async {
    seekCallCount++;
  }

  void setMockTrack(Track? track, {bool isPlaying = true}) {
    _mockTrack = track;
    _mockIsPlaying = isPlaying;
    notifyListeners();
  }

  void setMockVisualAmplitude(double amplitude) {
    _mockAmplitude = amplitude;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late AppDatabase db;
  late SharedPreferences prefs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late _TestPlaybackController playbackController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    final enJson = await File('i18n/en.jsonc').readAsString();
    final enMap = (jsoncDecode(enJson) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v.toString()),
    );

    localeController = LocaleController(_MockLocaleRepo(enMap), 'en');
    await localeController.whenReady;

    db = AppDatabase.inMemory();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(
      repository: settingsRepo,
    );
    playbackController = _TestPlaybackController(
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    settingsController.dispose();
    await db.close();
  });

  Widget buildTestApp({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }

  group('NowPlayingCoverArt Tests', () {
    testWidgets('Renders shrink SizedBox when no track is currently playing', (tester) async {
      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NowPlayingCoverArt), findsOneWidget);
      expect(find.byType(AlbumArtImage), findsNothing);
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('Renders AlbumArtImage with Hero when track is loaded', (tester) async {
      final track = Track(
        id: 42,
        filePath: '/music/test_beat.mp3',
        title: 'Beat Track',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
        artworkUri: 'hash_test_123',
      );

      playbackController.setMockTrack(track, isPlaying: true);

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NowPlayingCoverArt), findsOneWidget);
      expect(find.byType(AlbumArtImage), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);

      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(hero.tag, equals('now_playing_art_/music/test_beat.mp3'));
    });

    testWidgets('Reactivity to visual amplitude changes updates transforms', (tester) async {
      final track = Track(
        id: 43,
        filePath: '/music/subwoofer.mp3',
        title: 'Subwoofer Track',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
      );

      playbackController.setMockTrack(track, isPlaying: true);

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(seconds: 1));

      // Emit amplitude of 0.8
      playbackController.setMockVisualAmplitude(0.8);
      await tester.pump(const Duration(milliseconds: 50));

      expect(playbackController.currentVisualAmplitude, equals(0.8));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Swiping left (forward) triggers next track', (tester) async {
      final track = Track(
        id: 44,
        filePath: '/music/track44.mp3',
        title: 'Track 44',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
      );

      playbackController.setMockTrack(track, isPlaying: true);
      playbackController.mockHasNext = true;

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(playbackController.nextCallCount, equals(0));

      // Swipe from right to left (drag left) on the cover art
      await tester.drag(find.byType(NowPlayingCoverArt), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(playbackController.nextCallCount, equals(1));
    });

    testWidgets('Swiping right (backward) triggers previous track', (tester) async {
      final track = Track(
        id: 45,
        filePath: '/music/track45.mp3',
        title: 'Track 45',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
      );

      playbackController.setMockTrack(track, isPlaying: true);
      playbackController.mockHasPrevious = true;

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(playbackController.previousCallCount, equals(0));

      // Swipe from left to right (drag right) on the cover art
      await tester.drag(find.byType(NowPlayingCoverArt), const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(playbackController.previousCallCount, equals(1));
    });

    testWidgets('Small drag below threshold does not trigger track change', (tester) async {
      final track = Track(
        id: 46,
        filePath: '/music/track46.mp3',
        title: 'Track 46',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
      );

      playbackController.setMockTrack(track, isPlaying: true);

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pump(const Duration(milliseconds: 100));

      // Drag only 15 pixels slowly (below 40 threshold)
      final gesture = await tester.startGesture(tester.getCenter(find.byType(NowPlayingCoverArt)));
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(playbackController.nextCallCount, equals(0));
      expect(playbackController.previousCallCount, equals(0));
    });

    testWidgets('Tapping artwork cycles visualizer modes (wave -> bars -> circle -> off -> wave)', (tester) async {
      final track = Track(
        id: 50,
        filePath: '/music/track50.mp3',
        title: 'Visualizer Test Track',
        durationMs: 200000,
        fileSize: 1024,
        modifiedAt: 1000,
      );

      playbackController.setMockTrack(track, isPlaying: true);

      await tester.pumpWidget(buildTestApp(child: const NowPlayingCoverArt()));
      await tester.pumpAndSettle();

      // Default mode is wave: WaveVisualizerPainter is present
      final customPaintsWave = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(
        customPaintsWave.any((cp) => cp.painter is WaveVisualizerPainter),
        isTrue,
      );

      // 1. Tap artwork -> switches from wave to bars
      await tester.tap(find.byType(NowPlayingCoverArt));
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsRepo.getNowPlayingVisualizerMode(), equals(NowPlayingVisualizerMode.bars));
      final customPaintsBars = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(
        customPaintsBars.any((cp) => cp.painter is SpectrumBarsPainter),
        isTrue,
      );
      // In bars mode, WaveVisualizerPainter is NOT used
      expect(
        customPaintsBars.any((cp) => cp.painter is WaveVisualizerPainter),
        isFalse,
      );

      // 2. Tap artwork -> switches from bars to circle
      await tester.tap(find.byType(NowPlayingCoverArt));
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsRepo.getNowPlayingVisualizerMode(), equals(NowPlayingVisualizerMode.circle));
      final customPaintsCircle = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(
        customPaintsCircle.any((cp) => cp.painter is ReactiveCirclePainter),
        isTrue,
      );
      expect(find.byType(ReactiveCircleVisualizerWidget), findsOneWidget);
      // Logo has been cleanly removed from the circular visualizer
      expect(
        find.descendant(
          of: find.byType(ReactiveCircleVisualizerWidget),
          matching: find.byType(ClipOval),
        ),
        findsNothing,
      );

      // 3. Tap artwork -> switches from circle to off (pure cover)
      await tester.tap(find.byType(NowPlayingCoverArt));
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsRepo.getNowPlayingVisualizerMode(), equals(NowPlayingVisualizerMode.off));
      final customPaintsOff = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(
        customPaintsOff.any((cp) => cp.painter is WaveVisualizerPainter),
        isFalse,
      );
      expect(
        customPaintsOff.any((cp) => cp.painter is SpectrumBarsPainter),
        isFalse,
      );
      expect(
        customPaintsOff.any((cp) => cp.painter is ReactiveCirclePainter),
        isFalse,
      );
      // AlbumArtImage is displayed
      expect(find.byType(AlbumArtImage), findsOneWidget);

      // 4. Tap artwork -> switches from off back to wave
      await tester.tap(find.byType(NowPlayingCoverArt));
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsRepo.getNowPlayingVisualizerMode(), equals(NowPlayingVisualizerMode.wave));
      final customPaintsCycle = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(
        customPaintsCycle.any((cp) => cp.painter is WaveVisualizerPainter),
        isTrue,
      );
    });

    test('NowPlayingVisualizerMode enum and Factory strategy validation', () {
      expect(NowPlayingVisualizerMode.off.next, equals(NowPlayingVisualizerMode.wave));
      expect(NowPlayingVisualizerMode.wave.next, equals(NowPlayingVisualizerMode.bars));
      expect(NowPlayingVisualizerMode.bars.next, equals(NowPlayingVisualizerMode.circle));
      expect(NowPlayingVisualizerMode.circle.next, equals(NowPlayingVisualizerMode.off));

      expect(NowPlayingVisualizerMode.fromString('off'), equals(NowPlayingVisualizerMode.off));
      expect(NowPlayingVisualizerMode.fromString('wave'), equals(NowPlayingVisualizerMode.wave));
      expect(NowPlayingVisualizerMode.fromString('bars'), equals(NowPlayingVisualizerMode.bars));
      expect(NowPlayingVisualizerMode.fromString('circle'), equals(NowPlayingVisualizerMode.circle));
      expect(NowPlayingVisualizerMode.fromString('unknown'), equals(NowPlayingVisualizerMode.wave));

      expect(NowPlayingVisualizerFactory.getRenderer(NowPlayingVisualizerMode.off), isA<OffVisualizerRenderer>());
      expect(NowPlayingVisualizerFactory.getRenderer(NowPlayingVisualizerMode.wave), isA<WaveVisualizerRenderer>());
      expect(NowPlayingVisualizerFactory.getRenderer(NowPlayingVisualizerMode.bars), isA<BarsVisualizerRenderer>());
      expect(NowPlayingVisualizerFactory.getRenderer(NowPlayingVisualizerMode.circle), isA<ReactiveCircleVisualizerRenderer>());
    });

    test('resolveReactiveCircleColor accurately resolves colors and fallbacks', () {
      final darkTheme = ThemeData.dark();
      final lightTheme = ThemeData.light();

      // Dark mode fallback without track color -> Vibrant theme primary
      final darkFallback = resolveReactiveCircleColor(trackColor: null, theme: darkTheme);
      expect(darkFallback, equals(darkTheme.colorScheme.primary));

      // Dark mode with very dark track color -> adjusts lightness for neon visibility
      const darkBlue = Color(0xFF0A1028);
      final adjustedDark = resolveReactiveCircleColor(trackColor: darkBlue, theme: darkTheme);
      expect(HSLColor.fromColor(adjustedDark).lightness, greaterThanOrEqualTo(0.48));

      // Light mode fallback without track color -> theme primary
      final lightFallback = resolveReactiveCircleColor(trackColor: null, theme: lightTheme);
      expect(lightFallback, equals(lightTheme.colorScheme.primary));

      // Light mode with very light track color -> darkens lightness for contrast
      const lightYellow = Color(0xFFFFFFEE);
      final adjustedLight = resolveReactiveCircleColor(trackColor: lightYellow, theme: lightTheme);
      expect(HSLColor.fromColor(adjustedLight).lightness, lessThanOrEqualTo(0.52));
    });
  });

  group('AudioEffectsSheet Volume Normalization and Skip Silence Toggles', () {
    testWidgets('AudioEffectsSheet displays both switches and toggles state', (tester) async {
      await tester.pumpWidget(buildTestApp(child: const AudioEffectsSheet()));
      await tester.pumpAndSettle();

      // Find switch widgets (Volume Normalization, Skip Silence, Limiter, Mono)
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(4));

      // Initially Volume Normalization is true, Skip Silence is false
      expect(settingsController.volumeNormalization, isTrue);
      expect(settingsController.skipSilence, isFalse);

      // Toggle Skip Silence (switch index 1)
      await tester.ensureVisible(switches.at(1));
      await tester.pumpAndSettle();
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      expect(settingsController.skipSilence, isTrue);

      // Toggle Volume Normalization (switch index 0)
      await tester.ensureVisible(switches.at(0));
      await tester.pumpAndSettle();
      await tester.tap(switches.at(0));
      await tester.pumpAndSettle();

      expect(settingsController.volumeNormalization, isFalse);
    });
  });
}
