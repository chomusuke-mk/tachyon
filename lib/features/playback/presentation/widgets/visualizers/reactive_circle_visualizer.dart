import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Resolves the accent color for the reactive circle visualizer.
///
/// Uses [trackColor] if provided, adjusting luminance and saturation to guarantee
/// a luminous neon appearance.
/// If [trackColor] is null, falls back to a high-contrast hue against the background:
/// - Dark mode: High-voltage electric neon yellow (`#FFEE00`).
/// - Light mode: Saturated high-contrast theme primary.
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

  // Fallback high-contrast colors
  if (isDark) {
    return const Color(0xFFFFEE00); // Electric Neon Yellow
  } else {
    return theme.colorScheme.primary;
  }
}

/// Painter for the reactive circular audio visualizer.
///
/// Visual architecture (inspired by the iconic NCS / Trapcode Form visualizer style):
/// 1. 100% transparent background (no container box or background fill).
/// 2. Audio-reactive deforming thick rim: can squash, flatten, and ripple dynamically
///    with beat isolated sub-bass and frequency harmonics.
/// 3. Multi-layer glowing strokes (soft outer bloom, mid halo, solid thick ring, specular core).
/// 4. Inner circular clip strictly masking all particles and waves along the deformed rim.
/// 5. 3D undulating reactive particle mesh (malla reactiva) with both horizontal ribbon
///    connectors and vertical depth lattice lines with glowing nodes.
class ReactiveCirclePainter extends CustomPainter {
  final List<double> magnitudes;
  final double smoothedBass;
  final double smoothedRms;
  final double phase;
  final Color accentColor;
  final double cornerRadius;
  final bool isActive;

  const ReactiveCirclePainter({
    required this.magnitudes,
    required this.smoothedBass,
    required this.smoothedRms,
    required this.phase,
    required this.accentColor,
    this.cornerRadius = 20.0,
    this.isActive = true,
  });

  double _sampleEnergy(double u) {
    if (!isActive || magnitudes.isEmpty) return 0.04;
    // Map u from [-1.0, 1.0] to [0.0, magnitudes.length - 1]
    final norm = ((u + 1.0) * 0.5).clamp(0.0, 1.0);
    final b = norm * (magnitudes.length - 1);
    final b0 = b.floor().clamp(0, magnitudes.length - 1);
    final b1 = (b0 + 1).clamp(0, magnitudes.length - 1);
    final t = b - b0;
    final rawMag = magnitudes[b0] * (1.0 - t) + magnitudes[b1] * t;
    return (rawMag * 0.72 + smoothedBass * 0.35 + smoothedRms * 0.12).clamp(
      0.0,
      1.2,
    );
  }

