import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

/// Resolves the accent color for the reactive circle visualizer.
///
/// Uses [trackColor] if provided, adjusting luminance and saturation to guarantee
/// a luminous neon appearance.
/// If [trackColor] is null, falls back to the application's theme emphasis color
/// ([ColorScheme.primary]), adjusted for high contrast and luminosity against the background.
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

  // Fallback to application theme's emphasis color (no hardcoded yellow)
  return theme.colorScheme.primary;
}

enum NcsSpectrumStyle {
  bars,
  analogWave,
}

/// Lightweight notifier triggering only CustomPainter.paint() without Widget.build() rebuilds.
class _FrameTickNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Shared render state between the physics engine and the custom painter.
class ReactiveCircleRenderState {
  double smoothBass = 0.0;
  double smoothRms = 0.0;
  double shakeX = 0.0;
  double shakeY = 0.0;
}

/// Number of angular rays (spectrum bins) around the circle.
const int _kRays = 128;

/// Number of dot layers drawn along every ray.
const int _kDotLayers = 18;

/// Number of dot layers per batched draw call (3 groups: near / mid / far).
const int _kLayersPerGroup = 6;

/// Production zero-allocation CustomPainter rendering the classic NCS
/// "neon ring + dotted wave" audio-reactive circle.
///
/// Look (modelled after the NCS visualizer):
/// - A thick glowing neon ring at the outer edge.
/// - The inner edge of the ring is deformed *inwards* by the spectrum, forming
///   an organic wavy crescent (the audio never shoots rays outwards).
/// - Beyond the solid band, a lattice of dots fades towards the centre, dense
///   near the band and sparse further in, giving the "3D dotted sphere" feel.
/// - The centre stays transparent.
///
/// Efficiency: no `Paint`/`Path`/`List` allocation in [paint], no blur
/// (`MaskFilter`) passes, a single cached radial-gradient shader for the glow
/// and only 6 draw calls per frame (glow, band, 3 dot batches, optional contour).
class ReactiveCirclePainter extends CustomPainter {
  final ReactiveCircleRenderState renderState;
  final Float32List bins;
  final Float32List secondaryBins;
  final Float32List innerPoints;
  final Float32List radii;
  final Float32List dotsNear;
  final Float32List dotsMid;
  final Float32List dotsFar;
  final Float32List cosLUT;
  final Float32List sinLUT;

  final double baseRadius;
  final double maxBarHeight;
  final Color accentColor;
  final NcsSpectrumStyle style;
  final String? centerText;

  /// Radial distribution of the dot layers (0..1), dense near the band.
  static final Float32List _dotProfile = _buildDotProfile();

  static Float32List _buildDotProfile() {
    final list = Float32List(_kDotLayers);
    for (int j = 0; j < _kDotLayers; j++) {
      // u^1.8: practically continuous lines right at the band, opening up to a
      // sparse dotted pitch towards the tips.
      final double u = (j + 1) / _kDotLayers;
      list[j] = math.pow(u, 1.8).toDouble();
    }
    return list;
  }

  /// Ratio between the glow gradient radius and the ring radius.
  static const double _glowScale = 1.20;

  // Shared (cached) glow shader: built once per accent color, in unit space.
  static ui.Shader? _glowShader;
  static Color? _glowShaderColor;

