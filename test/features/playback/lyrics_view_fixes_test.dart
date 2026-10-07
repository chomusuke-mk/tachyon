import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/lrc_parser.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/lyrics_sources_dialog.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

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

class FakeBackendClient extends DirectTachyonBackendClient {
  FakeBackendClient(AppDatabase db) : super(database: db);

  String syncedLrcText = '''
[00:01.00]Line 1
[00:04.00]Line 2
[00:08.00]Line 3
[00:12.00]Line 4
[00:16.00]Line 5
[00:20.00]Line 6
[00:24.00]Line 7
[00:28.00]Line 8
[00:32.00]Line 9
[00:36.00]Line 10
[00:40.00]Line 11
[00:44.00]Line 12
[00:48.00]Line 13
[00:52.00]Line 14
[00:56.00]Line 15
''';

  String unsyncedLrcText = '''
Line 1 plain
Line 2 plain
Line 3 plain
Line 4 plain
Line 5 plain
Line 6 plain
Line 7 plain
Line 8 plain
Line 9 plain
Line 10 plain
''';

  String generate50Lines() {
    final buffer = StringBuffer();
    for (int i = 1; i <= 50; i++) {
      final s = i * 2;
      final m = s ~/ 60;
      final remS = s % 60;
      final timeStr = '${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}.00';
      buffer.writeln('[$timeStr]Track 2 Line $i');
    }
    return buffer.toString();
  }

  bool returnSynced = true;
  int resolveLyricsCallCount = 0;

  @override
  Future<LyricsResult?> resolveLyrics({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    bool allowRemote = true,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    resolveLyricsCallCount++;
    final text = filePath.contains('track2')
        ? generate50Lines()
        : (returnSynced ? syncedLrcText : unsyncedLrcText);
    final parsed = LrcParser.parse(text);
    return LyricsResult(
      lyrics: parsed,
      source: LyricsSource.file,
      state: LyricsSourceState.found,
      lyricsId: 101,
      isSynced: parsed.isSynced,
      lang: 'en',
    );
  }
}

class MockPlaybackController extends ChangeNotifier implements PlaybackController {
  @override
  List<PlaylistEntry> queue = [];

  @override
  int currentIndex = 0;

  @override
  Track? currentTrack;

  @override
  PlaylistEntry? get currentEntry =>
      queue.isNotEmpty && currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;

  void setCurrentTrack(Track? track) {
    currentTrack = track;
    notifyListeners();
  }

  @override
  bool isPlaying = true;

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  @override
  ValueListenable<Duration> get positionListenable => _position;
  @override
  Duration get position => _position.value;
  set position(Duration val) {
    _position.value = val;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration newPos) async {
    _position.value = newPos;
    notifyListeners();
  }

  @override
  bool isInfiniteMixEnabled = false;

  @override
  void toggleInfiniteMix() {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> reorderQueue(int from, int to) async {}

  @override
  Future<void> skipToQueueIndex(int index) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository settingsRepo;
  late AppDatabase db;
  late FakeBackendClient backend;
  late _FileSystemLocaleRepository localeRepo;
  late LocaleController localeControllerEs;
  late LocaleController localeControllerEn;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    db = AppDatabase.inMemory();
    backend = FakeBackendClient(db);
    localeRepo = _FileSystemLocaleRepository();

    localeControllerEs = LocaleController(localeRepo, 'es');
    await localeControllerEs.whenReady;

    localeControllerEn = LocaleController(localeRepo, 'en');
    await localeControllerEn.whenReady;
  });

  tearDownAll(() async {
    await db.close();
  });

  testWidgets('Problem 1: Manual scroll in synced lyrics does NOT auto-resume after 5 seconds', (tester) async {
    backend.returnSynced = true;
    final playback = MockPlaybackController();
    final lyrics = LyricsController(
      backendClient: backend,
      playbackController: playback,
      settingsRepository: settingsRepo,
    );

    lyrics.setLyricsViewVisible(true);

    const testTrack = Track(
      id: 1,
      filePath: '/music/track1.mp3',
      title: 'Track 1',
      durationMs: 180000,
      fileSize: 1000,
      modifiedAt: 1000,
    );

    playback.queue = [PlaylistEntry.forQueue(id: 1, track: testTrack)];
    playback.currentIndex = 0;
    playback.setCurrentTrack(testTrack);
    playback.position = const Duration(seconds: 2);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track1.mp3'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify lyrics loaded and synced
    expect(lyrics.hasLyrics, isTrue);
    expect(lyrics.isSynced, isTrue);

    // Initial state: not scroll locked, sync button not visible
    expect(lyrics.isUserScrollLocked, isFalse);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);

    // User scrolls manually
    lyrics.onUserScroll();
    await tester.pump();

    // Now locked, sync button is visible
    expect(lyrics.isUserScrollLocked, isTrue);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

    // Wait 6 seconds (previously timer was 5 seconds)
    await tester.pump(const Duration(seconds: 6));

    // Must REMAIN locked: no auto-resume timer jumping back!
    expect(lyrics.isUserScrollLocked, isTrue);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

    // Tapping sync button re-engages auto-scroll
    await tester.tap(find.byIcon(Icons.sync_rounded));
    await tester.pumpAndSettle();

    expect(lyrics.isUserScrollLocked, isFalse);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);

