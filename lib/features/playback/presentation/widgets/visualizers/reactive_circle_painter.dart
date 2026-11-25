import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Number of angular spectrum rays sampled around the reactive circle.
const int kReactiveCircleRays = 128;

/// Number of concentric dot layers rendered along every spectrum ray.
const int kReactiveCircleDotLayers = 18;

/// Number of dot layers batched into each depth draw group (`near`, `mid`, `far`).
const int kReactiveCircleLayersPerGroup = 6;

/// Resolves the accent color for the reactive circle visualizer.
///
/// Uses [trackColor] if provided, adjusting luminance and saturation to guarantee
/// a luminous neon appearance against the active [theme] brightness. When
/// [trackColor] is `null`, falls back to [ColorScheme.primary].
Color resolveReactiveCircleColor({
  Color? trackColor,
  required ThemeData theme,
}) {
  final isDark = theme.brightness == Brightness.dark;

  if (trackColor != null) {
    final hsl = HSLColor.fromColor(trackColor);
    if (isDark) {
      final adjustedLightness = hsl.lightness.clamp(0.48, 0.85);
      final adjustedSaturation = hsl.saturation.clamp(0.65, 1.0);
      return hsl
          .withLightness(adjustedLightness)
          .withSaturation(adjustedSaturation)
          .toColor();
    } else {
      final adjustedLightness = hsl.lightness.clamp(0.25, 0.52);
      final adjustedSaturation = hsl.saturation.clamp(0.70, 1.0);
      return hsl
          .withLightness(adjustedLightness)
          .withSaturation(adjustedSaturation)
          .toColor();
    }
  }

  return theme.colorScheme.primary;
}

/// Visual contour styles supported by [ReactiveCirclePainter].
enum NcsSpectrumStyle {
  /// Solid neon band surrounded by a dotted 3D sphere lattice.
  bars,

  /// Dual-layered glowing wave contours.
  analogWave,
}

/// Shared render metrics updated by the visualizer physics loop and consumed by
/// [ReactiveCirclePainter] without triggering widget rebuilds.
class ReactiveCircleRenderState {
  /// Smoothed low-frequency energy used to pulse the outer ring radius.
  double smoothBass = 0.0;

  /// Smoothed root-mean-square amplitude across all bands.
  double smoothRms = 0.0;

  /// Horizontal GPU micro-shake offset in logical pixels.
  double shakeX = 0.0;

  /// Vertical GPU micro-shake offset in logical pixels.
  double shakeY = 0.0;

  /// Creates a mutable [ReactiveCircleRenderState] initialized to zero.
  ReactiveCircleRenderState();
}

/// Zero-allocation [CustomPainter] rendering an NCS-style glowing neon ring
/// and dotted audio spectrum lattice.
///
/// Reuses preallocated [Paint], [Path], and [Float32List] buffers every frame
/// so [paint] incurs zero heap allocations and no blur shader passes.
class ReactiveCirclePainter extends CustomPainter {
  /// Shared frame physics values read directly on each paint pass.
  final ReactiveCircleRenderState renderState;

  /// Primary normalized spectrum magnitudes (`kReactiveCircleRays` entries).
  final Float32List bins;

  /// Secondary spectrum magnitudes used for analog wave contour layering.
  final Float32List secondaryBins;

  /// Scratch buffer storing `[x0, y0, ...]` inner contour coordinates.
  final Float32List innerPoints;

  /// Scratch buffer storing resolved inner radii for each angular ray.
  final Float32List radii;

  /// Scratch buffer storing near dot coordinates for batched point rendering.
  final Float32List dotsNear;

  /// Scratch buffer storing mid-depth dot coordinates.
  final Float32List dotsMid;

  /// Scratch buffer storing far dot coordinates.
  final Float32List dotsFar;

  /// Precomputed cosine lookup table for each ray angle.
  final Float32List cosLUT;

  /// Precomputed sine lookup table for each ray angle.
  final Float32List sinLUT;

  /// Unscaled outer ring radius in logical pixels.
  final double baseRadius;

  /// Maximum inward excursion amplitude for active spectrum peaks.
  final double maxBarHeight;

  /// Luminous neon color driving ring fill, dot gradients, and glow shader.
  final Color accentColor;

  /// Active rendering mode selecting dot lattice or analog contour lines.
  final NcsSpectrumStyle style;

  /// Optional monogram text painted at the center of the ring.
  final String? centerText;

  static final Float32List _dotProfile = _buildDotProfile();

  static Float32List _buildDotProfile() {
    final list = Float32List(kReactiveCircleDotLayers);
    for (int j = 0; j < kReactiveCircleDotLayers; j++) {
      // u^1.8 keeps dots dense near the band while opening gaps inward.
      final double u = (j + 1) / kReactiveCircleDotLayers;
      list[j] = math.pow(u, 1.8).toDouble();
    }
    return list;
  }

