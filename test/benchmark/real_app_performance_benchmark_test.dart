import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/app.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/audio_effects_sheet.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/studio_knob.dart';
import 'package:tachyon/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

class _FileSystemLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, value.toString().trim()));
  }
}

class BenchmarkPlaybackController extends PlaybackController {
  BenchmarkPlaybackController({super.store, required super.settingsRepository});

  PlaybackState _benchmarkState = const PlaybackState.initial();
  Track? _activeTrack;
  bool _activeIsPlaying = false;
  List<EngineItem<AudioPlayable>> _activeQueue = [];
  int _activeCurrentIndex = 0;

  @override
  PlaybackState get state => _benchmarkState;

  @override
  Track? get currentTrack => _activeTrack;

  @override
  bool get isPlaying => _activeIsPlaying;

  @override
  List<EngineItem<AudioPlayable>> get queue => _activeQueue;

  @override
  int get currentIndex => _activeCurrentIndex;

  @override
  double get volume => _benchmarkState.volume;

  @override
  double get rate => _benchmarkState.rate;

  @override
  double get pitch => _benchmarkState.pitch;

  @override
  Future<void> playTrack(
    AudioPlayable track, {
    List<AudioPlayable>? contextTracks,
  }) async {
    final list = contextTracks ?? [track];
    _activeQueue = [
      for (int i = 0; i < list.length; i++) list[i].toEngineItem(position: i),
    ];
    _activeCurrentIndex = list.indexOf(track);
    if (_activeCurrentIndex == -1) _activeCurrentIndex = 0;
    _activeTrack = track is Track ? track : null;
    _activeIsPlaying = true;
    _benchmarkState = _benchmarkState.copyWith(
      playing: true,
      index: _activeCurrentIndex,
      playables: _activeQueue,
    );
    notifyListeners();
  }

  @override
  Future<void> play() async {
    _activeIsPlaying = true;
    _benchmarkState = _benchmarkState.copyWith(playing: true);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _activeIsPlaying = false;
    _benchmarkState = _benchmarkState.copyWith(playing: false);
    notifyListeners();
  }

  @override
  Future<void> setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 2.0);
    _benchmarkState = _benchmarkState.copyWith(volume: clamped);
    notifyListeners();
  }

  @override
  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(0.5, 2.0);
    _benchmarkState = _benchmarkState.copyWith(rate: clamped);
    notifyListeners();
  }

  @override
  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0);
    _benchmarkState = _benchmarkState.copyWith(pitch: clamped);
    notifyListeners();
  }

  @override
  Future<void> setEqualizer(Equalizer equalizer) async {}

  @override
  Future<void> setReverb(Reverb reverb) async {}

  @override
  Future<void> setPreamp(double preampDb) async {}

  @override
  Future<void> setCrossfeed(CrossfeedMode mode) async {}

  @override
  Future<void> setSpatializer(double width) async {}

  @override
  Future<void> setLimiter(bool enabled) async {}
}

class ScreenBenchmarkMetric {
  final String actionName;
  final double elapsedMs;
  final int pumpFrames;
  final double rssMb;
  final double rssDeltaMb;
  final bool passed;
  final String details;

  const ScreenBenchmarkMetric({
    required this.actionName,
    required this.elapsedMs,
    required this.pumpFrames,
    required this.rssMb,
    required this.rssDeltaMb,
    required this.passed,
    this.details = '',
  });
}

