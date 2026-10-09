import 'dart:math' as math;
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

  WaveVisualizerPainter({
    required this.bands,
    required this.color,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final startX = cornerRadius;
    final endX = size.width - cornerRadius;
    if (endX <= startX) return;

    // Check if there is audible energy; if silent, do not draw protruding geometry
    final maxEnergy = bands.fold<double>(0.0, (m, b) => math.max(m, b));
    if (maxEnergy < 0.01) return;

    final spanX = endX - startX;
    final bandsCount = bands.length;

    // Map each frequency band to its vertex point
    final points = <Offset>[];
    for (int i = 0; i < bandsCount; i++) {
      final progress = (i + 0.5) / bandsCount;
      final x = startX + progress * spanX;
      // Perceptual boost for higher visual punch
      final rawIntensity = bands[i].clamp(0.0, 1.0);
      final y = rawIntensity * size.height;
      points.add(Offset(x, y));
    }

    // Build continuous path with steep flanks and rounded crest summits
    final fillPath = Path();
    fillPath.moveTo(startX, 0.0);

    // Curve from start dock anchor (startX, 0) to first band summit
    final firstPoint = points.first;
    final firstDx = (firstPoint.dx - startX) / 3.0;
    fillPath.cubicTo(
      startX + firstDx,
      0.0,
      firstPoint.dx - firstDx,
      firstPoint.dy,
      firstPoint.dx,
      firstPoint.dy,
    );

    // Smoothly connect band summits with horizontal tangent crests
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final dx = (p1.dx - p0.dx) / 3.0;

      fillPath.cubicTo(
        p0.dx + dx,
        p0.dy,
        p1.dx - dx,
        p1.dy,
        p1.dx,
        p1.dy,
      );
    }

    // Curve from last band summit to end dock anchor (endX, 0)
    final lastPoint = points.last;
    final lastDx = (endX - lastPoint.dx) / 3.0;
    fillPath.cubicTo(
      lastPoint.dx + lastDx,
      lastPoint.dy,
      endX - lastDx,
      0.0,
      endX,
      0.0,
    );

    fillPath.close();

    // Solid color fill (no borders, no gradient)
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(WaveVisualizerPainter oldDelegate) => true;
}
