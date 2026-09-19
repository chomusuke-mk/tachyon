import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_screen.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

class StubMetadataExtractor implements MetadataExtractor {
  @override
  Future<Track?> extractMetadata(String filePath) async => null;

  @override
  Stream<ScanProgress> scanDirectories(List<String> directories, {CancellationToken? cancellationToken}) =>
      const Stream.empty();

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async => null;
}

class StubLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {};
}

class MockAudioEngineService implements AudioEngineService {
  final StreamController<MediaPlayerState> _controller =
      StreamController<MediaPlayerState>.broadcast(sync: true);
  MediaPlayerState _state = const MediaPlayerState.initial();

  @override
  Stream<MediaPlayerState> get stateStream => _controller.stream;

  @override
  MediaPlayerState get currentState => _state;

  @override
  Future<void> open(
    List<Playable> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {}

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    _state = _state.copyWith(crossfadeConfig: config);
    _controller.add(_state);
  }
  @override
  Future<void> setLoopMode(Loop loop) async {}
  @override
  Future<void> toggleShuffle() async {}
  @override
  Future<void> insertNext(Playable playable) async {}
  @override
  Future<void> append(List<Playable> playables) async {}
  @override
  Future<void> remove(int index) async {}
  @override
  Future<void> reorder(int from, int to) async {}
  @override
  Future<void> setReplayGain(ReplayGainMode mode) async {}
  @override
  Future<void> setReplayGainPreamp(double preamp) async {}
  @override
  Future<void> setExclusiveAudio(bool exclusive) async {
    _state = _state.copyWith(exclusiveAudio: exclusive);
    _controller.add(_state);
  }
  @override
  Future<void> setMpvProperty(String property, String value) async {}
  @override
  Future<void> setMpvProperties(Map<String, String> properties) async {}
  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late MockAudioEngineService mockEngine;
  late SettingsRepository settingsRepo;
  late LocaleController localeController;
  late LibraryController libraryController;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);

    db = AppDatabaseImpl.inMemory();
    await db.init();

    mockEngine = MockAudioEngineService();

    localeController = LocaleController(StubLocaleRepository(), 'en');
    libraryController = LibraryController(
      database: db,
      metadataExtractor: StubMetadataExtractor(),
    );
    settingsController = SettingsController(
      settingsRepository: settingsRepo,
      audioEngineService: mockEngine,
      localeController: localeController,
    );
  });

  tearDown(() async {
    settingsController.dispose();
    libraryController.dispose();
    await mockEngine.dispose();
    await db.close();
  });

  Widget buildTestWidget({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: libraryController),
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
      ],
      child: MaterialApp(
        theme: TachyonTheme.darkTheme,
        home: child,
      ),
    );
  }

  void configureViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('renders SettingRow widgets and main setting sections', (tester) async {
    configureViewport(tester);
    await tester.pumpWidget(buildTestWidget(child: const SettingsScreen()));
    await tester.pump();

    // Verify multiple SettingRow widgets are rendered
    expect(find.byType(SettingRow), findsAtLeastNWidgets(4));

    // Verify Sliders, Switches, and DropdownButtons are present
    expect(find.byType(Switch), findsAtLeastNWidgets(2));
    expect(find.byType(Slider), findsAtLeastNWidgets(2));
    expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsAtLeastNWidgets(1));
  });

  testWidgets('toggling crossfade switch updates settings controller', (tester) async {
    configureViewport(tester);
    await tester.pumpWidget(buildTestWidget(child: const SettingsScreen()));
    await tester.pump();

    expect(settingsController.crossfadeEnabled, isTrue);

    // Find the crossfade Switch (the first enabled switch in the audio card)
    final crossfadeSwitch = find.byWidgetPredicate(
      (widget) => widget is Switch && widget.onChanged != null,
    ).first;

    await tester.tap(crossfadeSwitch);
    await tester.pump();

    expect(settingsController.crossfadeEnabled, isFalse);
  });

  testWidgets('displays music directories and allows removing an entry', (tester) async {
    configureViewport(tester);
    // Add two initial directories to settingsRepo
    await settingsRepo.saveSettings(settingsRepo.getSettings().copyWith(
      musicDirectories: ['/path/to/folder_a', '/path/to/folder_b'],
    ));
    await settingsController.init();

    await tester.pumpWidget(buildTestWidget(child: const SettingsScreen()));
    await tester.pump();

    expect(find.text('/path/to/folder_a'), findsOneWidget);
    expect(find.text('/path/to/folder_b'), findsOneWidget);

    // Find the remove button for the first directory and tap it
    final deleteButtons = find.byIcon(Icons.delete_outline_rounded);
    expect(deleteButtons, findsNWidgets(2));

    await tester.tap(deleteButtons.first);
    await tester.pump();

    expect(settingsController.musicDirectories.length, equals(1));
    expect(settingsController.musicDirectories.first, equals('/path/to/folder_b'));
  });

  testWidgets('theme mode dropdown allows selecting a theme', (tester) async {
    configureViewport(tester);
    await tester.pumpWidget(buildTestWidget(child: const SettingsScreen()));
    await tester.pump();

    final themeDropdown = find.byType(DropdownButton<ThemeMode>);
    expect(themeDropdown, findsOneWidget);

    await tester.tap(themeDropdown);
    await tester.pumpAndSettle();

    // Select Light theme (matches strings.sThemeLight or DropdownMenuItem with ThemeMode.light)
    final lightItem = find.byWidgetPredicate(
      (widget) => widget is DropdownMenuItem<ThemeMode> && widget.value == ThemeMode.light,
    ).last;
    await tester.tap(lightItem, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(settingsController.themeMode, equals(ThemeMode.light));
  });
}
