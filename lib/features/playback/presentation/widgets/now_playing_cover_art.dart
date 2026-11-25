import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:provider/provider.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_mode.dart';
import 'package:tachyon/features/playback/presentation/widgets/visualizers/now_playing_visualizer_renderer.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

class _VisualizerBallistics extends ChangeNotifier {
  final Float32List bands = Float32List(10);
  double smoothedBass = 0.0;
  double smoothedRms = 0.0;
  double rawPeak = 0.0;
  double leftChannel = 0.0;
  double rightChannel = 0.0;
  bool isPlaying = false;
  bool enabled = true;

  void reset() {
    bands.fillRange(0, 10, 0.0);
    smoothedBass = 0.0;
    smoothedRms = 0.0;
    rawPeak = 0.0;
    leftChannel = 0.0;
    rightChannel = 0.0;
    notifyListeners();
  }

  void updateFromVisualizer(ma.VisualizerData vis) {
    if (!enabled) return;
    final active = isPlaying;
    final rawRms = active ? vis.rms : 0.0;
    rawPeak = active ? vis.peak : 0.0;
    leftChannel = active ? vis.left : 0.0;
    rightChannel = active ? vis.right : 0.0;

    final visBands = vis.bands;
    final hasLiveBands = active && visBands.length >= 10;

    for (int i = 0; i < 10; i++) {
      final target = hasLiveBands ? visBands[i].clamp(0.0, 1.0) : 0.0;
      final cur = bands[i];
      var next = cur + (target - cur) * (target > cur ? 0.38 : 0.15);
      if (next < 0.01) next = 0.0;
      bands[i] = next;
    }

    final rawBass = hasLiveBands ? math.max(visBands[0], visBands[1]) : 0.0;
    final targetBass = active && rawBass > 0.16
        ? ((rawBass - 0.16) / (1.0 - 0.16)).clamp(0.0, 1.0)
        : 0.0;
    smoothedBass +=
        (targetBass - smoothedBass) * (targetBass > smoothedBass ? 0.35 : 0.14);
    if (smoothedBass < 0.01) smoothedBass = 0.0;

    smoothedRms = (smoothedRms * 0.85) + (rawRms * 0.15);
    notifyListeners();
  }
}

/// Self-contained, beat-reactive artwork and multi-mode visualizer component
/// for the Now Playing view.
class NowPlayingCoverArt extends StatefulWidget {
  /// Creates a [NowPlayingCoverArt].
  const NowPlayingCoverArt({super.key});

  @override
  State<NowPlayingCoverArt> createState() => _NowPlayingCoverArtState();
}

