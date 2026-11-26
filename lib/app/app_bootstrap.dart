import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app/app.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/app_memory_coordinator.dart';
import 'package:tachyon/core/lifecycle/desktop_tray_service.dart';
import 'package:tachyon/core/lifecycle/memory_optimizer.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/platform/permission_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/system_media_service.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/features/radios/data/radio_browser_service.dart';
import 'package:tachyon/features/radios/presentation/controllers/radio_controller.dart';
import 'package:tachyon/features/search/presentation/controllers/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';

/// Bootstraps core services, controllers, native lifecycle/tray bridges,
/// and mounts the root [App] inside a top-level [MultiProvider].
abstract final class AppBootstrap {
  static const _log = ScopedLogger('Bootstrap');

  /// Initializes all application dependencies and launches the Flutter UI.
  static Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    const buildMode = kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug');
    _log.i(
      'Starting Tachyon (buildMode=$buildMode, isWeb=$kIsWeb, '
      'platform=${defaultTargetPlatform.name}, '
      'logLevel=${AppLogger.minLevel.label}, '
      'envTachyonLogLevel="${AppLogger.envLogLevel}")',
    );
    await MiniaudioPlayer.ensureInitialized(
      rootIsolateToken: kIsWeb ? null : ServicesBinding.rootIsolateToken,
    );
    _log.d('MiniaudioPlayer engine initialized');
    PaintingBinding.instance.imageCache.maximumSize =
        AppMemoryCoordinator.activeImageCacheMaxSize;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        AppMemoryCoordinator.activeImageCacheMaxBytes;
    MiniaudioPlayer.config(
      logLevel: (kDebugMode || kIsWeb)
          ? MiniaudioLogLevel.info
          : MiniaudioLogLevel.error,
    );
    try {
      await SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        AppMemoryCoordinator.activeSkiaCacheMaxBytes,
      );
      _log.d(
        'Configured Skia cache=${AppMemoryCoordinator.activeSkiaCacheMaxBytes}B '
        'imageCache=${AppMemoryCoordinator.activeImageCacheMaxSize}/${AppMemoryCoordinator.activeImageCacheMaxBytes}B',
      );
    } catch (e) {
      _log.w('Failed to configure initial Skia cache limit: $e');
    }

    final sharedPreferences = await SharedPreferences.getInstance();
    final String dbPath;
    if (kIsWeb) {
      dbPath = '/database';
      await MetadataUtils.initAsync(
        thumbnailsPath: '/covers',
        tempPath: '/temp',
      );
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      final cacheDirectory = await getApplicationCacheDirectory();
      dbPath = p.join(appSupportDir.path, 'music.db');
      _log.d('Cache path: ${cacheDirectory.path}');
      _log.d('Data path: ${appSupportDir.path}');
      MetadataUtils.init(
        p.join(appSupportDir.path, 'covers'),
        p.join(cacheDirectory.path, 'covers'),
      );
    }

    final appDatabase = AppDatabase(dbPath: dbPath);
    await appDatabase.init();
    _log.d('AppDatabase initialized at $dbPath');

    final libraryStore = LibraryStore(appDatabase);
    await libraryStore.reloadFromDatabase();
    _log.d(
      'LibraryStore hydrated: tracks=${libraryStore.tracks.length} '
      'albums=${libraryStore.albums.length} artists=${libraryStore.artists.length} '
      'playlists=${libraryStore.playlists.length} radios=${libraryStore.radioStations.length}',
    );

    final metadataService = MetadataService(
      database: appDatabase,
      store: libraryStore,
    );

    final settingsRepository = SettingsRepository(sharedPreferences);
    final localeRepository = LocaleRepository();

    final playbackController = PlaybackController(
      store: libraryStore,
      settingsRepository: settingsRepository,
      metadataService: metadataService,
    );

    final libraryController = LibraryController(
      settingsRepository: settingsRepository,
      store: libraryStore,
      metadataService: metadataService,
    );

    final settingsController = SettingsController(
      repository: settingsRepository,
      playbackController: playbackController,
    );
    await settingsController.init();
    _log.d(
      'Settings initialized: themeMode=${settingsController.themeMode.name} '
      'oled=${settingsController.isOledMode} '
      'hasCustomBackground=${settingsController.customBackgroundPath?.isNotEmpty ?? false}',
    );

    String resolveDefaultLanguage() {
      final systemCode = ui.PlatformDispatcher.instance.locale.languageCode
          .toLowerCase();
      return languagesEndonyms.containsKey(systemCode) ? systemCode : 'en';
    }

    String initialLang = settingsController.appLanguage;
    if (initialLang == 'defaultOption') {
      initialLang = resolveDefaultLanguage();
    }
    final localeController = LocaleController(localeRepository, initialLang);
    await localeController.whenReady;
    _log.d('LocaleController ready: locale=${localeController.currentLocaleCode}');
    settingsController.localeListenable.addListener(() {
      final lang = settingsController.appLanguage;
      final effective = (lang == 'defaultOption')
          ? resolveDefaultLanguage()
          : lang;
      if (localeController.currentLocaleCode != effective) {
        localeController.setLocale(effective);
      }
    });

    final permissionsGranted = await PermissionUtils.areAllGranted();
    _log.d('Runtime permissions granted=$permissionsGranted');
    if (permissionsGranted) {
      await settingsController.ensureDefaultMusicDirectory();
      unawaited(libraryController.scanDirectories());
    }

    final playlistsController = PlaylistsController(store: libraryStore);
    final searchController = TachyonSearchController(store: libraryStore);

    final windowBridge = WindowControlBridge();
    await windowBridge.initialize();
    _log.d(
      'WindowControlBridge ready: hasNativeChannel=${windowBridge.hasNativeChannel} '
      'usesFlutterTitleBar=${windowBridge.usesFlutterTitleBar}',
    );

    final desktopTrayService = DesktopTrayService(
      playbackController: playbackController,
      localeController: localeController,
      windowBridge: windowBridge,
    );
    await desktopTrayService.initialize();

    final lifecycleController = AppLifecycleController(
      windowBridge: windowBridge,
      playbackController: playbackController,
      trayService: desktopTrayService,
    );

    final systemMediaService = await SystemMediaService.initialize(
      playbackController: playbackController,
      lifecycleController: lifecycleController,
    );
    _log.d('SystemMediaService initialized');

    final lyricsManager = LyricsManager(
      database: appDatabase,
      store: libraryStore,
    );

    final radioBrowserService = RadioBrowserService();
    final radioController = RadioController(
      service: radioBrowserService,
      store: libraryStore,
    );
    unawaited(radioController.init());

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: libraryStore),
          Provider<MetadataService>.value(value: metadataService),
          Provider<SettingsRepository>.value(value: settingsRepository),
          Provider<LocaleRepository>.value(value: localeRepository),
          Provider<SystemMediaService>.value(value: systemMediaService),
          Provider<WindowControlBridge>.value(value: windowBridge),
          Provider<DesktopTrayService>.value(value: desktopTrayService),
          ChangeNotifierProvider<AppLifecycleController>.value(
            value: lifecycleController,
          ),
          Provider<LyricsManager>.value(value: lyricsManager),
          Provider<RadioBrowserService>.value(value: radioBrowserService),
          ChangeNotifierProvider<RadioController>.value(value: radioController),
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<LocaleController>.value(
            value: localeController,
          ),
          ChangeNotifierProvider<LibraryController>.value(
            value: libraryController,
          ),
          ChangeNotifierProvider<PlaylistsController>.value(
            value: playlistsController,
          ),
          ChangeNotifierProvider<TachyonSearchController>.value(
            value: searchController,
          ),
          ChangeNotifierProvider<PlaybackController>.value(
            value: playbackController,
          ),
        ],
        child: App(permissionsGranted: permissionsGranted),
      ),
    );

    _log.i('Launching root App widget');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log.d('First frame rendered: triggering aggressive post-startup memory trim');
      MemoryOptimizer.trim(level: MemoryTrimLevel.aggressive);
      MemoryOptimizer.startPeriodicTrimmer();
    });
  }
}
