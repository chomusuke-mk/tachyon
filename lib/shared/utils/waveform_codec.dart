import 'dart:convert';
import 'dart:typed_data';

/// Compact Base64 codec for normalized audio waveform points (0.0 to 1.0).
///
/// Encodes points into 8-bit unsigned integers (0 to 255) and serializes
/// to Base64, producing ~136 characters for 100 points with negligible memory overhead.
abstract final class WaveformCodec {
  /// Encodes a list of normalized waveform points [0.0 ... 1.0] to a Base64 string.
  static String? encode(List<double>? points) {
    if (points == null || points.isEmpty) return null;
    final bytes = Uint8List(points.length);
    for (var i = 0; i < points.length; i++) {
      bytes[i] = (points[i].clamp(0.0, 1.0) * 255.0).round();
    }
    return base64Encode(bytes);
  }

  /// Decodes a Base64 string back into a list of normalized waveform points [0.0 ... 1.0].
  static List<double>? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      return List<double>.generate(
        bytes.length,
        (i) => bytes[i] / 255.0,
        growable: false,
      );
    } catch (_) {
      return null;
    }
  }
}
