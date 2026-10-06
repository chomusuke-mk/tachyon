import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';

import 'core/backend/backend.dart';
import 'features/library/presentation/library_controller.dart';
import 'features/locales/data/locale_repository.dart';
import 'features/locales/presentation/locale_controller.dart';
import 'features/playback/presentation/lyrics_controller.dart';
import 'features/playback/presentation/playback_controller.dart';
import 'features/playlists/presentation/playlists_controller.dart';
import 'features/search/presentation/tachyon_search_controller.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/presentation/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 15 * 1024 * 1024;

  final sharedPreferences = await SharedPreferences.getInstance();
  final appSupportDir = await getApplicationSupportDirectory();
  final cacheDirectory = await getApplicationCacheDirectory();
  final dbPath = p.join(appSupportDir.path, 'music.db');
  if (kDebugMode) {
    debugPrint("CACHE PATH: ${cacheDirectory.path}");
    debugPrint("DATA PATH: ${appSupportDir.path}");
  }
  CoverUtils.init(cacheDirectory);

  // Spawn and initialize the Core Service Isolate
  final backendClient = TachyonIsolateBackendClient();
  await backendClient.initialize(
    dbPath: dbPath,
    cacheDirPath: cacheDirectory.path,
  );

  final settingsRepository = SettingsRepository(sharedPreferences);
  final localeRepository = LocaleRepository();

  final settingsController = SettingsController(
    repository: settingsRepository,
    backend: backendClient,
  );
  await settingsController.init();

  String initialLang = settingsController.appLanguage;
  if (initialLang == "defaultOption" || initialLang == "default") {
    initialLang = ui.PlatformDispatcher.instance.locale.languageCode;
  }
  final localeController = LocaleController(localeRepository, initialLang);
  settingsController.addListener(() {
    final lang = settingsController.appLanguage;
    final effective = (lang == "defaultOption" || lang == "default")
        ? ui.PlatformDispatcher.instance.locale.languageCode
        : lang;
    if (localeController.currentLocaleCode != effective) {
      localeController.setLocale(effective);
    }
  });

  final libraryController = LibraryController(
    backend: backendClient,
    settingsRepository: settingsRepository,
  )..loadLibrary();

  final playlistsController = PlaylistsController(backend: backendClient)
    ..loadPlaylists();

  final searchController = TachyonSearchController(
    storeSupplier: () => libraryController.store,
  );

  final playbackController = PlaybackController(
    backend: backendClient,
    settingsRepository: settingsRepository,
    libraryStoreSupplier: () => libraryController.store,
  );

  final lyricsController = LyricsController(
    backendClient: backendClient,
    playbackController: playbackController,
    settingsRepository: settingsRepository,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: sharedPreferences),
        Provider<TachyonBackendClient>.value(value: backendClient),
        Provider<SettingsRepository>.value(value: settingsRepository),
        Provider<LocaleRepository>.value(value: localeRepository),
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
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
      ],
      child: const App(),
    ),
  );
}
