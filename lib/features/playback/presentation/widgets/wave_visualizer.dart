import 'package:flutter/material.dart';

/// Custom painter that renders a continuous, steep audio spectrum wave with
/// smoothly rounded crest summits (no sharp triangle spikes) directly beneath
/// the flat dock of a rounded album art container.
///
/// Key design attributes:
/// - Starts and ends exactly at the flat bottom segment ([cornerRadius] to [size.width - cornerRadius]).
/// - Natural L -> R spectrum: 60 Hz sub-bass on the left up to 16 kHz air on the right.
/// - Steep flanks with rounded crest tops: uses cubic Bézier curves with horizontal summit
///   tangents to form dramatic, fluid crests without sharp corner points.
/// - 100% solid color matching the resolved thumbnail / miniplayer background (no borders, no gradients).
class WaveVisualizerPainter extends CustomPainter {
  final List<double> bands;
  final Color color;
  final double cornerRadius;

  final Path _fillPath = Path();
  final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  WaveVisualizerPainter({
    required this.bands,
    required this.color,
    required this.cornerRadius,
  });

  static double _maxBandEnergy(List<double> values) {
    var maxVal = 0.0;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v > maxVal) maxVal = v;
    }
    return maxVal;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bandsCount = bands.length;
    if (bandsCount == 0) return;

    final startX = cornerRadius;
    final endX = size.width - cornerRadius;
    if (endX <= startX) return;

    // Check if there is audible energy; if silent, do not draw protruding geometry
    if (_maxBandEnergy(bands) < 0.01) return;

    final spanX = endX - startX;

    // Build continuous path with steep flanks and rounded crest summits
    _fillPath.reset();
    _fillPath.moveTo(startX, 0.0);

    var prevX = startX + (0.5 / bandsCount) * spanX;
    var prevY = bands[0].clamp(0.0, 1.0) * size.height;

    // Curve from start dock anchor (startX, 0) to first band summit
    final firstDx = (prevX - startX) / 3.0;
    _fillPath.cubicTo(
      startX + firstDx,
      0.0,
      prevX - firstDx,
      prevY,
      prevX,
      prevY,
    );

    // Smoothly connect band summits with horizontal tangent crests
    for (int i = 1; i < bandsCount; i++) {
      final nextX = startX + ((i + 0.5) / bandsCount) * spanX;
      final nextY = bands[i].clamp(0.0, 1.0) * size.height;
      final dx = (nextX - prevX) / 3.0;

      _fillPath.cubicTo(
        prevX + dx,
        prevY,
        nextX - dx,
        nextY,
        nextX,
        nextY,
      );
      prevX = nextX;
      prevY = nextY;
    }

    // Curve from last band summit to end dock anchor (endX, 0)
    final lastDx = (endX - prevX) / 3.0;
    _fillPath.cubicTo(
      prevX + lastDx,
      prevY,
      endX - lastDx,
      0.0,
      endX,
      0.0,
    );

    _fillPath.close();

    // Solid color fill (no borders, no gradient)
    _fillPaint.color = color;
    canvas.drawPath(_fillPath, _fillPaint);
  }

  @override
  bool shouldRepaint(WaveVisualizerPainter oldDelegate) {
    if (identical(this, oldDelegate)) return false;
    if (color != oldDelegate.color || cornerRadius != oldDelegate.cornerRadius) {
      return true;
    }
    if (bands.length != oldDelegate.bands.length) return true;

    final newMax = _maxBandEnergy(bands);
    final oldMax = _maxBandEnergy(oldDelegate.bands);
    if (newMax < 0.01 && oldMax < 0.01) return false;

    for (var i = 0; i < bands.length; i++) {
      if ((bands[i] - oldDelegate.bands[i]).abs() > 0.002) {
        return true;
      }
    }
    return false;
  }
}
