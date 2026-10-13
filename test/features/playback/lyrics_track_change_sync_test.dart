import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/backend/services/lrc_parser.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

String _lrc(String prefix, int count, {int stepSeconds = 4}) {
  final buffer = StringBuffer();
  for (int i = 0; i < count; i++) {
    final s = 1 + i * stepSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    buffer.writeln('[$mm:$ss.00]$prefix Line ${i + 1} with extra words here');
  }
  return buffer.toString();
}

/// Backend whose lyrics for "remote" tracks resolve only when the test
/// completes the corresponding completer (simulating a slow API call).
class _DelayedBackendClient extends DirectTachyonBackendClient {
  _DelayedBackendClient(AppDatabase db) : super(database: db);

  final Map<String, Completer<void>> pending = {};
  final Set<String> remotePaths = {};

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
    if (remotePaths.contains(filePath)) {
      final completer = pending.putIfAbsent(filePath, Completer<void>.new);
      await completer.future;
    }
    final parsed = LrcParser.parse(
      _lrc(filePath.contains('b') ? 'B' : 'A', 40),
    );
    return LyricsResult(
      lyricsId: trackId,
      lyrics: parsed,
      source: LyricsSource.lrclib,
      state: LyricsSourceState.found,
      isSynced: true,
    );
  }

  final Map<int, Completer<void>> pendingTranslations = {};
  bool delayTranslations = false;
  final Set<int> remoteTranslationIds = {};

  @override
  Future<List<String>?> translateLyrics({
    required int lyricsId,
    required String targetLang,
    String? sourceLang,
    required List<String> rawLines,
  }) async {
    if (delayTranslations && remoteTranslationIds.contains(lyricsId)) {
      await pendingTranslations
          .putIfAbsent(lyricsId, Completer<void>.new)
          .future;
    }
    return rawLines.map((l) => 'TR $l translated text').toList();
  }
}

class _Playback extends ChangeNotifier implements PlaybackController {
  @override
  Track? currentTrack;

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  @override
  ValueListenable<Duration> get positionListenable => _position;
  @override
  Duration get position => _position.value;
  set position(Duration v) => _position.value = v;

  /// Mirrors the real controller: position notifier first, then discrete notify.
  void changeTrack(Track track, Duration pos) {
    currentTrack = track;
    _position.value = pos;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration p) async => _position.value = p;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository settingsRepo;
  late AppDatabase db;
  late LocaleController locale;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    settingsRepo = SettingsRepository(await SharedPreferences.getInstance());
    db = AppDatabase.inMemory();
    locale = LocaleController(_EmptyLocaleRepository(), 'en');
    await locale.whenReady;
  });

  tearDownAll(() async => db.close());

  const trackA = Track(
    id: 1,
    filePath: '/music/a.mp3',
    title: 'A',
    durationMs: 200000,
    fileSize: 1,
    modifiedAt: 1,
    artists: [Artist(id: 1, name: 'X')],
  );
  const trackB = Track(
    id: 2,
    filePath: '/music/b.mp3',
    title: 'B',
    durationMs: 200000,
    fileSize: 1,
    modifiedAt: 1,
    artists: [Artist(id: 1, name: 'X')],
  );

  Widget host(_Playback playback, LyricsController lyrics) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackController>.value(value: playback),
        ChangeNotifierProvider<LyricsController>.value(value: lyrics),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final p = context.watch<PlaybackController>();
              return LyricsView(filePath: p.currentTrack!.filePath);
            },
          ),
        ),
      ),
    );
  }

  /// Returns the `X Line N` id of the line rendered closest to the viewport center.
  String centeredLine(WidgetTester tester) {
    final viewport = tester.getRect(find.byType(ListView));
    final idRegex = RegExp(r'[AB] Line \d+');
    String? best;
    double bestDist = double.infinity;
    for (final element in find.textContaining('Line ').evaluate()) {
      final box = element.renderObject as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final d = (center.dy - viewport.center.dy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = idRegex.firstMatch((element.widget as Text).data ?? '')?.group(0);
      }
    }
    return best ?? '';
  }

  for (final mode in LyricsDisplayMode.values) {
    for (final width in [800.0, 380.0]) {
      for (final remote in [false, true]) {
        testWidgets(
          'Skip keeps sync (remote=$remote, mode=${mode.name}, width=$width)',
          (tester) async {
            tester.view.physicalSize = Size(width, 600);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await settingsRepo.setLyricsDisplayMode(mode);

            // Remote: B's lyrics come from the API and its translation is not
            // cached yet (still in flight / failed) while A's is cached.
            final backend = _DelayedBackendClient(db)
              ..delayTranslations = remote;
            if (remote) {
              backend.remotePaths.add(trackB.filePath);
              backend.remoteTranslationIds.add(trackB.id!);
            }
            final playback = _Playback()..currentTrack = trackA;
            playback.position = const Duration(seconds: 121); // A: Line 31
            final lyrics = LyricsController(
              backendClient: backend,
              playbackController: playback,
              settingsRepository: settingsRepo,
            );
            lyrics.setLyricsViewVisible(true);

            await tester.pumpWidget(host(playback, lyrics));
            await tester.pumpAndSettle();
            expect(lyrics.currentIndex, 30);
            expect(centeredLine(tester), 'A Line 31');

            // Skip to B: the backend may still report A's position for a moment.
            playback.changeTrack(trackB, const Duration(seconds: 121));
            await tester.pump();
            playback.position = Duration.zero;
            await tester.pump(const Duration(milliseconds: 300));
            playback.position = const Duration(milliseconds: 1500);
            await tester.pump(const Duration(milliseconds: 300));

            if (remote) {
              expect(lyrics.isLoading, isTrue);
              backend.pending[trackB.filePath]!.complete();
            }
            await tester.pumpAndSettle();
            expect(lyrics.hasLyrics, isTrue);
            expect(lyrics.lines.first.text, startsWith('B Line 1 '));
            expect(lyrics.currentIndex, 0);
            expect(centeredLine(tester), 'B Line 1');

            // Natural advance (250 ms ticks) follows the new song.
            var ms = 1500;
            for (int line = 2; line <= 30; line++) {
              final target = (1 + (line - 1) * 4) * 1000;
              while (ms < target) {
                ms += 250;
                playback.position = Duration(milliseconds: ms);
                await tester.pump(const Duration(milliseconds: 250));
              }
              await tester.pumpAndSettle();
              expect(lyrics.currentIndex, line - 1);
              expect(centeredLine(tester), 'B Line $line', reason: 'line $line');
            }

            lyrics.dispose();
            playback.dispose();
          },
        );
      }
    }
  }
}
