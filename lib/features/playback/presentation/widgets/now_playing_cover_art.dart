import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_mode.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_renderer.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Self-contained, beat-reactive artwork and multi-mode visualizer component
/// for the Now Playing view.
///
/// Supports 4 distinct visual display modes (extensible via [NowPlayingVisualizerRenderer]):
/// 1. [NowPlayingVisualizerMode.off]: Pure album art cover without visualizer or pulsation.
/// 2. [NowPlayingVisualizerMode.wave]: Cover art with continuous reactive wave underneath and bass pulse.
/// 3. [NowPlayingVisualizerMode.bars]: Studio 10-band spectrum analyzer from miniaudio_player,
///    replacing the cover art.
/// 4. [NowPlayingVisualizerMode.circle]: Reactive circular audio visualizer
///    with pulsing neon ring and 3D undulating particle wave lattice ribbons
///    (inspired by the iconic NCS visualizer style).
///
/// Tapping on the artwork seamlessly cycles through the modes with HUD pill confirmation
/// and persists the user preference across app restarts. Horizontal drag gestures
/// handle next/previous track navigation.
class NowPlayingCoverArt extends StatefulWidget {
  const NowPlayingCoverArt({super.key});

  @override
  State<NowPlayingCoverArt> createState() => _NowPlayingCoverArtState();
}

