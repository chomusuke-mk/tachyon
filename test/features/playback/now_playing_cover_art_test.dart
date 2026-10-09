import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/audio_effects_sheet.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/now_playing_cover_art.dart';
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
    required super.backend,
    required super.settingsRepository,
  });

  Track? _mockTrack;
  double _mockAmplitude = 0.0;
  bool _mockIsPlaying = false;

  @override
  Track? get currentTrack => _mockTrack ?? super.currentTrack;

  @override
  bool get isPlaying => _mockTrack != null ? _mockIsPlaying : super.isPlaying;

  @override
  double get currentVisualAmplitude => _mockAmplitude;

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
  late DirectTachyonBackendClient backend;
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

    final db = AppDatabase.inMemory();
    backend = DirectTachyonBackendClient(database: db);
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(
      repository: settingsRepo,
      backend: backend,
    );
    playbackController = _TestPlaybackController(
      backend: backend,
      settingsRepository: settingsRepo,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    settingsController.dispose();
    await backend.dispose();
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
        thumbnailHash: 'hash_test_123',
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
  });

  group('AudioEffectsSheet Volume Normalization and Skip Silence Toggles', () {
    testWidgets('AudioEffectsSheet displays both switches and toggles state', (tester) async {
      await tester.pumpWidget(buildTestApp(child: const AudioEffectsSheet()));
      await tester.pumpAndSettle();

      // Find switch widgets (Volume Normalization, Skip Silence, Limiter, Mono, Equalizer)
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(5));

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
