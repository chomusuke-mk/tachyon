import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/audio_effects_sheet.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart'
    show CrossfeedMode;
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
  late DirectTachyonBackendClient backend;
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

    final db = AppDatabase.inMemory();
    backend = DirectTachyonBackendClient(database: db);
    repository = SettingsRepository(prefs);
    settingsController = SettingsController(
      repository: repository,
      backend: backend,
    );
    playbackController = PlaybackController(
      backend: backend,
      settingsRepository: repository,
    );
  });

  tearDown(() async {
    playbackController.dispose();
    await backend.dispose();
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
    expect(find.text('Stereo Width'), findsOneWidget);
    expect(find.text('Bauer Crossfeed (bs2b)'), findsOneWidget);

    // Verify Card 5: Equalizer Title
    expect(find.text('Equalizer'), findsOneWidget);

    // Turn Equalizer ON to view Preamp
    await settingsController.setEqualizerEnabled(true);
    await tester.pumpAndSettle();

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
    expect(settingsController.crossfeedMode, equals(CrossfeedMode.off));
    await settingsController.setCrossfeed(CrossfeedMode.moffatBauer);
    expect(settingsController.crossfeedMode, equals(CrossfeedMode.moffatBauer));

    // Enable EQ and adjust Preamp
    await settingsController.setEqualizerEnabled(true);
    await tester.pumpAndSettle();
    expect(settingsController.preampDb, equals(0.0));
    await settingsController.setPreamp(-3.5);
    expect(settingsController.preampDb, equals(-3.5));
  });
}
