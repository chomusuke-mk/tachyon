import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/playback/presentation/waveform_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveformSlider Widget Tests', () {
    testWidgets('renders elapsed and remaining timestamps with tabular figures', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformSlider(
              position: const Duration(minutes: 1, seconds: 23),
              duration: const Duration(minutes: 3, seconds: 45),
              onSeek: (_) {},
            ),
          ),
        ),
      );

      // Verify formatted timestamps are rendered
      expect(find.text('01:23'), findsOneWidget);
      // Remaining = 3:45 - 1:23 = 2:22 -> -02:22
      expect(find.text('-02:22'), findsOneWidget);

      // Verify Tabular Figures font feature is applied to Text widgets
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final text in textWidgets) {
        if (text.data == '01:23' || text.data == '-02:22') {
          final fontFeatures = text.style?.fontFeatures;
          expect(fontFeatures, isNotNull);
          expect(
            fontFeatures!.any((f) => f == const FontFeature.tabularFigures()),
            isTrue,
            reason: 'Text ${text.data} must have FontFeature.tabularFigures() for anti-jitter',
          );
        }
      }
    });

    testWidgets('tapping remaining time toggles between remaining and total duration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformSlider(
              position: const Duration(minutes: 1, seconds: 23),
              duration: const Duration(minutes: 3, seconds: 45),
              onSeek: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('-02:22'), findsOneWidget);

      // Tap remaining text
      await tester.tap(find.text('-02:22'));
      await tester.pumpAndSettle();

      // Now total duration 03:45 is displayed
      expect(find.text('03:45'), findsOneWidget);
      expect(find.text('-02:22'), findsNothing);

      // Tap again to toggle back
      await tester.tap(find.text('03:45'));
      await tester.pumpAndSettle();

      expect(find.text('-02:22'), findsOneWidget);
    });

    testWidgets('renders CustomPaint waveform', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformSlider(
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 120),
              isBuffering: true,
              onSeek: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('calls onSeek when tapped along the waveform track', (tester) async {
      Duration? finalSeekPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 30),
                  duration: const Duration(seconds: 100),
                  onSeek: (val) {
                    finalSeekPosition = val;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(of: find.byType(WaveformSlider), matching: find.byType(GestureDetector)).first;
      final topLeft = tester.getTopLeft(customPaintFinder);
      final size = tester.getSize(customPaintFinder);
      final targetPoint = Offset(topLeft.dx + size.width * 0.75, topLeft.dy + size.height / 2);

      await tester.tapAt(targetPoint);
      await tester.pumpAndSettle();

      expect(finalSeekPosition, isNotNull);
      // 75% of 100 seconds = 75 seconds
      expect(finalSeekPosition!.inSeconds, equals(75));
    });

    testWidgets('drags along track and calls onSeek on drag end', (tester) async {
      Duration? finalSeekPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: WaveformSlider(
                  position: const Duration(seconds: 10),
                  duration: const Duration(seconds: 100),
                  onSeek: (val) {
                    finalSeekPosition = val;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(of: find.byType(WaveformSlider), matching: find.byType(GestureDetector)).first;
      final topLeft = tester.getTopLeft(customPaintFinder);
      final size = tester.getSize(customPaintFinder);

      final startPoint = Offset(topLeft.dx + size.width * 0.1, topLeft.dy + size.height / 2);
      final gesture = await tester.startGesture(startPoint);
      await tester.pump();

      // Drag to 50%
      final midPoint = Offset(topLeft.dx + size.width * 0.5, topLeft.dy + size.height / 2);
      await gesture.moveTo(midPoint);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(finalSeekPosition, isNotNull);
      // 50% of 100 seconds = 50 seconds
      expect(finalSeekPosition!.inSeconds, equals(50));
    });
  });
}