  static const double _glowScale = 1.20;

  static ui.Shader? _glowShader;
  static Color? _glowShaderColor;

  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _bandPaint = Paint()..style = PaintingStyle.fill;
  final Paint _dotsNearPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _dotsMidPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _dotsFarPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _contourPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  final Paint _contourBackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  final Path _bandPath = Path()..fillType = PathFillType.evenOdd;
  final Path _innerPath = Path();
  final Path _secondaryPath = Path();

  TextPainter? _cachedTextPainter;
  String? _lastText;
  Color? _lastAccentColor;

  /// Creates a [ReactiveCirclePainter] with preallocated buffers and styling.
  ReactiveCirclePainter({
    super.repaint,
    ReactiveCircleRenderState? renderState,
    Float32List? bins,
    Float32List? secondaryBins,
    Float32List? innerPoints,
    Float32List? radii,
    Float32List? dotsNear,
    Float32List? dotsMid,
    Float32List? dotsFar,
    Float32List? cosLUT,
    Float32List? sinLUT,
    double? baseRadius,
    double? maxBarHeight,
    required this.accentColor,
    this.style = NcsSpectrumStyle.bars,
    this.centerText,
  }) : renderState = renderState ?? ReactiveCircleRenderState(),
       bins = bins ?? Float32List(kReactiveCircleRays),
       secondaryBins = secondaryBins ?? Float32List(kReactiveCircleRays),
       innerPoints = innerPoints ?? Float32List(kReactiveCircleRays * 2),
       radii = radii ?? Float32List(kReactiveCircleRays),
       dotsNear =
           dotsNear ??
           Float32List(kReactiveCircleRays * kReactiveCircleLayersPerGroup * 2),
       dotsMid =
           dotsMid ??
           Float32List(kReactiveCircleRays * kReactiveCircleLayersPerGroup * 2),
       dotsFar =
           dotsFar ??
           Float32List(kReactiveCircleRays * kReactiveCircleLayersPerGroup * 2),
       cosLUT = cosLUT ?? Float32List(kReactiveCircleRays),
       sinLUT = sinLUT ?? Float32List(kReactiveCircleRays),
       baseRadius = baseRadius ?? 100.0,
       maxBarHeight = maxBarHeight ?? 80.0 {
    _updatePaints(accentColor);
  }

  void _updatePaints(Color color) {
    if (_glowShader == null || _glowShaderColor != color) {
      const double ring = 1.0 / _glowScale;
      _glowShader = ui.Gradient.radial(
        Offset.zero,
        1.0,
        [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.10),
          color.withValues(alpha: 0.42),
          color.withValues(alpha: 0.0),
        ],
        const [0.0, ring * 0.80, ring, 1.0],
      );
      _glowShaderColor = color;
    }
    _glowPaint.shader = _glowShader;
    _bandPaint.color = Color.lerp(color, Colors.white, 0.10)!;
    _dotsNearPaint.color = Color.lerp(color, Colors.white, 0.35)!;
    _dotsMidPaint.color =
        Color.lerp(color, Colors.white, 0.20)!.withValues(alpha: 0.75);
    _dotsFarPaint.color = color.withValues(alpha: 0.55);

    _contourPaint
      ..color = Color.lerp(color, Colors.white, 0.70)!.withValues(alpha: 0.85)
      ..strokeWidth = 2.0;
    _contourBackPaint
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 5.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width * 0.5;
    final double cy = size.height * 0.5;

    final double dynamicScale = 1.0 + (renderState.smoothBass * 0.05);
    final double ringRadius = baseRadius * dynamicScale;
    final double ringWidth = math.max(3.0, ringRadius * 0.035);

    canvas.save();
    canvas.translate(renderState.shakeX, renderState.shakeY);

    canvas.save();
    canvas.translate(cx, cy);
    final double glowRadius = ringRadius * _glowScale;
    canvas.scale(glowRadius, glowRadius);
    canvas.drawCircle(Offset.zero, 1.0, _glowPaint);
    canvas.restore();

    final double innerBase = ringRadius - ringWidth;
    final double dotWidth = math.max(1.1, ringRadius * 0.0085);
    _dotsNearPaint.strokeWidth = dotWidth;
    _dotsMidPaint.strokeWidth = dotWidth;
    _dotsFarPaint.strokeWidth = dotWidth * 1.1;

    if (style == NcsSpectrumStyle.analogWave) {
      _fillInnerPoints(
        secondaryBins,
        cx,
        cy,
        innerBase,
        ringRadius * 0.30,
        ringRadius,
      );
      _buildClosedPath(_secondaryPath);
    }
    _fillInnerPoints(bins, cx, cy, innerBase, ringRadius * 0.22, ringRadius);
    _buildClosedPath(_innerPath);

