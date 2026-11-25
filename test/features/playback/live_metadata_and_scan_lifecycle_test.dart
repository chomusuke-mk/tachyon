import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/screens/now_playing_screen.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/shell/presentation/widgets/mini_player_bar.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

// Minimal valid 1x1 PNG pixel for Image.memory verification
final Uint8List _kSamplePngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FileLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString().trim()));
  }
}

class _ControllableMetadataService extends MetadataService {
  final StreamController<ScanProgress> _controller =
      StreamController<ScanProgress>.broadcast();
  bool _scanning = false;

  _ControllableMetadataService({
    required super.database,
    required super.store,
  });

  @override
  bool get isScanning => _scanning;

  @override
  Stream<ScanProgress> get progressStream => _controller.stream;

  void emitProgress(ScanProgress progress) {
    _scanning = progress.isRunning;
    _controller.add(progress);
  }

  void closeControllable() {
    _controller.close();
  }
}

class _LiveMockPlaybackController extends PlaybackController {
  _LiveMockPlaybackController({
    required super.settingsRepository,
    super.store,
    super.metadataService,
  });

  AudioPlayable? _mockPlayable;
  bool _mockIsLiveStream = false;
  ma.AudioMetadata? _mockLiveMetadata;
  ma.AudioInfo? _mockLiveAudioInfo;

  void setMockPlayable(
    AudioPlayable? playable, {
    bool isLiveStream = false,
    ma.AudioMetadata? liveMetadata,
    ma.AudioInfo? liveAudioInfo,
  }) {
    _mockPlayable = playable;
    _mockIsLiveStream = isLiveStream;
    _mockLiveMetadata = liveMetadata;
    _mockLiveAudioInfo = liveAudioInfo;
    notifyListeners();
  }

  @override
  AudioPlayable? get currentPlayable =>
      _mockPlayable != null ? resolvePlayable(_mockPlayable!) : null;

  @override
  Track? get currentTrack {
    final p = currentPlayable;
    return p is Track ? p : null;
  }

  @override
  bool get isLiveStream => _mockIsLiveStream || (currentPlayable?.isStream ?? false);

  @override
  ma.AudioMetadata? get liveMetadata => _mockLiveMetadata;

  @override
  ma.AudioInfo? get liveAudioInfo => _mockLiveAudioInfo;

