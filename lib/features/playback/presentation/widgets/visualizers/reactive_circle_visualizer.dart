import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/reactive_circle_painter.dart';

export 'package:tachyon/features/playback/presentation/widgets/visualizers/reactive_circle_painter.dart';

/// Lightweight notifier triggering only CustomPainter.paint() without Widget.build() rebuilds.
class _FrameTickNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
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
  /// Width and height of the square visualizer canvas in logical pixels.
  final double size;

  /// Corner radius value accepted for layout consistency across renderers.
  final double cornerRadius;

  /// Fallback 10-band spectrum magnitudes (`0.0` to `1.0`) when [displayBandsProvider] is `null`.
  final List<double> displayBands;

  /// Fallback smoothed bass energy (`0.0` to `1.0`).
  final double smoothedBass;

  /// Fallback smoothed RMS amplitude (`0.0` to `1.0`) when [smoothedRmsProvider] is `null`.
  final double smoothedRms;

  /// Fallback instantaneous peak amplitude (`0.0` to `1.0`) when [rawPeakProvider] is `null`.
  final double rawPeak;

  /// Fallback left-channel audio level (`0.0` to `1.0`) when [leftChannelProvider] is `null`.
  final double leftChannel;

  /// Fallback right-channel audio level (`0.0` to `1.0`) when [rightChannelProvider] is `null`.
  final double rightChannel;

  /// Primary neon accent color for the ring and spectrum dot lattice.
  final Color accentColor;

  /// Whether audio playback is active when [isPlayingProvider] is `null`.
  final bool isPlaying;

  /// Optional zero-rebuild callback returning live 10-band spectrum magnitudes.
  final List<double> Function()? displayBandsProvider;

  /// Optional zero-rebuild callback returning live smoothed RMS amplitude.
  final double Function()? smoothedRmsProvider;

  /// Optional zero-rebuild callback returning live instantaneous peak amplitude.
  final double Function()? rawPeakProvider;

  /// Optional zero-rebuild callback returning the live left-channel level.
  final double Function()? leftChannelProvider;

  /// Optional zero-rebuild callback returning the live right-channel level.
  final double Function()? rightChannelProvider;

  /// Optional zero-rebuild callback returning whether playback is currently active.
  final bool Function()? isPlayingProvider;

  /// Listenable synchronized with playback activity to wake and sleep the ticker.
  final Listenable? frameListenable;

  /// Contour rendering style applied by [ReactiveCirclePainter].
  final NcsSpectrumStyle style;

  /// Optional widget centered inside the ring with reactive bass pulse and micro-shake.
  final Widget? centerChild;

  /// Optional text painted in the center when [centerChild] is `null`.
  final String? centerText;

  /// Creates a [ReactiveCircleVisualizerWidget].
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

  static const int _halfBins = kReactiveCircleRays ~/ 2;
  static const int _totalBins = kReactiveCircleRays;

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
  final Float32List _dotsNear = Float32List(
    _totalBins * kReactiveCircleLayersPerGroup * 2,
  );
  final Float32List _dotsMid = Float32List(
    _totalBins * kReactiveCircleLayersPerGroup * 2,
  );
  final Float32List _dotsFar = Float32List(
    _totalBins * kReactiveCircleLayersPerGroup * 2,
  );

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
