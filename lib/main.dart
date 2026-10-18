import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/system_media_service.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';
import 'package:tachyon/shared/utils/permission_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 25;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 4 * 1024 * 1024;
  try {
    SystemChannels.skia.invokeMethod<void>(
      'Skia.setResourceCacheMaxBytes',
      4 * 1024 * 1024,
    );
  } catch (_) {}

  final sharedPreferences = await SharedPreferences.getInstance();
  final appSupportDir = await getApplicationSupportDirectory();
  final cacheDirectory = await getApplicationCacheDirectory();
  final dbPath = p.join(appSupportDir.path, 'music.db');
  if (kDebugMode) {
    debugPrint("CACHE PATH: ${cacheDirectory.path}");
    debugPrint("DATA PATH: ${appSupportDir.path}");
  }
  MetadataUtils.init(
    p.join(appSupportDir.path, 'covers'),
    p.join(cacheDirectory.path, 'covers'),
  );

  // 1. Initialize Block 3 (BD) and Block 2 (Store)
  final appDatabase = AppDatabase(dbPath: dbPath);
  await appDatabase.init();

  final libraryStore = LibraryStore(appDatabase);
  await libraryStore.reloadFromDatabase();

  // 2. Initialize Block 5 (Metadata)
  final metadataService = MetadataService(
    database: appDatabase,
    store: libraryStore,
  );

  final settingsRepository = SettingsRepository(sharedPreferences);
  final localeRepository = LocaleRepository();

  // 3. Initialize Block 4 (Play Manager)
  final playbackController = PlaybackController(
    store: libraryStore,
    settingsRepository: settingsRepository,
  );

  // 4. Initialize Presentation Controllers (Block 1: UI)
  final libraryController = LibraryController(
    settingsRepository: settingsRepository,
    store: libraryStore,
    metadataService: metadataService,
  );

  final settingsController = SettingsController(
    repository: settingsRepository,
    playbackController: playbackController,
    libraryController: libraryController,
  );
  await settingsController.init();

  String resolveDefaultLanguage() {
    final systemCode = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    return languagesEndonyms.containsKey(systemCode) ? systemCode : 'en';
  }

  String initialLang = settingsController.appLanguage;
  if (initialLang == "defaultOption") {
    initialLang = resolveDefaultLanguage();
  }
  final localeController = LocaleController(localeRepository, initialLang);
  settingsController.addListener(() {
    final lang = settingsController.appLanguage;
    final effective = (lang == "defaultOption")
        ? resolveDefaultLanguage()
        : lang;
    if (localeController.currentLocaleCode != effective) {
      localeController.setLocale(effective);
    }
  });

  // Only register the default music folder and auto-scan once permissions are
  // granted; otherwise PermissionsGate does it after the user grants them.
  final permissionsGranted = await PermissionUtils.areAllGranted();
  if (permissionsGranted) {
    await settingsController.ensureDefaultMusicDirectory();
    unawaited(libraryController.scanDirectories());
  }

  final playlistsController = PlaylistsController(store: libraryStore);
  final searchController = TachyonSearchController(store: libraryStore);

  final systemMediaService = await SystemMediaService.initialize(
    playbackController: playbackController,
  );

  // 5. Initialize Block 6 (Lyrics)
  final lyricsManager = LyricsManager(
    database: appDatabase,
    store: libraryStore,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: sharedPreferences),
        Provider<AppDatabase>.value(value: appDatabase),
        ChangeNotifierProvider<LibraryStore>.value(value: libraryStore),
        Provider<MetadataService>.value(value: metadataService),
        Provider<SettingsRepository>.value(value: settingsRepository),
        Provider<LocaleRepository>.value(value: localeRepository),
        Provider<SystemMediaService>.value(value: systemMediaService),
        Provider<LyricsManager>.value(value: lyricsManager),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
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
    MemoryOptimizer.trim(aggressive: true);
    MemoryOptimizer.startPeriodicTrimmer();
  });
}
