import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Studio spectrum analyzer painter rendering clean, fluid, audio-reactive
/// vertical gradient bars across the full width of the artwork, floating
/// transparently with peak caps and zero dB/Hz clutter.
class SpectrumBarsPainter extends CustomPainter {
  final List<double> magnitudes;
  final bool isActive;
  final double cornerRadius;
  final Color? accentColor;

  static const LinearGradient defaultSpectrumGradient = LinearGradient(
    colors: [
      Color(0xFF06B6D4), // Cyan
      Color(0xFF3B82F6), // Blue
      Color(0xFF8B5CF6), // Violet
      Color(0xFFF43F5E), // Rose
    ],
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
  );

  const SpectrumBarsPainter({
    required this.magnitudes,
    this.isActive = true,
    this.cornerRadius = 20.0,
    this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bandCount = math.max(1, magnitudes.isEmpty ? 10 : magnitudes.length);
    const spacing = 4.0;
    final totalSpacing = spacing * (bandCount - 1);
    final barWidth = math.max(2.0, (size.width - totalSpacing) / bandCount);

    final barGradient = accentColor != null
        ? LinearGradient(
            colors: [
              accentColor!.withValues(alpha: 0.40),
              accentColor!,
              Colors.white.withValues(alpha: 0.90),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          )
        : defaultSpectrumGradient;

    for (int i = 0; i < bandCount; i++) {
      final mag = (i < magnitudes.length && isActive)
          ? magnitudes[i].clamp(0.0, 1.0)
          : 0.03;

      final x = i * (barWidth + spacing);
      final barHeight = math.max(6.0, size.height * mag);
      final y = size.height - barHeight;

      final barRect = Rect.fromLTWH(x, y, barWidth, barHeight);
      final barPaint = Paint()
        ..shader = barGradient.createShader(barRect)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          barRect,
          Radius.circular(math.min(barWidth / 2, 4.0)),
        ),
        barPaint,
      );

      // Peak cap line
      if (isActive && mag > 0.06) {
        final capPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = 2.0;
        canvas.drawLine(
          Offset(x, y - 3),
          Offset(x + barWidth, y - 3),
          capPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumBarsPainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.magnitudes != magnitudes;
  }
}