class _NowPlayingCoverArtState extends State<NowPlayingCoverArt>
    with TickerProviderStateMixin {
  static const double _cornerRadius = 20.0;

  static const List<double> _zeroBands = <double>[
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
  ];

  // Inertia and damping tracking arrays:
  // Smooth Exponential Moving Average filters to eliminate high-frequency jitter/trembling
  final List<double> _smoothedBands = List<double>.filled(10, 0.0);
  double _smoothedBass = 0.0;
  double _smoothedRms = 0.0;

  String? _lastThumbnailHash;
  Color? _resolvedColor;

  double _dragOffset = 0.0;
  late final AnimationController _resetController;
  Animation<double>? _resetAnimation;

  late final AnimationController _hudController;
  Timer? _hudTimer;
  NowPlayingVisualizerMode _mode = NowPlayingVisualizerMode.wave;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _dragOffset = _resetAnimation?.value ?? 0.0;
        });
      });

    _hudController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Read persisted mode and enable hardware visualizer DSP on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<SettingsRepository?>(context, listen: false) ??
            Provider.of<SettingsController?>(context, listen: false)?.repository;
        if (repo != null) {
          setState(() {
            _mode = repo.getNowPlayingVisualizerMode();
          });
        }
        context.read<PlaybackController>().setVisualizerEnabled(true);
      }
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _hudController.dispose();
    _resetController.dispose();
    super.dispose();
  }

  void _cycleVisualizerMode() {
    setState(() {
      _mode = _mode.next;
    });

    final repo = Provider.of<SettingsRepository?>(context, listen: false) ??
        Provider.of<SettingsController?>(context, listen: false)?.repository;
    repo?.setNowPlayingVisualizerMode(_mode);

    // Trigger HUD pill overlay
    _hudTimer?.cancel();
    _hudController.forward();
    _hudTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        _hudController.reverse();
      }
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_resetController.isAnimating) {
      _resetController.stop();
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0.0;
    });
  }

  void _onHorizontalDragEnd(
    DragEndDetails details,
    PlaybackController playback,
  ) {
    final velocity = details.primaryVelocity ?? 0.0;
    const threshold = 40.0;
    const velocityThreshold = 250.0;

    if (_dragOffset < -threshold || velocity < -velocityThreshold) {
      // Swiped forward (finger moved right to left) -> next track
      if (playback.hasNext) {
        playback.next();
      }
    } else if (_dragOffset > threshold || velocity > velocityThreshold) {
      // Swiped backward (finger moved left to right) -> previous track
      if (playback.hasPrevious) {
        playback.previous();
      } else {
        playback.seek(Duration.zero);
      }
    }

    _animateReset();
  }

  void _onHorizontalDragCancel() {
    _animateReset();
  }

  void _animateReset() {
    _resetAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _resetController,
        curve: Curves.easeOutCubic,
      ),
    );
    _resetController.forward(from: 0.0);
  }

  @override
  void deactivate() {
    final controller = context.read<PlaybackController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        controller.setVisualizerEnabled(false);
      }
    });
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

    ArtworkColorResolver.resolveColor(
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

  Widget _buildHudBadge(AppStringKey strings) {
    final IconData icon;
    final String label;

    switch (_mode) {
      case NowPlayingVisualizerMode.off:
        icon = Icons.image_outlined;
        label = strings.npVisualizerOff;
      case NowPlayingVisualizerMode.wave:
        icon = Icons.waves_rounded;
        label = strings.npVisualizerWave;
      case NowPlayingVisualizerMode.bars:
        icon = Icons.bar_chart_rounded;
        label = strings.npVisualizerBars;
      case NowPlayingVisualizerMode.circle:
        icon = Icons.blur_circular_rounded;
        label = strings.npVisualizerCircle;
    }

    return AnimatedBuilder(
      animation: _hudController,
      builder: (context, _) {
        if (_hudController.value <= 0.01) return const SizedBox.shrink();
        return Positioned(
          top: 14.0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: _hudController.value,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.0,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final currentPlayable = playback.currentPlayable;
    if (currentPlayable == null) {
      return const SizedBox.shrink();
    }

    final filePath = currentPlayable.filePath;
    final thumbnailHash = currentPlayable.thumbnailHash;
    final isPlaying = playback.isPlaying;
    final theme = Theme.of(context);
    final strings = context.watch<LocaleController>().localeStrings;

    _resolveThumbnailColor(thumbnailHash, theme);

    // Compute solid color matching miniplayer background
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final waveColor = _resolvedColor ??
        (isOled
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerHigh);

    final renderer = NowPlayingVisualizerFactory.getRenderer(_mode);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cycleVisualizerMode,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: (details) => _onHorizontalDragEnd(details, playback),
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxSide =
                math.min(constraints.maxWidth, constraints.maxHeight);
            final size =
                maxSide.isFinite && maxSide > 0 ? maxSide * 0.84 : 280.0;

            return ValueListenableBuilder<List<double>>(
              valueListenable: playback.visualizerListenable,
              builder: (context, vis, cachedHeroChild) {
                // Raw hardware snapshot: [0] rms, [1] peak, [2] left, [3] right, [4..13] bands
                final hasLiveBands = isPlaying && vis.length >= 14;
                final double rawRms =
                    (isPlaying && vis.isNotEmpty) ? vis[0] : 0.0;

                // 1. Audio Ballistics with Fluid Inertia for Frequency Bands:
                var hasNonZeroBand = false;
                for (int i = 0; i < 10; i++) {
                  final target =
                      hasLiveBands ? vis[4 + i].clamp(0.0, 1.0) : 0.0;
                  if (target > _smoothedBands[i]) {
                    _smoothedBands[i] += (target - _smoothedBands[i]) * 0.38;
                  } else {
                    _smoothedBands[i] += (target - _smoothedBands[i]) * 0.15;
                  }
                  if (_smoothedBands[i] < 0.01) {
                    _smoothedBands[i] = 0.0;
                  } else {
                    hasNonZeroBand = true;
                  }
                }
                final List<double> displayBands = hasNonZeroBand
                    ? List<double>.of(_smoothedBands, growable: false)
                    : _zeroBands;

                // 2. Audio Ballistics with Inertia for Bass ONLY (Sub-bass & Kick drum: bands 0 and 1)
                final rawBass =
                    hasLiveBands ? math.max(vis[4], vis[5]) : 0.0;

                final targetBass = isPlaying && rawBass > 0.16
                    ? ((rawBass - 0.16) / (1.0 - 0.16)).clamp(0.0, 1.0)
                    : 0.0;

                if (targetBass > _smoothedBass) {
                  _smoothedBass += (targetBass - _smoothedBass) * 0.35;
                } else {
                  _smoothedBass += (targetBass - _smoothedBass) * 0.14;
                }
                if (_smoothedBass < 0.01) _smoothedBass = 0.0;

                // 3. Ambient RMS smoothing
                _smoothedRms = (_smoothedRms * 0.85) + (rawRms * 0.15);

                // 4. Delegate visual presentation to selected strategy renderer
                final scale = renderer.computeScale(_smoothedBass);

                Widget cardStack = SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      renderer.render(
                        context: context,
                        size: size,
                        cornerRadius: _cornerRadius,
                        coverArt: cachedHeroChild!,
                        displayBands: displayBands,
                        smoothedBass: _smoothedBass,
                        smoothedRms: _smoothedRms,
                        waveColor: waveColor,
                        trackColor: _resolvedColor,
                        isPlaying: isPlaying,
                      ),
                      _buildHudBadge(strings),
                    ],
                  ),
                );

                if (scale != 1.0) {
                  cardStack = Transform.scale(scale: scale, child: cardStack);
                }
                if (_dragOffset != 0.0) {
                  cardStack = Transform.translate(
                    offset: Offset(_dragOffset.clamp(-120.0, 120.0), 0.0),
                    child: cardStack,
                  );
                }
                return cardStack;
              },
              child: Hero(
                tag: 'now_playing_art_$filePath',
                child: (currentPlayable is RadioStation &&
                        currentPlayable.faviconUrl?.isNotEmpty == true)
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: CachedNetworkImage(
                            imageUrl: currentPlayable.faviconUrl!,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => Icon(
                              Icons.radio_rounded,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            errorWidget: (context, url, error) => Icon(
                              Icons.radio_rounded,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : AlbumArtImage(
                        thumbnailHash: thumbnailHash,
                        quality: ThumbnailQuality.high,
                        fit: BoxFit.cover,
                        fallback: Icon(
                          currentPlayable.isStream
                              ? Icons.radio_rounded
                              : Icons.album_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
