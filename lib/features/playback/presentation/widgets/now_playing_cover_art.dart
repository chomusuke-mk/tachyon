import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/wave_visualizer.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Self-contained, beat-reactive artwork component for the Now Playing view.
///
/// Encapsulates its own state and dependencies via [context.watch], safely
/// detaching itself from its parent container. Renders a bass-isolated drum-like
/// pulse animation (+8% scale on bass only with inertia damping) and draws a
/// continuous audio wave positioned cleanly behind/under the cover art without
/// causing layout flex overflow.
class NowPlayingCoverArt extends StatefulWidget {
  const NowPlayingCoverArt({super.key});

  @override
  State<NowPlayingCoverArt> createState() => _NowPlayingCoverArtState();
}

class _NowPlayingCoverArtState extends State<NowPlayingCoverArt> {
  static const double _cornerRadius = 20.0;
  static const double _visualizerHeight = 56.0; // Duplicated wave height

  // Inertia and damping tracking arrays:
  // Smooth Exponential Moving Average filters to eliminate high-frequency jitter/trembling
  final List<double> _smoothedBands = List<double>.filled(10, 0.0);
  double _smoothedBass = 0.0;
  double _smoothedRms = 0.0;

  String? _lastThumbnailHash;
  Color? _resolvedColor;

  @override
  void initState() {
    super.initState();
    // Enable hardware visualizer DSP on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlaybackController>().setVisualizerEnabled(true);
      }
    });
  }

  @override
  void deactivate() {
    context.read<PlaybackController>().setVisualizerEnabled(false);
    super.deactivate();
  }

  void _resolveThumbnailColor(String? hash, ThemeData theme) {
    if (hash == null || hash.isEmpty) {
      if (_resolvedColor != null) {
        _resolvedColor = null;
        _lastThumbnailHash = null;
      }
      return;
    }
    if (hash == _lastThumbnailHash) return;
    _lastThumbnailHash = hash;

    MiniPlayerColorResolver.resolveColor(
      thumbnailHash: hash,
      theme: theme,
    ).then((color) {
      if (mounted && _lastThumbnailHash == hash && _resolvedColor != color) {
        setState(() {
          _resolvedColor = color;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final currentTrack = playback.currentTrack;
    if (currentTrack == null) {
      return const SizedBox.shrink();
    }

    final filePath = currentTrack.filePath;
    final thumbnailHash =
        currentTrack.thumbnailHash ?? currentTrack.album?.thumbnailHash;
    final isPlaying = playback.isPlaying;
    final theme = Theme.of(context);

    _resolveThumbnailColor(thumbnailHash, theme);

    // Compute solid color matching miniplayer background
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final waveColor =
        _resolvedColor ??
        (isOled
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerHigh);

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSide = math.min(constraints.maxWidth, constraints.maxHeight);
          final size = maxSide.isFinite && maxSide > 0 ? maxSide * 0.84 : 280.0;

          return ValueListenableBuilder<List<double>>(
            valueListenable: playback.visualizerListenable,
            builder: (context, vis, cachedHeroChild) {
              // Raw hardware snapshot: [0] rms, [1] peak, [2] left, [3] right, [4..13] bands
              final double rawRms = (isPlaying && vis.isNotEmpty)
                  ? vis[0]
                  : 0.0;
              final List<double> rawBands = (isPlaying && vis.length >= 14)
                  ? vis.sublist(4)
                  : List.filled(10, 0.0);

              // 1. Audio Ballistics with Fluid Inertia for Frequency Bands:
              // Attack and decay with damping to eliminate high-frequency buzzing/jitter
              final displayBands = List<double>.filled(10, 0.0);
              for (int i = 0; i < 10; i++) {
                final target = isPlaying ? rawBands[i].clamp(0.0, 1.0) : 0.0;
                if (target > _smoothedBands[i]) {
                  _smoothedBands[i] += (target - _smoothedBands[i]) * 0.38;
                } else {
                  _smoothedBands[i] += (target - _smoothedBands[i]) * 0.15;
                }
                if (_smoothedBands[i] < 0.01) _smoothedBands[i] = 0.0;
                displayBands[i] = _smoothedBands[i];
              }

              // 2. Audio Ballistics with Inertia for Bass ONLY (Sub-bass & Kick drum: bands 0 and 1)
              // Noise gate and momentum smoothing to eliminate trembling from voices & ambient noise!
              final rawBass = (rawBands.length >= 2)
                  ? math.max(rawBands[0], rawBands[1])
                  : (rawBands.isNotEmpty ? rawBands[0] : 0.0);

              final targetBass = isPlaying && rawBass > 0.16
                  ? ((rawBass - 0.16) / (1.0 - 0.16)).clamp(0.0, 1.0)
                  : 0.0;

              if (targetBass > _smoothedBass) {
                // Smooth attack with physical mass (reaches peak over ~100ms instead of instantaneous twitch)
                _smoothedBass += (targetBass - _smoothedBass) * 0.35;
              } else {
                // Smooth elastic release
                _smoothedBass += (targetBass - _smoothedBass) * 0.14;
              }
              if (_smoothedBass < 0.01) _smoothedBass = 0.0;

              // 3. Ambient RMS smoothing
              _smoothedRms = (_smoothedRms * 0.85) + (rawRms * 0.15);

              // 4. Bass-reactive scale: exactly 8% maximum bounce with inertia
              final scale = 1.0 + (_smoothedBass * 0.08);

              // Dynamic shadow density reacting to sustained energy
              final shadowBlur = 14.0 + (_smoothedRms * 32.0);
              final spread = 2.0 + (_smoothedRms * 8.0);
              final shadowAlpha = (0.2 + (_smoothedRms * 0.35)).clamp(
                0.0,
                0.65,
              );

              return Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Continuous Wave Visualizer:
                      // Positioned directly at the bottom edge of the card, projecting downwards.
                      // Stack paint order places this behind the card. In NowPlayingScreen,
                      // subsequent flex children (song title/controls) paint on top of this overflow!
                      Positioned(
                        top: size - 1.0,
                        left: 0,
                        width: size,
                        height: _visualizerHeight,
                        child: CustomPaint(
                          size: Size(size, _visualizerHeight),
                          painter: WaveVisualizerPainter(
                            bands: displayBands,
                            color: waveColor,
                            cornerRadius: _cornerRadius,
                          ),
                        ),
                      ),

                      // 2. The Album Art container (fully rounded 4 corners, sits on top of wave dock)
                      Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_cornerRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowAlpha,
                              ),
                              blurRadius: shadowBlur,
                              spreadRadius: spread,
                              offset: Offset(0, 14.0 + (_smoothedBass * 10.0)),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(_cornerRadius),
                          child: cachedHeroChild,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Hero(
              tag: 'now_playing_art_$filePath',
              child: AlbumArtImage(
                thumbnailHash: thumbnailHash,
                quality: ThumbnailQuality.high,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}