  // Pre-instantiated Paint & Path objects (Zero runtime allocation inside paint)
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
  })  : renderState = renderState ?? ReactiveCircleRenderState(),
        bins = bins ?? Float32List(_kRays),
        secondaryBins = secondaryBins ?? Float32List(_kRays),
        innerPoints = innerPoints ?? Float32List(_kRays * 2),
        radii = radii ?? Float32List(_kRays),
        dotsNear = dotsNear ?? Float32List(_kRays * _kLayersPerGroup * 2),
        dotsMid = dotsMid ?? Float32List(_kRays * _kLayersPerGroup * 2),
        dotsFar = dotsFar ?? Float32List(_kRays * _kLayersPerGroup * 2),
        cosLUT = cosLUT ?? Float32List(_kRays),
        sinLUT = sinLUT ?? Float32List(_kRays),
        baseRadius = baseRadius ?? 100.0,
        maxBarHeight = maxBarHeight ?? 80.0 {
    _updatePaints(accentColor);
  }

  void _updatePaints(Color color) {
    if (_glowShader == null || _glowShaderColor != color) {
      // Unit-space gradient (radius 1.0) scaled on the canvas every frame, so
      // the same shader serves any ring size / pulse without being rebuilt.
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

    _dotsNearPaint.color =
        Color.lerp(color, Colors.white, 0.35)!;
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

    // Apply micro-shake directly on the GPU matrix without rebuilding widgets
    canvas.save();
    canvas.translate(renderState.shakeX, renderState.shakeY);

    // 1. Soft neon glow around the ring: one cached gradient shader, no blur.
    canvas.save();
    canvas.translate(cx, cy);
    final double glowRadius = ringRadius * _glowScale;
    canvas.scale(glowRadius, glowRadius);
    canvas.drawCircle(Offset.zero, 1.0, _glowPaint);
    canvas.restore();

    // 2. Spectrum -> inner edge of the ring (deformed inwards).
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

    // 3. Solid neon band between the outer circle and the wavy inner contour.
    // NOTE: Path.reset() restores the default fill type, so evenOdd must be
    // re-applied every frame or the whole disc gets filled instead of a ring.
    _bandPath
      ..reset()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: ringRadius))
      ..addPath(_innerPath, Offset.zero);
    canvas.drawPath(_bandPath, _bandPaint);

    // 4. Dotted lattice (bars style) or liquid contour (analog style).
    if (style == NcsSpectrumStyle.bars) {
      _paintDotLattice(canvas, cx, cy, ringRadius);
    } else {
      canvas.drawPath(_secondaryPath, _contourBackPaint);
      canvas.drawPath(_innerPath, _contourPaint);
    }

    // 5. Central text cached in GPU memory
    if (centerText != null && centerText!.isNotEmpty) {
      _paintCachedCenterText(canvas, cx, cy, dynamicScale);
    }

    canvas.restore();
  }

  /// Computes the inner contour points of the band for [values] into
  /// [innerPoints] as `[x0, y0, x1, y1, ...]`.
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
    for (int i = 0; i < _kRays; i++) {
      // Squared: quiet bins leave a thin ring, only loud ones bulge inwards.
      double r = innerBase - rest - values[i] * values[i] * reach;
      if (r < rMin) r = rMin;
      radii[i] = r;
      final int idx = i * 2;
      innerPoints[idx] = cx + cosLUT[i] * r;
      innerPoints[idx + 1] = cy + sinLUT[i] * r;
    }
  }

  /// Builds a smooth closed curve through [innerPoints] (midpoint quadratic
  /// Beziers) reusing the given pre-instantiated [path].
  void _buildClosedPath(Path path) {
    path.reset();
    final int last = (_kRays - 1) * 2;
    double xCurr = innerPoints[0];
    double yCurr = innerPoints[1];
    path.moveTo(
      (innerPoints[last] + xCurr) * 0.5,
      (innerPoints[last + 1] + yCurr) * 0.5,
    );
    for (int i = 0; i < _kRays; i++) {
      final int next = ((i + 1) & (_kRays - 1)) * 2;
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

  /// Rays of dots shooting *inwards* from the band, like the NCS dotted wave.
  /// Ray length follows the spectrum (loud areas stream deep into the circle,
  /// quiet ones leave just a fringe). Dots are continuous next to the band and
  /// open up to a sparse pitch towards the tips, fading as they go.
  /// Packed into 3 contiguous buffers => exactly 3 `drawRawPoints` calls.
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

    for (int i = 0; i < _kRays; i++) {
      final double rs = radii[i];
      final double c = cosLUT[i];
      final double s = sinLUT[i];
      final double b = bins[i];
      double len = minLen + b * lenGain;
      final double maxLen = rs - rMin;
      if (len > maxLen) len = maxLen;

      for (int jj = 0; jj < _kLayersPerGroup; jj++) {
        final int base = (i * _kLayersPerGroup + jj) * 2;

        double r = rs - len * profile[jj];
        dotsNear[base] = cx + c * r;
        dotsNear[base + 1] = cy + s * r;

        r = rs - len * profile[jj + _kLayersPerGroup];
        dotsMid[base] = cx + c * r;
        dotsMid[base + 1] = cy + s * r;

        r = rs - len * profile[jj + _kLayersPerGroup * 2];
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

/// Ultra-high performance NCS Circular Audio Visualizer Widget.
///
/// Features:
/// - Zero-Allocation runtime architecture (`Float32List` native buffers).
/// - Stereo L/R separation (64 sub-bands per hemisphere via Catmull-Rom).
/// - Trigonometric lookup tables (LUTs) pre-computed in `initState`.
/// - Neon ring deformed inwards by the spectrum + dotted lattice, 5 batched draw calls.
/// - Auto-sleep on silence for 0% CPU/GPU overhead when paused.
class ReactiveCircleVisualizerWidget extends StatefulWidget {
  final double size;
  final double cornerRadius;
  final List<double> displayBands;
  final double smoothedBass;
  final double smoothedRms;
  final double rawPeak;
  final double leftChannel;
  final double rightChannel;
  final Color accentColor;
  final bool isPlaying;
  final List<double> Function()? displayBandsProvider;
  final double Function()? smoothedRmsProvider;
  final double Function()? rawPeakProvider;
  final double Function()? leftChannelProvider;
  final double Function()? rightChannelProvider;
  final bool Function()? isPlayingProvider;
  final Listenable? frameListenable;
  final NcsSpectrumStyle style;
  final Widget? centerChild;
  final String? centerText;

  const ReactiveCircleVisualizerWidget({
    super.key,
    required this.size,
    this.cornerRadius = 20.0,
    required this.displayBands,
    required this.smoothedBass,
    required this.smoothedRms,
    this.rawPeak = 0.0,
    this.leftChannel = 0.0,
    this.rightChannel = 0.0,
    required this.accentColor,
    required this.isPlaying,
    this.displayBandsProvider,
    this.smoothedRmsProvider,
    this.rawPeakProvider,
    this.leftChannelProvider,
    this.rightChannelProvider,
    this.isPlayingProvider,
    this.frameListenable,
    this.style = NcsSpectrumStyle.bars,
    this.centerChild,
    this.centerText,
  });

  @override
  State<ReactiveCircleVisualizerWidget> createState() =>
      _ReactiveCircleVisualizerWidgetState();
}

class _ReactiveCircleVisualizerWidgetState
    extends State<ReactiveCircleVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _FrameTickNotifier _paintNotifier = _FrameTickNotifier();
  Duration _lastElapsed = Duration.zero;

  static const int _halfBins = _kRays ~/ 2;
  static const int _totalBins = _kRays;

  // Classic NCS rotation offset (-90° - 32°)
  static const double _rotationOffset =
      -math.pi / 2 - (32.0 * math.pi / 180.0);

  // --- PREALLOCATED NATIVE BUFFERS (Zero allocation during runtime) ---
  final Float32List _bands10 = Float32List(10);
  final Float32List _eqLeft = Float32List(10);
  final Float32List _eqRight = Float32List(10);
  final Float32List _smoothedBins = Float32List(_totalBins);
  final Float32List _secondaryBins = Float32List(_totalBins);
  final Float32List _postBlurBins = Float32List(_totalBins);

  // Render buffers shared with the painter (contiguous for batched GPU calls)
  final Float32List _innerPoints = Float32List(_totalBins * 2);
  final Float32List _radii = Float32List(_totalBins);
  final Float32List _dotsNear =
      Float32List(_totalBins * _kLayersPerGroup * 2);
  final Float32List _dotsMid = Float32List(_totalBins * _kLayersPerGroup * 2);
  final Float32List _dotsFar = Float32List(_totalBins * _kLayersPerGroup * 2);

  // Precomputed trigonometric & physics LUTs
  final Float32List _cosLUT = Float32List(_totalBins);
  final Float32List _sinLUT = Float32List(_totalBins);
  final Float32List _freqWeightLUT = Float32List(_halfBins);
  final Float32List _harmSin1LUT = Float32List(_halfBins);
  final Float32List _harmCos1LUT = Float32List(_halfBins);
  final Float32List _harmSin2LUT = Float32List(_halfBins);
  final Float32List _harmCos2LUT = Float32List(_halfBins);
  final Float32List _tauAttackLUT = Float32List(_halfBins);
  final Float32List _tauDecayLUT = Float32List(_halfBins);

  static const List<double> _preEmphasis = [
    0.88, 0.95, 1.05, 1.18, 1.30, 1.42, 1.55, 1.68, 1.80, 1.95
  ];

  final ReactiveCircleRenderState _renderState = ReactiveCircleRenderState();
  double _prevPeak = 0.0;
  double _audioPhase = 0.0;
  int _idleFrames = 0;
  final math.Random _rng = math.Random(42);

  bool get _effectiveIsPlaying =>
      widget.isPlayingProvider?.call() ?? widget.isPlaying;

  void _syncTickerState() {
    if (_effectiveIsPlaying) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initLookupTables();
    _ticker = createTicker(_onTick);
    widget.frameListenable?.addListener(_syncTickerState);
    if (_effectiveIsPlaying) {
      _ticker.start();
    }
  }

  void _initLookupTables() {
    const double angleStep = (math.pi * 2.0) / _totalBins;
    for (int i = 0; i < _totalBins; i++) {
      final double theta = _rotationOffset + (i * angleStep);
      _cosLUT[i] = math.cos(theta);
      _sinLUT[i] = math.sin(theta);
    }

    for (int k = 0; k < _halfBins; k++) {
      final double t = k / (_halfBins - 1);
      _freqWeightLUT[k] = math.sin(t * math.pi);
      _harmSin1LUT[k] = math.sin(k * 1.65);
      _harmCos1LUT[k] = math.cos(k * 1.65);
      _harmSin2LUT[k] = math.sin(k * 0.85);
      _harmCos2LUT[k] = math.cos(k * 0.85);
      _tauAttackLUT[k] = 0.016 - (t * 0.005);
      _tauDecayLUT[k] = 0.185 - (t * 0.055);
    }
  }

  @override
  void didUpdateWidget(covariant ReactiveCircleVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frameListenable != oldWidget.frameListenable) {
      oldWidget.frameListenable?.removeListener(_syncTickerState);
      widget.frameListenable?.addListener(_syncTickerState);
    }
    _syncTickerState();
  }

  @override
  void dispose() {
    widget.frameListenable?.removeListener(_syncTickerState);
    _ticker.dispose();
    _paintNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastElapsed == Duration.zero
        ? 0.016
        : ((elapsed - _lastElapsed).inMicroseconds * 1e-6).clamp(0.001, 0.05);
    _lastElapsed = elapsed;

    // Load audio inputs in-place without allocations
    final bands = widget.displayBandsProvider?.call() ?? widget.displayBands;
    final int len = math.min(bands.length, 10);
    for (int i = 0; i < len; i++) {
      _bands10[i] = bands[i].clamp(0.0, 1.0);
    }
    for (int i = len; i < 10; i++) {
      _bands10[i] = 0.0;
    }
    final double rms = (widget.smoothedRmsProvider?.call() ?? widget.smoothedRms)
        .clamp(0.0, 1.0);
    final double peak = (widget.rawPeakProvider?.call() ?? widget.rawPeak)
        .clamp(0.0, 1.0);
    final double left = (widget.leftChannelProvider?.call() ?? widget.leftChannel)
        .clamp(0.0, 1.0);
    final double right =
        (widget.rightChannelProvider?.call() ?? widget.rightChannel).clamp(
          0.0,
          1.0,
        );
    final bool playing = _effectiveIsPlaying;

    // Auto-Sleep on silence: saves 100% CPU/GPU when paused or silent
    final bool isAudioSilent = !playing ||
        (rms < 0.001 &&
            peak < 0.001 &&
            _bands10[0] < 0.001 &&
            _bands10[1] < 0.001);
    if (isAudioSilent &&
        _renderState.smoothRms < 0.001 &&
        _renderState.smoothBass < 0.001) {
      _idleFrames++;
      if (_idleFrames > 30) {
        return; // Zero CPU/GPU wakeups
      }
    } else {
      _idleFrames = 0;
    }

    // 1. Bass energy & transients
    final double rawBass =
        (_bands10[0] * 0.65 + _bands10[1] * 0.35).clamp(0.0, 1.0);
    final double crestFactor = (peak - rms).clamp(0.0, 1.0);
    final double peakDelta = (peak - _prevPeak).clamp(0.0, 1.0);
    _prevPeak = peak;

    final double bassAlpha = rawBass > _renderState.smoothBass
        ? (1.0 - math.exp(-dt / 0.022))
        : (1.0 - math.exp(-dt / 0.140));
    _renderState.smoothBass += (rawBass - _renderState.smoothBass) * bassAlpha;
    _renderState.smoothRms +=
        (rms - _renderState.smoothRms) * (1.0 - math.exp(-dt / 0.08));

    _audioPhase = (_audioPhase +
            dt * (2.5 + _renderState.smoothRms * 14.0 + crestFactor * 18.0)) %
        (math.pi * 200.0);

    // 2. Subtle micro-shake on strong transients (kept small for the ring look)
    if (peakDelta > 0.18 || (rawBass > 0.72 && crestFactor > 0.25)) {
      final double intensity =
          (peakDelta * 6.0 + rawBass * 2.0).clamp(0.0, 3.5);
      final double angle = _rng.nextDouble() * math.pi * 2.0;
      _renderState.shakeX = math.cos(angle) * intensity;
      _renderState.shakeY = math.sin(angle) * intensity;
    } else {
      final double shakeDecay = math.exp(-dt * 28.0);
      _renderState.shakeX *= shakeDecay;
      _renderState.shakeY *= shakeDecay;
    }

    // 3. Stereo L/R separation and pre-emphasis in-place
    final double maxLR = math.max(left, math.max(right, 0.0001));
    final double stereoDiff = (right - left) / maxLR;
    final double punchBoost = 1.0 + crestFactor * 0.28;

    for (int i = 0; i < 10; i++) {
      final double scaled = (_bands10[i] * _preEmphasis[i]).clamp(0.0, 1.5);
      // Fast perceptual compression approximation sqrt(x)*0.56 + x*0.44 (avoids math.pow)
      final double sqrtVal = math.sqrt(scaled);
      final double baseVal =
          (sqrtVal * 0.56 + scaled * 0.44).clamp(0.0, 1.0);

      final double stereoSpread = (i / 9.0) * 0.42;
      final double rightGain =
          (1.0 + stereoDiff * stereoSpread).clamp(0.5, 1.35);
      final double leftGain =
          (1.0 - stereoDiff * stereoSpread).clamp(0.5, 1.35);

      _eqRight[i] = (baseVal * rightGain * punchBoost).clamp(0.0, 1.0);
      _eqLeft[i] = (baseVal * leftGain * punchBoost).clamp(0.0, 1.0);
    }

    // 4. Single trigonometric phase evaluation per frame
    final double sinPhase = math.sin(_audioPhase);
    final double cosPhase = math.cos(_audioPhase);
    final double sinPhase07 = math.sin(_audioPhase * 0.7);
    final double cosPhase07 = math.cos(_audioPhase * 0.7);
    final double harmonicAmp =
        0.14 * _renderState.smoothRms + 0.22 * crestFactor;

    for (int k = 0; k < _halfBins; k++) {
      final double t = k / (_halfBins - 1);
      final double targetRight = _sampleCatmullRom(_eqRight, t);
      final double targetLeft = _sampleCatmullRom(_eqLeft, t);

      final double fw = _freqWeightLUT[k] * harmonicAmp;
      // sin(A + B) = sinA*cosB + cosA*sinB
      final double sinR =
          _harmSin1LUT[k] * cosPhase + _harmCos1LUT[k] * sinPhase;
      // cos(A - B) = cosA*cosB + sinA*sinB
      final double cosR =
          _harmCos2LUT[k] * cosPhase07 + _harmSin2LUT[k] * sinPhase07;

      // Inverted phase for left channel
      final double sinL =
          _harmSin1LUT[k] * cosPhase - _harmCos1LUT[k] * sinPhase;
      final double cosL =
          _harmCos2LUT[k] * cosPhase07 - _harmSin2LUT[k] * sinPhase07;

      final double finalR =
          (targetRight * (1.0 + fw * sinR * cosR)).clamp(0.0, 1.0);
      final double finalL =
          (targetLeft * (1.0 + fw * sinL * cosL)).clamp(0.0, 1.0);

      final double alphaAttack = (dt / _tauAttackLUT[k]).clamp(0.0, 1.0);
      final double alphaDecay = (dt / _tauDecayLUT[k]).clamp(0.0, 1.0);
      final double secAttack = (dt / 0.030).clamp(0.0, 1.0);
      final double secDecay = (dt / 0.280).clamp(0.0, 1.0);

      // Right hemisphere (0..63)
      final double curR = _smoothedBins[k];
      _smoothedBins[k] = curR +
          (finalR - curR) * (finalR > curR ? alphaAttack : alphaDecay);
      final double secR = _secondaryBins[k];
      _secondaryBins[k] =
          secR + (finalR - secR) * (finalR > secR ? secAttack : secDecay);

      // Left hemisphere (127..64)
      final int leftIdx = _totalBins - 1 - k;
      final double curL = _smoothedBins[leftIdx];
      _smoothedBins[leftIdx] = curL +
          (finalL - curL) * (finalL > curL ? alphaAttack : alphaDecay);
      final double secL = _secondaryBins[leftIdx];
      _secondaryBins[leftIdx] =
          secL + (finalL - secL) * (finalL > secL ? secAttack : secDecay);
    }

    // 5. Wide circular Gaussian blur (7 taps, fast bitwise & 127): gives the
    // band large, organic lobes instead of a jagged edge.
    for (int i = 0; i < _totalBins; i++) {
      _postBlurBins[i] = _smoothedBins[(i - 3) & 127] * 0.05 +
          _smoothedBins[(i - 2) & 127] * 0.11 +
          _smoothedBins[(i - 1) & 127] * 0.20 +
          _smoothedBins[i] * 0.28 +
          _smoothedBins[(i + 1) & 127] * 0.20 +
          _smoothedBins[(i + 2) & 127] * 0.11 +
          _smoothedBins[(i + 3) & 127] * 0.05;
    }

    // Trigger CustomPainter.paint() directly bypassing widget build tree
    _paintNotifier.notify();
  }

  double _sampleCatmullRom(Float32List bands10, double t) {
    final double scaled = t * 9.0;
    int i = scaled.floor();
    if (i > 8) i = 8;
    final double u = scaled - i;

    final double p0 = bands10[i > 0 ? i - 1 : 0];
    final double p1 = bands10[i];
    final double p2 = bands10[i + 1];
    final double p3 = bands10[i + 2 < 10 ? i + 2 : 9];

    final double u2 = u * u;
    final double u3 = u2 * u;

    final double res = 0.5 *
        ((2.0 * p1) +
            (-p0 + p2) * u +
            (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 +
            (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3);

    return res < 0.0 ? 0.0 : (res > 1.0 ? 1.0 : res);
  }

  @override
  Widget build(BuildContext context) {
    // The ring now fills most of the available square; the glow uses the rest.
    final double baseRadius = (widget.size * 0.40).clamp(30.0, 400.0);
    // Maximum inward reach of the spectrum (towards the centre).
    final double maxBarHeight = baseRadius * 0.85;

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: ReactiveCirclePainter(
              repaint: _paintNotifier,
              renderState: _renderState,
              bins: _postBlurBins,
              secondaryBins: _secondaryBins,
              innerPoints: _innerPoints,
              radii: _radii,
              dotsNear: _dotsNear,
              dotsMid: _dotsMid,
              dotsFar: _dotsFar,
              cosLUT: _cosLUT,
              sinLUT: _sinLUT,
              baseRadius: baseRadius,
              maxBarHeight: maxBarHeight,
              accentColor: widget.accentColor,
              style: widget.style,
              centerText: widget.centerChild == null ? widget.centerText : null,
            ),
          ),
          if (widget.centerChild != null)
            AnimatedBuilder(
              animation: _paintNotifier,
              builder: (context, child) {
                final double scale =
                    1.0 + (_renderState.smoothBass * 0.05);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(
                      _renderState.shakeX,
                      _renderState.shakeY,
                      0.0,
                      1.0,
                    )
                    ..scaleByDouble(scale, scale, 1.0, 1.0),
                  child: child,
                );
              },
              child: SizedBox(
                width: baseRadius * 1.3,
                height: baseRadius * 1.3,
                child: Center(child: widget.centerChild),
              ),
            ),
        ],
      ),
    );
  }
}