CatalogSnapshot _generateRealisticCatalog() {
  final artists = [
    const RawArtistDto(id: 1, name: 'Queen'),
    const RawArtistDto(id: 2, name: 'David Bowie'),
    const RawArtistDto(id: 3, name: 'Pink Floyd'),
    const RawArtistDto(id: 4, name: 'Led Zeppelin'),
    const RawArtistDto(id: 5, name: 'The Beatles'),
    const RawArtistDto(id: 6, name: 'Daft Punk'),
    const RawArtistDto(id: 7, name: 'Miles Davis'),
    const RawArtistDto(id: 8, name: 'Radiohead'),
  ];

  final albums = [
    const RawAlbumDto(
      id: 1,
      name: 'A Night at the Opera',
      artistId: 1,
      year: 1975,
    ),
    const RawAlbumDto(
      id: 2,
      name: 'The Rise and Fall of Ziggy',
      artistId: 2,
      year: 1972,
    ),
    const RawAlbumDto(
      id: 3,
      name: 'The Dark Side of the Moon',
      artistId: 3,
      year: 1973,
    ),
    const RawAlbumDto(id: 4, name: 'Led Zeppelin IV', artistId: 4, year: 1971),
    const RawAlbumDto(id: 5, name: 'Abbey Road', artistId: 5, year: 1969),
    const RawAlbumDto(id: 6, name: 'Discovery', artistId: 6, year: 2001),
    const RawAlbumDto(id: 7, name: 'Kind of Blue', artistId: 7, year: 1959),
    const RawAlbumDto(id: 8, name: 'OK Computer', artistId: 8, year: 1997),
  ];

  final genres = [
    const RawGenreDto(id: 1, name: 'Rock'),
    const RawGenreDto(id: 2, name: 'Electronic'),
    const RawGenreDto(id: 3, name: 'Jazz'),
    const RawGenreDto(id: 4, name: 'Alternative'),
    const RawGenreDto(id: 5, name: 'Progressive Rock'),
  ];

  final tracks = <RawTrackDto>[];
  final trackArtists = <TrackArtistPair>[];
  final trackGenres = <TrackGenrePair>[];

  int trackId = 1;
  for (int albumIdx = 0; albumIdx < albums.length; albumIdx++) {
    final album = albums[albumIdx];
    final artistId = album.artistId!;
    for (int t = 1; t <= 10; t++) {
      tracks.add(
        RawTrackDto(
          id: trackId,
          filePath: '/music/album_${album.id}/track_$t.mp3',
          title: '${album.name} - Track $t',
          durationMs: (180 + (t * 15)) * 1000,
          fileSize: 5000000 + (t * 100000),
          modifiedAt: 1700000000 + t,
          albumId: album.id,
          discNumber: 1,
          trackNumber: t,
        ),
      );
      trackArtists.add(TrackArtistPair(trackId: trackId, artistId: artistId));
      trackGenres.add(
        TrackGenrePair(
          trackId: trackId,
          genreId: (albumIdx % genres.length) + 1,
        ),
      );
      trackId++;
    }
  }

  final playlists = [
    const RawPlaylistDto(
      id: 1,
      name: 'Classics Selection',
      createdAt: 1700000000,
      type: 0,
    ),
    const RawPlaylistDto(
      id: 2,
      name: 'Chill Vibes',
      createdAt: 1700000100,
      type: 0,
    ),
  ];

  final playlistEntries = [
    const RawPlaylistEntryDto(
      id: 1,
      playlistId: 1,
      trackId: 1,
      position: 0,
      addedAt: 1700000001,
    ),
    const RawPlaylistEntryDto(
      id: 2,
      playlistId: 1,
      trackId: 2,
      position: 1,
      addedAt: 1700000002,
    ),
    const RawPlaylistEntryDto(
      id: 3,
      playlistId: 1,
      trackId: 11,
      position: 2,
      addedAt: 1700000003,
    ),
    const RawPlaylistEntryDto(
      id: 4,
      playlistId: 2,
      trackId: 21,
      position: 0,
      addedAt: 1700000004,
    ),
    const RawPlaylistEntryDto(
      id: 5,
      playlistId: 2,
      trackId: 31,
      position: 1,
      addedAt: 1700000005,
    ),
  ];

  return CatalogSnapshot(
    artists: artists,
    albums: albums,
    genres: genres,
    tracks: tracks,
    playlists: playlists,
    playlistEntries: playlistEntries,
    trackArtists: trackArtists,
    trackGenres: trackGenres,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tachyon Real Application Performance & Resource Benchmark', () {
    late SharedPreferences prefs;
    late SettingsRepository settingsRepository;
    late LocaleRepository localeRepository;
    late LocaleController localeController;
    late AppDatabase database;
    late LibraryStore libraryStore;
    late MetadataService metadataService;
    late BenchmarkPlaybackController playbackController;
    late SettingsController settingsController;
    late LibraryController libraryController;
    late PlaylistsController playlistsController;
    late TachyonSearchController searchController;

    final List<ScreenBenchmarkMetric> benchmarkResults = [];

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settingsRepository = SettingsRepository(prefs);

      localeRepository = _FileSystemLocaleRepository();
      localeController = LocaleController(localeRepository, 'en');
      await localeController.whenReady;

      database = AppDatabase.inMemory();
      final catalog = _generateRealisticCatalog();
      libraryStore = LibraryStore.fromSnapshot(catalog, database);

      metadataService = MetadataService(
        database: database,
        store: libraryStore,
      );

      playbackController = BenchmarkPlaybackController(
        store: libraryStore,
        settingsRepository: settingsRepository,
      );

      settingsController = SettingsController(
        repository: settingsRepository,
        playbackController: playbackController,
      );
      await settingsController.init();

      libraryController = LibraryController(
        settingsRepository: settingsRepository,
        store: libraryStore,
        metadataService: metadataService,
      );

      playlistsController = PlaylistsController(store: libraryStore);
      searchController = TachyonSearchController(store: libraryStore);
    });

    tearDownAll(() async {
      final peakRssMb = ProcessInfo.maxRss / (1024 * 1024);
      final currentRssMb = ProcessInfo.currentRss / (1024 * 1024);

      debugPrint(
        '\n====================================================================================================',
      );
      debugPrint(
        '              TACHYON REAL APPLICATION PERFORMANCE & RESOURCE BENCHMARK',
      );
      debugPrint(
        '====================================================================================================',
      );
      debugPrint(
        ' Screen / User Action                    | Latency (ms) | Frames | RAM (RSS) | RAM Δ (MB) | Status ',
      );
      debugPrint(
        '----------------------------------------------------------------------------------------------------',
      );

      for (final m in benchmarkResults) {
        final actionStr = m.actionName.padRight(40);
        final timeStr = '${m.elapsedMs.toStringAsFixed(1)} ms'.padLeft(12);
        final framesStr = m.pumpFrames.toString().padLeft(6);
        final rssStr = '${m.rssMb.toStringAsFixed(1)} MB'.padLeft(9);
        final deltaSign = m.rssDeltaMb >= 0 ? '+' : '';
        final deltaStr = '$deltaSign${m.rssDeltaMb.toStringAsFixed(2)} MB'
            .padLeft(10);
        final statusStr = m.passed ? '[PASS]' : '[FAIL]';

        debugPrint(
          '$actionStr | $timeStr | $framesStr | $rssStr | $deltaStr | $statusStr',
        );
      }

      debugPrint(
        '====================================================================================================',
      );
      debugPrint(
        ' Total Evaluated Actions: ${benchmarkResults.length} | Current RSS: ${currentRssMb.toStringAsFixed(1)} MB | Peak RSS: ${peakRssMb.toStringAsFixed(1)} MB',
      );
      debugPrint(
        '====================================================================================================\n',
      );

      playbackController.dispose();
      settingsController.dispose();
      libraryController.dispose();
      playlistsController.dispose();
      searchController.dispose();
      await database.close();
    });

    Widget buildFullApplication() {
      return MultiProvider(
        providers: [
          Provider<SharedPreferences>.value(value: prefs),
          Provider<AppDatabase>.value(value: database),
          ChangeNotifierProvider<LibraryStore>.value(value: libraryStore),
          Provider<MetadataService>.value(value: metadataService),
          Provider<SettingsRepository>.value(value: settingsRepository),
          Provider<LocaleRepository>.value(value: localeRepository),
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
        child: const App(permissionsGranted: true),
      );
    }

    Future<ScreenBenchmarkMetric> measureAction(
      WidgetTester tester, {
      required String name,
      required Future<void> Function() action,
    }) async {
      stderr.writeln('>>> [BENCHMARK START]: $name');
      final initialRss = ProcessInfo.currentRss / (1024 * 1024);
      final sw = Stopwatch()..start();

      await action();
      stderr.writeln('    Action invoked for $name, settling...');
      final pumpFrames = await tester.pumpAndSettle();

      sw.stop();
      final finalRss = ProcessInfo.currentRss / (1024 * 1024);
      final deltaRss = finalRss - initialRss;
      final elapsedMs = sw.elapsedMicroseconds / 1000.0;
      stderr.writeln(
        '<<< [BENCHMARK DONE]: $name in ${elapsedMs.toStringAsFixed(1)}ms ($pumpFrames frames)',
      );

      final err = tester.takeException();
      if (err != null) {
        stderr.writeln('*** ERROR in $name: $err');
      }

      final metric = ScreenBenchmarkMetric(
        actionName: name,
        elapsedMs: elapsedMs,
        pumpFrames: pumpFrames,
        rssMb: finalRss,
        rssDeltaMb: deltaRss,
        passed: err == null,
      );
      benchmarkResults.add(metric);
      return metric;
    }

    testWidgets(
      'Benchmark Complete Real App Flow Across All Screens and Actions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // 1. Initial Launch & Shell Mount (Tracks Tab)
        final launchMetric = await measureAction(
          tester,
          name: 'Cold Launch & Shell Render',
          action: () async {
            await tester.pumpWidget(buildFullApplication());
          },
        );
        expect(launchMetric.passed, isTrue);
        expect(find.byType(TachyonShell), findsOneWidget);
        expect(find.byType(TrackTile), findsWidgets);

        // 2. Tracks Screen Scroll Action
        final scrollMetric = await measureAction(
          tester,
          name: 'TracksScreen Vertical Scroll',
          action: () async {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -350),
            );
          },
        );
        expect(scrollMetric.passed, isTrue);

        // 3. Track Playback Selection
        final playMetric = await measureAction(
          tester,
          name: 'Track Selection & MiniPlayer Mount',
          action: () async {
            final firstTrack = libraryStore.tracks.first;
            await playbackController.playTrack(firstTrack);
          },
        );
        expect(playMetric.passed, isTrue);
        expect(find.byType(MiniPlayerBar), findsOneWidget);

        // 4. Navigate to Albums Tab
        final albumsMetric = await measureAction(
          tester,
          name: 'AlbumsScreen Navigation Rail Tab',
          action: () async {
            await tester.tap(find.byIcon(Icons.album_outlined));
          },
        );
        expect(albumsMetric.passed, isTrue);
        expect(find.byType(AlbumCard), findsWidgets);

        // 5. Open Album Detail Screen and Return
        final albumDetailMetric = await measureAction(
          tester,
          name: 'AlbumDetailScreen Open & Pop',
          action: () async {
            await tester.tap(find.byType(AlbumCard).first);
            await tester.pumpAndSettle();
            expect(find.byType(AlbumDetailScreen), findsOneWidget);
            Navigator.of(tester.element(find.byType(AlbumDetailScreen))).pop();
          },
        );
        expect(albumDetailMetric.passed, isTrue);

        // 6. Navigate to Artists Tab
        final artistsMetric = await measureAction(
          tester,
          name: 'ArtistsScreen Navigation Rail Tab',
          action: () async {
            await tester.tap(find.byIcon(Icons.person_outline));
          },
        );
        expect(artistsMetric.passed, isTrue);

        // 7. Open Artist Detail Screen and Return
        final artistDetailMetric = await measureAction(
          tester,
          name: 'ArtistDetailScreen Open & Pop',
          action: () async {
            await tester.tap(find.text('Queen').first);
            await tester.pumpAndSettle();
            expect(find.byType(ArtistDetailScreen), findsOneWidget);
            Navigator.of(tester.element(find.byType(ArtistDetailScreen))).pop();
          },
        );
        expect(artistDetailMetric.passed, isTrue);

        // 8. Navigate to Playlists Tab & Create Playlist
        final playlistsMetric = await measureAction(
          tester,
          name: 'PlaylistsScreen Tab & Create Action',
          action: () async {
            await tester.tap(find.byIcon(Icons.playlist_play_outlined));
            await tester.pumpAndSettle();
            await playlistsController.createPlaylist('Benchmark Playlist');
          },
        );
        expect(playlistsMetric.passed, isTrue);
        expect(find.text('Benchmark Playlist'), findsOneWidget);

        // 9. Open Playlist Detail Screen and Return
        final playlistDetailMetric = await measureAction(
          tester,
          name: 'PlaylistDetailScreen Open & Pop',
          action: () async {
            await tester.tap(find.text('Classics Selection').first);
            await tester.pumpAndSettle();
            expect(find.byType(PlaylistDetailScreen), findsOneWidget);
            Navigator.of(tester.element(find.byType(PlaylistDetailScreen)))
                .pop();
          },
        );
        expect(playlistDetailMetric.passed, isTrue);

        // 10. Navigate to Genres Tab
        final genresMetric = await measureAction(
          tester,
          name: 'GenresScreen Navigation Rail Tab',
          action: () async {
            await tester.tap(find.byIcon(Icons.category_outlined));
          },
        );
        expect(genresMetric.passed, isTrue);
        expect(find.text('Rock'), findsWidgets);

        // 11. Navigate to Folders Tab
        final foldersMetric = await measureAction(
          tester,
          name: 'FoldersScreen Navigation Rail Tab',
          action: () async {
            await tester.tap(find.byIcon(Icons.folder_outlined));
          },
        );
        expect(foldersMetric.passed, isTrue);

        // 12. Navigate to Settings Tab & Toggle Theme
        final settingsMetric = await measureAction(
          tester,
          name: 'SettingsScreen & Full Theme Rebuild',
          action: () async {
            await tester.tap(find.byIcon(Icons.settings_outlined));
            await tester.pumpAndSettle();

            // Full App tree rebuild test: Dark -> Light -> Dark
            await settingsController.setThemeMode(ThemeMode.light);
            await tester.pumpAndSettle();
            await settingsController.setThemeMode(ThemeMode.dark);
          },
        );
        expect(settingsMetric.passed, isTrue);

        // 13. Open NowPlayingScreen Modal & Adjust Volume Slider
        final nowPlayingMetric = await measureAction(
          tester,
          name: 'NowPlayingScreen Modal & Volume Drag',
          action: () async {
            NowPlayingScreen.open(tester.element(find.byType(TachyonShell)));
            await tester.pumpAndSettle();
            expect(find.byType(NowPlayingScreen), findsOneWidget);

            // Tap volume button to open popup
            final volumeBtn = find.descendant(
              of: find.byType(NowPlayingScreen),
              matching: find.byIcon(Icons.volume_up_rounded),
            );
            if (volumeBtn.evaluate().isNotEmpty) {
              await tester.tap(volumeBtn.first);
              await tester.pumpAndSettle();
              final volumeSliders = find.byType(Slider);
              if (volumeSliders.evaluate().isNotEmpty) {
                await tester.drag(
                  volumeSliders.last,
                  const Offset(-30, 0),
                  warnIfMissed: false,
                );
                await tester.pumpAndSettle();
              }
            }

            // Toggle Play / Pause inside NowPlayingScreen
            final pauseBtn = find.descendant(
              of: find.byType(NowPlayingScreen),
              matching: find.byIcon(Icons.pause_rounded),
            );
            if (pauseBtn.evaluate().isNotEmpty) {
              await tester.tap(pauseBtn.first);
              await tester.pumpAndSettle();
            }
            final playBtn = find.descendant(
              of: find.byType(NowPlayingScreen),
              matching: find.byIcon(Icons.play_arrow_rounded),
            );
            if (playBtn.evaluate().isNotEmpty) {
              await tester.tap(playBtn.first);
              await tester.pumpAndSettle();
            }

            // Close modal
            Navigator.of(tester.element(find.byType(NowPlayingScreen))).pop();
          },
        );
        expect(nowPlayingMetric.passed, isTrue);

        // 14. Open AudioEffectsSheet Modal & Tune Equalizer and Reverb
        final effectsMetric = await measureAction(
          tester,
          name: 'AudioEffectsSheet & EQ / Reverb DSP',
          action: () async {
            NowPlayingScreen.open(tester.element(find.byType(TachyonShell)));
            await tester.pumpAndSettle();

            // Open Audio Effects dialog
            final eqBtn = find.descendant(
              of: find.byType(NowPlayingScreen),
              matching: find.byIcon(Icons.equalizer_rounded),
            );
            await tester.tap(eqBtn.first);
            await tester.pumpAndSettle();
            expect(find.byType(AudioEffectsSheet), findsOneWidget);

            // Enable Equalizer and tune band 0
            await settingsController.setEqualizerEnabled(true);
            await tester.pumpAndSettle();
            await settingsController.setEqualizerBandGain(0, 4.5);
            await tester.pumpAndSettle();

            // Enable Reverb and switch preset
            await settingsController.setReverbEnabled(true);
            await tester.pumpAndSettle();
            await settingsController.setReverbPreset('concertHall');
            await tester.pumpAndSettle();
            expect(settingsController.reverbPreset, equals('concertHall'));

            // Test StudioKnob interaction
            expect(find.byType(StudioKnob), findsWidgets);
            await tester.drag(
              find.byType(StudioKnob).first,
              const Offset(0, -30),
              warnIfMissed: false,
            );
            await tester.pumpAndSettle();

            // Pop effects dialog and now playing screen
            Navigator.of(tester.element(find.byType(AudioEffectsSheet))).pop();
            await tester.pumpAndSettle();
            Navigator.of(tester.element(find.byType(NowPlayingScreen))).pop();
          },
        );
        expect(effectsMetric.passed, isTrue);

        // 15. Navigate back to Tracks & Open Search Screen with Real-Time Debounce
        final searchMetric = await measureAction(
          tester,
          name: 'SearchScreen & Real-Time Debounce',
          action: () async {
            await tester.tap(find.byIcon(Icons.music_note_outlined));
            await tester.pumpAndSettle();

            // Open Search
            await tester.tap(find.byIcon(Icons.search_rounded).first);
            await tester.pumpAndSettle();
            expect(find.byType(SearchScreen), findsOneWidget);

            // Enter text and wait for debounce
            await tester.enterText(find.byType(TextField), 'Ziggy');
            await tester.pump(const Duration(milliseconds: 350));
            await tester.pumpAndSettle();
            expect(searchController.matchedTracks, isNotEmpty);

            // Return back
            Navigator.of(tester.element(find.byType(SearchScreen))).pop();
          },
        );
        expect(searchMetric.passed, isTrue);

        // Summary assertions: All actions passed and responded smoothly
        for (final metric in benchmarkResults) {
          expect(
            metric.passed,
            isTrue,
            reason: '${metric.actionName} failed execution',
          );
          expect(
            metric.elapsedMs,
            lessThan(3000.0),
            reason: '${metric.actionName} took too long: ${metric.elapsedMs}ms',
          );
        }
      },
    );
  });
}
