import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/playback/presentation/waveform_slider.dart';

void main() {
  group('WaveformSlider Widget Tests', () {
    testWidgets('Renders waveform slider and initial time text counters', (
      WidgetTester tester,
    ) async {
      Duration? soughtDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 45),
                  duration: const Duration(seconds: 180),
                  onSeek: (dur) => soughtDuration = dur,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify elapsed time label
      expect(find.text('0:45'), findsOneWidget);
      // Verify total/remaining time label
      expect(find.text('-2:15'), findsOneWidget);
      // CustomPaint is present for waveform
      expect(find.byType(CustomPaint), findsWidgets);
      expect(soughtDuration, isNull);
    });

    testWidgets('Tapping duration toggle switches between remaining and total duration', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 60),
                  duration: const Duration(seconds: 200),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // Initial state displays negative remaining duration
      expect(find.text('-2:20'), findsOneWidget);

      // Tap on the remaining duration text
      await tester.tap(find.text('-2:20'));
      await tester.pump();

      // Now displays full total duration
      expect(find.text('3:20'), findsOneWidget);

      // Tap again to switch back
      await tester.tap(find.text('3:20'));
      await tester.pump();
      expect(find.text('-2:20'), findsOneWidget);
    });

    testWidgets('Playlist position indicator displays index and total count when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  currentIndex: 3,
                  totalCount: 15,
                  playlistPosition: () => const Duration(minutes: 8),
                  playlistDuration: () => const Duration(minutes: 45),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // Shows "3 / 15"
      expect(find.text('3 / 15'), findsOneWidget);

      // Tap toggles playlist duration readout
      await tester.tap(find.text('3 / 15'));
      await tester.pump();
      expect(find.text('8:00 / 45:00'), findsOneWidget);
    });

    testWidgets('Tap-to-seek calls onSeek with duration clamped to position fraction', (
      WidgetTester tester,
    ) async {
      Duration? soughtDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: Duration.zero,
                  duration: const Duration(seconds: 200),
                  onSeek: (dur) => soughtDuration = dur,
                ),
              ),
            ),
          ),
        ),
      );

      // Find the gesture detector over the waveform area
      final gestureFinder = find.byType(GestureDetector).first;
      final topLeft = tester.getTopLeft(gestureFinder);
      final size = tester.getSize(gestureFinder);

      // Tap exactly at 50% along the width (200px)
      await tester.tapAt(Offset(topLeft.dx + size.width * 0.5, topLeft.dy + size.height * 0.5));
      await tester.pump();

      // Expected sought duration is ~100s (50% of 200s)
      expect(soughtDuration, isNotNull);
      expect(soughtDuration!.inSeconds, equals(100));
    });

    testWidgets('Drag clamping suppresses intermediate seeks and fires onSeek on drag end', (
      WidgetTester tester,
    ) async {
      final seeks = <Duration>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 50),
                  duration: const Duration(seconds: 100),
                  onSeek: (dur) => seeks.add(dur),
                ),
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byType(GestureDetector).first;

      // Start drag at center (50% = 50s) and drag past right boundary (+500px)
      final gesture = await tester.startGesture(tester.getCenter(gestureFinder));
      await gesture.moveBy(const Offset(500, 0));
      await tester.pump();

      // During active drag, onSeek must NOT have been called yet
      expect(seeks, isEmpty);

      // Finish drag
      await gesture.up();
      await tester.pump();

      // Upon release, onSeek is called clamped to max duration (100s)
      expect(seeks.length, equals(1));
      expect(seeks.first.inSeconds, equals(100));
    });

    testWidgets('Negative drag coordinates clamp to 0 duration safely', (
      WidgetTester tester,
    ) async {
      final seeks = <Duration>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 50),
                  duration: const Duration(seconds: 100),
                  onSeek: (dur) => seeks.add(dur),
                ),
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byType(GestureDetector).first;

      // Drag far to the left past 0
      final gesture = await tester.startGesture(tester.getCenter(gestureFinder));
      await gesture.moveBy(const Offset(-600, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seeks.length, equals(1));
      expect(seeks.first, equals(Duration.zero));
    });

    testWidgets('Edge case: zero duration does not cause division by zero or NaN crashes', (
      WidgetTester tester,
    ) async {
      Duration? soughtDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: Duration.zero,
                  duration: Duration.zero,
                  onSeek: (dur) => soughtDuration = dur,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('-0:00'), findsOneWidget);
      final gestureFinder = find.byType(GestureDetector).first;
      await tester.tap(gestureFinder);
      await tester.pump();

      expect(soughtDuration, isNotNull);
      expect(soughtDuration!.inMilliseconds, lessThanOrEqualTo(1));
    });

    testWidgets('Edge case: position exceeding duration is clamped gracefully', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 150),
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // Elapsed time displays clamped position
      expect(find.text('1:40'), findsOneWidget);
      expect(find.text('-0:00'), findsOneWidget);
    });

    testWidgets('WaveformSlider can be safely wrapped in a RepaintBoundary for render isolation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: RepaintBoundary(
                  key: const ValueKey('waveform_repaint_boundary'),
                  child: WaveformSlider(
                    position: const Duration(seconds: 25),
                    duration: const Duration(seconds: 100),
                    isBuffering: true,
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('waveform_repaint_boundary')), findsOneWidget);
      final renderRepaint = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('waveform_repaint_boundary')),
      );
      expect(renderRepaint.isRepaintBoundary, isTrue);

      // Verify CustomPaint paints inside RepaintBoundary without exceptions
      expect(find.descendant(
        of: find.byKey(const ValueKey('waveform_repaint_boundary')),
        matching: find.byType(CustomPaint),
      ), findsWidgets);
    });

    testWidgets('CustomPainter shouldRepaint contracts', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // Find the CustomPaint widget used for waveform
      final customPaintFinder = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter!;

      // Same painter instance does not need repaint
      expect(painter.shouldRepaint(painter), isFalse);
    });

    testWidgets('WaveformSlider consumes positionListenable reactively without full rebuilds', (
      WidgetTester tester,
    ) async {
      final positionNotifier = ValueNotifier<Duration>(const Duration(seconds: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  positionListenable: positionNotifier,
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('0:10'), findsOneWidget);
      expect(find.text('-1:30'), findsOneWidget);

      positionNotifier.value = const Duration(seconds: 25);
      await tester.pump();

      expect(find.text('0:25'), findsOneWidget);
      expect(find.text('-1:15'), findsOneWidget);
    });

    testWidgets('WaveformSlider provides click cursor via MouseRegion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final mouseRegionFinder = find.descendant(
        of: find.byType(WaveformSlider),
        matching: find.byType(MouseRegion),
      );
      expect(mouseRegionFinder, findsWidgets);
      final mouseRegion = tester.widget<MouseRegion>(mouseRegionFinder.first);
      expect(mouseRegion.cursor, equals(SystemMouseCursors.click));
    });

    testWidgets('WaveformSlider contains internal RepaintBoundary for painter isolation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final repaintFinder = find.descendant(
        of: find.byType(WaveformSlider),
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintFinder, findsWidgets);
    });

    testWidgets('CustomPainter shouldRepaint quantizes 50ms buckets and respects dragging', (
      WidgetTester tester,
    ) async {
      final positionNotifier = ValueNotifier<Duration>(const Duration(milliseconds: 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(milliseconds: 1000),
                  positionListenable: positionNotifier,
                  duration: const Duration(seconds: 100),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final customPaint1 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter1 = customPaint1.painter!;

      // Advance by 15ms (1015ms ~/ 50 == 1000ms ~/ 50 == 20)
      positionNotifier.value = const Duration(milliseconds: 1015);
      await tester.pump();

      final customPaint2 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter2 = customPaint2.painter!;

      // shouldRepaint should be false for within-bucket change
      expect(painter2.shouldRepaint(painter1), isFalse);

      // Advance past 50ms bucket boundary (1060ms ~/ 50 == 21)
      positionNotifier.value = const Duration(milliseconds: 1060);
      await tester.pump();

      final customPaint3 = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).first,
      );
      final painter3 = customPaint3.painter!;

      // shouldRepaint should be true across bucket boundary
      expect(painter3.shouldRepaint(painter2), isTrue);
    });
  });
}
