import 'package:flutter/material.dart';

class WaveVisualizerPainter extends CustomPainter {
  final List<double> bands;
  final Color color;

  WaveVisualizerPainter({required this.bands, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
      
    final int barsCount = 20;
    
    // Gap between bars
    const double gap = 2.0; 
    // Calculate exact width for each bar so they fit perfectly in the size.width
    final double barWidth = (size.width - (gap * (barsCount - 1))) / barsCount;

    for (int i = 0; i < barsCount; i++) {
      // Mirror the 10 frequency bands:
      // Left side (0-9) gets higher frequencies on the outside, bass in the center?
      // Usually bass is in the center. 
      // i=9 and i=10 are the center. So bandIndex=0 should map to center.
      // i=0 -> band=9
      // i=9 -> band=0
      // i=10 -> band=0
      // i=19 -> band=9
      final bandIndex = i < 10 ? 9 - i : i - 10;
      final intensity = bands[bandIndex];
      
      final x = i * (barWidth + gap);
      
      // Ensure a minimum height of 2px even when silent
      final barHeight = (intensity * size.height).clamp(2.0, size.height);
      
      // Bars go downwards from y=0
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, 0, barWidth, barHeight),
        bottomLeft: const Radius.circular(2.0),
        bottomRight: const Radius.circular(2.0),
      );
      
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(WaveVisualizerPainter oldDelegate) {
    return true; // Repaint continuously as data changes
  }
}
