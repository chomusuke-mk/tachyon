import 'package:flutter/material.dart';
import 'package:miniaudio_player/miniaudio_player.dart';

/// Custom painter visualizing the 10-band ISO 266 parametric equalizer frequency response.
///
/// Draws a smooth biquad interpolation spline curve with soft frequency axis grid lines,
/// interactive response nodes, and application theme-aware palette.
class EqCurvePainter extends CustomPainter {
  final Equalizer equalizer;
  final Color activeColor;
  final Color backgroundColor;
  final Color? gridLineColor;
  final Color? zeroLineColor;
  final Color? labelColor;

  const EqCurvePainter({
    required this.equalizer,
    this.activeColor = const Color(0xFF00D1FF),
    this.backgroundColor = const Color(0xFF090D18),
    this.gridLineColor,
    this.zeroLineColor,
    this.labelColor,
  });

  static const int bandCount = 10;

  static double getXForBand(int index, double width) {
    return (width / (bandCount + 1)) * (index + 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      bgPaint,
    );

    final centerY = size.height / 2;
    final verticalAmplitude = size.height * 0.38;

    final effectiveGridColor = gridLineColor ?? const Color(0xFF1B2438);
    final effectiveZeroColor = zeroLineColor ?? const Color(0xFF26324A);
    final effectiveLabelColor = labelColor ?? const Color(0xFF6B7A99);

    final bandXPositions = <double>[];
    for (int i = 0; i < bandCount; i++) {
      bandXPositions.add(getXForBand(i, size.width));
    }

    // 1. Soft vertical axis lines for each frequency band
    final verticalAxisPaint = Paint()
      ..color = effectiveGridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    for (int i = 0; i < bandCount; i++) {
      final x = bandXPositions[i];
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), verticalAxisPaint);
    }

    // 2. Horizontal center line for 0 dB
    final zeroLinePaint = Paint()
      ..color = effectiveZeroColor
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      zeroLinePaint,
    );

    // 3. Horizontal guide lines for +12 dB and -12 dB
    final guideLinePaint = Paint()
      ..color = effectiveGridColor
      ..strokeWidth = 1.0;
    final topLimitY = centerY - verticalAmplitude;
    final bottomLimitY = centerY + verticalAmplitude;
    canvas.drawLine(
      Offset(0, topLimitY),
      Offset(size.width, topLimitY),
      guideLinePaint,
    );
    canvas.drawLine(
      Offset(0, bottomLimitY),
      Offset(size.width, bottomLimitY),
      guideLinePaint,
    );

    // 4. Internal dB scale labels
    _drawInternalLabel(canvas, '+12dB', const Offset(8, 4), effectiveLabelColor);
    _drawInternalLabel(canvas, '0dB', Offset(8, centerY - 6), effectiveLabelColor);
    _drawInternalLabel(
      canvas,
      '-12dB',
      Offset(8, size.height - 18),
      effectiveLabelColor,
    );

    // 5. Spline curve calculation
    final path = Path();
    final fillPath = Path();
    final bands = equalizer.toList();
    final nodePoints = <Offset>[];

    path.moveTo(0, centerY);
    fillPath.moveTo(0, centerY);

    for (int i = 0; i < bandCount; i++) {
      final gain = bands[i].clamp(-12.0, 12.0);
      final y = centerY - (gain / 12.0) * verticalAmplitude;
      final x = bandXPositions[i];
      nodePoints.add(Offset(x, y));

      if (i == 0) {
        path.quadraticBezierTo(x * 0.5, centerY, x, y);
        fillPath.quadraticBezierTo(x * 0.5, centerY, x, y);
      } else {
        final prevX = bandXPositions[i - 1];
        final prevGain = bands[i - 1].clamp(-12.0, 12.0);
        final prevY = centerY - (prevGain / 12.0) * verticalAmplitude;
        final midX = (prevX + x) / 2;
        path.cubicTo(midX, prevY, midX, y, x, y);
        fillPath.cubicTo(midX, prevY, midX, y, x, y);
      }
    }

    path.lineTo(size.width, centerY);
    fillPath.lineTo(size.width, centerY);
    fillPath.close();

    // 6. Fill gradient under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          activeColor.withValues(alpha: 0.25),
          activeColor.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 7. Stroke curve
    final strokePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);

    // 8. Draw frequency nodes & guidelines
    for (int i = 0; i < nodePoints.length; i++) {
      final pt = nodePoints[i];

      final projPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.3)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(pt.dx, centerY), pt, projPaint);

      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 6.0, glowPaint);

      final pointPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 3.5, pointPaint);

      final centerDotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 1.5, centerDotPaint);
    }
  }

  void _drawInternalLabel(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant EqCurvePainter oldDelegate) {
    return oldDelegate.equalizer != equalizer ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.gridLineColor != gridLineColor ||
        oldDelegate.zeroLineColor != zeroLineColor ||
        oldDelegate.labelColor != labelColor;
  }
}