    lyrics.dispose();
    playback.dispose();
  });

  testWidgets('Problem 1 Case 2: Manual scroll in unsynced lyrics does NOT lock scroll or show sync button', (tester) async {
    backend.returnSynced = false;
    final playback = MockPlaybackController();
    final lyrics = LyricsController(
      backendClient: backend,
      playbackController: playback,
      settingsRepository: settingsRepo,
    );

    lyrics.setLyricsViewVisible(true);

    const testTrack = Track(
      id: 2,
      filePath: '/music/track_unsynced.mp3',
      title: 'Unsynced Track',
      durationMs: 180000,
      fileSize: 1000,
      modifiedAt: 1000,
    );

    playback.queue = [PlaylistEntry.forQueue(id: 2, track: testTrack)];
    playback.currentIndex = 0;
    playback.setCurrentTrack(testTrack);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track_unsynced.mp3'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(lyrics.hasLyrics, isTrue);
    expect(lyrics.isSynced, isFalse);

    // Simulate user scroll
    lyrics.onUserScroll();
    await tester.pump();

    // Must NOT lock scroll and must NOT show sync button
    expect(lyrics.isUserScrollLocked, isFalse);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);

    // Wait 6 seconds
    await tester.pump(const Duration(seconds: 6));
    expect(lyrics.isUserScrollLocked, isFalse);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);

    lyrics.dispose();
    playback.dispose();
  });

  testWidgets('Problem 3: Settings dialog translation tab displays Retranslate button', (tester) async {
    backend.returnSynced = true;
    final playback = MockPlaybackController();
    final lyrics = LyricsController(
      backendClient: backend,
      playbackController: playback,
      settingsRepository: settingsRepo,
    );
    final settingsCtrl = SettingsController(
      repository: settingsRepo,
      backend: backend,
    );

    lyrics.setLyricsViewVisible(true);

    const testTrack = Track(
      id: 1,
      filePath: '/music/track1.mp3',
      title: 'Track 1',
      durationMs: 180000,
      fileSize: 1000,
      modifiedAt: 1000,
    );

    playback.queue = [PlaylistEntry.forQueue(id: 1, track: testTrack)];
    playback.currentIndex = 0;
    playback.setCurrentTrack(testTrack);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsSourcesDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // On Sources tab, button is 'Volver a buscar'
    expect(find.text('Volver a buscar'), findsOneWidget);

    // Switch to Translation tab
    await tester.tap(find.text('Traducción'));
    await tester.pumpAndSettle();

    // On Translation tab, button must be 'Volver a traducir' with translate icon, NOT 'Volver a buscar'!
    expect(find.text('Volver a traducir'), findsOneWidget);
    expect(find.text('Volver a buscar'), findsNothing);
    expect(find.byIcon(Icons.translate_rounded), findsWidgets);

    lyrics.dispose();
    playback.dispose();
    settingsCtrl.dispose();
  });

  testWidgets('Problem 4: Rate limit messages explicitly distinguish lyrics server vs translation service', (tester) async {
    // In Spanish
    expect(localeControllerEs.localeStrings.npLyricsRateLimitError, contains('servicio de traducción'));
    expect(localeControllerEs.localeStrings.npLyricsThresholdWaitingFormatted(10), contains('servidor de letras'));

    // In English
    expect(localeControllerEn.localeStrings.npLyricsRateLimitError, contains('Translation service'));
    expect(localeControllerEn.localeStrings.npLyricsThresholdWaitingFormatted(10), contains('Lyrics server'));
  });

  testWidgets('Problem 2: Track transition from 15 to 50 lines centers active line and keeps it visible', (tester) async {
    backend.returnSynced = true;
    final playback = MockPlaybackController();
    final lyrics = LyricsController(
      backendClient: backend,
      playbackController: playback,
      settingsRepository: settingsRepo,
    );

    lyrics.setLyricsViewVisible(true);

    const track1 = Track(
      id: 1,
      filePath: '/music/track1.mp3',
      title: 'Track 1',
      durationMs: 180000,
      fileSize: 1024,
      modifiedAt: 1000,
      artists: [Artist(id: 1, name: 'Artist 1')],
      album: Album(id: 1, name: 'Album 1'),
    );

    const track2 = Track(
      id: 2,
      filePath: '/music/track2.mp3',
      title: 'Track 2',
      durationMs: 180000,
      fileSize: 1024,
      modifiedAt: 1000,
      artists: [Artist(id: 2, name: 'Artist 2')],
      album: Album(id: 2, name: 'Album 2'),
    );

    playback.queue = [
      PlaylistEntry.forQueue(id: 1, track: track1),
      PlaylistEntry.forQueue(id: 2, track: track2),
    ];
    playback.currentIndex = 0;
    playback.setCurrentTrack(track1);
    playback.position = const Duration(seconds: 4);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track1.mp3'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(lyrics.lines.length, equals(15));
    expect(find.text('Line 2'), findsOneWidget);

    // Now transition to track 2 (50 lines) with playback position at line 35 (seconds = 35 * 2 = 70s)
    playback.currentIndex = 1;
    playback.setCurrentTrack(track2);
    playback.position = const Duration(seconds: 70);

    // Rebuild for track 2
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track2.mp3'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(lyrics.lines.length, equals(50));
    expect(lyrics.currentIndex, equals(34)); // index 34 is Line 35 (starts at 70s)

    // Line 35 must be rendered and visible in the viewport!
    expect(find.text('Track 2 Line 35'), findsOneWidget);
    // Line 1 should not be in the viewport
    expect(find.text('Track 2 Line 1'), findsNothing);

    // Advance to line 36 (seconds = 72)
    playback.position = const Duration(seconds: 72);
    await tester.pumpAndSettle();

    expect(lyrics.currentIndex, equals(35)); // Line 36
    expect(find.text('Track 2 Line 36'), findsOneWidget);

    lyrics.dispose();
    playback.dispose();
  });

  testWidgets('Problem: Minimizing and reopening player with 50-line synced lyrics centers active line after advance', (tester) async {
    backend.returnSynced = true;
    final playback = MockPlaybackController();
    final lyrics = LyricsController(
      backendClient: backend,
      playbackController: playback,
      settingsRepository: settingsRepo,
    );

    const track = Track(
      id: 2,
      filePath: '/music/track2.mp3',
      title: 'Track 2',
      durationMs: 180000,
      fileSize: 1024,
      modifiedAt: 1000,
      artists: [Artist(id: 2, name: 'Artist 2')],
      album: Album(id: 2, name: 'Album 2'),
    );

    playback.queue = [PlaylistEntry.forQueue(id: 2, track: track)];
    playback.currentIndex = 0;
    playback.setCurrentTrack(track);
    playback.position = const Duration(seconds: 4); // Line 2

    // 1. Open NowPlaying with LyricsView
    lyrics.setLyricsViewVisible(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track2.mp3'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(lyrics.lines.length, equals(50));
    expect(lyrics.currentIndex, equals(1)); // index 1 is Line 2
    expect(find.text('Track 2 Line 2'), findsOneWidget);

    // 2. "Minimize player": close NowPlaying screen (unmount LyricsView)
    lyrics.setLyricsViewVisible(false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Text('Mini Player Shell'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3. Advance / seek track to 70s (Line 35) while player is minimized
    playback.position = const Duration(seconds: 70);
    await tester.pumpAndSettle();

    // 4. "Re-open player": push NowPlaying screen again (remount LyricsView)
    lyrics.setLyricsViewVisible(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
          ChangeNotifierProvider<LyricsController>.value(value: lyrics),
          ChangeNotifierProvider<LocaleController>.value(value: localeControllerEs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LyricsView(filePath: '/music/track2.mp3'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 5. Must have centered on Line 35, NOT stuck at offset 0
    expect(lyrics.currentIndex, equals(34)); // Line 35
    expect(find.text('Track 2 Line 35'), findsOneWidget);
    expect(find.text('Track 2 Line 1'), findsNothing);

    // 6. Natural advancement while player remains open continues to follow
    playback.position = const Duration(seconds: 72); // Line 36
    await tester.pumpAndSettle();

    expect(lyrics.currentIndex, equals(35)); // Line 36
    expect(find.text('Track 2 Line 36'), findsOneWidget);

    lyrics.dispose();
    playback.dispose();
  });

  testWidgets('ensureLyricsLoaded does not duplicate backend resolve calls while loading', (tester) async {
    final client = FakeBackendClient(db);
    final cooldown = LyricsCooldownManager();
    final playback = MockPlaybackController();
    playback.currentTrack = const Track(
      id: 999,
      filePath: '/music/track_test.mp3',
      title: 'Track Test',
      durationMs: 180000,
      fileSize: 1000,
      modifiedAt: 1000,
      artists: [Artist(name: 'Artist Test')],
    );

    final lyrics = LyricsController(
      backendClient: client,
      playbackController: playback,
      cooldownManager: cooldown,
      settingsRepository: settingsRepo,
    );
    lyrics.setLyricsViewVisible(true);

    // Call ensureLyricsLoaded twice concurrently
    final f1 = lyrics.ensureLyricsLoaded();
    final f2 = lyrics.ensureLyricsLoaded();
    await Future.wait([f1, f2]);

    expect(client.resolveLyricsCallCount, equals(1));

    lyrics.dispose();
    playback.dispose();
  });
}
