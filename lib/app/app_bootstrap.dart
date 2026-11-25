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
  /// Initializes all application dependencies and launches the Flutter UI.
  static Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    await MiniaudioPlayer.ensureInitialized(
      rootIsolateToken: kIsWeb ? null : ServicesBinding.rootIsolateToken,
    );
    PaintingBinding.instance.imageCache.maximumSize =
        AppMemoryCoordinator.activeImageCacheMaxSize;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        AppMemoryCoordinator.activeImageCacheMaxBytes;
    MiniaudioPlayer.config(
      logLevel: (kDebugMode || kIsWeb)
          ? MiniaudioLogLevel.debug
          : MiniaudioLogLevel.error,
    );
    try {
      await SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        AppMemoryCoordinator.activeSkiaCacheMaxBytes,
      );
    } catch (_) {}

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
      if (kDebugMode) {
        debugPrint('CACHE PATH: ${cacheDirectory.path}');
        debugPrint('DATA PATH: ${appSupportDir.path}');
      }
      MetadataUtils.init(
        p.join(appSupportDir.path, 'covers'),
        p.join(cacheDirectory.path, 'covers'),
      );
    }

    final appDatabase = AppDatabase(dbPath: dbPath);
    await appDatabase.init();

    final libraryStore = LibraryStore(appDatabase);
    await libraryStore.reloadFromDatabase();

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
    if (permissionsGranted) {
      await settingsController.ensureDefaultMusicDirectory();
      unawaited(libraryController.scanDirectories());
    }

    final playlistsController = PlaylistsController(store: libraryStore);
    final searchController = TachyonSearchController(store: libraryStore);

    final windowBridge = WindowControlBridge();
    await windowBridge.initialize();

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      MemoryOptimizer.trim(level: MemoryTrimLevel.aggressive);
      MemoryOptimizer.startPeriodicTrimmer();
    });
  }
}
