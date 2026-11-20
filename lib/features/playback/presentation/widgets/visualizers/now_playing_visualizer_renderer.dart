import 'package:flutter/material.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_mode.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/reactive_circle_visualizer.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/spectrum_bars_visualizer.dart';
import 'package:tachyon/features/playback/presentation/widgets/wave_visualizer.dart';

/// Extensible contract for rendering different Now Playing visualizer modes.
abstract class NowPlayingVisualizerRenderer {
  const NowPlayingVisualizerRenderer();

  /// Builds the visual content within the given dimensions.
  Widget render({
    required BuildContext context,
    required double size,
    required double cornerRadius,
    required Widget coverArt,
    required List<double> displayBands,
    required double smoothedBass,
    required double smoothedRms,
    required Color waveColor,
    required bool isPlaying,
    Color? trackColor,
    double rawPeak = 0.0,
    double leftChannel = 0.0,
    double rightChannel = 0.0,
    Listenable? frameListenable,
    List<double> Function()? bandsProvider,
    double Function()? smoothedRmsProvider,
    double Function()? rawPeakProvider,
    double Function()? leftChannelProvider,
    double Function()? rightChannelProvider,
    bool Function()? isPlayingProvider,
  });

  /// Scale multiplier applied to the artwork container (e.g. bass pulse).
  double computeScale(double smoothedBass) => 1.0;
}

/// Mode 1: Off — Pure album art without visualizer waves or bass pulsation.
class OffVisualizerRenderer extends NowPlayingVisualizerRenderer {
  const OffVisualizerRenderer();

  @override
  Widget render({
    required BuildContext context,
    required double size,
    required double cornerRadius,
    required Widget coverArt,
    required List<double> displayBands,
    required double smoothedBass,
    required double smoothedRms,
    required Color waveColor,
    required bool isPlaying,
    Color? trackColor,
    double rawPeak = 0.0,
    double leftChannel = 0.0,
    double rightChannel = 0.0,
    Listenable? frameListenable,
    List<double> Function()? bandsProvider,
    double Function()? smoothedRmsProvider,
    double Function()? rawPeakProvider,
    double Function()? leftChannelProvider,
    double Function()? rightChannelProvider,
    bool Function()? isPlayingProvider,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: coverArt,
      ),
    );
  }

  @override
  double computeScale(double smoothedBass) => 1.0;
}

/// Mode 2: Wave — Album art with continuous reactive wave docked underneath
/// and beat-isolated bass pulsation (+8% max bounce).
class WaveVisualizerRenderer extends NowPlayingVisualizerRenderer {
  static const double visualizerHeight = 56.0;

  const WaveVisualizerRenderer();

  @override
  Widget render({
    required BuildContext context,
    required double size,
    required double cornerRadius,
    required Widget coverArt,
    required List<double> displayBands,
    required double smoothedBass,
    required double smoothedRms,
    required Color waveColor,
    required bool isPlaying,
    Color? trackColor,
    double rawPeak = 0.0,
    double leftChannel = 0.0,
    double rightChannel = 0.0,
    Listenable? frameListenable,
    List<double> Function()? bandsProvider,
    double Function()? smoothedRmsProvider,
    double Function()? rawPeakProvider,
    double Function()? leftChannelProvider,
    double Function()? rightChannelProvider,
    bool Function()? isPlayingProvider,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Continuous Wave Visualizer docked underneath the album art
          Positioned(
            top: size - 1.0,
            left: 0,
            width: size,
            height: visualizerHeight,
            child: CustomPaint(
              size: Size(size, visualizerHeight),
              painter: WaveVisualizerPainter(
                repaint: frameListenable,
                bands: displayBands,
                bandsProvider: bandsProvider,
                color: waveColor,
                cornerRadius: cornerRadius,
              ),
            ),
          ),

          // 2. The Album Art container
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cornerRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cornerRadius),
              child: coverArt,
            ),
          ),
        ],
      ),
    );
  }

  @override
  double computeScale(double smoothedBass) => 1.0 + (smoothedBass * 0.08);
}

/// Mode 3: Bars — Studio 10-band spectrum analyzer visualizer from miniaudio_player,
/// replacing the cover art completely.
class BarsVisualizerRenderer extends NowPlayingVisualizerRenderer {
  const BarsVisualizerRenderer();

