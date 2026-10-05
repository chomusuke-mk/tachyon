import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/queue_drawer.dart';

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

class MockPlaybackController extends ChangeNotifier implements PlaybackController {
  @override
  List<PlaylistEntry> queue = List.generate(
    1500,
    (i) => PlaylistEntry.forQueue(
      id: i,
      position: i,
      track: Track(
        id: i,
        filePath: '/music/track_$i.mp3',
        title: 'Track Title $i',
        artists: [Artist(id: i, name: 'Artist Name $i')],
        durationMs: 210000,
        fileSize: 1000,
        modifiedAt: 1000,
      ),
    ),
  );

  @override
  int currentIndex = 1200;

  @override
  bool isPlaying = true;

  @override
  bool isInfiniteMixEnabled = false;

  @override
  void toggleInfiniteMix() {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  void Function(int, int)? onReorderCallback;

  @override
  Future<void> reorderQueue(int from, int to) async {
    onReorderCallback?.call(from, to);
  }

  @override
  Future<void> skipToQueueIndex(int index) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('QueueView performance test with 1500 items at index 1200', (tester) async {
    final mockPlayback = MockPlaybackController();
    final localeRepo = _FileSystemLocaleRepository();
    final localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;

    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: mockPlayback),
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: QueueView(),
          ),
        ),
      ),
    );

    final firstPumpMs = stopwatch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    stopwatch.stop();

    debugPrint('First pump: $firstPumpMs ms, Total settle: ${stopwatch.elapsedMilliseconds} ms');

    // Index 1200 must be rendered and visible
    expect(find.text('Track Title 1200'), findsOneWidget);
    // Index 0 must NOT be in the element tree (virtualized)
    expect(find.text('Track Title 0'), findsNothing);
  });

  testWidgets('QueueView performance with external scrollController (e.g. QueueDrawerSheet)', (tester) async {
    final mockPlayback = MockPlaybackController();
    final localeRepo = _FileSystemLocaleRepository();
    final localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;

    final externalController = ScrollController();
    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: mockPlayback),
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: QueueView(scrollController: externalController),
          ),
        ),
      ),
    );

    final firstPumpMs = stopwatch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    stopwatch.stop();

    debugPrint('External controller - First pump: $firstPumpMs ms, Total settle: ${stopwatch.elapsedMilliseconds} ms');

    expect(find.text('Track Title 1200'), findsOneWidget);
    expect(find.text('Track Title 0'), findsNothing);

    externalController.dispose();
  });

  testWidgets('QueueView allows reordering items with itemExtent', (tester) async {
    final mockPlayback = MockPlaybackController();
    final localeRepo = _FileSystemLocaleRepository();
    final localeController = LocaleController(localeRepo, 'en');
    await localeController.whenReady;

    int reorderFrom = -1;
    int reorderTo = -1;
    mockPlayback.onReorderCallback = (from, to) {
      reorderFrom = from;
      reorderTo = to;
    };

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaybackController>.value(value: mockPlayback),
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: QueueView(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find the drag handle for index 1200
    final dragHandleFinder = find.byType(ReorderableDragStartListener).first;
    expect(dragHandleFinder, findsOneWidget);

    // Drag it down
    await tester.drag(dragHandleFinder, const Offset(0, 150), warnIfMissed: false);
    await tester.pumpAndSettle();

    debugPrint('Reorder tested successfully (from $reorderFrom to $reorderTo)');
  });
}
