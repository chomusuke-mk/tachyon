import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({
    required super.backend,
    required super.settingsRepository,
  });

  Track? _mockTrack;
  Duration _mockDuration = Duration.zero;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  @override
  Duration get duration =>
      _mockDuration > Duration.zero ? _mockDuration : super.duration;

  void setMockTrack(Track? track, {Duration? duration}) {
    _mockTrack = track;
    if (duration != null) _mockDuration = duration;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SettingsRepository settingsRepo;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;
  });

  setUp(() {
    MiniPlayerColorResolver.clearCache();
  });

  group('MiniPlayerColorResolver tests', () {
    test('computeColor produces proper contrasts for dark, light, and OLED themes', () {
      const extractedScheme = ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFFFB3B3),
        onPrimary: Color(0xFF680016),
        primaryContainer: Color(0xFF733335),
        onPrimaryContainer: Color(0xFFFFDADA),
        secondary: Color(0xFFE7BDBA),
        onSecondary: Color(0xFF442928),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        surface: Color(0xFF1A1111),
        onSurface: Color(0xFFF1DFDF),
        surfaceContainerHigh: Color(0xFF322827),
      );

      final darkTheme = TachyonTheme.darkTheme;
      final oledTheme = TachyonTheme.oledTheme;
      final lightTheme = TachyonTheme.lightTheme;

      // Dark theme computation
      final darkColor = MiniPlayerColorResolver.computeColor(
        extractedScheme: extractedScheme,
        themeScheme: darkTheme.colorScheme,
        isDark: true,
        isOled: false,
      );
      expect(darkColor, isNotNull);
      expect(darkColor.a, 1.0);

      // OLED theme computation
      final oledColor = MiniPlayerColorResolver.computeColor(
        extractedScheme: extractedScheme,
        themeScheme: oledTheme.colorScheme,
        isDark: true,
        isOled: true,
      );
      expect(oledColor, isNotNull);
      expect(oledColor.a, 1.0);

      // Light theme computation
      final lightColor = MiniPlayerColorResolver.computeColor(
        extractedScheme: extractedScheme,
        themeScheme: lightTheme.colorScheme,
        isDark: false,
        isOled: false,
      );
      expect(lightColor, isNotNull);
      expect(lightColor.a, 1.0);
    });

    test('resolveColor returns null gracefully when thumbnail file is absent', () async {
      final darkTheme = TachyonTheme.darkTheme;
      final color = await MiniPlayerColorResolver.resolveColor(
        thumbnailHash: 'non_existent_hash',
        theme: darkTheme,
      );
      expect(color, isNull);
    });

    test('resolveColor uses cached value on subsequent calls', () async {
      const testHash = 'test_cached_hash';
      const fakeColor = Color(0xFF334455);
      final cacheKey = '$testHash:dark:std';
      MiniPlayerColorResolver.cache[cacheKey] = fakeColor;

      final color = await MiniPlayerColorResolver.resolveColor(
        thumbnailHash: testHash,
        theme: TachyonTheme.darkTheme,
      );
      expect(color, equals(fakeColor));
    });
  });

  group('MiniPlayerBar widget tests', () {
    late AppDatabase db;
    late DirectTachyonBackendClient backend;
    late _TestPlaybackController playback;

    setUp(() {
      db = AppDatabase.inMemory();
      backend = DirectTachyonBackendClient(database: db);
      playback = _TestPlaybackController(backend: backend, settingsRepository: settingsRepo);
    });

    tearDown(() async {
      playback.dispose();
      await backend.dispose();
      await db.close();
    });

    testWidgets('MiniPlayerBar renders SizedBox.shrink when currentTrack is null', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MiniPlayerBar(isDesktop: false),
            ),
          ),
        ),
      );

      expect(find.byType(MiniPlayerBar), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MiniPlayerBar),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
    });

    testWidgets('MiniPlayerBar renders fallback surfaceContainerHigh when track has no thumbnail', (tester) async {
      final track = Track(
        id: 1,
        filePath: '/music/song1.mp3',
        title: 'Song Without Art',
        durationMs: 200000,
        fileSize: 1000,
        modifiedAt: 0,
        artists: const [Artist(id: 1, name: 'Sample Artist')],
      );
      playback.setMockTrack(track);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: MaterialApp(
            theme: TachyonTheme.darkTheme,
            home: const Scaffold(
              body: MiniPlayerBar(isDesktop: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song Without Art'), findsOneWidget);
      expect(find.text('Sample Artist'), findsOneWidget);

      final materialFinder = find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.byType(Material),
      );
      expect(materialFinder, findsWidgets);

      final material = tester.widget<Material>(materialFinder.first);
      expect(material.color, equals(TachyonTheme.darkTheme.colorScheme.surfaceContainerHigh));
    });

    testWidgets('MiniPlayerBar applies cached thumbnail-related background color', (tester) async {
      const customHash = 'art_hash_custom';
      const expectedArtColor = Color(0xFF4A2528);

      final cacheKey = '$customHash:dark:std';
      MiniPlayerColorResolver.cache[cacheKey] = expectedArtColor;

      final track = Track(
        id: 2,
        filePath: '/music/song2.mp3',
        title: 'Song With Art',
        durationMs: 240000,
        fileSize: 2000,
        modifiedAt: 0,
        thumbnailHash: customHash,
        artists: const [Artist(id: 2, name: 'Vibrant Band')],
      );
      playback.setMockTrack(track);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: MaterialApp(
            theme: TachyonTheme.darkTheme,
            home: const Scaffold(
              body: MiniPlayerBar(isDesktop: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final materialFinder = find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.byType(Material),
      );
      expect(materialFinder, findsWidgets);

      final material = tester.widget<Material>(materialFinder.first);
      expect(material.color, equals(expectedArtColor));
    });

    testWidgets('MiniPlayerBar onTap callback triggers when clicked', (tester) async {
      var tapped = false;
      final track = Track(
        id: 3,
        filePath: '/music/song3.mp3',
        title: 'Clickable Song',
        durationMs: 150000,
        fileSize: 1500,
        modifiedAt: 0,
      );
      playback.setMockTrack(track);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MiniPlayerBar(
                isDesktop: false,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MiniPlayerBar));
      expect(tapped, isTrue);
    });

    testWidgets('MiniPlayerBar desktop mode renders extra controls', (tester) async {
      final track = Track(
        id: 4,
        filePath: '/music/desktop_song.mp3',
        title: 'Desktop Song',
        durationMs: 180000,
        fileSize: 1500,
        modifiedAt: 0,
      );
      playback.setMockTrack(track, duration: const Duration(minutes: 3));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ],
          child: MaterialApp(
            home: const Scaffold(
              body: MiniPlayerBar(isDesktop: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.text('00:00 / 03:00'), findsOneWidget);
    });
  });
}
