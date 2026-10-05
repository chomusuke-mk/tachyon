import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/shared/widgets/artist_card.dart';

class _TestLocaleRepo extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final json = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late LocaleController esLocaleController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    localeController = LocaleController(_TestLocaleRepo(), 'en');
    await localeController.whenReady;

    esLocaleController = LocaleController(_TestLocaleRepo(), 'es');
    await esLocaleController.whenReady;
  });

  Widget buildTestApp(Widget child, {LocaleController? controller}) {
    return ChangeNotifierProvider<LocaleController>.value(
      value: controller ?? localeController,
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }

  final testArtist = Artist(
    id: 1,
    name: 'Radiohead',
    albums: [],
    tracks: [],
  );

  final testAlbum = Album(
    id: 10,
    name: 'OK Computer',
    artist: testArtist,
    year: 1997,
    tracks: [],
  );

  final testTrack = Track(
    id: 100,
    title: 'Paranoid Android',
    filePath: '/music/radiohead/ok_computer/02_paranoid_android.mp3',
    fileSize: 1000,
    modifiedAt: 0,
    durationMs: 387000,
    artists: [testArtist],
    album: testAlbum,
  );

  testAlbum.tracks.add(testTrack);
  testArtist.tracks.add(testTrack);
  testArtist.albums.add(testAlbum);

  group('AlbumCard hover play button', () {
    testWidgets('shows play button on hover with alPlayAll tooltip and handles callbacks',
        (tester) async {
      bool tapped = false;
      bool played = false;

      await tester.pumpWidget(
        buildTestApp(
          AlbumCard(
            album: testAlbum,
            width: 150,
            onTap: () => tapped = true,
            onPlay: () => played = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, opacity is 0.0
      final opacityFinder = find.byType(AnimatedOpacity);
      expect(opacityFinder, findsOneWidget);
      AnimatedOpacity opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(AlbumCard)));
      await tester.pumpAndSettle();

      // Opacity should now be 1.0
      opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 1.0);

      // Find the play button inside AlbumCard
      final playButtonFinder = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
      expect(playButtonFinder, findsOneWidget);

      final iconButton = tester.widget<IconButton>(playButtonFinder);
      expect(iconButton.tooltip, localeController.localeStrings.alPlayAll);

      // Tap the play button
      await tester.tap(playButtonFinder);
      await tester.pumpAndSettle();

      expect(played, isTrue);
      expect(tapped, isFalse); // Play button click must NOT trigger card onTap

      // Tap card body outside play button
      final topLeft = tester.getTopLeft(find.byType(AlbumCard));
      await tester.tapAt(topLeft + const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);

      // Mouse exit hides play button
      await gesture.moveTo(const Offset(800, 800));
      await tester.pumpAndSettle();

      opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 0.0);
    });
  });

  group('AlbumListTile hover play button', () {
    testWidgets('shows play button on hover with alPlayAll tooltip and handles callbacks',
        (tester) async {
      bool tapped = false;
      bool played = false;

      await tester.pumpWidget(
        buildTestApp(
          AlbumListTile(
            album: testAlbum,
            onTap: () => tapped = true,
            onPlay: () => played = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially trailing is chevron
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.play_arrow_rounded), findsNothing);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(AlbumListTile)));
      await tester.pumpAndSettle();

      // On hover, trailing replaces chevron with play button
      final playButtonFinder = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
      expect(playButtonFinder, findsOneWidget);

      final iconButton = tester.widget<IconButton>(playButtonFinder);
      expect(iconButton.tooltip, localeController.localeStrings.alPlayAll);

      // Tap play button
      await tester.tap(playButtonFinder);
      await tester.pumpAndSettle();

      expect(played, isTrue);
      expect(tapped, isFalse);

      // Mouse exit restores chevron
      await gesture.moveTo(const Offset(800, 800));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('ArtistCard hover play button', () {
    testWidgets('shows play button on hover with arPlayAll tooltip and handles callbacks',
        (tester) async {
      bool tapped = false;
      bool played = false;

      await tester.pumpWidget(
        buildTestApp(
          ArtistCard(
            artist: testArtist,
            radius: 50,
            onTap: () => tapped = true,
            onPlay: () => played = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, opacity is 0.0
      final opacityFinder = find.byType(AnimatedOpacity);
      expect(opacityFinder, findsOneWidget);
      AnimatedOpacity opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(ArtistCard)));
      await tester.pumpAndSettle();

      // Opacity should now be 1.0
      opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 1.0);

      // Find the play button inside ArtistCard
      final playButtonFinder = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
      expect(playButtonFinder, findsOneWidget);

      final iconButton = tester.widget<IconButton>(playButtonFinder);
      expect(iconButton.tooltip, localeController.localeStrings.arPlayAll);

      // Tap the play button
      await tester.tap(playButtonFinder);
      await tester.pumpAndSettle();

      expect(played, isTrue);
      expect(tapped, isFalse); // Play button click must NOT trigger card onTap

      // Tap card body outside play button
      final topLeft = tester.getTopLeft(find.byType(ArtistCard));
      await tester.tapAt(topLeft + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);

      // Mouse exit hides play button
      await gesture.moveTo(const Offset(800, 800));
      await tester.pumpAndSettle();

      opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 0.0);
    });
  });

  group('ArtistListTile hover play button', () {
    testWidgets('shows play button on hover with arPlayAll tooltip and handles callbacks',
        (tester) async {
      bool tapped = false;
      bool played = false;

      await tester.pumpWidget(
        buildTestApp(
          ArtistListTile(
            artist: testArtist,
            onTap: () => tapped = true,
            onPlay: () => played = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially trailing is chevron
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.play_arrow_rounded), findsNothing);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(ArtistListTile)));
      await tester.pumpAndSettle();

      // On hover, trailing replaces chevron with play button
      final playButtonFinder = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
      expect(playButtonFinder, findsOneWidget);

      final iconButton = tester.widget<IconButton>(playButtonFinder);
      expect(iconButton.tooltip, localeController.localeStrings.arPlayAll);

      // Tap play button
      await tester.tap(playButtonFinder);
      await tester.pumpAndSettle();

      expect(played, isTrue);
      expect(tapped, isFalse);

      // Mouse exit restores chevron
      await gesture.moveTo(const Offset(800, 800));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('Spanish i18n localization for hover tooltips', () {
    testWidgets('tooltips match Spanish translations in Spanish locale', (tester) async {
      expect(esLocaleController.localeStrings.alPlayAll, 'Reproducir álbum');
      expect(esLocaleController.localeStrings.arPlayAll, 'Reproducir todas las pistas');

      await tester.pumpWidget(
        buildTestApp(
          Column(
            children: [
              AlbumCard(album: testAlbum, width: 120),
              ArtistCard(artist: testArtist, radius: 40),
            ],
          ),
          controller: esLocaleController,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Hover over AlbumCard
      await gesture.moveTo(tester.getCenter(find.byType(AlbumCard)));
      await tester.pumpAndSettle();

      final albumPlayButton = find.descendant(
        of: find.byType(AlbumCard),
        matching: find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
      );
      expect(albumPlayButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(albumPlayButton).tooltip,
        'Reproducir álbum',
      );

      // Hover over ArtistCard
      await gesture.moveTo(tester.getCenter(find.byType(ArtistCard)));
      await tester.pumpAndSettle();

      final artistPlayButton = find.descendant(
        of: find.byType(ArtistCard),
        matching: find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
      );
      expect(artistPlayButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(artistPlayButton).tooltip,
        'Reproducir todas las pistas',
      );
    });
  });
}