  @override
  ResolvedPlaybackMetadata? get currentDisplayMetadata {
    final playable = currentPlayable;
    if (playable == null) return null;
    return ResolvedPlaybackMetadata.resolve(
      playable: playable,
      liveMetadata: _mockLiveMetadata,
      liveAudioInfo: _mockLiveAudioInfo,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResolvedPlaybackMetadata Unit Tests', () {
    test('Radio livestream splits ICY StreamTitle, builds info badge, and exposes embedded artwork bytes', () {
      final station = RadioStation(
        id: 1,
        name: 'SomaFM Groove Salad',
        streamUrl: 'https://ice.somafm.com/groovesalad',
        genre: 'Ambient',
        createdAt: DateTime(2026),
      );
      final liveMeta = ma.AudioMetadata(
        genre: 'Downtempo',
        icy: const ma.IcyMetadata(
          streamTitle: 'Tycho - Awake',
          stationName: 'SomaFM Groove Salad',
          stationGenre: 'Ambient',
          bitrateKbps: 192,
        ),
        pictures: [
          ma.AudioPicture(
            pictureType: ma.PictureType.coverFront,
            mimeType: ma.MimeType.png,
            bytes: _kSamplePngBytes,
          ),
        ],
      );
      const liveInfo = ma.AudioInfo(
        sampleRate: 44100,
        channels: 2,
        bitrate: 192000,
        codec: 'MP3',
      );

      final resolved = ResolvedPlaybackMetadata.resolve(
        playable: station,
        liveMetadata: liveMeta,
        liveAudioInfo: liveInfo,
      );

      expect(resolved.title, equals('Awake'));
      expect(resolved.subtitle, equals('Tycho • SomaFM Groove Salad'));
      expect(resolved.liveStreamBadge, equals('Downtempo • 192 kbps • MP3'));
      expect(resolved.artworkBytes, equals(_kSamplePngBytes));
      expect(resolved.clickableArtists, isEmpty);
      expect(resolved.isFromLiveMetadata, isTrue);
    });

    test('Radio livestream without live metadata preserves station name and genre cleanly', () {
      final station = RadioStation(
        id: 2,
        name: 'Chillhop Radio',
        streamUrl: 'https://stream.chillhop.com/live',
        genre: 'Lofi / Beats',
        createdAt: DateTime(2026),
      );

      final resolved = ResolvedPlaybackMetadata.resolve(playable: station);

      expect(resolved.title, equals('Chillhop Radio'));
      expect(resolved.subtitle, equals('Lofi / Beats'));
      expect(resolved.liveStreamBadge, isNull);
      expect(resolved.artworkBytes, isNull);
      expect(resolved.isFromLiveMetadata, isFalse);
    });

    test('Pending local track overlays live AudioMetadata, whereas persisted track strictly keeps DB metadata', () {
      const pendingTrack = Track(
        id: null,
        filePath: '/music/01.flac',
        title: '01',
        durationMs: 0,
        fileSize: 1000,
        modifiedAt: 100,
        isMetadataPending: true,
      );
      final liveMeta = ma.AudioMetadata(
        title: 'Live Decoded Title',
        trackArtist: 'Live Artist',
        album: 'Live Album',
        pictures: [
          ma.AudioPicture(
            pictureType: ma.PictureType.coverFront,
            mimeType: ma.MimeType.png,
            bytes: _kSamplePngBytes,
          ),
        ],
      );

      final pendingResolved = ResolvedPlaybackMetadata.resolve(
        playable: pendingTrack,
        liveMetadata: liveMeta,
      );
      expect(pendingResolved.title, equals('Live Decoded Title'));
      expect(pendingResolved.subtitle, equals('Live Artist'));
      expect(pendingResolved.album, equals('Live Album'));
      expect(pendingResolved.artworkBytes, equals(_kSamplePngBytes));
      expect(pendingResolved.isFromLiveMetadata, isTrue);

      const savedTrack = Track(
        id: 42,
        filePath: '/music/01.flac',
        title: 'Saved DB Title',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 100,
        artists: [Artist(id: 7, name: 'Saved Artist')],
        isMetadataPending: false,
      );
      final savedResolved = ResolvedPlaybackMetadata.resolve(
        playable: savedTrack,
        liveMetadata: liveMeta,
      );
      expect(savedResolved.title, equals('Saved DB Title'));
      expect(savedResolved.subtitle, equals('Saved Artist'));
      expect(savedResolved.artworkBytes, isNull);
      expect(savedResolved.clickableArtists.length, equals(1));
      expect(savedResolved.isFromLiveMetadata, isFalse);
    });
  });

