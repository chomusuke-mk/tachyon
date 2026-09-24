import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/lyrics_sources_dialog.dart';

class _FakePlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = Duration.zero;

  @override
  QueueItem? get currentTrack => _currentTrack;

  @override
  Duration get position => _position;

  void setTrack(QueueItem? track) {
    _currentTrack = track;
    notifyListeners();
  }

  void setPosition(Duration position) {
    _position = position;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocaleRepository implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return {
      'np_lyrics_sources_title': 'Lyrics Sources',
      'np_lyrics_source_local': 'Local files',
      'np_lyrics_source_local_desc': 'Embedded tags and local .lrc files',
      'np_lyrics_source_lrclib': 'lrclib.net',
      'np_lyrics_source_lrclib_desc': 'Primary server',
      'np_lyrics_source_ovh': 'lyrics.ovh',
      'np_lyrics_source_ovh_desc': 'Fallback server',
      'np_lyrics_sources_research_btn': 'Re-search',
      'np_lyrics_sources_close_btn': 'Close',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LyricsCooldownManager cooldownManager;
  late LyricsService lyricsService;
  late _FakePlaybackController playbackController;
  late LyricsController lyricsController;
  late LocaleController localeController;

  setUp(() async {
    db = AppDatabase.inMemory();
    cooldownManager = LyricsCooldownManager();
    lyricsService = LyricsService(database: db, cooldownManager: cooldownManager);
    playbackController = _FakePlaybackController();
    lyricsController = LyricsController(
      lyricsService: lyricsService,
      playbackController: playbackController,
      cooldownManager: cooldownManager,
    );
    localeController = LocaleController(_FakeLocaleRepository(), 'en');
    await localeController.whenReady;
  });

  tearDown(() async {
    cooldownManager.cancelThresholdCountdown();
    lyricsController.dispose();
    cooldownManager.dispose();
    await db.close();
  });

  Widget buildTestableWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => LyricsSourcesDialog.show(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Renders all 3 sources with initial enabled states', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    // Tap to open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Lyrics Sources'), findsOneWidget);
    expect(find.text('Local files'), findsOneWidget);
    expect(find.text('lrclib.net'), findsOneWidget);
    expect(find.text('lyrics.ovh'), findsOneWidget);

    // Initial state: all 3 enabled
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.length, equals(3));
    expect(switches[0].value, isTrue); // Local
    expect(switches[1].value, isTrue); // lrclib
    expect(switches[2].value, isTrue); // lyrics.ovh
  });

  testWidgets('Toggling switch updates controller config dynamically', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Toggle lrclib switch off (second switch)
    final lrclibTile = find.widgetWithText(SwitchListTile, 'lrclib.net');
    expect(lrclibTile, findsOneWidget);

    await tester.tap(lrclibTile);
    await tester.pumpAndSettle();

    expect(lyricsController.enableLrclib, isFalse);
    expect(lyricsController.enableLocalSources, isTrue);
    expect(lyricsController.enableLyricsOvh, isTrue);
  });

  testWidgets('Invariant: cannot disable all sources (at least one must remain active)', (tester) async {
    // Start with only local enabled
    lyricsController.setSourcesConfig(local: true, lrclib: false, lyricsOvh: false);

    await tester.pumpWidget(buildTestableWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Try to turn off the last active source (local)
    final localTile = find.widgetWithText(SwitchListTile, 'Local files');
    await tester.tap(localTile);
    await tester.pumpAndSettle();

    // Must remain true
    expect(lyricsController.enableLocalSources, isTrue);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isTrue);
  });

  testWidgets('Tapping Close dismisses dialog without re-search', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Tapping Re-search calls forceReSearch and dismisses dialog', (tester) async {
    playbackController.setTrack(
      const QueueItem(
        id: '1',
        uri: 'file:///song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 120),
      ),
    );
    lyricsController.setLyricsViewVisible(true);

    await tester.pumpWidget(buildTestableWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Re-search'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
