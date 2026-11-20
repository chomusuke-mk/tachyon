import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/playback/presentation/queue_drawer.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_logo_avatar.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

class _MockPlaybackController extends PlaybackController {
  _MockPlaybackController({required super.settingsRepository});

  RadioStation? _radioStation;
  Track? _track;
  bool _isRadio = false;
  final List<RadioStation> _radioQueue = [];

  void setMockRadio(RadioStation station) {
    _radioStation = station;
    _track = null;
    _isRadio = true;
    _radioQueue.clear();
    _radioQueue.add(station);
    notifyListeners();
  }

  void setMockTrack(Track track) {
    _track = track;
    _radioStation = null;
    _isRadio = false;
    notifyListeners();
  }

  RadioStation? get currentRadio => _radioStation;

  @override
  Track? get currentTrack => _track;

  @override
  AudioPlayable? get currentPlayable => _isRadio ? _radioStation : _track;

  @override
  List<AudioSource<AudioPlayable>> get queue => _isRadio
      ? _radioQueue.map((r) => r.toAudioSource()).toList()
      : super.queue;

  @override
  int get currentIndex => _isRadio ? 0 : super.currentIndex;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(repository: settingsRepo);
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;
  });

  group('AlbumArtImage Unified Image Resolver', () {
    testWidgets(
      'Renders CachedNetworkImage for remote HTTP URL with RAM bounds and BoxFit.cover',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AlbumArtImage(
                artworkUri: 'https://example.com/logo.png',
                width: 80,
                height: 80,
                quality: ThumbnailQuality.low,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );

        final cachedImageFinder = find.byType(CachedNetworkImage);
        expect(cachedImageFinder, findsOneWidget);

        final cachedImage = tester.widget<CachedNetworkImage>(
          cachedImageFinder,
        );
        expect(cachedImage.imageUrl, equals('https://example.com/logo.png'));
        expect(cachedImage.fit, equals(BoxFit.cover));
        expect(cachedImage.memCacheWidth, isNotNull);
        expect(cachedImage.memCacheHeight, isNull);
        expect(cachedImage.width, equals(80));
        expect(cachedImage.height, equals(80));
      },
    );

    testWidgets(
      'Renders Image.file for local artwork file preserving native aspect ratio with BoxFit.cover',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('album_art_test_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final testFile = File('${tempDir.path}/test_cover')
          ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlbumArtImage(
                artworkUri: testFile.path,
                width: 100,
                height: 100,
                quality: ThumbnailQuality.medium,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );

        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);

        final image = tester.widget<Image>(imageFinder);
        expect(image.fit, equals(BoxFit.cover));
        // cacheHeight must be null so Flutter decodes proportionally without squashing
        final resizeProvider = image.image as ResizeImage;
        expect(resizeProvider.width, isNotNull);
        expect(resizeProvider.height, isNull);
      },
    );

    testWidgets('Resolves RadioStation playable to remote artwork URL', (
      tester,
    ) async {
      final radio = RadioStation(
        id: 42,
        name: 'Chillhop Beats',
        streamUrl: 'https://stream.chillhop.com/live',
        faviconUrl: 'https://chillhop.com/favicon.png',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlbumArtImage(
              playable: radio,
              width: 120,
              height: 120,
              quality: ThumbnailQuality.medium,
            ),
          ),
        ),
      );

      final cachedImageFinder = find.byType(CachedNetworkImage);
      expect(cachedImageFinder, findsOneWidget);

      final cachedImage = tester.widget<CachedNetworkImage>(cachedImageFinder);
      expect(cachedImage.imageUrl, equals('https://chillhop.com/favicon.png'));
      expect(cachedImage.fit, equals(BoxFit.cover));
    });

    testWidgets(
      'Provides radio icon fallback for stream/radio playables without art',
      (tester) async {
        final radioWithoutArt = RadioStation(
          id: 99,
          name: 'Voice Radio',
          streamUrl: 'https://stream.voice.org/audio',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlbumArtImage(
                playable: radioWithoutArt,
                width: 60,
                height: 60,
              ),
            ),
          ),
        );

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byIcon(Icons.radio_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Provides album icon fallback for local tracks without artwork',
      (tester) async {
        final trackWithoutArt = Track(
          id: 7,
          filePath: '/music/acoustic.flac',
          title: 'Acoustic Solitude',
          durationMs: 210000,
          fileSize: 15000000,
          modifiedAt: 1234567,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlbumArtImage(
                playable: trackWithoutArt,
                width: 60,
                height: 60,
              ),
            ),
          ),
        );

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byIcon(Icons.album_rounded), findsOneWidget);
      },
    );
  });

  group('NowPlayingScreen and QueueDrawer Radio Station Artwork & Tooltip', () {
    testWidgets(
      'QueueView displays AlbumArtImage with playable for RadioStation items',
      (tester) async {
        final radio = RadioStation(
          id: 101,
          name: 'Electro Radio',
          streamUrl: 'https://electro.fm/stream',
          faviconUrl: 'https://electro.fm/logo.png',
          createdAt: DateTime.now(),
        );

        final playback = _MockPlaybackController(
          settingsRepository: settingsRepo,
        );
        playback.setMockRadio(radio);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
              ChangeNotifierProvider<LocaleController>.value(
                value: localeController,
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsController,
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: QueueView())),
          ),
        );
        await tester.pump();

        // Find AlbumArtImage inside queue tile
        final albumArtFinder = find.byType(AlbumArtImage);
        expect(albumArtFinder, findsWidgets);

        final albumArt = tester.widget<AlbumArtImage>(albumArtFinder.first);
        expect(albumArt.playable, isA<RadioStation>());
        expect(
          albumArt.playable?.artworkUri,
          equals('https://electro.fm/logo.png'),
        );
      },
    );

    testWidgets(
      'NowPlayingScreen displays radio-specific favorite tooltip for radio station',
      (tester) async {
        ArtworkColorResolver.cache['https://jazz.lounge/icon.png:dark:std'] =
            const Color(0xFF334455);
        ArtworkColorResolver.cache['https://jazz.lounge/icon.png:light:std'] =
            const Color(0xFF334455);

        final radio = RadioStation(
          id: 202,
          name: 'Jazz Lounge',
          streamUrl: 'https://jazz.lounge/stream',
          faviconUrl: 'https://jazz.lounge/icon.png',
          isFavorite: false,
          createdAt: DateTime.now(),
        );

        final playback = _MockPlaybackController(
          settingsRepository: settingsRepo,
        );
        playback.setMockRadio(radio);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PlaybackController>.value(value: playback),
              ChangeNotifierProvider<LocaleController>.value(
                value: localeController,
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsController,
              ),
            ],
            child: const MaterialApp(home: NowPlayingScreen()),
          ),
        );
        await tester.pump();

        // The heart button tooltip should be "Add to Favorite Stations" (rd_like), NOT "Add to Liked Songs" (np_like)
        final iconButtons = tester.widgetList<IconButton>(
          find.byType(IconButton),
        );
        final favoriteBtn = iconButtons.firstWhere(
          (btn) => btn.tooltip == localeController.localeStrings.rdLike,
        );
        expect(favoriteBtn, isNotNull);
        expect(
          favoriteBtn.tooltip,
          equals(localeController.localeStrings.rdLike),
        );
        expect(
          favoriteBtn.tooltip,
          isNot(equals(localeController.localeStrings.npLike)),
        );

        await tester.pump(const Duration(seconds: 6));
      },
    );

    testWidgets(
      'RadioLogoAvatar bounds CachedNetworkImage memory cache to prevent high RAM',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RadioLogoAvatar(
                faviconUrl: 'https://radio.example/logo.png',
                size: 48,
              ),
            ),
          ),
        );

        final cachedImageFinder = find.byType(CachedNetworkImage);
        expect(cachedImageFinder, findsOneWidget);

        final cachedImage = tester.widget<CachedNetworkImage>(
          cachedImageFinder,
        );
        expect(cachedImage.memCacheWidth, isNotNull);
        expect(cachedImage.memCacheWidth, isPositive);
        expect(cachedImage.filterQuality, equals(FilterQuality.medium));
      },
    );
  });
}
