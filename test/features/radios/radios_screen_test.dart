import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/radios/presentation/radios_screen.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

class _TestPlaybackController extends PlaybackController {
  _TestPlaybackController({required super.settingsRepository});

  AudioPlayable? playedPlayable;

  @override
  Future<void> playTrack(
    AudioPlayable track, {
    List<AudioPlayable>? contextTracks,
  }) async {
    playedPlayable = track;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late AppDatabase db;
  late LibraryStore store;
  late SettingsRepository settingsRepo;
  late _TestPlaybackController playback;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;
  });

  setUp(() {
    db = AppDatabase.inMemory();
    store = LibraryStore.fromSnapshot(
      const CatalogSnapshot(
        tracks: [],
        albums: [],
        artists: [],
        genres: [],
        playlists: [],
        playlistEntries: [],
        trackArtists: [],
        trackGenres: [],
      ),
      db,
    );
    playback = _TestPlaybackController(settingsRepository: settingsRepo);
  });

  Widget createSubject() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryStore>.value(value: store),
        ChangeNotifierProvider<PlaybackController>.value(value: playback),
      ],
      child: const MaterialApp(
        home: RadiosScreen(),
      ),
    );
  }

  group('RadiosScreen Widget Tests', () {
    testWidgets('Renders empty state when no radio stations exist', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Radios'), findsOneWidget);
      expect(find.text('No Radio Stations'), findsOneWidget);
      expect(find.text('Add Station'), findsWidgets);
    });

    testWidgets('Adding a new radio station updates store and displays item', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Tap add station in app bar
      await tester.tap(find.byTooltip('Add Station'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      // Fill form
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Station Name'),
        'SomaFM Groove Salad',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream URL (HTTP/HTTPS/M3U8)'),
        'https://ice1.somafm.com/groovesalad-128-mp3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Genre'),
        'Ambient / Downtempo',
      );

      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('SomaFM Groove Salad'), findsOneWidget);
      expect(find.text('Ambient / Downtempo'), findsOneWidget);
      expect(store.radioStations.length, 1);
      expect(store.radioStations.first.name, 'SomaFM Groove Salad');
    });

    testWidgets('Tapping a radio station triggers playback.playTrack', (tester) async {
      final station = await store.saveRadioStationInStore(
        RadioStation(
          name: 'KEXP 90.3 FM',
          streamUrl: 'https://live-aac-128.kexp.org/kexp128.aac',
          genre: 'Alternative / Eclectic',
          createdAt: DateTime.now(),
        ),
      );
      expect(station, isNotNull);

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('KEXP 90.3 FM'), findsOneWidget);

      // Tap station
      await tester.tap(find.text('KEXP 90.3 FM'));
      await tester.pump();

      expect(playback.playedPlayable, isNotNull);
      expect(playback.playedPlayable?.title, 'KEXP 90.3 FM');
      expect(playback.playedPlayable?.filePath, 'https://live-aac-128.kexp.org/kexp128.aac');
      expect(playback.playedPlayable?.isStream, isTrue);
    });

    testWidgets('Toggling favorite heart button updates station favorite state', (tester) async {
      final station = await store.saveRadioStationInStore(
        RadioStation(
          name: 'BBC Radio 6 Music',
          streamUrl: 'https://stream.live.bbcsports.com/radio6.m3u8',
          genre: 'Indie / Post-Punk',
          createdAt: DateTime.now(),
        ),
      );
      expect(station, isNotNull);
      expect(station!.isFavorite, isFalse);

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Find heart icon
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();

      expect(store.radioStations.first.isFavorite, isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('Deleting a radio station removes it from store and UI', (tester) async {
      final station = await store.saveRadioStationInStore(
        RadioStation(
          name: 'Station to Delete',
          streamUrl: 'https://stream.delete.me/live.mp3',
          createdAt: DateTime.now(),
        ),
      );
      expect(station, isNotNull);

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Station to Delete'), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Tap delete
      await tester.tap(find.text('Delete Station'));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Station to Delete'), findsNothing);
      expect(store.radioStations, isEmpty);
    });
  });
}
