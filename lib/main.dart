import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app.dart';

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

  // Spawn and initialize the Core Service Isolate
  final backendClient = TachyonIsolateBackendClient();
  await backendClient.initialize(
    dbPath: dbPath,
    cacheDirPath: cacheDirectory.path,
  );

  runApp(
    MultiProvider(
      providers: [
        // =====================================================================
        // CAPA 1: INFRAESTRUCTURA BASE Y BACKEND CLIENT
        // =====================================================================
        Provider<SharedPreferences>.value(value: sharedPreferences),
        Provider<TachyonBackendClient>.value(value: backendClient),
        Provider<LocaleRepository>(create: (_) => LocaleRepository()),
        ProxyProvider<SharedPreferences, SettingsRepository>(
          update: (_, prefs, prev) => prev ?? SettingsRepository(prefs),
        ),

        // =====================================================================
        // CAPA 2: CONTROLADORES DE ESTADO (UI Y REACTIVIDAD DESACOPLADA)
        // =====================================================================
        ChangeNotifierProxyProvider2<
          SettingsRepository,
          TachyonBackendClient,
          SettingsController
        >(
          create: (context) => SettingsController(
            settingsRepository: context.read<SettingsRepository>(),
            backendClient: context.read<TachyonBackendClient>(),
          ),
          update: (_, repo, backend, prev) =>
              prev ??
              SettingsController(
                settingsRepository: repo,
                backendClient: backend,
              ),
        ),

        ChangeNotifierProxyProvider2<
          LocaleRepository,
          SettingsController,
          LocaleController
        >(
          create: (context) {
            final repo = context.read<LocaleRepository>();
            final settings = context.read<SettingsController>();
            String initialLang = settings.appLanguage;
            if (initialLang == "defaultOption" || initialLang == "default") {
              initialLang = ui.PlatformDispatcher.instance.locale.languageCode;
            }
            return LocaleController(repo, initialLang);
          },
          update: (context, repo, settings, prev) {
            String currentLang = settings.appLanguage;
            if (currentLang == "defaultOption" || currentLang == "default") {
              currentLang = ui.PlatformDispatcher.instance.locale.languageCode;
            }
            if (prev != null && prev.currentLocaleCode != currentLang) {
              prev.setLocale(currentLang);
            }
            return prev ?? LocaleController(repo, currentLang);
          },
        ),

        ChangeNotifierProxyProvider2<
          TachyonBackendClient,
          SettingsRepository,
          LibraryController
        >(
          create: (context) => LibraryController(
            backendClient: context.read<TachyonBackendClient>(),
            settingsRepository: context.read<SettingsRepository>(),
          )..loadLibrary(),
          update: (_, backend, settings, prev) =>
              prev ??
              LibraryController(
                backendClient: backend,
                settingsRepository: settings,
              ),
        ),

        ChangeNotifierProxyProvider<TachyonBackendClient, PlaylistsController>(
          create: (context) => PlaylistsController(
            backendClient: context.read<TachyonBackendClient>(),
          )..loadPlaylists(),
          update: (_, backend, prev) =>
              prev ?? PlaylistsController(backendClient: backend),
        ),

        ChangeNotifierProxyProvider<TachyonBackendClient, TachyonSearchController>(
          create: (context) => TachyonSearchController(
            backendClient: context.read<TachyonBackendClient>(),
          ),
          update: (_, backend, prev) =>
              prev ?? TachyonSearchController(backendClient: backend),
        ),

        ChangeNotifierProxyProvider2<
          TachyonBackendClient,
          SettingsRepository,
          PlaybackController
        >(
          create: (context) => PlaybackController(
            backendClient: context.read<TachyonBackendClient>(),
            settingsRepository: context.read<SettingsRepository>(),
          ),
          update: (_, backend, repo, prev) =>
              prev ??
              PlaybackController(
                backendClient: backend,
                settingsRepository: repo,
              ),
        ),

        ChangeNotifierProxyProvider3<
          TachyonBackendClient,
          PlaybackController,
          SettingsRepository,
          LyricsController
        >(
          create: (context) => LyricsController(
            backendClient: context.read<TachyonBackendClient>(),
            playbackController: context.read<PlaybackController>(),
            settingsRepository: context.read<SettingsRepository>(),
          ),
          update: (_, backend, playback, settings, prev) =>
              prev ??
              LyricsController(
                backendClient: backend,
                playbackController: playback,
                settingsRepository: settings,
              ),
        ),
      ],
      child: const App(),
    ),
  );
}
