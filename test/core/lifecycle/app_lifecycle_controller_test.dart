import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app/app.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/app_memory_coordinator.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/permissions/presentation/permissions_gate.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/controllers/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/shell/presentation/screens/tachyon_shell.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return const <String, String>{};
    final decoded = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }
}

class _TrackingPlaybackController extends PlaybackController {
  int playOrPauseCount = 0;
  int nextCount = 0;
  int previousCount = 0;
  int toggleShuffleCount = 0;
  bool mockPlaying = false;

  _TrackingPlaybackController({
    super.store,
    required super.settingsRepository,
  });

  @override
  bool get isPlaying => mockPlaying;

  @override
  Future<void> playOrPause() async {
    playOrPauseCount++;
    mockPlaying = !mockPlaying;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    nextCount++;
  }

  @override
  Future<void> previous() async {
    previousCount++;
  }

  @override
  Future<void> toggleShuffle() async {
    toggleShuffleCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleController & 3-State Power Modes', () {
    late SharedPreferences prefs;
    late SettingsRepository settingsRepo;
    late _TrackingPlaybackController playbackController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      playbackController = _TrackingPlaybackController(
        settingsRepository: settingsRepo,
      );
      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );
    });

    tearDown(() {
      AppMemoryCoordinator.cancelPendingTrims();
      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );
      playbackController.dispose();
    });

    test('transitions Active -> Suspended on desktop minimize & focus loss with debounce cancellation', () async {
      final bridge = WindowControlBridge(
        attachChannelHandler: false,
        isDesktopOverride: true,
      );
      final lifecycle = AppLifecycleController(
        windowBridge: bridge,
        playbackController: playbackController,
        focusLossDebounce: const Duration(milliseconds: 60),
        startTrimmerOnActive: false,
        observeFlutterLifecycle: false,
      );
      addTearDown(() {
        lifecycle.dispose();
        bridge.dispose();
      });

      expect(lifecycle.mode, equals(AppLifecycleMode.active));
      expect(lifecycle.isActive, isTrue);
      expect(lifecycle.isUiThrottled, isFalse);

      // Transient focus loss that recovers before debounce expires stays Active.
      bridge.simulateWindowStateForTest(
        const DesktopWindowState(isFocused: false, isMinimized: false),
      );
      expect(lifecycle.mode, equals(AppLifecycleMode.active));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bridge.simulateWindowStateForTest(
        const DesktopWindowState(isFocused: true, isMinimized: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(lifecycle.mode, equals(AppLifecycleMode.active));

      // Sustained focus loss enters Suspended after debounce.
      bridge.simulateWindowStateForTest(
        const DesktopWindowState(isFocused: false, isMinimized: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(lifecycle.mode, equals(AppLifecycleMode.suspended));
      expect(lifecycle.isSuspended, isTrue);
      expect(lifecycle.isUiThrottled, isTrue);
      expect(
        playbackController.lifecycleMode,
        equals(AppLifecycleMode.suspended),
      );

      // Refocusing returns immediately to Active.
      bridge.simulateWindowStateForTest(
        const DesktopWindowState(isFocused: true, isMinimized: false),
      );
      expect(lifecycle.mode, equals(AppLifecycleMode.active));

      // Desktop minimize enters Suspended without waiting for debounce.
      bridge.simulateWindowStateForTest(
        const DesktopWindowState(isFocused: false, isMinimized: true),
      );
      expect(lifecycle.mode, equals(AppLifecycleMode.suspended));
    });

    test('PlaybackController suppresses scoped UI notifiers in suspended mode and flushes dirty domains on active', () {
      int trackNotifications = 0;
      int transportNotifications = 0;
      playbackController.trackListenable.addListener(() => trackNotifications++);
      playbackController.transportListenable.addListener(
        () => transportNotifications++,
      );

      playbackController.setLifecycleMode(AppLifecycleMode.suspended);
      playbackController.notifyListeners();
      playbackController.notifyListeners();

      expect(trackNotifications, equals(0));
      expect(transportNotifications, equals(0));

      playbackController.setLifecycleMode(AppLifecycleMode.active);
      expect(trackNotifications, equals(1));
      expect(transportNotifications, equals(1));
    });

    test('enterBackground locks mode against suspended downgrade, purges imageCache, and restores cleanly', () async {
      final calls = <String>[];
      final bridge = WindowControlBridge(
        attachChannelHandler: false,
        isDesktopOverride: true,
        invokeOverride: <T>(String method, [Object? args]) async {
          calls.add(method);
          return null;
        },
      );
      final lifecycle = AppLifecycleController(
        windowBridge: bridge,
        playbackController: playbackController,
        startTrimmerOnActive: false,
        observeFlutterLifecycle: false,
      );
      addTearDown(() {
        lifecycle.dispose();
        bridge.dispose();
      });

      await lifecycle.enterBackground();
      expect(lifecycle.mode, equals(AppLifecycleMode.background));
      expect(lifecycle.isBackground, isTrue);
      expect(calls, contains('enterBackgroundMode'));
      expect(PaintingBinding.instance.imageCache.maximumSize, equals(0));
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, equals(0));

      // Background mode cannot be downgraded to Suspended by hidden/paused events.
      lifecycle.enterSuspended();
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lifecycle.mode, equals(AppLifecycleMode.background));

      // On desktop, Flutter resumed alone does not leave tray background; tray restore does.
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lifecycle.mode, equals(AppLifecycleMode.background));

      bridge.simulateTrayActionForTest(DesktopTrayAction.restore);
      await Future<void>.delayed(Duration.zero);
      expect(lifecycle.mode, equals(AppLifecycleMode.active));
      expect(calls, contains('restoreFromBackground'));
      expect(
        PaintingBinding.instance.imageCache.maximumSize,
        equals(AppMemoryCoordinator.activeImageCacheMaxSize),
      );
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        equals(AppMemoryCoordinator.activeImageCacheMaxBytes),
      );
    });

    test('Android task removal while playing enters background mode and mobile resume restores active', () async {
      final bridge = WindowControlBridge(
        attachChannelHandler: false,
        isDesktopOverride: false,
      );
      final lifecycle = AppLifecycleController(
        windowBridge: bridge,
        playbackController: playbackController,
        startTrimmerOnActive: false,
        observeFlutterLifecycle: false,
      );
      addTearDown(() {
        lifecycle.dispose();
        bridge.dispose();
      });

      // Swiping away when paused only enters suspended.
      await lifecycle.handleTaskRemoved(isPlaying: false);
      expect(lifecycle.mode, equals(AppLifecycleMode.suspended));

      // Swiping away while audio is playing (TachyonAudioHandler.onTaskRemoved) enters background.
      final handler = TachyonAudioHandler(
        playbackController: playbackController,
        onTaskRemovedWhilePlaying: () =>
            lifecycle.handleTaskRemoved(isPlaying: true),
      );
      addTearDown(handler.dispose);

      const track = Track(
        id: 1,
        filePath: '/music/test.mp3',
        title: 'Test Track',
        durationMs: 120000,
        fileSize: 1000,
        modifiedAt: 0,
      );
      handler.playbackState.add(
        as_lib.PlaybackState(
          playing: true,
          processingState: as_lib.AudioProcessingState.ready,
          updatePosition: const Duration(seconds: 10),
        ),
      );
      handler.mediaItem.add(
        as_lib.MediaItem(id: track.filePath, title: track.title),
      );

      await handler.onTaskRemoved();
      expect(lifecycle.mode, equals(AppLifecycleMode.background));

      // Opening the app back on Android triggers resumed -> restores to active.
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(lifecycle.mode, equals(AppLifecycleMode.active));
    });

    test('tray actions dispatch playback commands and close handler', () async {
      int closedCount = 0;
      final bridge = WindowControlBridge(
        attachChannelHandler: false,
        isDesktopOverride: true,
      );
      final lifecycle = AppLifecycleController(
        windowBridge: bridge,
        playbackController: playbackController,
        startTrimmerOnActive: false,
        observeFlutterLifecycle: false,
        onCloseRequested: () async {
          closedCount++;
        },
      );
      addTearDown(() {
        lifecycle.dispose();
        bridge.dispose();
      });

      bridge.simulateTrayActionForTest(DesktopTrayAction.playPause);
      bridge.simulateTrayActionForTest(DesktopTrayAction.next);
      bridge.simulateTrayActionForTest(DesktopTrayAction.previous);
      bridge.simulateTrayActionForTest(DesktopTrayAction.toggleShuffle);
      bridge.simulateTrayActionForTest(DesktopTrayAction.quit);
      await Future<void>.delayed(Duration.zero);

      expect(playbackController.playOrPauseCount, equals(1));
      expect(playbackController.nextCount, equals(1));
      expect(playbackController.previousCount, equals(1));
      expect(playbackController.toggleShuffleCount, equals(1));
      expect(closedCount, equals(1));
    });
  });

  group('App & TachyonShell Lifecycle Widget Tests', () {
    late Directory tempDir;
    late AppDatabase db;
    late LibraryStore store;
    late SettingsRepository settingsRepo;
    late _TestLocaleRepo localeRepo;
    late MetadataService metadataService;
    late _TrackingPlaybackController playback;
    late SettingsController settings;
    late LocaleController locale;
    late LibraryController library;
    late PlaylistsController playlists;
    late TachyonSearchController search;
    late WindowControlBridge bridge;
    late AppLifecycleController lifecycle;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tempDir = await Directory.systemTemp.createTemp('tachyon_app_lc');
      MetadataUtils.init(tempDir.path, tempDir.path);
      AppMemoryCoordinator.cancelPendingTrims();
      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );

      db = AppDatabase.inMemory();
      await db.init();
      store = LibraryStore(db);
      await store.reloadFromDatabase();

      settingsRepo = SettingsRepository(prefs);
      localeRepo = _TestLocaleRepo();
      metadataService = MetadataService(database: db, store: store);
      playback = _TrackingPlaybackController(
        store: store,
        settingsRepository: settingsRepo,
      );
      settings = SettingsController(
        repository: settingsRepo,
        playbackController: playback,
      );
      await settings.init();
      locale = LocaleController(localeRepo, 'en');
      await locale.whenReady;
      library = LibraryController(
        settingsRepository: settingsRepo,
        store: store,
        metadataService: metadataService,
      );
      playlists = PlaylistsController(store: store);
      search = TachyonSearchController(store: store);

      // Simulate a non-GNOME X11 Linux runner (hasNativeHeaderBar: false, hasSystemDecorations: true).
      bridge = WindowControlBridge(
        attachChannelHandler: false,
        isDesktopOverride: true,
        invokeOverride: <T>(String method, [Object? args]) async {
          if (method == 'getWindowState') {
            return <Object?, Object?>{
              'hasNativeHeaderBar': false,
              'hasSystemDecorations': true,
              'isMinimized': false,
              'isFocused': true,
              'isMaximized': false,
              'isHiddenToTray': false,
            } as T;
          }
          return null;
        },
      );
      await bridge.initialize();

      lifecycle = AppLifecycleController(
        windowBridge: bridge,
        playbackController: playback,
        startTrimmerOnActive: false,
        observeFlutterLifecycle: false,
      );
    });

    tearDown(() async {
      AppMemoryCoordinator.cancelPendingTrims();
      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );
      lifecycle.dispose();
      bridge.dispose();
      search.dispose();
      playlists.dispose();
      library.dispose();
      locale.dispose();
      settings.dispose();
      playback.dispose();
      store.dispose();
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'App pauses TickerMode in suspended, unmounts entire UI in background, remounts cleanly on restore, and shows X11 fallback button when non-CSD decorated',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LibraryStore>.value(value: store),
              Provider<MetadataService>.value(value: metadataService),
              Provider<SettingsRepository>.value(value: settingsRepo),
              Provider<LocaleRepository>.value(value: localeRepo),
              Provider<WindowControlBridge>.value(value: bridge),
              ChangeNotifierProvider<AppLifecycleController>.value(
                value: lifecycle,
              ),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<LocaleController>.value(value: locale),
              ChangeNotifierProvider<LibraryController>.value(value: library),
              ChangeNotifierProvider<PlaylistsController>.value(
                value: playlists,
              ),
              ChangeNotifierProvider<TachyonSearchController>.value(
                value: search,
              ),
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
            ],
            child: const App(permissionsGranted: true),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Active mode: TachyonShell mounted, inherited TickerMode active, X11 fallback tray button visible.
        expect(find.byType(TachyonShell), findsOneWidget);
        expect(find.byKey(const Key('shell_btn_background')), findsOneWidget);
        expect(
          TickerMode.valuesOf(tester.element(find.byType(TachyonShell))).enabled,
          isTrue,
        );

        // Suspended mode: keeps TachyonShell mounted (preserving route & scroll) while disabling tickers.
        lifecycle.enterSuspended();
        await tester.pump();
        expect(find.byType(TachyonShell), findsOneWidget);
        expect(
          TickerMode.valuesOf(tester.element(find.byType(TachyonShell))).enabled,
          isFalse,
        );

        // Background mode (triggered via the X11 fallback button): unmounts entire UI down to SizedBox.shrink().
        await tester.tap(find.byKey(const Key('shell_btn_background')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(lifecycle.mode, equals(AppLifecycleMode.background));
        expect(find.byType(TachyonShell), findsNothing);
        expect(find.byType(MaterialApp), findsNothing);

        // Restoring from background remounts the main shell cleanly without PermissionsGate blocking it.
        await lifecycle.restoreFromBackground();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(lifecycle.mode, equals(AppLifecycleMode.active));
        expect(find.byType(TachyonShell), findsOneWidget);
        expect(find.byType(PermissionsGate), findsOneWidget);
      },
    );
  });
}
