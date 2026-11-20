import 'package:flutter/material.dart';
import 'package:miniaudio_player/miniaudio_player.dart';

/// Custom painter visualizing the 10-band ISO 266 parametric equalizer frequency response.
///
/// Draws a smooth biquad interpolation spline curve with soft frequency axis grid lines,
/// interactive response nodes, and application theme-aware palette with reusable paints/paths.
class EqCurvePainter extends CustomPainter {
  final Equalizer equalizer;
  final Color activeColor;
  final Color backgroundColor;
  final Color? gridLineColor;
  final Color? zeroLineColor;
  final Color? labelColor;

  static const int bandCount = 10;

  static final List<double> _xCache = List<double>.filled(bandCount, 0.0);
  static double _xCacheWidth = -1.0;

  static final List<Offset> _nodePoints = List<Offset>.filled(
    bandCount,
    Offset.zero,
  );
  static final Path _curvePath = Path();
  static final Path _fillPath = Path();

  static final Paint _bgPaint = Paint();
  static final Paint _verticalAxisPaint = Paint()..strokeWidth = 1.0;
  static final Paint _zeroLinePaint = Paint()..strokeWidth = 1.2;
  static final Paint _guideLinePaint = Paint()..strokeWidth = 1.0;
  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()
    ..strokeWidth = 2.2
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final Paint _projPaint = Paint()..strokeWidth = 1.2;
  static final Paint _glowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _pointPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _centerDotPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static Color? _cachedLabelColor;
  static TextPainter? _tpPlus12;
  static TextPainter? _tpZero;
  static TextPainter? _tpMinus12;

  const EqCurvePainter({
    required this.equalizer,
    this.activeColor = const Color(0xFF00D1FF),
    this.backgroundColor = const Color(0xFF090D18),
    this.gridLineColor,
    this.zeroLineColor,
    this.labelColor,
  });

  static double getXForBand(int index, double width) {
    return (width / (bandCount + 1)) * (index + 1);
  }

  static void _ensureLabelPainters(Color color) {
    if (_cachedLabelColor == color && _tpPlus12 != null) return;
    _cachedLabelColor = color;
    TextPainter makeLabel(String text) {
      return TextPainter(
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
    }

    _tpPlus12 = makeLabel('+12dB');
    _tpZero = makeLabel('0dB');
    _tpMinus12 = makeLabel('-12dB');
  }

  @override
  void paint(Canvas canvas, Size size) {
    _bgPaint.color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      _bgPaint,
    );

    final centerY = size.height / 2;
    final verticalAmplitude = size.height * 0.38;

    final effectiveGridColor = gridLineColor ?? const Color(0xFF1B2438);
    final effectiveZeroColor = zeroLineColor ?? const Color(0xFF26324A);
    final effectiveLabelColor = labelColor ?? const Color(0xFF6B7A99);

    if (_xCacheWidth != size.width) {
      _xCacheWidth = size.width;
      for (int i = 0; i < bandCount; i++) {
        _xCache[i] = getXForBand(i, size.width);
      }
    }

    // 1. Soft vertical axis lines for each frequency band
    _verticalAxisPaint.color = effectiveGridColor.withValues(alpha: 0.35);
    for (int i = 0; i < bandCount; i++) {
      final x = _xCache[i];
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _verticalAxisPaint);
    }

    // 2. Horizontal center line for 0 dB
    _zeroLinePaint.color = effectiveZeroColor;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _zeroLinePaint,
    );

    // 3. Horizontal guide lines for +12 dB and -12 dB
    _guideLinePaint.color = effectiveGridColor;
    final topLimitY = centerY - verticalAmplitude;
    final bottomLimitY = centerY + verticalAmplitude;
    canvas.drawLine(
      Offset(0, topLimitY),
      Offset(size.width, topLimitY),
      _guideLinePaint,
    );
    canvas.drawLine(
      Offset(0, bottomLimitY),
      Offset(size.width, bottomLimitY),
      _guideLinePaint,
    );

    // 4. Cached dB scale labels
    _ensureLabelPainters(effectiveLabelColor);
    _tpPlus12!.paint(canvas, const Offset(8, 4));
    _tpZero!.paint(canvas, Offset(8, centerY - 6));
    _tpMinus12!.paint(canvas, Offset(8, size.height - 18));

    // 5. Spline curve calculation
    _curvePath.reset();
    _fillPath.reset();
    final bands = equalizer.toList();

    _curvePath.moveTo(0, centerY);
    _fillPath.moveTo(0, centerY);

    double prevY = centerY;
    for (int i = 0; i < bandCount; i++) {
      final gain = bands[i].clamp(-12.0, 12.0);
      final y = centerY - (gain / 12.0) * verticalAmplitude;
      final x = _xCache[i];
      _nodePoints[i] = Offset(x, y);

      if (i == 0) {
        _curvePath.quadraticBezierTo(x * 0.5, centerY, x, y);
        _fillPath.quadraticBezierTo(x * 0.5, centerY, x, y);
      } else {
        final prevX = _xCache[i - 1];
        final midX = (prevX + x) / 2;
        _curvePath.cubicTo(midX, prevY, midX, y, x, y);
        _fillPath.cubicTo(midX, prevY, midX, y, x, y);
      }
      prevY = y;
    }

    _curvePath.lineTo(size.width, centerY);
    _fillPath.lineTo(size.width, centerY);
    _fillPath.close();

    // 6. Fill gradient under curve
    _fillPaint.shader = LinearGradient(
      colors: [
        activeColor.withValues(alpha: 0.25),
        activeColor.withValues(alpha: 0.0),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Offset.zero & size);
    canvas.drawPath(_fillPath, _fillPaint);

    // 7. Stroke curve
    _strokePaint.color = activeColor;
    canvas.drawPath(_curvePath, _strokePaint);

    // 8. Draw frequency nodes & guidelines
    _projPaint.color = activeColor.withValues(alpha: 0.3);
    _glowPaint.color = activeColor.withValues(alpha: 0.35);
    _pointPaint.color = activeColor;
    for (int i = 0; i < bandCount; i++) {
      final pt = _nodePoints[i];
      canvas.drawLine(Offset(pt.dx, centerY), pt, _projPaint);
      canvas.drawCircle(pt, 6.0, _glowPaint);
      canvas.drawCircle(pt, 3.5, _pointPaint);
      canvas.drawCircle(pt, 1.5, _centerDotPaint);
    }
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