class _NowPlayingCoverArtState extends State<NowPlayingCoverArt>
    with TickerProviderStateMixin {
  static const double _cornerRadius = 20.0;

  final _VisualizerBallistics _ballistics = _VisualizerBallistics();
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);

  PlaybackController? _playback;
  ValueListenable<ma.VisualizerData>? _visListenable;

  String? _lastArtworkUri;
  Color? _resolvedColor;

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
        _dragOffsetNotifier.value = _resetAnimation?.value ?? 0.0;
      });

    _hudController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repo = Provider.of<SettingsRepository?>(context, listen: false) ??
          Provider.of<SettingsController?>(context, listen: false)?.repository;
      if (repo != null) {
        final savedMode = repo.getNowPlayingVisualizerMode();
        if (savedMode != _mode) {
          setState(() {
            _mode = savedMode;
          });
        }
      }
      _bindPlaybackController();
    });
  }

  void _bindPlaybackController() {
    final playback = _playback ?? context.read<PlaybackController>();
    _playback = playback;
    _ballistics.enabled = _mode != NowPlayingVisualizerMode.off;
    _ballistics.isPlaying = playback.isPlaying;

    if (_visListenable == null) {
      _visListenable = playback.visualizerDataListenable;
      _visListenable!.addListener(_onVisualizerTick);
      playback.transportListenable.addListener(_onTransportChanged);
    }

    playback.setVisualizerEnabled(_mode != NowPlayingVisualizerMode.off);
  }

  void _onTransportChanged() {
    final p = _playback;
    if (p == null) return;
    final playing = p.isPlaying;
    if (_ballistics.isPlaying != playing) {
      _ballistics.isPlaying = playing;
      if (!playing) {
        _ballistics.reset();
      } else {
        _ballistics.updateFromVisualizer(_visListenable!.value);
      }
    }
  }

  void _onVisualizerTick() {
    final vis = _visListenable?.value;
    if (vis == null) return;
    _ballistics.updateFromVisualizer(vis);
  }

  @override
  void dispose() {
    _visListenable?.removeListener(_onVisualizerTick);
    _playback?.transportListenable.removeListener(_onTransportChanged);
    _hudTimer?.cancel();
    _hudController.dispose();
    _resetController.dispose();
    _dragOffsetNotifier.dispose();
    _ballistics.dispose();
    super.dispose();
  }

  void _cycleVisualizerMode() {
    final nextMode = _mode.next;
    final visEnabled = nextMode != NowPlayingVisualizerMode.off;
    setState(() {
      _mode = nextMode;
    });
    _ballistics.enabled = visEnabled;
    if (!visEnabled) {
      _ballistics.reset();
    }
    _playback?.setVisualizerEnabled(visEnabled);

    final repo = Provider.of<SettingsRepository?>(context, listen: false) ??
        Provider.of<SettingsController?>(context, listen: false)?.repository;
    repo?.setNowPlayingVisualizerMode(nextMode);

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
    _dragOffsetNotifier.value += details.primaryDelta ?? 0.0;
  }

  void _onHorizontalDragEnd(
    DragEndDetails details,
    PlaybackController playback,
  ) {
    final velocity = details.primaryVelocity ?? 0.0;
    const threshold = 40.0;
    const velocityThreshold = 250.0;
    final offset = _dragOffsetNotifier.value;

    if (offset < -threshold || velocity < -velocityThreshold) {
      // Swiped forward (finger moved right to left) -> next track
      if (playback.hasNext) {
        playback.next();
      }
    } else if (offset > threshold || velocity > velocityThreshold) {
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
      begin: _dragOffsetNotifier.value,
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
    final controller = _playback ?? context.read<PlaybackController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        controller.setVisualizerEnabled(false);
      }
    });
    super.deactivate();
  }

  void _resolveArtworkColor(String? artworkUri, ThemeData theme) {
    if (artworkUri == null || artworkUri.isEmpty) {
      if (_resolvedColor != null) {
        _resolvedColor = null;
        _lastArtworkUri = null;
      }
      return;
    }
    if (artworkUri == _lastArtworkUri) return;
    _lastArtworkUri = artworkUri;

    ArtworkColorResolver.resolveColor(
      artworkUri: artworkUri,
      theme: theme,
    ).then((color) {
      if (mounted && _lastArtworkUri == artworkUri && _resolvedColor != color) {
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
    final playback = context.read<PlaybackController>();
    final theme = Theme.of(context);
    final strings = context.watch<LocaleController>().localeStrings;
    final renderer = NowPlayingVisualizerFactory.getRenderer(_mode);
    final motionListenable = Listenable.merge([
      _ballistics,
      _dragOffsetNotifier,
    ]);

    return ListenableBuilder(
      listenable: playback.trackListenable,
      builder: (context, _) {
        final currentPlayable = playback.currentPlayable;
        if (currentPlayable == null) {
          return const SizedBox.shrink();
        }

        final displayMeta = playback.currentDisplayMetadata;
        final artworkUri = displayMeta?.artworkUri ?? currentPlayable.artworkUri;
        final artworkBytes = displayMeta?.artworkBytes;

        _ballistics.isPlaying = playback.isPlaying;
        final filePath = currentPlayable.filePath;
        _resolveArtworkColor(artworkUri, theme);
        final waveColor = _resolvedColor ?? theme.colorScheme.primary;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cycleVisualizerMode,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: (details) =>
              _onHorizontalDragEnd(details, playback),
          onHorizontalDragCancel: _onHorizontalDragCancel,
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxSide = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final size = maxSide.isFinite && maxSide > 0
                    ? maxSide * 0.84
                    : 280.0;

                final coverHero = Hero(
                  tag: 'now_playing_art_$filePath',
                  child: AlbumArtImage(
                    playable: currentPlayable,
                    artworkUri: artworkUri,
                    artworkBytes: artworkBytes,
                    quality: ThumbnailQuality.high,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                );

                final stableCardStack = SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      renderer.render(
                        context: context,
                        size: size,
                        cornerRadius: _cornerRadius,
                        coverArt: coverHero,
                        displayBands: _ballistics.bands,
                        smoothedBass: _ballistics.smoothedBass,
                        smoothedRms: _ballistics.smoothedRms,
                        waveColor: waveColor,
                        trackColor: _resolvedColor,
                        isPlaying: _ballistics.isPlaying,
                        rawPeak: _ballistics.rawPeak,
                        leftChannel: _ballistics.leftChannel,
                        rightChannel: _ballistics.rightChannel,
                        frameListenable: _ballistics,
                        bandsProvider: () => _ballistics.bands,
                        smoothedRmsProvider: () => _ballistics.smoothedRms,
                        rawPeakProvider: () => _ballistics.rawPeak,
                        leftChannelProvider: () => _ballistics.leftChannel,
                        rightChannelProvider: () => _ballistics.rightChannel,
                        isPlayingProvider: () => _ballistics.isPlaying,
                      ),
                      _buildHudBadge(strings),
                    ],
                  ),
                );

                return AnimatedBuilder(
                  animation: motionListenable,
                  child: stableCardStack,
                  builder: (context, child) {
                    final scale = renderer.computeScale(
                      _ballistics.smoothedBass,
                    );
                    final dragOffset = _dragOffsetNotifier.value;
                    Widget result = child!;
                    if (scale != 1.0) {
                      result = Transform.scale(scale: scale, child: result);
                    }
                    if (dragOffset != 0.0) {
                      result = Transform.translate(
                        offset: Offset(dragOffset.clamp(-120.0, 120.0), 0.0),
                        child: result,
                      );
                    }
                    return result;
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
