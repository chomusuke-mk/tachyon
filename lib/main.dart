import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app.dart';

import 'dart:ui' as ui;

import 'core/database/app_database.dart';
import 'core/services/audio_engine_service.dart';
import 'core/services/audio_player_adapter.dart';
import 'core/services/cover_cache_service.dart';
import 'core/services/metadata_extractor.dart';
import 'core/services/queue_manager.dart';
import 'core/services/lyrics_service.dart';
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
  await AudioPlayerAdapter.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  final database = AppDatabase();
  await database.init();
  final cacheDirectory = await getApplicationCacheDirectory();
  runApp(
    MultiProvider(
      providers: [
        // =====================================================================
        // CAPA 1: INFRAESTRUCTURA BASE Y SINGLETONS
        // =====================================================================
        Provider<SharedPreferences>.value(value: sharedPreferences),
        Provider<AppDatabase>.value(value: database),
        Provider<QueueManager>(create: (_) => QueueManager()),
        Provider<LocaleRepository>(create: (_) => LocaleRepository()),

        // CoverCacheService debe estar antes de MetadataExtractor (dependencia)
        ProxyProvider<AppDatabase, CoverCacheService>(
          update: (_, db, prev) =>
              prev ?? CoverCacheService(cacheDirectory: cacheDirectory),
        ),
        ProxyProvider2<AppDatabase, CoverCacheService, MetadataExtractor>(
          update: (_, db, cover, prev) =>
              prev ?? MetadataExtractor(database: db, coverCacheService: cover),
        ),
        ProxyProvider<QueueManager, AudioEngineService>(
          update: (_, queueMgr, prev) =>
              prev ?? AudioEngineService(queueManager: queueMgr),
        ),
        ProxyProvider<SharedPreferences, SettingsRepository>(
          update: (_, prefs, prev) => prev ?? SettingsRepository(prefs),
        ),

        // =====================================================================
        // CAPA 2: SERVICIOS Y REPOSITORIOS DEPENDIENTES
        // =====================================================================
        ProxyProvider<AppDatabase, LyricsService>(
          update: (_, db, prev) => prev ?? LyricsService(database: db),
        ),

        // =====================================================================
        // CAPA 3: CONTROLADORES DE ESTADO (UI Y REACTIVIDAD)
        // =====================================================================
        ChangeNotifierProxyProvider2<
          SettingsRepository,
          AudioEngineService,
          SettingsController
        >(
          create: (context) => SettingsController(
            settingsRepository: context.read<SettingsRepository>(),
            audioEngineService: context.read<AudioEngineService>(),
          ),
          update: (_, repo, audioEngine, prev) =>
              prev ??
              SettingsController(
                settingsRepository: repo,
                audioEngineService: audioEngine,
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
            return LocaleController(repo, settings.appLanguage);
          },
          update: (context, repo, settings, prev) {
            String currentLang = settings.appLanguage;
            if (currentLang == "defaultOption") {
              currentLang = ui.PlatformDispatcher.instance.locale.languageCode;
            }
            if (prev != null && prev.currentLocaleCode != currentLang) {
              prev.setLocale(currentLang);
            }
            return prev ?? LocaleController(repo, currentLang);
          },
        ),

        ChangeNotifierProxyProvider3<
          AppDatabase,
          MetadataExtractor,
          CoverCacheService,
          LibraryController
        >(
          create: (context) => LibraryController(
            database: context.read<AppDatabase>(),
            metadataExtractor: context.read<MetadataExtractor>(),
            coverCacheService: context.read<CoverCacheService>(),
          )..loadLibrary(),
          update: (_, db, meta, cover, prev) =>
              prev ??
              LibraryController(
                database: db,
                metadataExtractor: meta,
                coverCacheService: cover,
              ),
        ),

        ChangeNotifierProxyProvider<AppDatabase, PlaylistsController>(
          create: (context) =>
              PlaylistsController(database: context.read<AppDatabase>())
                ..loadPlaylists(),
          update: (_, db, prev) => prev ?? PlaylistsController(database: db),
        ),

        ChangeNotifierProxyProvider<AppDatabase, TachyonSearchController>(
          create: (context) =>
              TachyonSearchController(database: context.read<AppDatabase>()),
          update: (_, db, prev) =>
              prev ?? TachyonSearchController(database: db),
        ),

        ChangeNotifierProxyProvider3<
          AudioEngineService,
          AppDatabase,
          SettingsRepository,
          PlaybackController
        >(
          create: (context) => PlaybackController(
            audioEngineService: context.read<AudioEngineService>(),
            database: context.read<AppDatabase>(),
            settingsRepository: context.read<SettingsRepository>(),
          ),
          update: (_, audio, db, repo, prev) =>
              prev ??
              PlaybackController(
                audioEngineService: audio,
                database: db,
                settingsRepository: repo,
              ),
        ),

        ChangeNotifierProxyProvider2<
          LyricsService,
          PlaybackController,
          LyricsController
        >(
          create: (context) => LyricsController(
            lyricsService: context.read<LyricsService>(),
            playbackController: context.read<PlaybackController>(),
          ),
          update: (_, lyrics, playback, prev) =>
              prev ??
              LyricsController(
                lyricsService: lyrics,
                playbackController: playback,
              ),
        ),
      ],
      child: const App(),
    ),
  );
}
