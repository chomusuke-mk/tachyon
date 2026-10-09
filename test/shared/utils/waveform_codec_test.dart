import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

void main() {
  group('WaveformCodec', () {
    test('encode returns null for null or empty lists', () {
      expect(WaveformCodec.encode(null), isNull);
      expect(WaveformCodec.encode([]), isNull);
    });

    test('decode returns null for null or empty strings', () {
      expect(WaveformCodec.decode(null), isNull);
      expect(WaveformCodec.decode(''), isNull);
    });

    test('encodes and decodes normalized points correctly within 8-bit precision', () {
      final original = [0.0, 0.25, 0.5, 0.75, 1.0];
      final encoded = WaveformCodec.encode(original);

      expect(encoded, isNotNull);
      expect(encoded, isNotEmpty);

      final decoded = WaveformCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.length, equals(original.length));

      for (var i = 0; i < original.length; i++) {
        expect(decoded[i], closeTo(original[i], 1.0 / 255.0));
      }
    });

    test('clamps out-of-range values during encoding', () {
      final points = [-0.5, 0.0, 1.0, 1.5];
      final encoded = WaveformCodec.encode(points);
      final decoded = WaveformCodec.decode(encoded)!;

      expect(decoded[0], closeTo(0.0, 0.01));
      expect(decoded[1], closeTo(0.0, 0.01));
      expect(decoded[2], closeTo(1.0, 0.01));
      expect(decoded[3], closeTo(1.0, 0.01));
    });

    test('handles 100 points typical miniaudio waveform resolution', () {
      final points = List.generate(100, (i) => i / 99.0);
      final encoded = WaveformCodec.encode(points);
      final decoded = WaveformCodec.decode(encoded)!;

      expect(decoded.length, equals(100));
      for (var i = 0; i < 100; i++) {
        expect(decoded[i], closeTo(points[i], 1.0 / 255.0));
      }
    });
  });

  group('Track Waveform sampling methods', () {
    test('getPointAtProgress returns 0.0 when waveform is null or empty', () {
      final trackWithoutWaveform = Track(
        id: 1,
        title: 'Song',
        filePath: '/test.mp3',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
        waveform: null,
      );

      expect(trackWithoutWaveform.getPointAtProgress(0.5), equals(0.0));
      expect(trackWithoutWaveform.getPointAtPosition(const Duration(seconds: 90), const Duration(minutes: 3)), equals(0.0));

      final trackWithEmptyWaveform = Track(
        id: 2,
        title: 'Song 2',
        filePath: '/test2.mp3',
        durationMs: 180000,
        fileSize: 1000,
        modifiedAt: 1000,
        waveform: const [],
      );

      expect(trackWithEmptyWaveform.getPointAtProgress(0.5), equals(0.0));
    });

    test('getPointAtProgress correctly samples normalized amplitudes', () {
      final points = [0.1, 0.5, 0.9];
      final track = Track(
        id: 1,
        title: 'Song',
        filePath: '/test.mp3',
        durationMs: 100000,
        fileSize: 1000,
        modifiedAt: 1000,
        waveform: points,
      );

      // Start
      expect(track.getPointAtProgress(0.0), closeTo(0.1, 0.001));
      // End
      expect(track.getPointAtProgress(1.0), closeTo(0.9, 0.001));
      // Midpoint
      expect(track.getPointAtProgress(0.5), closeTo(0.5, 0.001));
      // Clamping negative or > 1.0
      expect(track.getPointAtProgress(-0.2), closeTo(0.1, 0.001));
      expect(track.getPointAtProgress(1.5), closeTo(0.9, 0.001));
    });

    test('getPointAtPosition calculates progress and samples accurately', () {
      final points = [0.2, 0.4, 0.6, 0.8];
      final track = Track(
        id: 1,
        title: 'Song',
        filePath: '/test.mp3',
        durationMs: 40000,
        fileSize: 1000,
        modifiedAt: 1000,
        waveform: points,
      );

      const total = Duration(seconds: 40);
      expect(track.getPointAtPosition(Duration.zero, total), closeTo(0.2, 0.001));
      expect(track.getPointAtPosition(const Duration(seconds: 40), total), closeTo(0.8, 0.001));

      // Duration.zero edge case
      expect(track.getPointAtPosition(const Duration(seconds: 10), Duration.zero), equals(0.0));
    });
  });
}