  @override
  Widget render({
    required BuildContext context,
    required double size,
    required double cornerRadius,
    required Widget coverArt,
    required List<double> displayBands,
    required double smoothedBass,
    required double smoothedRms,
    required Color waveColor,
    required bool isPlaying,
    Color? trackColor,
    double rawPeak = 0.0,
    double leftChannel = 0.0,
    double rightChannel = 0.0,
    Listenable? frameListenable,
    List<double> Function()? bandsProvider,
    double Function()? smoothedRmsProvider,
    double Function()? rawPeakProvider,
    double Function()? leftChannelProvider,
    double Function()? rightChannelProvider,
    bool Function()? isPlayingProvider,
  }) {
    final accentColor = resolveReactiveCircleColor(
      trackColor: trackColor,
      theme: Theme.of(context),
    );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: SpectrumBarsPainter(
          repaint: frameListenable,
          magnitudes: displayBands,
          magnitudesProvider: bandsProvider,
          isActive: isPlaying,
          isActiveProvider: isPlayingProvider,
          cornerRadius: cornerRadius,
          accentColor: accentColor,
        ),
      ),
    );
  }

  @override
  double computeScale(double smoothedBass) => 1.0 + (smoothedBass * 0.03);
}

/// Mode 4: Circle — Reactive circular audio visualizer with pulsing neon ring
/// and 3D undulating particle wave lattice ribbons (inspired by the iconic NCS visualizer style).
class ReactiveCircleVisualizerRenderer extends NowPlayingVisualizerRenderer {
  const ReactiveCircleVisualizerRenderer();

  @override
  Widget render({
    required BuildContext context,
    required double size,
    required double cornerRadius,
    required Widget coverArt,
    required List<double> displayBands,
    required double smoothedBass,
    required double smoothedRms,
    required Color waveColor,
    required bool isPlaying,
    Color? trackColor,
    double rawPeak = 0.0,
    double leftChannel = 0.0,
    double rightChannel = 0.0,
    Listenable? frameListenable,
    List<double> Function()? bandsProvider,
    double Function()? smoothedRmsProvider,
    double Function()? rawPeakProvider,
    double Function()? leftChannelProvider,
    double Function()? rightChannelProvider,
    bool Function()? isPlayingProvider,
  }) {
    final accentColor = resolveReactiveCircleColor(
      trackColor: trackColor,
      theme: Theme.of(context),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ReactiveCircleVisualizerWidget(
        size: size,
        cornerRadius: cornerRadius,
        displayBands: displayBands,
        smoothedBass: smoothedBass,
        smoothedRms: smoothedRms,
        rawPeak: rawPeak,
        leftChannel: leftChannel,
        rightChannel: rightChannel,
        accentColor: accentColor,
        isPlaying: isPlaying,
        frameListenable: frameListenable,
        displayBandsProvider: bandsProvider,
        smoothedRmsProvider: smoothedRmsProvider,
        rawPeakProvider: rawPeakProvider,
        leftChannelProvider: leftChannelProvider,
        rightChannelProvider: rightChannelProvider,
        isPlayingProvider: isPlayingProvider,
      ),
    );
  }

  @override
  double computeScale(double smoothedBass) => 1.0;
}

/// Central registry mapping each [NowPlayingVisualizerMode] to its renderer.
/// Easily extensible for future modes (circular, vu meter, particles, etc.).
class NowPlayingVisualizerFactory {
  static final Map<NowPlayingVisualizerMode, NowPlayingVisualizerRenderer>
      _renderers = {
    NowPlayingVisualizerMode.off: const OffVisualizerRenderer(),
    NowPlayingVisualizerMode.wave: const WaveVisualizerRenderer(),
    NowPlayingVisualizerMode.bars: const BarsVisualizerRenderer(),
    NowPlayingVisualizerMode.circle: const ReactiveCircleVisualizerRenderer(),
  };

  static NowPlayingVisualizerRenderer getRenderer(NowPlayingVisualizerMode mode) {
    return _renderers[mode] ?? const WaveVisualizerRenderer();
  }
}
