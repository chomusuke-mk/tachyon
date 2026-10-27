import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/albums_screen.dart';
import 'package:tachyon/features/library/presentation/artists_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

class _FileSystemLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    final stringMap = json.map(
      (key, value) => MapEntry(key, value.toString().trim()),
    );
    stringMap.removeWhere((_, value) => value.isEmpty);
    return stringMap;
  }
}

CatalogSnapshot _createScreenSnapshot() {
  return CatalogSnapshot(
    artists: const [
      RawArtistDto(id: 1, name: 'The Beatles'),
      RawArtistDto(id: 2, name: 'Pink Floyd'),
    ],
    albums: const [
      RawAlbumDto(id: 10, name: 'Abbey Road', year: 1969, artistId: 1),
      RawAlbumDto(id: 20, name: 'The Dark Side of the Moon', year: 1973, artistId: 2),
    ],
    tracks: const [
      RawTrackDto(
        id: 1001,
        filePath: '/music/beatles/come_together.mp3',
        title: 'Come Together',
        durationMs: 259000,
        fileSize: 6200000,
        modifiedAt: 1000,
        albumId: 10,
      ),
      RawTrackDto(
        id: 1002,
        filePath: '/music/pink_floyd/time.mp3',
        title: 'Time',
        durationMs: 425000,
        fileSize: 10200000,
        modifiedAt: 2000,
        albumId: 20,
      ),
    ],
    genres: const [],
    playlists: const [],
    playlistEntries: const [],
    trackArtists: const [
      TrackArtistPair(trackId: 1001, artistId: 1),
      TrackArtistPair(trackId: 1002, artistId: 2),
    ],
    trackGenres: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository settingsRepository;
  late LocaleController localeController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(prefs);
    final localeRepo = _FileSystemLocaleRepository();
    localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;
  });

  Widget buildTestWidget({required Widget child, required LibraryController library}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ChangeNotifierProvider<LibraryController>.value(value: library),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('AlbumsScreen sort popup changes sort option and toggles direction', (tester) async {
    final store = LibraryStore.fromSnapshot(_createScreenSnapshot());
    final library = LibraryController(
      settingsRepository: settingsRepository,
      store: store,
    );

    await tester.pumpWidget(buildTestWidget(
      child: const AlbumsScreen(),
      library: library,
    ));
    await tester.pumpAndSettle();

    // Default state
    expect(library.albumSortOption, equals(AlbumSortOption.title));
    expect(library.albumSortAscending, isTrue);

    // Find and tap sort button
    final sortButton = find.byIcon(Icons.sort_rounded);
    expect(sortButton, findsOneWidget);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    // The upward arrow should be visible for Title
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // Tap Year sort option
    final yearOption = find.text(localeController.localeStrings.alSortYear);
    expect(yearOption, findsOneWidget);
    await tester.tap(yearOption);
    await tester.pumpAndSettle();

    expect(library.albumSortOption, equals(AlbumSortOption.year));
    expect(library.albumSortAscending, isTrue);

    // Open popup again and tap Year to toggle descending
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    await tester.tap(yearOption);
    await tester.pumpAndSettle();

    expect(library.albumSortOption, equals(AlbumSortOption.year));
    expect(library.albumSortAscending, isFalse);

    // Open popup again and verify downward arrow
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    library.dispose();
  });

  testWidgets('ArtistsScreen sort popup changes sort option and toggles direction', (tester) async {
    final store = LibraryStore.fromSnapshot(_createScreenSnapshot());
    final library = LibraryController(
      settingsRepository: settingsRepository,
      store: store,
    );

    await tester.pumpWidget(buildTestWidget(
      child: const ArtistsScreen(),
      library: library,
    ));
    await tester.pumpAndSettle();

    // Default state
    expect(library.artistSortOption, equals(ArtistSortOption.name));
    expect(library.artistSortAscending, isTrue);

    // Find and tap sort button
    final sortButton = find.byIcon(Icons.sort_rounded);
    expect(sortButton, findsOneWidget);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    // Upward arrow visible for Name
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // Tap Tracks sort option
    final tracksOption = find.text(localeController.localeStrings.arSortTracks);
    expect(tracksOption, findsOneWidget);
    await tester.tap(tracksOption);
    await tester.pumpAndSettle();

    expect(library.artistSortOption, equals(ArtistSortOption.tracks));
    expect(library.artistSortAscending, isTrue);

    // Tap Tracks again to toggle descending
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    await tester.tap(tracksOption);
    await tester.pumpAndSettle();

    expect(library.artistSortOption, equals(ArtistSortOption.tracks));
    expect(library.artistSortAscending, isFalse);

    // Verify downward arrow
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    library.dispose();
  });
}
