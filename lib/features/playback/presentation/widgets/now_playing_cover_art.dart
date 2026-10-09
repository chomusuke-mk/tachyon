import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/playback/presentation/widgets/wave_visualizer.dart';

/// Self-contained, beat-reactive artwork component for the Now Playing view.
///
/// Encapsulates its own state and dependencies via [context.watch], safely
/// detaching itself from its parent container. Renders a prominent bass-reactive
/// animation that pumps and scales in sync with the current audio energy,
/// and draws a continuous audio wave directly attached beneath the cover art.
class NowPlayingCoverArt extends StatefulWidget {
  const NowPlayingCoverArt({super.key});

  @override
  State<NowPlayingCoverArt> createState() => _NowPlayingCoverArtState();
}

class _NowPlayingCoverArtState extends State<NowPlayingCoverArt> {
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

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSide = math.min(constraints.maxWidth, constraints.maxHeight - 90.0);
          final size = maxSide.isFinite && maxSide > 0 ? maxSide * 0.85 : 280.0;

          return ValueListenableBuilder<List<double>>(
            valueListenable: playback.visualizerListenable,
            builder: (context, vis, cachedHeroChild) {
              // vis: [0] rms, [1] peak, [2] left, [3] right, [4..13] bands
              final double rms = vis.isNotEmpty ? vis[0] : 0.0;
              final List<double> bands = vis.length >= 14 ? vis.sublist(4) : List.filled(10, 0.0);

              // Audio reactivity - purely scale bounce on bass (like pressing a drum)
              // No movement or floating when quiet.
              final scale = 1.0 + (rms * 0.15);
              
              // Shadow logic based on energy
              final shadowBlur = 12.0 + (rms * 32.0);
              final spread = 2.0 + (rms * 8.0);
              final shadowAlpha = (0.2 + (rms * 0.3)).clamp(0.0, 0.6);

              final waveColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.8);

              return Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The Cover Art (Square)
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        // Slightly rounded top corners, sharp bottom corners so the wave attaches perfectly
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16.0),
                          topRight: Radius.circular(16.0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha),
                            blurRadius: shadowBlur,
                            spreadRadius: spread,
                            offset: Offset(0, 16.0 + (rms * 12.0)),
                          ),
                        ],
                      ),
                      // Use a ClipRRect matching the container
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16.0),
                          topRight: Radius.circular(16.0),
                        ),
                        child: cachedHeroChild,
                      ),
                    ),
                    // The continuous wave visualizer directly beneath and attached to the cover
                    CustomPaint(
                      size: Size(size, 90.0), // The maximum height of the wave amplitude pointing down
                      painter: WaveVisualizerPainter(
                        bands: bands,
                        color: waveColor,
                      ),
                    ),
                  ],
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
