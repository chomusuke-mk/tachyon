import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/audio_effects_sheet.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

class _MockLocaleRepo extends LocaleRepository {
  final Map<String, String> strings;
  _MockLocaleRepo(this.strings);

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async =>
      strings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SharedPreferences prefs;
  late SettingsRepository repository;
  late SettingsController settingsController;
  late PlaybackController playbackController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    final enJson = await File('i18n/en.jsonc').readAsString();
    final enMap = (jsoncDecode(enJson) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v.toString()),
    );

    localeController = LocaleController(_MockLocaleRepo(enMap), 'en');
    await localeController.whenReady;

    repository = SettingsRepository(prefs);
    playbackController = PlaybackController(
      settingsRepository: repository,
    );
    settingsController = SettingsController(
      repository: repository,
      playbackController: playbackController,
    );
  });

  tearDown(() {
    settingsController.dispose();
    playbackController.dispose();
  });

  Widget buildTestableWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<PlaybackController>.value(
          value: playbackController,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AudioEffectsSheet(isDialog: true),
        ),
      ),
    );
  }

  testWidgets('AudioEffectsSheet renders all DSP effect controls and sections',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Audio Effects'), findsOneWidget);

    // Verify Card 3: Limiter & Mono Audio
    expect(find.text('True-Peak Limiter'), findsOneWidget);
    expect(find.text('Mono Audio'), findsOneWidget);

    // Verify Card 4: Stereo & DSP Effects
    expect(find.text('Stereo & DSP Effects'), findsOneWidget);
    expect(find.text('Stereo Balance'), findsOneWidget);
    expect(find.text('Stereo Width'), findsNWidgets(2)); // Stereo effect width + Reverb width knob
    expect(find.text('Bauer Crossfeed (bs2b)'), findsOneWidget);

    // Verify Card 5: Studio Reverb (always active, controls rendered directly without switches)
    expect(find.text('Studio Reverb'), findsOneWidget);
    expect(find.text('Room Size'), findsOneWidget);
    expect(find.text('Damping'), findsOneWidget);
    expect(find.text('Dry Level'), findsOneWidget);

    // Verify Card 6: Equalizer Title & Preamp (always visible, controls rendered directly without switches)
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Preamp'), findsOneWidget);
  });

  testWidgets('AudioEffectsSheet updates DSP settings on interaction',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Verify Limiter default is true
    expect(settingsController.limiterEnabled, isTrue);

    // Toggle Limiter
    await settingsController.setLimiter(false);
    expect(settingsController.limiterEnabled, isFalse);

    // Toggle Mono
    expect(settingsController.mono, isFalse);
    await settingsController.setMono(true);
    expect(settingsController.mono, isTrue);

    // Change Balance
    expect(settingsController.balance, equals(0.0));
    await settingsController.setBalance(0.5);
    expect(settingsController.balance, equals(0.5));

    // Change Spatializer Width
    expect(settingsController.spatializerWidth, equals(1.0));
    await settingsController.setSpatializer(1.4);
    expect(settingsController.spatializerWidth, equals(1.4));

    // Change Crossfeed Mode
    expect(settingsController.crossfeed, equals(Crossfeed.off));
    await settingsController.setCrossfeed(Crossfeed.moffatBauer);
    expect(settingsController.crossfeed, equals(Crossfeed.moffatBauer));

    // Toggle Reverb & adjust parameters
    expect(settingsController.reverbEnabled, isFalse);
    await settingsController.setReverbEnabled(true);
    expect(settingsController.reverbEnabled, isTrue);

    await settingsController.setReverbPreset('studio');
    expect(settingsController.reverbPreset, equals('studio'));
    expect(settingsController.reverbRoomSize, equals(0.5));

    await settingsController.setReverbRoomSize(0.85);
    expect(settingsController.reverbPreset, equals('custom'));
    expect(settingsController.reverbRoomSize, equals(0.85));

    await settingsController.setReverbDamping(0.4);
    expect(settingsController.reverbDamping, equals(0.4));

    await settingsController.setReverbWidth(0.75);
    expect(settingsController.reverbWidth, equals(0.75));

    await settingsController.setReverbWet(0.5);
    expect(settingsController.reverbWet, equals(0.5));

    await settingsController.setReverbDry(1.2);
    expect(settingsController.reverbDry, equals(1.2));

    // Reverb reset back to 'off'
    await settingsController.setReverbPreset('off');
    expect(settingsController.reverbPreset, equals('off'));
    expect(settingsController.reverbRoomSize, equals(0.0));
    expect(settingsController.reverbEnabled, isFalse);

    // Adjust Preamp and Equalizer
    expect(settingsController.preampDb, equals(0.0));
    await settingsController.setPreamp(-3.5);
    expect(settingsController.preampDb, equals(-3.5));

    // Equalizer reset back to 'flat'
    await settingsController.setEqualizerPreset('flat');
    await settingsController.setPreamp(0.0);
    expect(settingsController.equalizerPreset, equals('flat'));
    expect(settingsController.preampDb, equals(0.0));
    await tester.pumpAndSettle();
  });

  group('Scoped reactivity & v4 persistence round-trips', () {
    test('DSP changes notify only their scoped domain listenable, not themeListenable', () async {
      int themeNotifications = 0;
      int eqNotifications = 0;
      int reverbNotifications = 0;
      int spatialNotifications = 0;
      int enhancementsNotifications = 0;

      settingsController.themeListenable.addListener(() => themeNotifications++);
      settingsController.equalizerListenable.addListener(() => eqNotifications++);
      settingsController.reverbListenable.addListener(() => reverbNotifications++);
      settingsController.spatialListenable.addListener(() => spatialNotifications++);
      settingsController.enhancementsListenable.addListener(
        () => enhancementsNotifications++,
      );

      await settingsController.setPreamp(-4.0);
      await settingsController.setEqualizerBandGain(2, 3.5);
      await settingsController.setReverbRoomSize(0.7);
      await settingsController.setBalance(-0.25);
      await settingsController.setCrossfeed(Crossfeed.chuMoy);
      await settingsController.setSilenceSkipMode(SilenceSkipMode.continuous);

      expect(themeNotifications, equals(0));
      expect(eqNotifications, equals(2));
      expect(reverbNotifications, equals(1));
      expect(spatialNotifications, equals(2));
      expect(enhancementsNotifications, equals(1));
    });

    test('PlaybackController volume updates notify tuningListenable and volumeListenable without trackListenable', () async {
      int trackNotifications = 0;
      int queueNotifications = 0;
      int tuningNotifications = 0;
      int volumeNotifications = 0;

      playbackController.trackListenable.addListener(() => trackNotifications++);
      playbackController.queueListenable.addListener(() => queueNotifications++);
      playbackController.tuningListenable.addListener(() => tuningNotifications++);
      playbackController.volumeListenable.addListener(() => volumeNotifications++);

      await playbackController.setVolume(0.65);

      expect(playbackController.volume, closeTo(0.65, 1e-6));
      expect(playbackController.volumeListenable.value, closeTo(0.65, 1e-6));
      expect(tuningNotifications, equals(1));
      expect(volumeNotifications, equals(1));
      expect(trackNotifications, equals(0));
      expect(queueNotifications, equals(0));
    });

    test('Crossfeed legacy index migration and custom Crossfeed + SilenceSkipMode persistence', () async {
      // Legacy integer index 0 -> off, 1 -> moffatBauer, 2 -> chuMoy
      await prefs.setInt('s_crossfeed', 1);
      expect(SettingsRepository(prefs).getSettings().crossfeed, equals(Crossfeed.moffatBauer));

      await prefs.setInt('s_crossfeed', 2);
      expect(SettingsRepository(prefs).getSettings().crossfeed, equals(Crossfeed.chuMoy));

      await prefs.setInt('s_crossfeed', 0);
      expect(SettingsRepository(prefs).getSettings().crossfeed, equals(Crossfeed.off));

      // Custom Crossfeed parameters round-trip
      const customCf = Crossfeed(enabled: true, cutoffHz: 950.0, feedDb: 8.5);
      await settingsController.setCrossfeed(customCf);
      expect(SettingsRepository(prefs).getSettings().crossfeed, equals(customCf));

      // SilenceSkipMode round-trip
      await settingsController.setSilenceSkipMode(SilenceSkipMode.trimEdges);
      final reloaded = SettingsRepository(prefs).getSettings();
      expect(reloaded.skipSilence, isTrue);
      expect(reloaded.silenceSkipMode, equals(SilenceSkipMode.trimEdges));
      expect(reloaded.silenceSkipConfig.enabled, isTrue);
      expect(reloaded.silenceSkipConfig.mode, equals(SilenceSkipMode.trimEdges));
    });
  });
}
