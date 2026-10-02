import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/lyrics_sources_dialog.dart';

class _FakePlaybackController extends ChangeNotifier implements PlaybackController {
  QueueItem? _currentTrack;
  Duration _position = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);

  @override
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _positionNotifier;

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
    _positionNotifier.value = position;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTranslationClient implements LyricsTranslationClient {
  List<String> mockTranslations = [];

  @override
  Future<TranslationResult> translate(
    List<String> texts, {
    required String targetLanguage,
  }) async {
    return TranslationResult(
      originalLines: texts,
      translatedLines: mockTranslations.isNotEmpty
          ? mockTranslations
          : texts.map((t) => '[es] $t').toList(),
      targetLanguage: targetLanguage,
      isSuccess: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocaleRepository implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final base = {
      'np_lyrics_empty': 'No lyrics found for this track',
      'np_lyrics_sources': 'Lyrics sources',
      'np_lyrics_research': 'Re-search lyrics',
      'np_lyrics_resume_sync': 'Sync',
      'np_lyrics_translate': 'Translate lyrics',
      'np_lyrics_translating': 'Translating lyrics...',
      'np_lyrics_original': 'Original',
      'np_lyrics_translated': 'Translated',
      'np_lyrics_interleaved': 'Interleaved',
      'np_lyrics_sources_title': 'Lyrics Sources',
      'np_lyrics_source_local': 'Local files',
      'np_lyrics_source_local_desc': 'Embedded tags and local .lrc files',
      'np_lyrics_source_lrclib': 'lrclib.net',
      'np_lyrics_source_lrclib_desc': 'Primary server',
      'np_lyrics_source_ovh': 'lyrics.ovh',
      'np_lyrics_source_ovh_desc': 'Fallback server',
      'np_lyrics_sources_research_btn': 'Re-search',
      'np_lyrics_sources_close_btn': 'Close',
      'np_lyrics_source_embedded': 'Embedded',
      'np_lyrics_source_file': 'LRC file',
      'np_lyrics_source_none': 'No source',
    };
    final map = <String, String>{};
    for (final key in AppStringKey().allKeys) {
      map[key] = base[key] ?? key;
    }
    return map;
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
  late _FakeTranslationClient translationClient;
  late LyricsController lyricsController;
  late LocaleController localeController;

  setUp(() async {
    db = AppDatabase.inMemory();
    cooldownManager = LyricsCooldownManager();
    final mockLrclib = LrclibClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
      minPacing: Duration.zero,
    );
    final mockOvh = LyricsOvhClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    lyricsService = LyricsService(
      database: db,
      cooldownManager: cooldownManager,
      lrclibClient: mockLrclib,
      lyricsOvhClient: mockOvh,
    );
    playbackController = _FakePlaybackController();
    translationClient = _FakeTranslationClient();
    lyricsController = LyricsController(
      lyricsService: lyricsService,
      playbackController: playbackController,
      cooldownManager: cooldownManager,
      translationClient: translationClient,
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
      child: const MaterialApp(
        home: Scaffold(
          body: LyricsView(),
        ),
      ),
    );
  }

  testWidgets('Top controls bar is visible even when lyrics are empty', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Verify empty state is displayed
    expect(find.text('No lyrics found for this track'), findsOneWidget);

    // Verify top controls bar is ALSO mounted and visible
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
  });

  testWidgets('Tapping sources button opens LyricsSourcesDialog', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(LyricsSourcesDialog), findsOneWidget);
    expect(find.text('Lyrics Sources'), findsOneWidget);
  });

  testWidgets('Tapping re-search button invokes forceReSearch', (tester) async {
    const lrc = '[00:01.00]Song lyric';
    playbackController.setTrack(
      const QueueItem(
        id: '1',
        uri: 'file:///song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 120),
        extras: {'lyrics': lrc},
      ),
    );
    lyricsController.setLyricsViewVisible(true);

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    final reSearchBtn = find.byIcon(Icons.refresh_rounded);
    expect(reSearchBtn, findsOneWidget);
    await tester.tap(reSearchBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Interleaved translation mode renders both original and translated text', (tester) async {
    const lrc = '[00:01.00]Hello world\n[00:05.00]Goodbye world';
    playbackController.setTrack(
      const QueueItem(
        id: '1',
        uri: 'file:///song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 120),
        extras: {'lyrics': lrc},
      ),
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    expect(find.text('Hello world'), findsOneWidget);

    // Perform translation
    translationClient.mockTranslations = ['Hola mundo', 'Adiós mundo'];
    await lyricsController.translateLyrics();
    lyricsController.setTranslationDisplayMode(LyricsDisplayMode.interleaved);
    await tester.pumpAndSettle();

    // In interleaved mode, both original and translated text appear in the view
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Hola mundo'), findsOneWidget);
    expect(find.text('Goodbye world'), findsOneWidget);
    expect(find.text('Adiós mundo'), findsOneWidget);
  });

  testWidgets('User scroll lock displays localized sync button', (tester) async {
    const lrc = '[00:01.00]Line 1\n[00:02.00]Line 2\n[00:03.00]Line 3';
    playbackController.setTrack(
      const QueueItem(
        id: '1',
        uri: 'file:///song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 120),
        extras: {'lyrics': lrc},
      ),
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Trigger user scroll lock
    lyricsController.onUserScroll();
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);

    lyricsController.resumeAutoScroll();
    await tester.pumpAndSettle();
  });
}