  group('PlaybackController Scan Lifecycle & Store Upgrade Tests', () {
    test('Tracks MetadataService scan lifecycle and upgrades active pending track after DB hydration', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsRepo = SettingsRepository(prefs);
      final db = AppDatabase.inMemory();
      final store = LibraryStore(db);
      final metadataService = _ControllableMetadataService(
        database: db,
        store: store,
      );
      final playback = _LiveMockPlaybackController(
        settingsRepository: settingsRepo,
        store: store,
        metadataService: metadataService,
      );

      expect(playback.isLibraryAnalysisActive, isFalse);

      const pendingPath = '/music/pending_song.mp3';
      store.stageDiscoveredFiles([
        const DiscoveredAudioFile(path: pendingPath, size: 1024, modifiedAt: 1),
      ]);
      final stagedTrack = store.getTrackByPath(pendingPath)!;
      playback.setMockPlayable(stagedTrack);

      metadataService.emitProgress(const ScanProgress(stage: ScanStage.extracting));
      await pumpEventQueue();
      expect(playback.isLibraryAnalysisActive, isTrue);

      var trackNotifications = 0;
      playback.trackListenable.addListener(() => trackNotifications++);

      // Simulate full extraction persistence completing in DB and store reloading
      await db.upsertTracks([
        const ExtractedTrackData(
          filePath: pendingPath,
          title: 'Final Analyzed Song',
          artistNames: ['Final Artist'],
          durationMs: 240000,
          fileSize: 1024,
          modifiedAt: 1,
        ),
      ]);
      await store.reloadFromDatabase();
      metadataService.emitProgress(const ScanProgress(stage: ScanStage.completed));
      await pumpEventQueue();

      expect(playback.isLibraryAnalysisActive, isFalse);
      expect(trackNotifications, greaterThan(0));
      expect(playback.currentTrack?.id, isNotNull);
      expect(playback.currentTrack?.title, equals('Final Analyzed Song'));
      expect(playback.currentTrack?.isMetadataPending, isFalse);

      playback.dispose();
      metadataService.closeControllable();
      await db.close();
    });
  });

  group('Widget Rendering of Pending Tracks, ArtworkBytes & Live Radio ICY', () {
    late LocaleController localeController;
    late SettingsRepository settingsRepo;
    late SettingsController settingsController;
    late AppDatabase db;
    late LibraryStore store;
    late LibraryController libraryController;
    late PlaylistsController playlistsController;
    late LyricsManager lyricsManager;
    late _LiveMockPlaybackController playbackController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      settingsController = SettingsController(repository: settingsRepo);
      await settingsController.init();
      localeController = LocaleController(_FileLocaleRepo(), 'en');
      await localeController.whenReady;

      db = AppDatabase.inMemory();
      store = LibraryStore.fromSnapshot(const CatalogSnapshot.empty(), db);
      libraryController = LibraryController(
        settingsRepository: settingsRepo,
        store: store,
      );
      playlistsController = PlaylistsController(store: store);
      lyricsManager = LyricsManager(database: db, store: store);
      playbackController = _LiveMockPlaybackController(
        settingsRepository: settingsRepo,
        store: store,
      );
    });

    tearDown(() async {
      playbackController.dispose();
      libraryController.dispose();
      playlistsController.dispose();
      settingsController.dispose();
      localeController.dispose();
      await db.close();
    });

    testWidgets('TrackTile shows --:-- for unanalyzed pending tracks with 0 duration', (tester) async {
      const pendingTrack = Track(
        id: null,
        filePath: '/music/unanalyzed.mp3',
        title: 'unanalyzed',
        durationMs: 0,
        fileSize: 500,
        modifiedAt: 1,
        isMetadataPending: true,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TrackTile(track: pendingTrack),
            ),
          ),
        ),
      );

      expect(find.text('unanalyzed'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
    });

    testWidgets('AlbumArtImage renders MemoryImage when artworkBytes are supplied', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlbumArtImage(
              artworkBytes: _kSamplePngBytes,
              width: 64,
              height: 64,
            ),
          ),
        ),
      );
      await tester.pump();

      final imageWidget = tester.widget<Image>(find.byType(Image));
      final provider = imageWidget.image;
      final inner = provider is ResizeImage ? provider.imageProvider : provider;
      expect(inner, isA<MemoryImage>());
      expect((inner as MemoryImage).bytes, equals(_kSamplePngBytes));
    });

    testWidgets('NowPlayingScreen and MiniPlayerBar display live radio ICY title, station subtitle, and badge', (tester) async {
      final station = RadioStation(
        id: 10,
        name: 'Nightride FM',
        streamUrl: 'https://stream.nightride.fm/nightride.mp3',
        genre: 'Synthwave',
        createdAt: DateTime(2026),
      );
      playbackController.setMockPlayable(
        station,
        isLiveStream: true,
        liveMetadata: ma.AudioMetadata(
          genre: 'Retrowave',
          icy: const ma.IcyMetadata(
            streamTitle: 'Timecop1983 - On the Run',
            stationName: 'Nightride FM',
            bitrateKbps: 320,
          ),
        ),
        liveAudioInfo: const ma.AudioInfo(
          sampleRate: 44100,
          channels: 2,
          bitrate: 320000,
          codec: 'MP3',
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<LyricsManager>.value(value: lyricsManager),
            ChangeNotifierProvider<SettingsController>.value(value: settingsController),
            ChangeNotifierProvider<LibraryStore>.value(value: store),
            ChangeNotifierProvider<LibraryController>.value(value: libraryController),
            ChangeNotifierProvider<PlaybackController>.value(value: playbackController),
            ChangeNotifierProvider<PlaylistsController>.value(value: playlistsController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: NowPlayingScreen()),
                  MiniPlayerBar(isDesktop: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('On the Run'), findsNWidgets(2));
      expect(find.text('Timecop1983 • Nightride FM'), findsNWidgets(2));
      expect(find.text('Retrowave • 320 kbps • MP3'), findsOneWidget);
    });
  });
}