    // Path.reset() clears fillType, so re-apply evenOdd every frame.
    _bandPath
      ..reset()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: ringRadius))
      ..addPath(_innerPath, Offset.zero);
    canvas.drawPath(_bandPath, _bandPaint);

    if (style == NcsSpectrumStyle.bars) {
      _paintDotLattice(canvas, cx, cy, ringRadius);
    } else {
      canvas.drawPath(_secondaryPath, _contourBackPaint);
      canvas.drawPath(_innerPath, _contourPaint);
    }

    if (centerText != null && centerText!.isNotEmpty) {
      _paintCachedCenterText(canvas, cx, cy, dynamicScale);
    }

    canvas.restore();
  }

  void _fillInnerPoints(
    Float32List values,
    double cx,
    double cy,
    double innerBase,
    double reach,
    double ringRadius,
  ) {
    final double rMin = ringRadius * 0.5;
    final double rest = ringRadius * 0.01;
    for (int i = 0; i < kReactiveCircleRays; i++) {
      double r = innerBase - rest - values[i] * values[i] * reach;
      if (r < rMin) r = rMin;
      radii[i] = r;
      final int idx = i * 2;
      innerPoints[idx] = cx + cosLUT[i] * r;
      innerPoints[idx + 1] = cy + sinLUT[i] * r;
    }
  }

  void _buildClosedPath(Path path) {
    path.reset();
    final int last = (kReactiveCircleRays - 1) * 2;
    double xCurr = innerPoints[0];
    double yCurr = innerPoints[1];
    path.moveTo(
      (innerPoints[last] + xCurr) * 0.5,
      (innerPoints[last + 1] + yCurr) * 0.5,
    );
    for (int i = 0; i < kReactiveCircleRays; i++) {
      final int next = ((i + 1) & (kReactiveCircleRays - 1)) * 2;
      final double xNext = innerPoints[next];
      final double yNext = innerPoints[next + 1];
      path.quadraticBezierTo(
        xCurr,
        yCurr,
        (xCurr + xNext) * 0.5,
        (yCurr + yNext) * 0.5,
      );
      xCurr = xNext;
      yCurr = yNext;
    }
    path.close();
  }

  void _paintDotLattice(
    Canvas canvas,
    double cx,
    double cy,
    double ringRadius,
  ) {
    final double rMin = ringRadius * 0.16;
    final double minLen = ringRadius * 0.10;
    final double lenGain = ringRadius * 0.85;
    final Float32List profile = _dotProfile;

    for (int i = 0; i < kReactiveCircleRays; i++) {
      final double rs = radii[i];
      final double c = cosLUT[i];
      final double s = sinLUT[i];
      final double b = bins[i];
      double len = minLen + b * lenGain;
      final double maxLen = rs - rMin;
      if (len > maxLen) len = maxLen;

      for (int jj = 0; jj < kReactiveCircleLayersPerGroup; jj++) {
        final int base = (i * kReactiveCircleLayersPerGroup + jj) * 2;

        double r = rs - len * profile[jj];
        dotsNear[base] = cx + c * r;
        dotsNear[base + 1] = cy + s * r;

        r = rs - len * profile[jj + kReactiveCircleLayersPerGroup];
        dotsMid[base] = cx + c * r;
        dotsMid[base + 1] = cy + s * r;

        r = rs - len * profile[jj + kReactiveCircleLayersPerGroup * 2];
        dotsFar[base] = cx + c * r;
        dotsFar[base + 1] = cy + s * r;
      }
    }

    canvas.drawRawPoints(ui.PointMode.points, dotsFar, _dotsFarPaint);
    canvas.drawRawPoints(ui.PointMode.points, dotsMid, _dotsMidPaint);
    canvas.drawRawPoints(ui.PointMode.points, dotsNear, _dotsNearPaint);
  }

  void _paintCachedCenterText(
    Canvas canvas,
    double cx,
    double cy,
    double scale,
  ) {
    if (_cachedTextPainter == null ||
        _lastText != centerText ||
        _lastAccentColor != accentColor) {
      _lastText = centerText;
      _lastAccentColor = accentColor;
      _cachedTextPainter = TextPainter(
        text: TextSpan(
          text: centerText,
          style: TextStyle(
            color: Color.lerp(accentColor, Colors.white, 0.85),
            fontSize: baseRadius * 0.38,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, scale);
    final tp = _cachedTextPainter!;
    tp.paint(canvas, Offset(-tp.width * 0.5, -tp.height * 0.5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReactiveCirclePainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.baseRadius != baseRadius ||
        oldDelegate.maxBarHeight != maxBarHeight ||
        oldDelegate.style != style;
  }
}
