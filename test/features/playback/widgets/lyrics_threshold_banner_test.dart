import 'package:flutter/foundation.dart';
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
import 'package:tachyon/features/playback/presentation/widgets/lyrics_threshold_banner.dart';

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

class _FakeLocaleRepository implements LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return {
      'np_lyrics_threshold_waiting': 'lrclib.net rate limit detected, waiting {seconds} seconds...',
      'np_lyrics_banner_dismiss': 'Dismiss',
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
    lyricsController.dispose();
    cooldownManager.dispose();
    await db.close();
  });

  Widget buildTestableWidget({VoidCallback? onDismiss}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LyricsController>.value(value: lyricsController),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LyricsThresholdBanner(onDismiss: onDismiss),
        ),
      ),
    );
  }

  testWidgets('Hidden when isThresholdWaiting is false', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsNothing);
    expect(find.byKey(const ValueKey('threshold_banner_hidden')), findsOneWidget);
  });

  testWidgets('Visible when isThresholdWaiting is true and remaining seconds > 0', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    cooldownManager.startThresholdCountdown(
      seconds: 7,
      onAutoRetry: () async {},
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('waiting 7 seconds'), findsOneWidget);

    cooldownManager.cancelThresholdCountdown();
    await tester.pumpAndSettle();
  });

  testWidgets('Updates reactively when threshold countdown updates', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    cooldownManager.startThresholdCountdown(
      seconds: 5,
      onAutoRetry: () async {},
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('waiting 5 seconds'), findsOneWidget);

    // Fast-forward 1 second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('waiting 4 seconds'), findsOneWidget);

    cooldownManager.cancelThresholdCountdown();
    await tester.pumpAndSettle();
  });

  testWidgets('Dismiss button hides banner immediately and invokes onDismiss', (tester) async {
    bool dismissedCalled = false;
    await tester.pumpWidget(buildTestableWidget(onDismiss: () {
      dismissedCalled = true;
    }));

    cooldownManager.startThresholdCountdown(
      seconds: 6,
      onAutoRetry: () async {},
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsOneWidget);

    final dismissBtn = find.byTooltip('Dismiss');
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsNothing);
    expect(dismissedCalled, isTrue);

    cooldownManager.cancelThresholdCountdown();
    await tester.pumpAndSettle();
  });

  testWidgets('Banner reappears on new countdown after previous countdown ended', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    // First countdown
    cooldownManager.startThresholdCountdown(
      seconds: 3,
      onAutoRetry: () async {},
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsOneWidget);

    // Dismiss by user
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsNothing);

    // Cancel / end countdown
    cooldownManager.cancelThresholdCountdown();
    await tester.pumpAndSettle();

    // Start a new countdown
    cooldownManager.startThresholdCountdown(
      seconds: 8,
      onAutoRetry: () async {},
    );
    lyricsController.setLyricsViewVisible(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('threshold_banner_visible')), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    cooldownManager.cancelThresholdCountdown();
    await tester.pumpAndSettle();
  });
}
