import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/domain/app_settings.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_screen.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/app_background.dart';

class _MockLocaleRepo extends LocaleRepository {
  final Map<String, String> strings;
  _MockLocaleRepo(this.strings);

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => strings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late DirectTachyonBackendClient backend;
  late SharedPreferences prefs;
  late SettingsRepository repository;
  late SettingsController settingsController;

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
  });

  tearDown(() async {
    await backend.dispose();
  });

  group('TachyonTheme Appearance Customization', () {
    test('buildDarkTheme applies custom seedColor and background opacity', () {
      const customSeed = Color(0xFF10B981); // Emerald Green
      final standardTheme = TachyonTheme.buildDarkTheme(
        seedColor: customSeed,
        hasCustomBackground: false,
      );
      final customBgTheme = TachyonTheme.buildDarkTheme(
        seedColor: customSeed,
        hasCustomBackground: true,
      );

      expect(standardTheme.brightness, Brightness.dark);
      expect(standardTheme.scaffoldBackgroundColor, TachyonColors.darkCanvas);
      expect(standardTheme.colorScheme.primary, isNotNull);

      expect(customBgTheme.scaffoldBackgroundColor, Colors.transparent);
      expect(customBgTheme.appBarTheme.backgroundColor, Colors.transparent);
    });

    test('buildOledTheme creates pure black canvas #000000', () {
      final oledTheme = TachyonTheme.buildOledTheme(
        seedColor: const Color(0xFF3B82F6),
        hasCustomBackground: false,
      );

      expect(oledTheme.brightness, Brightness.dark);
      expect(oledTheme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(oledTheme.colorScheme.surface, const Color(0xFF000000));
    });

    test('buildLightTheme creates clean light surface', () {
      final lightTheme = TachyonTheme.buildLightTheme(
        seedColor: const Color(0xFFFF5722),
        hasCustomBackground: false,
      );

      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, TachyonColors.lightCanvas);
    });
  });

  group('AppSettings and SettingsRepository persistence', () {
    test('stores and reads default appearance values correctly', () {
      final settings = repository.getSettings();

      expect(settings.accentColorValue, 0xFF7C4DFF);
      expect(settings.accentColor, const Color(0xFF7C4DFF));
      expect(settings.isOledMode, isFalse);
      expect(settings.customBackgroundPath, isNull);
      expect(settings.backgroundBlurSigma, 20.0);
      expect(settings.backgroundDimOpacity, 0.65);
    });

    test('persists customized appearance values in SharedPreferences', () async {
      await repository.setAccentColor(0xFF3B82F6);
      await repository.setIsOledMode(true);
      await repository.setCustomBackgroundPath('/path/to/my_bg.jpg');
      await repository.setBackgroundBlurSigma(35.0);
      await repository.setBackgroundDimOpacity(0.80);

      final loaded = repository.getSettings();
      expect(loaded.accentColorValue, 0xFF3B82F6);
      expect(loaded.accentColor, const Color(0xFF3B82F6));
      expect(loaded.isOledMode, isTrue);
      expect(loaded.customBackgroundPath, '/path/to/my_bg.jpg');
      expect(loaded.backgroundBlurSigma, 35.0);
      expect(loaded.backgroundDimOpacity, 0.80);
    });

    test('copyWith updates appearance properties accurately', () {
      const initial = AppSettings(lastPlayedFilePath: null);
      final updated = initial.copyWith(
        accentColorValue: 0xFF10B981,
        isOledMode: true,
        customBackgroundPath: '/custom.png',
        backgroundBlurSigma: 12.0,
        backgroundDimOpacity: 0.5,
      );

      expect(updated.accentColorValue, 0xFF10B981);
      expect(updated.isOledMode, isTrue);
      expect(updated.customBackgroundPath, '/custom.png');
      expect(updated.backgroundBlurSigma, 12.0);
      expect(updated.backgroundDimOpacity, 0.5);

      final clearedBg = updated.copyWith(clearCustomBackground: true);
      expect(clearedBg.customBackgroundPath, isNull);
    });
  });

  group('SettingsController Appearance Controls', () {
    test('setAccentColor updates settings and notifies listeners', () async {
      var notified = false;
      settingsController.addListener(() => notified = true);

      await settingsController.setAccentColor(0xFF00E5FF);

      expect(notified, isTrue);
      expect(settingsController.accentColorValue, 0xFF00E5FF);
      expect(settingsController.accentColor, const Color(0xFF00E5FF));
      expect(repository.getSettings().accentColorValue, 0xFF00E5FF);
    });

    test('setIsOledMode updates state and persists', () async {
      await settingsController.setIsOledMode(true);

      expect(settingsController.isOledMode, isTrue);
      expect(repository.getSettings().isOledMode, isTrue);
    });

    test('setBackgroundBlurSigma clamps and updates values', () async {
      await settingsController.setBackgroundBlurSigma(60.0);
      expect(settingsController.backgroundBlurSigma, 50.0);

      await settingsController.setBackgroundBlurSigma(-5.0);
      expect(settingsController.backgroundBlurSigma, 0.0);
    });

    test('setBackgroundDimOpacity clamps and updates values', () async {
      await settingsController.setBackgroundDimOpacity(1.2);
      expect(settingsController.backgroundDimOpacity, 0.95);

      await settingsController.setBackgroundDimOpacity(0.05);
      expect(settingsController.backgroundDimOpacity, 0.1);
    });

    test('setCustomBackground(null) clears background', () async {
      await repository.setCustomBackgroundPath('/dummy/path.jpg');
      await settingsController.init();
      expect(settingsController.customBackgroundPath, '/dummy/path.jpg');

      final success = await settingsController.setCustomBackground(null);
      expect(success, isTrue);
      expect(settingsController.customBackgroundPath, isNull);
      expect(repository.getSettings().customBackgroundPath, isNull);
    });
  });

  group('AppBackground Widget Tests', () {
    testWidgets('renders SizedBox.shrink when imagePath is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBackground(imagePath: null),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when file does not exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBackground(imagePath: '/non/existent/image.png'),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('SettingsScreen UI Widget Tests', () {
    Widget createSettingsScreenWidget() {
      final libraryController = LibraryController(
        backend: backend,
        settingsRepository: repository,
        store: LibraryStore(),
      );

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ChangeNotifierProvider<SettingsController>.value(value: settingsController),
          ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    testWidgets('renders Appearance section with color circles and OLED toggle', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createSettingsScreenWidget());
      await tester.pumpAndSettle();

      // Check for theme dropdown
      expect(find.text('Theme'), findsOneWidget);
      // Check for OLED option
      expect(find.text('Pure OLED'), findsOneWidget);
      // Check for Accent Color
      expect(find.text('Accent Color'), findsOneWidget);
      // Check for Custom Background
      expect(find.text('Custom Background'), findsOneWidget);
      expect(find.text('Select Image'), findsOneWidget);

      // Check that 8 predefined color circles are rendered
      final accentColorsWrap = find.byKey(const Key('accent_colors_wrap'));
      expect(
        find.descendant(
          of: accentColorsWrap,
          matching: find.byType(InkWell),
        ),
        findsNWidgets(TachyonColors.predefinedAccentColors.length),
      );

      // Verify the default seed color has the check icon
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Tap another color circle (e.g. second color)
      final colorCircles = find.descendant(
        of: accentColorsWrap,
        matching: find.byType(InkWell),
      );
      await tester.tap(colorCircles.at(1));
      await tester.pumpAndSettle();

      expect(
        settingsController.accentColorValue,
        TachyonColors.predefinedAccentColors[1].toARGB32(),
      );
    });

    testWidgets('toggling OLED mode switch updates controller', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createSettingsScreenWidget());
      await tester.pumpAndSettle();

      expect(settingsController.isOledMode, isFalse);

      final oledSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('Pure OLED'),
          matching: find.byType(Row),
        ),
        matching: find.byType(Switch),
      );

      await tester.tap(oledSwitch);
      await tester.pumpAndSettle();

      expect(settingsController.isOledMode, isTrue);
    });
  });
}
