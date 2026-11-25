import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/radios/data/radio_browser_service.dart';
import 'package:tachyon/features/radios/presentation/controllers/radio_controller.dart';
import 'package:tachyon/features/radios/presentation/screens/radios_screen.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_filter_picker_dialog.dart';
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
  List<AudioPlayable>? contextTrackList;

  @override
  Future<void> playTrack(
    AudioPlayable track, {
    List<AudioPlayable>? contextTracks,
  }) async {
    playedPlayable = track;
    contextTrackList = contextTracks;
  }
}

class _TestRadioBrowserService extends RadioBrowserService {
  List<RadioStation> topStationsToReturn = [];
  List<String> tagsToReturn = ['Rock', 'Jazz', 'Classical'];
  List<String> countriesToReturn = ['United Kingdom', 'France'];

  @override
  Future<List<RadioStation>> getTopStations({int limit = 40}) async {
    return topStationsToReturn;
  }

  @override
  Future<List<RadioStation>> searchStations({
    String? name,
    String? country,
    String? tag,
    int limit = 40,
  }) async {
    return topStationsToReturn.where((s) {
      if (name != null &&
          name.isNotEmpty &&
          !s.name.toLowerCase().contains(name.toLowerCase())) {
        return false;
      }
      if (country != null && country != 'All' && s.country != country) {
        return false;
      }
      if (tag != null &&
          tag != 'All' &&
          !(s.genre?.toLowerCase().contains(tag.toLowerCase()) ?? false)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<String>> getPopularTags({int limit = 30}) async => tagsToReturn;

  @override
  Future<List<String>> getPopularCountries({int limit = 30}) async =>
      countriesToReturn;

  @override
  Future<List<RadioStation>> validateAndRefreshStations(
    List<RadioStation> savedStations,
  ) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late AppDatabase db;
  late LibraryStore store;
  late SettingsRepository settingsRepo;
  late _TestPlaybackController playback;
  late _TestRadioBrowserService radioService;
  late RadioController radioController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;
  });

  setUp(() async {
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

    radioService = _TestRadioBrowserService();
    radioService.topStationsToReturn = [
      RadioStation(
        stationUuid: 'discover-uuid-1',
        name: 'Planet Rock',
        streamUrl: 'https://planet.rock/live.m3u8',
        genre: 'Rock',
        country: 'United Kingdom',
        createdAt: DateTime.now(),
      ),
      RadioStation(
        stationUuid: 'discover-uuid-2',
        name: 'FIP Jazz',
        streamUrl: 'https://fip.jazz/audio.aac',
        genre: 'Jazz',
        country: 'France',
        createdAt: DateTime.now(),
      ),
    ];

    radioController = RadioController(service: radioService, store: store);
    await radioController.init();
  });

  Widget createSubject() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        Provider<SettingsRepository>.value(value: settingsRepo),
        ChangeNotifierProvider<LibraryStore>.value(value: store),
        ChangeNotifierProvider<PlaybackController>.value(value: playback),
        Provider<RadioBrowserService>.value(value: radioService),
        ChangeNotifierProvider<RadioController>.value(value: radioController),
      ],
      child: const MaterialApp(
        home: RadiosScreen(),
      ),
    );
  }

  group('RadiosScreen Widget Tests', () {
    testWidgets('Renders tabs and empty state when no saved radio stations exist',
        (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Radios'), findsOneWidget);
      expect(find.text('My Stations'), findsOneWidget);
      expect(find.text('Discover'), findsWidgets);
      expect(find.text('No Radio Stations'), findsOneWidget);
    });

    testWidgets('Adding a new radio station with image updates store and UI',
        (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Tap add station in app bar
      await tester.tap(find.byTooltip('Add Station'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      // Fill form with name, streamUrl, and imageUrl
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Station Name'),
        'SomaFM Groove Salad',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream URL (HTTP/HTTPS/M3U8)'),
        'https://ice1.somafm.com/groovesalad-128-mp3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Logo / Image URL'),
        'https://somafm.com/img/groovesalad120.png',
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
      expect(
        store.radioStations.first.faviconUrl,
        'https://somafm.com/img/groovesalad120.png',
      );
    });

    testWidgets('Tapping a radio station loads entire list as queue in playback',
        (tester) async {
      await store.saveRadioStationInStore(
        RadioStation(
          name: 'KEXP 90.3 FM',
          streamUrl: 'https://live-aac-128.kexp.org/kexp128.aac',
          genre: 'Alternative / Eclectic',
          createdAt: DateTime.now(),
        ),
      );
      await store.saveRadioStationInStore(
        RadioStation(
          name: 'NTS Radio 1',
          streamUrl: 'https://stream.nts.live/stream',
          genre: 'Eclectic',
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('KEXP 90.3 FM'), findsOneWidget);
      expect(find.text('NTS Radio 1'), findsOneWidget);

      // Tap station
      await tester.tap(find.text('KEXP 90.3 FM'));
      await tester.pump();

      expect(playback.playedPlayable, isNotNull);
      expect(playback.playedPlayable?.title, 'KEXP 90.3 FM');
      expect(playback.contextTrackList, isNotNull);
      // Entire station list loaded in contextTracks queue!
      expect(playback.contextTrackList?.length, 2);
    });

    testWidgets('Toggling favorite heart button updates station favorite state',
        (tester) async {
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

    testWidgets('Deleting a radio station removes it from store and UI',
        (tester) async {
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

    testWidgets('Switching to Discover tab shows preloaded stations, search bar, and filter dialogs',
        (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Switch to Discover tab
      await tester.tap(find.text('Discover').first);
      await tester.pumpAndSettle();

      expect(find.text('Planet Rock'), findsOneWidget);
      expect(find.text('FIP Jazz'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All Genres'), findsOneWidget);
      expect(find.text('All Countries'), findsOneWidget);

      // Tap Genre picker button -> opens RadioFilterPickerDialog
      await tester.tap(find.text('All Genres'));
      await tester.pumpAndSettle();

      expect(find.byType(RadioFilterPickerDialog), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);

      // Select 'Rock'
      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(radioController.selectedTag, 'Rock');
    });

    testWidgets('Saving a station from Discover tab persists into LibraryStore',
        (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Switch to Discover tab
      await tester.tap(find.text('Discover').first);
      await tester.pumpAndSettle();

      expect(find.text('Planet Rock'), findsOneWidget);

      // Find bookmark add button for Planet Rock
      final bookmarkAddFinder = find.byIcon(Icons.bookmark_add_outlined);
      expect(bookmarkAddFinder, findsWidgets);

      await tester.tap(bookmarkAddFinder.first);
      await tester.pumpAndSettle();

      // Planet Rock should now be in store!
      expect(store.radioStations.length, 1);
      expect(store.radioStations.first.name, 'Planet Rock');
      expect(store.radioStations.first.stationUuid, 'discover-uuid-1');
    });

    testWidgets('Toggling Cards / List view mode persists in SettingsRepository',
        (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(settingsRepo.getCardView('radios', defaultValue: false), isFalse);

      // Tap toggle view mode in AppBar
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(settingsRepo.getCardView('radios', defaultValue: false), isTrue);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    });
  });
}
