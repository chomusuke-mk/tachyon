import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Unmodifiable [List<double>] view backed directly by a compact 8-bit [Uint8List].
///
/// Reduces per-track waveform memory by ~75% compared to [Float32List] (100 bytes
/// vs 400 bytes per 100-point waveform) with zero eager float conversion loop during
/// catalog hydration.
final class _Uint8WaveformList extends ListBase<double> {
  final Uint8List _bytes;

  const _Uint8WaveformList(this._bytes);

  @override
  int get length => _bytes.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Cannot modify an unmodifiable waveform list');

  @override
  double operator [](int index) => _bytes[index] * (1.0 / 255.0);

  @override
  void operator []=(int index, double value) =>
      throw UnsupportedError('Cannot modify an unmodifiable waveform list');
}

/// Compact Base64 codec for normalized audio waveform points (0.0 to 1.0).
///
/// Encodes points into 8-bit unsigned integers (0 to 255) and serializes
/// to Base64, producing ~136 characters for 100 points with negligible memory overhead.
abstract final class WaveformCodec {
  /// Encodes a list of normalized waveform points [0.0 ... 1.0] to a Base64 string.
  static String? encode(List<double>? points) {
    if (points == null || points.isEmpty) return null;
    if (points is _Uint8WaveformList) {
      return base64Encode(points._bytes);
    }
    final bytes = Uint8List(points.length);
    for (var i = 0; i < points.length; i++) {
      bytes[i] = (points[i].clamp(0.0, 1.0) * 255.0).round();
    }
    return base64Encode(bytes);
  }

  /// Decodes a Base64 string back into an unmodifiable list of normalized waveform points [0.0 ... 1.0].
  static List<double>? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return null;
      return _Uint8WaveformList(bytes);
    } catch (_) {
      return null;
    }
  }
}