  double _sampleEnergyByAngle(double theta) {
    if (!isActive || magnitudes.isEmpty) return 0.04;
    // Normalized position based on trigonometric angle
    final norm = ((math.sin(theta) + 1.0) * 0.5).clamp(0.0, 1.0);
    final b = norm * (magnitudes.length - 1);
    final b0 = b.floor().clamp(0, magnitudes.length - 1);
    final b1 = (b0 + 1).clamp(0, magnitudes.length - 1);
    final t = b - b0;
    return (magnitudes[b0] * (1.0 - t) + magnitudes[b1] * t).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Canvas background is 100% transparent (no dark rect or stars)
    final center = Offset(size.width / 2, size.height / 2);
    final diameter = math.min(size.width, size.height);
    final baseRadius = diameter * 0.38;

    // 1. Deformed Reactive Perimeter Geometry
    // Computes dynamic squash-and-stretch ("círculo aplastado/chancado") and harmonic perturbations
    const int numSteps = 120;
    final perimeterOffsets = <Offset>[];
    final perimeterPath = Path();

    final bass = isActive ? smoothedBass.clamp(0.0, 1.0) : 0.0;

    for (int k = 0; k < numSteps; k++) {
      final theta = k * (2 * math.pi / numSteps);

      // Squash-and-stretch: when bass kicks, circle squashes vertically and bulges horizontally
      final squash = bass * 0.20 * math.cos(2 * theta);

      // Audio-reactive harmonic ripple along perimeter
      final angleEnergy = _sampleEnergyByAngle(theta);
      final wave =
          (angleEnergy * 0.12 * math.sin(5 * theta - phase * 2.0)) +
          (bass * 0.07 * math.cos(3 * theta + phase));

      final r =
          (baseRadius * (1.0 + bass * 0.10) +
                  (baseRadius * squash) +
                  (baseRadius * wave))
              .clamp(baseRadius * 0.55, diameter * 0.48);

      final px = center.dx + r * math.cos(theta);
      final py = center.dy + r * math.sin(theta);
      final pt = Offset(px, py);

      perimeterOffsets.add(pt);
      if (k == 0) {
        perimeterPath.moveTo(px, py);
      } else {
        perimeterPath.lineTo(px, py);
      }
    }
    perimeterPath.close();

    // 2. Inner Clip: Confines the reactive 3D lattice strictly inside the deforming perimeter
    canvas.save();
    canvas.clipPath(perimeterPath);

    // 3. Render 3D Reactive Mesh (Malla reactiva con líneas cruzadas y nodos)
    _drawReactiveMesh(canvas, center, baseRadius);

    canvas.restore();

    // 4. Luminous Deformed Thick Border ("borde mas grueso y reactivo")
    final strokeWidth = 10.0 + (bass * 8.0);

    // Layer A: Soft outer bloom halo
    final outerHaloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.2
      ..color = accentColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawPath(perimeterPath, outerHaloPaint);

    // Layer B: Mid-intensity halo
    final midHaloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.4
      ..color = accentColor.withValues(alpha: 0.48)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);
    canvas.drawPath(perimeterPath, midHaloPaint);

    // Layer C: Core thick deforming solid rim
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = accentColor;
    canvas.drawPath(perimeterPath, ringPaint);

