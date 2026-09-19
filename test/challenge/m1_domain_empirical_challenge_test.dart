import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';

/// Mock repository with configurable latency to stress-test async race conditions
class StressMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> bundles;
  final Duration simulatedDelay;

  StressMockLocaleRepository(this.bundles, {this.simulatedDelay = Duration.zero});

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    return Map<String, String>.from(bundles[localeCode] ?? <String, String>{});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // CHALLENGE 1: Crossfade Mathematical Invariants & Precision (1,000 Points)
  // ==========================================================================
  group('Crossfade Mathematical Invariant Stress (1,000 Points)', () {
    test('Equal-Power invariant Va(t)^2 + Vb(t)^2 == Vmaster^2 across 1,000 points', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.equalPower);
      const testMasterVolumes = [1.0, 50.0, 100.0, 150.0, 200.0];

      for (final masterVolume in testMasterVolumes) {
        final expectedEnergy = masterVolume * masterVolume;
        double maxAbsDeviation = 0.0;
        double sumDeviation = 0.0;

        for (int i = 0; i < 1000; i++) {
          final progress = i / 999.0;
          final vA = config.calculateFadeOutVolume(progress, masterVolume);
          final vB = config.calculateFadeInVolume(progress, masterVolume);

          final calculatedEnergy = (vA * vA) + (vB * vB);
          final deviation = (calculatedEnergy - expectedEnergy).abs();

          if (deviation > maxAbsDeviation) {
            maxAbsDeviation = deviation;
          }
          sumDeviation += deviation;

          // Float64 IEEE 754 precision tolerance
          final tolerance = masterVolume == 1.0 ? 1e-12 : (expectedEnergy * 1e-11);
          expect(
            deviation,
            lessThan(tolerance),
            reason: 'Failed equal-power invariant at p=$progress, Vm=$masterVolume: energy=$calculatedEnergy, diff=$deviation',
          );
        }

        final avgDeviation = sumDeviation / 1000.0;
        // ignore: avoid_print
        print('Equal-Power invariant (Vm=$masterVolume): maxDev=${maxAbsDeviation.toStringAsExponential(3)}, avgDev=${avgDeviation.toStringAsExponential(3)}');

        expect(maxAbsDeviation, lessThan(masterVolume == 1.0 ? 1e-12 : 1e-8));
        expect(avgDeviation, lessThan(masterVolume == 1.0 ? 1e-13 : 1e-9));
      }
    });

    test('Linear curve invariant Va(t) + Vb(t) == Vmaster across 1,000 points', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.linear);
      const masterVolume = 100.0;

      double maxDev = 0.0;
      for (int i = 0; i < 1000; i++) {
        final progress = i / 999.0;
        final vA = config.calculateFadeOutVolume(progress, masterVolume);
        final vB = config.calculateFadeInVolume(progress, masterVolume);

        final sumAmplitude = vA + vB;
        final dev = (sumAmplitude - masterVolume).abs();
        if (dev > maxDev) maxDev = dev;

        expect(
          dev,
          lessThan(1e-12),
          reason: 'Linear amplitude conservation failed at p=$progress: sum=$sumAmplitude',
        );
      }
      // ignore: avoid_print
      print('Linear curve invariant (Vm=100.0): maxDev=${maxDev.toStringAsExponential(3)}');
    });

    test('Floating-point residual check on endpoint p = 1.0 for Fade-Out', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.equalPower);
      const masterVolume = 100.0;

      final vA = config.calculateFadeOutVolume(1.0, masterVolume);
      final vB = config.calculateFadeInVolume(1.0, masterVolume);

      // ignore: avoid_print
      print('At p=1.0: FadeOut Va = ${vA.toStringAsExponential(8)}, FadeIn Vb = $vB');

      // Vb is exactly 100.0
      expect(vB, equals(100.0));

      // Va is non-zero due to math.cos(pi/2) float precision (approx 6.12e-15 * 100 = 6.12e-13)
      expect(vA, closeTo(0.0, 1e-12));
    });

    test('Extreme progress clamping (p < 0.0 and p > 1.0)', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.equalPower);
      const masterVolume = 100.0;

      final extremeUnder = [-1e-9, -1.0, -100.0, -1e12];
      for (final p in extremeUnder) {
        final vA = config.calculateFadeOutVolume(p, masterVolume);
        final vB = config.calculateFadeInVolume(p, masterVolume);
        expect(vA, equals(masterVolume));
        expect(vB, equals(0.0));
      }

      final extremeOver = [1.0000001, 2.0, 100.0, 1e12];
      for (final p in extremeOver) {
        final vA = config.calculateFadeOutVolume(p, masterVolume);
        final vB = config.calculateFadeInVolume(p, masterVolume);
        // Va is clamped to cos(pi/2), which is ~6.12e-13
        expect(vA, closeTo(0.0, 1e-12));
        expect(vB, equals(masterVolume));
      }
    });

    test('Duration clamping bounds [1s, 12s]', () {
      expect(const CrossfadeConfig(duration: Duration(seconds: -10)).clampedDuration, equals(const Duration(seconds: 1)));
      expect(const CrossfadeConfig(duration: Duration.zero).clampedDuration, equals(const Duration(seconds: 1)));
      expect(const CrossfadeConfig(duration: Duration(milliseconds: 999)).clampedDuration, equals(const Duration(seconds: 1)));
      expect(const CrossfadeConfig(duration: Duration(seconds: 1)).clampedDuration, equals(const Duration(seconds: 1)));
      expect(const CrossfadeConfig(duration: Duration(seconds: 7)).clampedDuration, equals(const Duration(seconds: 7)));
      expect(const CrossfadeConfig(duration: Duration(seconds: 12)).clampedDuration, equals(const Duration(seconds: 12)));
      expect(const CrossfadeConfig(duration: Duration(seconds: 13)).clampedDuration, equals(const Duration(seconds: 12)));
      expect(const CrossfadeConfig(duration: Duration(days: 365)).clampedDuration, equals(const Duration(seconds: 12)));
    });

    test('Short track duration clamping (D_track < D_crossfade)', () {
      const config = CrossfadeConfig(duration: Duration(seconds: 5));

      // 4-second track -> half track = 2s
      expect(config.effectiveDuration(const Duration(seconds: 4)), equals(const Duration(seconds: 2)));

      // 1-second track -> half track = 500ms
      expect(config.effectiveDuration(const Duration(seconds: 1)), equals(const Duration(milliseconds: 500)));

      // 100ms track -> half track = 50ms
      expect(config.effectiveDuration(const Duration(milliseconds: 100)), equals(const Duration(milliseconds: 50)));

      // 0ms or negative track -> 0ms
      expect(config.effectiveDuration(Duration.zero), equals(Duration.zero));
      expect(config.effectiveDuration(const Duration(seconds: -5)), equals(Duration.zero));

      // Disabled config -> 0ms regardless of track duration
      const disabledConfig = CrossfadeConfig(enabled: false, duration: Duration(seconds: 5));
      expect(disabledConfig.effectiveDuration(const Duration(minutes: 5)), equals(Duration.zero));
    });
  });

  // ==========================================================================
  // CHALLENGE 2: Lyrics Parsing & SplayTreeMap O(log n) Latency
  // ==========================================================================
  group('Lyrics Parsing & SplayTreeMap Benchmark', () {
    test('LRC parsing handles extreme/corrupt inputs gracefully', () {
      // 1. Negative header offset causing negative timestamp -> clamped to 0
      const lrcNegative = '''
[offset:-5000]
[00:02.00]First line (2000 - 5000 = -3000ms -> clamped to 0)
[00:10.00]Second line (10000 - 5000 = 5000ms)
''';
      final resNeg = LyricLine.parseLrc(lrcNegative);
      expect(resNeg.length, equals(2));
      expect(resNeg[0].timestampMs, equals(0));
      expect(resNeg[1].timestampMs, equals(5000));

      // 2. Huge positive offset (+1 hour)
      const lrcHugeOffset = '''
[offset:3600000]
[00:01.00]Hour later
''';
      final resHuge = LyricLine.parseLrc(lrcHugeOffset);
      expect(resHuge[0].timestampMs, equals(3601000));

      // 3. Out of order timestamps are automatically sorted
      const lrcOutOfOrder = '''
[02:00.00]Line 3
[00:10.00]Line 1
[01:00.00]Line 2
''';
      final resOrdered = LyricLine.parseLrc(lrcOutOfOrder);
      expect(resOrdered[0].text, equals('Line 1'));
      expect(resOrdered[0].timestampMs, equals(10000));
      expect(resOrdered[1].text, equals('Line 2'));
      expect(resOrdered[1].timestampMs, equals(60000));
      expect(resOrdered[2].text, equals('Line 3'));
      expect(resOrdered[2].timestampMs, equals(120000));

      // 4. Duplicate identical timestamps on separate lines
      const lrcDuplicates = '''
[00:05.00]Line A
[00:05.00]Line B
''';
      final resDup = LyricLine.parseLrc(lrcDuplicates);
      expect(resDup.length, equals(2));
      expect(resDup[0].timestampMs, equals(5000));
      expect(resDup[1].timestampMs, equals(5000));

      // 5. Corrupt / empty / non-standard lines
      const lrcCorrupt = '''
[offset:not_a_number]
[invalid_tag]
Just a plain sentence without brackets
[99:99.99]Very late line
''';
      final resCorrupt = LyricLine.parseLrc(lrcCorrupt);
      expect(resCorrupt.any((l) => l.text == 'Just a plain sentence without brackets' && !l.isSynced), isTrue);
      expect(resCorrupt.any((l) => l.isSynced && l.timestampMs == (99 * 60 + 99) * 1000 + 990), isTrue);
    });

    test('Defect Verification: Minutes >= 100 (3-digit minutes) rejected by regex', () {
      // In DJ sets, podcasts, symphonies > 99 minutes:
      const longMixLrc = '''
[99:50.00]Before 100 min
[100:05.00]After 100 min
''';
      final parsed = LyricLine.parseLrc(longMixLrc);

      // ignore: avoid_print
      print('Parsed lines for >= 100 min:');
      for (final l in parsed) {
        // ignore: avoid_print
        print('  line: "${l.text}", timestampMs=${l.timestampMs}, isSynced=${l.isSynced}');
      }

      // Line 1: [99:50.00] matches \d{2} -> isSynced: true
      final line99 = parsed.firstWhere((l) => l.text == 'Before 100 min');
      expect(line99.isSynced, isTrue);

      // Line 2: [100:05.00] matches \d{1,} -> isSynced: true, timestampMs: 6005000
      final line100 = parsed.firstWhere((l) => l.text.contains('After 100 min'));
      expect(line100.isSynced, isTrue, reason: 'Regex \\d{1,} parses 3-digit minutes');
      expect(line100.timestampMs, equals((100 * 60 + 5) * 1000));
    });

    test('10,000-line valid LRC dataset generation, parsing & index building', () {
      final buffer = StringBuffer();
      buffer.writeln('[ti:Stress Test Track]');
      buffer.writeln('[ar:Stress Artist]');
      buffer.writeln('[offset:100]');

      // To stay within 2-digit minutes (< 100 min = 6000s), distribute 10,000 lines over 5,000 seconds (every 500ms)
      for (int i = 0; i < 10000; i++) {
        final totalCentis = i * 50; // Each step is 500ms (50 centiseconds)
        final totalSeconds = totalCentis ~/ 100;
        final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
        final ss = (totalSeconds % 60).toString().padLeft(2, '0');
        final centis = (totalCentis % 100).toString().padLeft(2, '0');
        buffer.writeln('[$mm:$ss.$centis] Lyric line number $i');
      }

      final swParse = Stopwatch()..start();
      final lyrics = LyricLine.parseLrc(buffer.toString());
      swParse.stop();

      expect(lyrics.length, equals(10000));
      // ignore: avoid_print
      print('10,000 lines LRC parse time: ${swParse.elapsedMilliseconds}ms');
      expect(swParse.elapsedMilliseconds, lessThan(1000));

      final swIndex = Stopwatch()..start();
      final indexMap = LyricLine.buildIndex(lyrics);
      swIndex.stop();

      expect(indexMap.length, equals(10000));
      // ignore: avoid_print
      print('10,000 lines SplayTreeMap index build time: ${swIndex.elapsedMilliseconds}ms');
      expect(swIndex.elapsedMilliseconds, lessThan(200));
    });

    test('SplayTreeMap O(log n) lookup latency benchmark (>10,000 lookups)', () {
      // 1. Build index with 10,000 lines
      final lyrics = List.generate(10000, (i) {
        return LyricLine(
          timestampMs: i * 500, // Every 500ms up to 5,000,000ms
          text: 'Line $i',
          isSynced: true,
        );
      });
      final indexMap = LyricLine.buildIndex(lyrics);
      expect(indexMap.length, equals(10000));

      // 2. Warm-up JIT with 10,000 lookups
      final random = math.Random(12345);
      for (int i = 0; i < 10000; i++) {
        LyricLine.findActiveIndex(indexMap, random.nextInt(5000000));
      }

      // 3. Timed benchmark: 10,000 Sequential Playback lookups (temporal locality)
      final swSequential = Stopwatch()..start();
      int sinkSeq = 0;
      for (int i = 0; i < 10000; i++) {
        sinkSeq ^= LyricLine.findActiveIndex(indexMap, i * 500);
      }
      swSequential.stop();

      // 4. Timed benchmark: 10,000 Random Access lookups (arbitrary seeks)
      final queryPositions = List.generate(10000, (_) => random.nextInt(5000000));
      final swRandom = Stopwatch()..start();
      int sinkRand = 0;
      for (int i = 0; i < 10000; i++) {
        sinkRand ^= LyricLine.findActiveIndex(indexMap, queryPositions[i]);
      }
      swRandom.stop();

      expect(sinkSeq ^ sinkRand, isNotNull);

      final seqMs = swSequential.elapsedMilliseconds;
      final seqMicros = swSequential.elapsedMicroseconds;
      final randMs = swRandom.elapsedMilliseconds;
      final randMicros = swRandom.elapsedMicroseconds;

      // ignore: avoid_print
      print('SplayTreeMap Sequential (10,000 lookups): ${seqMs}ms ($seqMicrosµs, avg ${(seqMicros / 10000.0).toStringAsFixed(2)}µs/lookup)');
      // ignore: avoid_print
      print('SplayTreeMap Random Seek (10,000 lookups): ${randMs}ms ($randMicrosµs, avg ${(randMicros / 10000.0).toStringAsFixed(2)}µs/lookup)');

      // Sequential playback lookups should be blazingly fast (< 10ms)
      expect(seqMs, lessThan(10));

    });
  });

  // ==========================================================================
  // CHALLENGE 3: i18n Stress, Rapid Concurrent Switching & Fallback
  // ==========================================================================
  group('i18n High-Concurrency & Fallback Stress', () {
    test('Rapid sequential locale switching (1,000 iterations) maintains state integrity', () async {
      final mockRepo = StressMockLocaleRepository({
        'en': {
          'np_title': 'Now Playing',
          'np_play': 'Play',
          's_title': 'Settings',
        },
        'es': {
          'np_title': 'Reproduciendo Ahora',
          'np_play': 'Reproducir',
          's_title': 'Ajustes',
        },
      });

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      final sw = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        final target = i.isEven ? 'es' : 'en';
        await controller.setLocale(target);
      }
      sw.stop();

      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(controller.localeStrings.npPlay, equals('Play'));
      // ignore: avoid_print
      print('1,000 sequential locale switches took: ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('Missing key fallback resilience across partial bundles', () async {
      final mockRepo = StressMockLocaleRepository({
        'en': {
          'np_title': 'Now Playing',
          'np_play': 'Play',
          'np_pause': 'Pause',
          's_title': 'Settings',
        },
        'partial_lang': {
          'np_title': 'Titre En Cours',
          // np_play, np_pause, s_title are missing
        },
        'empty_lang': {},
      });

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      // Switch to partial
      await controller.setLocale('partial_lang');
      expect(controller.currentLocaleCode, equals('partial_lang'));
      expect(controller.localeStrings.npTitle, equals('Titre En Cours'));
      // Missing keys must fall back to English
      expect(controller.localeStrings.npPlay, equals('Play'));
      expect(controller.localeStrings.npPause, equals('Pause'));
      expect(controller.localeStrings.sTitle, equals('Settings'));

      // Switch to empty
      await controller.setLocale('empty_lang');
      expect(controller.currentLocaleCode, equals('empty_lang'));
      // All keys must fall back to English
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(controller.localeStrings.npPlay, equals('Play'));
      expect(controller.localeStrings.sTitle, equals('Settings'));
    });

    test('Defect Verification: Rapid concurrent asynchronous locale switching race condition', () async {
      final mockRepo = StressMockLocaleRepository(
        {
          'en': {
            'np_title': 'Now Playing',
            'np_play': 'Play',
          },
          'es': {
            'np_title': 'Reproduciendo Ahora',
            'np_play': 'Reproducir',
          },
        },
        // 5ms simulated asynchronous asset/disk I/O delay
        simulatedDelay: const Duration(milliseconds: 5),
      );

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      // Concurrently fire switch to 'es', immediately followed by switch to 'en'
      final futEs = controller.setLocale('es');
      final futEn = controller.setLocale('en');

      await Future.wait([futEs, futEn]);

      // ignore: avoid_print
      print('Concurrent final state: code=${controller.currentLocaleCode}, title="${controller.localeStrings.npTitle}"');

      // The user requested 'en' last, so currentLocaleCode is 'en'.
      // With request sequence token counter, stale async completions are dropped!
      final hasRaceCondition = controller.currentLocaleCode == 'en' && controller.localeStrings.npTitle == 'Reproduciendo Ahora';
      // ignore: avoid_print
      print('Race condition resolved: ${!hasRaceCondition}');
      expect(hasRaceCondition, isFalse, reason: 'Request token counter drops stale async completions');
      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
    });
  });
}