    // Layer D: White-hot specular core line
    final specularPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, strokeWidth * 0.28)
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(perimeterPath, specularPaint);
  }

  void _drawReactiveMesh(Canvas canvas, Offset center, double radius) {
    // -------------------------------------------------------------
    // SHEET 1: Foreground Lower Reactive Mesh (Malla reactiva inferior)
    // -------------------------------------------------------------
    const int fgCols = 32;
    const int fgRows = 16;

    final grid = List.generate(
      fgRows,
      (_) => List<Offset>.filled(fgCols, Offset.zero),
    );
    final energies = List.generate(
      fgRows,
      (_) => List<double>.filled(fgCols, 0.0),
    );

    for (int j = 0; j < fgRows; j++) {
      final v = j / (fgRows - 1); // 0.0 near -> 1.0 deep
      final z = 1.0 + (v * 1.30);
      final s = 1.0 / z; // perspective scale

      final yRowBase = center.dy + (radius * 0.20) + (v * radius * 0.38 * s);

      for (int i = 0; i < fgCols; i++) {
        final u = -1.0 + (i / (fgCols - 1)) * 2.0;
        final energy = _sampleEnergy(u);
        energies[j][i] = energy;

        // Traveling harmonic wave undulations
        final wave1 = math.sin(u * 3.8 + phase - (v * 1.8));
        final wave2 = math.cos(u * 2.2 - (phase * 0.65) + (v * 1.1));
        final displacement =
            (radius * 0.40) * energy * wave1 + (radius * 0.12) * wave2;

        final px = center.dx + (u * radius * 0.95) * s;
        final py = yRowBase - (displacement * s);
        grid[j][i] = Offset(px, py);
      }
    }

    final rowLinePaint = Paint()..style = PaintingStyle.stroke;
    final colLinePaint = Paint()..style = PaintingStyle.stroke;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final specularDotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    // 1A. Draw horizontal row ribbon lines
    for (int j = 0; j < fgRows; j++) {
      final v = j / (fgRows - 1);
      final s = 1.0 / (1.0 + (v * 1.30));
      final lineAlpha = math.min(
        1.0,
        (0.14 + 0.18 * (1.0 - v * 0.45)) * (0.45 + 0.55 * (smoothedBass + 0.2)),
      );
      rowLinePaint
        ..strokeWidth = math.max(0.7, 1.4 * s)
        ..color = accentColor.withValues(alpha: lineAlpha);
      canvas.drawPoints(ui.PointMode.polygon, grid[j], rowLinePaint);
    }

    // 1B. Draw vertical column mesh lines (creates the tangible "malla reactiva" structure)
    for (int i = 0; i < fgCols; i++) {
      final colPoints = <Offset>[];
      for (int j = 0; j < fgRows; j++) {
        colPoints.add(grid[j][i]);
      }
      final colAlpha = math.min(0.8, 0.10 + 0.15 * (smoothedBass + 0.1));
      colLinePaint
        ..strokeWidth = 0.8
        ..color = accentColor.withValues(alpha: colAlpha);
      canvas.drawPoints(ui.PointMode.polygon, colPoints, colLinePaint);
    }

    // 1C. Draw 3D glowing nodes at mesh intersections
    for (int j = 0; j < fgRows; j++) {
      final v = j / (fgRows - 1);
      final s = 1.0 / (1.0 + (v * 1.30));

      for (int i = 0; i < fgCols; i++) {
        final pt = grid[j][i];
        final energy = energies[j][i];

        final dotRadius = math.max(1.1, (2.6 * s) * (1.0 + (energy * 0.45)));
        final dotAlpha = math.min(
          1.0,
          (0.38 + 0.62 * (1.0 - v * 0.40)) * (0.50 + 0.50 * energy),
        );

        dotPaint.color = accentColor.withValues(alpha: dotAlpha);
        canvas.drawCircle(pt, dotRadius, dotPaint);

        if (energy > 0.45) {
          final specAlpha = math.min(0.9, (energy - 0.45) / 0.55);
          specularDotPaint.color = Colors.white.withValues(alpha: specAlpha);
          canvas.drawCircle(pt, dotRadius * 0.45, specularDotPaint);
        }
      }
    }

    // -------------------------------------------------------------
    // SHEET 2: Background Upper Reactive Mesh (Malla reactiva superior)
    // -------------------------------------------------------------
    const int bgCols = 28;
    const int bgRows = 12;

    final bgGrid = List.generate(
      bgRows,
      (_) => List<Offset>.filled(bgCols, Offset.zero),
    );
    final bgEnergies = List.generate(
      bgRows,
      (_) => List<double>.filled(bgCols, 0.0),
    );

    for (int j = 0; j < bgRows; j++) {
      final v = j / (bgRows - 1);
      final z = 1.0 + (v * 1.30);
      final s = 1.0 / z;

      final yRowBase = center.dy - (radius * 0.28) - (v * radius * 0.28 * s);

      for (int i = 0; i < bgCols; i++) {
        final u = -1.0 + (i / (bgCols - 1)) * 2.0;
        final energy = _sampleEnergy(u);
        bgEnergies[j][i] = energy;

        final wave1 = math.sin(u * 3.4 - (phase * 0.8) + (v * 1.4));
        final wave2 = math.cos(u * 4.2 + (phase * 0.5));
        final displacement =
            (radius * 0.28) * (energy * 0.75) * wave1 + (radius * 0.08) * wave2;

        final px = center.dx + (u * radius * 0.94) * s;
        final py = yRowBase + (displacement * s);
        bgGrid[j][i] = Offset(px, py);
      }
    }

    // 2A. Upper mesh row lines
    for (int j = 0; j < bgRows; j++) {
      final v = j / (bgRows - 1);
      final s = 1.0 / (1.0 + (v * 1.30));
      final lineAlpha = math.min(
        0.8,
        (0.08 + 0.12 * (1.0 - v * 0.45)) * (0.35 + 0.65 * (smoothedRms + 0.2)),
      );
      rowLinePaint
        ..strokeWidth = math.max(0.6, 1.0 * s)
        ..color = accentColor.withValues(alpha: lineAlpha);
      canvas.drawPoints(ui.PointMode.polygon, bgGrid[j], rowLinePaint);
    }

    // 2B. Upper mesh column lines
    for (int i = 0; i < bgCols; i++) {
      final colPoints = <Offset>[];
      for (int j = 0; j < bgRows; j++) {
        colPoints.add(bgGrid[j][i]);
      }
      colLinePaint
        ..strokeWidth = 0.6
        ..color = accentColor.withValues(alpha: 0.08);
      canvas.drawPoints(ui.PointMode.polygon, colPoints, colLinePaint);
    }

    // 2C. Upper mesh dots
    for (int j = 0; j < bgRows; j++) {
      final v = j / (bgRows - 1);
      final s = 1.0 / (1.0 + (v * 1.30));

      for (int i = 0; i < bgCols; i++) {
        final pt = bgGrid[j][i];
        final energy = bgEnergies[j][i];

        final dotRadius = math.max(0.9, (2.0 * s) * (1.0 + (energy * 0.35)));
        final dotAlpha = math.min(
          0.85,
          (0.25 + 0.45 * (1.0 - v * 0.40)) * (0.45 + 0.55 * energy),
        );

        dotPaint.color = accentColor.withValues(alpha: dotAlpha);
        canvas.drawCircle(pt, dotRadius, dotPaint);

        if (energy > 0.55) {
          final specAlpha = math.min(0.8, (energy - 0.55) / 0.45);
          specularDotPaint.color = Colors.white.withValues(alpha: specAlpha);
          canvas.drawCircle(pt, dotRadius * 0.40, specularDotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ReactiveCirclePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.smoothedBass != smoothedBass ||
        oldDelegate.smoothedRms != smoothedRms ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isActive != isActive ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.magnitudes != magnitudes;
  }
}

/// Self-contained stateful widget driving continuous 60fps wave phase,
/// hosting the [ReactiveCirclePainter], and embedding the circular translucent
/// application icon at the center.
class ReactiveCircleVisualizerWidget extends StatefulWidget {
  final double size;
  final double cornerRadius;
  final List<double> displayBands;
  final double smoothedBass;
  final double smoothedRms;
  final Color accentColor;
  final bool isPlaying;

  const ReactiveCircleVisualizerWidget({
    super.key,
    required this.size,
    this.cornerRadius = 20.0,
    required this.displayBands,
    required this.smoothedBass,
    required this.smoothedRms,
    required this.accentColor,
    required this.isPlaying,
  });

  @override
  State<ReactiveCircleVisualizerWidget> createState() =>
      _ReactiveCircleVisualizerWidgetState();
}

class _ReactiveCircleVisualizerWidgetState
    extends State<ReactiveCircleVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phaseController;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.isPlaying) {
      _phaseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ReactiveCircleVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_phaseController.isAnimating) {
          _phaseController.repeat();
        }
      } else {
        _phaseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _phaseController,
      builder: (context, _) {
        final phase = _phaseController.value * 2 * math.pi;
        return Stack(
          alignment: Alignment.center,
          children: [
            // 1. Reactive Deformed Circle & 3D Undulating Lattice Mesh
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: ReactiveCirclePainter(
                magnitudes: widget.displayBands,
                smoothedBass: widget.smoothedBass,
                smoothedRms: widget.smoothedRms,
                phase: phase,
                accentColor: widget.accentColor,
                cornerRadius: widget.cornerRadius,
                isActive: widget.isPlaying,
              ),
            ),
          ],
        );
      },
    );
  }
}
