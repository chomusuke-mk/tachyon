import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:provider/provider.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/library/presentation/screens/artist_detail_screen.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';
import 'package:tachyon/shared/utils/duration_formatter.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/text_link.dart';

/// Persistent mini player bar displaying current playback info, progress, and transport controls.
class MiniPlayerBar extends StatefulWidget {
  /// Whether to use the taller desktop layout with seekable progress bar and extended controls.
  final bool isDesktop;

  /// Optional callback invoked when the user taps the mini player bar.
  final VoidCallback? onTap;

  /// Creates a [MiniPlayerBar].
  const MiniPlayerBar({super.key, required this.isDesktop, this.onTap});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  static const _log = ScopedLogger('MiniPlayerBar');

  String? _lastRequestedKey;
  String? _currentArtworkUri;
  Color? _extractedColor;

  Widget _buildProgressBar(
    PlaybackController playback,
    ColorScheme colorScheme,
    bool isLiveStream,
  ) {
    final barHeight = widget.isDesktop ? 4.0 : 2.5;
    if (isLiveStream) {
      return SizedBox(
        width: double.infinity,
        height: barHeight,
        child: CustomPaint(
          painter: _MiniProgressPainter(
            repaint: playback.positionListenable,
            positionListenable: playback.positionListenable,
            bufferListenable: playback.bufferListenable,
            durationProvider: () => playback.duration,
            isLiveStream: true,
            activeColor: Colors.redAccent,
            bufferedColor: Colors.redAccent.withValues(alpha: 0.25),
            trackColor: colorScheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: barHeight,
      child: CustomPaint(
        painter: _MiniProgressPainter(
          repaint: Listenable.merge([
            playback.positionListenable,
            playback.bufferListenable,
          ]),
          positionListenable: playback.positionListenable,
          bufferListenable: playback.bufferListenable,
          durationProvider: () => playback.duration,
          isLiveStream: false,
          activeColor: colorScheme.primary,
          bufferedColor: colorScheme.primary.withValues(alpha: 0.25),
          trackColor: colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  Widget _buildDesktopDurationCounter(
    PlaybackController playback,
    TextStyle? style,
    bool isLiveStream,
    Duration trackDuration,
  ) {
    final tabularStyle = style?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (isLiveStream) {
      return RepaintBoundary(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            ValueListenableBuilder<int>(
              valueListenable: playback.positionSecondsListenable,
              builder: (context, sec, _) {
                return Text(
                  'LIVE ${Duration(seconds: sec).toFormattedString(padMinutes: true)}',
                  style: tabularStyle?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: playback.positionSecondsListenable,
        builder: (context, sec, _) {
          final dur = playback.duration > Duration.zero
              ? playback.duration
              : trackDuration;
          return Text(
            '${Duration(seconds: sec).toFormattedString(padMinutes: true)} / ${dur.toFormattedString(padMinutes: true)}',
            style: tabularStyle,
          );
        },
      ),
    );
  }

  void _requestColorResolution(
    String artworkUri,
    ThemeData theme,
    String cacheKey,
  ) {
    if (_lastRequestedKey == cacheKey) return;
    _lastRequestedKey = cacheKey;
    _currentArtworkUri = artworkUri;

    ArtworkColorResolver.resolveColor(
      artworkUri: artworkUri,
      theme: theme,
    ).then((color) {
      if (!mounted) return;
      if (_currentArtworkUri != artworkUri) return;
      if (color != null) {
        setState(() {
          _extractedColor = color;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;
    final playback = context.read<PlaybackController>();

    return ListenableBuilder(
      listenable: playback.trackListenable,
      builder: (context, _) {
        final currentPlayable = playback.currentPlayable;
        _log.vLazy(
          () =>
              'MiniPlayerBar.build isDesktop=${widget.isDesktop} playable=${currentPlayable?.filePath} '
              'lifecycleMode=${playback.lifecycleMode.name}',
        );
        if (currentPlayable == null) return const SizedBox.shrink();

        final displayMeta = playback.currentDisplayMetadata;
        final artworkUri = displayMeta?.artworkUri ?? currentPlayable.artworkUri;
        final artworkBytes = displayMeta?.artworkBytes;
        final displayTitle = displayMeta?.title ?? currentPlayable.title;
        final displaySubtitle =
            displayMeta?.subtitle ?? currentPlayable.artistNames.join(', ');
        final clickableArtists = displayMeta?.clickableArtists ?? const [];
        final isLiveStream = playback.isLiveStream;
        final trackDuration = playback.duration;

        final isDark = theme.brightness == Brightness.dark;
        final isOled = isDark && colorScheme.surface == const Color(0xFF000000);
        final cacheKey = (artworkUri != null && artworkUri.trim().isNotEmpty)
            ? '$artworkUri:${theme.brightness.name}:${isOled ? 'oled' : 'std'}'
            : null;

        final Color targetColor;

        if (cacheKey != null &&
            ArtworkColorResolver.cache.containsKey(cacheKey)) {
          targetColor = ArtworkColorResolver.cache[cacheKey]!;
        } else if (_extractedColor != null &&
            _currentArtworkUri == artworkUri) {
          targetColor = _extractedColor!;
        } else {
          targetColor = ArtworkColorResolver.getColor(
            artworkUri: artworkUri,
            theme: theme,
          );
          if (artworkUri != null && artworkUri.trim().isNotEmpty) {
            _requestColorResolution(artworkUri, theme, cacheKey!);
          }
        }

        final height = widget.isDesktop ? 72.0 : 64.0;

        return RepaintBoundary(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: targetColor),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            builder: (context, animatedColor, child) {
              return Material(
                color: animatedColor ?? targetColor,
                elevation: widget.isDesktop ? 2 : 4,
                child: child,
              );
            },
            child: InkWell(
              onTap: widget.onTap,
              child: SizedBox(
                height: height,
                child: Column(
                  children: [
                    // Top linear progress bar (0 widget rebuilds per tick)
                    RepaintBoundary(
                      child: !widget.isDesktop
                          ? _buildProgressBar(
                              playback,
                              colorScheme,
                              isLiveStream,
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) {
                                      if (playback.isLiveStream) return;
                                      final totalMs =
                                          playback.duration.inMilliseconds;
                                      if (totalMs <= 0) return;
                                      final width = constraints.maxWidth;
                                      if (width <= 0) return;
                                      final fraction =
                                          (details.localPosition.dx / width)
                                              .clamp(0.0, 1.0);
                                      final seekTarget = Duration(
                                        milliseconds:
                                            (totalMs * fraction).round(),
                                      );
                                      playback.seek(seekTarget);
                                    },
                                    child: Container(
                                      height: 8.0,
                                      alignment: Alignment.topCenter,
                                      child: _buildProgressBar(
                                        playback,
                                        colorScheme,
                                        isLiveStream,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    // Main Mini Player Row
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          children: [
                            // Thumbnail
                            Hero(
                              tag:
                                  'now_playing_art_${currentPlayable.filePath}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: SizedBox(
                                  width: widget.isDesktop ? 48 : 42,
                                  height: widget.isDesktop ? 48 : 42,
                                  child: AlbumArtImage(
                                    playable: currentPlayable,
                                    artworkUri: artworkUri,
                                    artworkBytes: artworkBytes,
                                    width: widget.isDesktop ? 48 : 42,
                                    height: widget.isDesktop ? 48 : 42,
                                    quality: ThumbnailQuality.low,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Title & Artist (with live ICY / scan-time metadata)
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (widget.isDesktop &&
                                      !currentPlayable.isStream &&
                                      clickableArtists.isNotEmpty)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (
                                            int i = 0;
                                            i < clickableArtists.length;
                                            i++
                                          ) ...[
                                            if (i > 0)
                                              Text(
                                                ', ',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            TextLink(
                                              text: clickableArtists[i].name,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              hoverColor: colorScheme.primary,
                                              defaultColor:
                                                  colorScheme.onSurfaceVariant,
                                              onTap: () => Navigator.of(context)
                                                  .push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          ArtistDetailScreen(
                                                            artist:
                                                                clickableArtists[i],
                                                          ),
                                                    ),
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      displaySubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),

                            // Desktop Extra Controls
                            if (widget.isDesktop) ...[
                              _buildDesktopDurationCounter(
                                playback,
                                theme.textTheme.bodySmall,
                                isLiveStream,
                                trackDuration,
                              ),
                              const SizedBox(width: 16),
                              ListenableBuilder(
                                listenable: playback.controlsListenable,
                                builder: (context, _) {
                                  final loop = playback.loopMode;
                                  final shuffled = playback.isShuffled;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              loop == LoopMode.one
                                                  ? Icons.repeat_one_rounded
                                                  : Icons.repeat_rounded,
                                              size: 24,
                                            ),
                                            if (loop == LoopMode.all)
                                              Positioned(
                                                child: Text(
                                                  'A',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        color: loop != LoopMode.off
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        tooltip: loop == LoopMode.one
                                            ? strings.npRepeatOne
                                            : (loop == LoopMode.all
                                                  ? strings.npRepeatAll
                                                  : strings.npRepeatOff),
                                        onPressed: playback.toggleLoopMode,
                                      ),
                                      IconButton(
                                        icon: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            const Icon(
                                              Icons.shuffle_rounded,
                                              size: 24,
                                            ),
                                            if (shuffled)
                                              Positioned(
                                                left: 3,
                                                child: Container(
                                                  width: 3,
                                                  height: 3,
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        color: shuffled
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        tooltip: shuffled
                                            ? strings.npShuffleOn
                                            : strings.npShuffleOff,
                                        onPressed: playback.toggleShuffle,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],

                            // Leaf Transport Controls (Prev on desktop / Play-Pause / Next)
                            ListenableBuilder(
                              listenable: playback.transportListenable,
                              builder: (context, _) {
                                final playing = playback.isPlaying;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.isDesktop)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.skip_previous_rounded,
                                        ),
                                        tooltip: strings.npPrevious,
                                        onPressed: playback.hasPrevious
                                            ? playback.previous
                                            : null,
                                      ),
                                    IconButton.filledTonal(
                                      icon: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          transitionBuilder: (
                                            Widget child,
                                            Animation<double> animation,
                                          ) {
                                            return ScaleTransition(
                                              scale: animation,
                                              child: RotationTransition(
                                                turns: Tween<double>(
                                                  begin: 0.9,
                                                  end: 1.0,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Icon(
                                            playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            key: ValueKey<bool>(playing),
                                            size: 26,
                                          ),
                                        ),
                                      ),
                                      tooltip: playing
                                          ? strings.npPause
                                          : strings.npPlay,
                                      onPressed: playback.playOrPause,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_next_rounded),
                                      tooltip: strings.npNext,
                                      onPressed: playback.hasNext
                                          ? playback.next
                                          : null,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniProgressPainter extends CustomPainter {
  final ValueListenable<Duration> positionListenable;
  final ValueListenable<ma.Buffer> bufferListenable;
  final Duration Function() durationProvider;
  final bool isLiveStream;
  final Color activeColor;
  final Color bufferedColor;
  final Color trackColor;

  static final Paint _paint = Paint()..style = PaintingStyle.fill;

  _MiniProgressPainter({
    required super.repaint,
    required this.positionListenable,
    required this.bufferListenable,
    required this.durationProvider,
    required this.isLiveStream,
    required this.activeColor,
    required this.bufferedColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Background track
    _paint.color = trackColor;
    canvas.drawRect(Offset.zero & size, _paint);

    if (isLiveStream) {
      _paint.color = activeColor;
      canvas.drawRect(Offset.zero & size, _paint);
      return;
    }

    final totalMs = durationProvider().inMilliseconds;
    if (totalMs <= 0) return;

    final prog = (positionListenable.value.inMilliseconds / totalMs).clamp(
      0.0,
      1.0,
    );
    final playheadX = size.width * prog;

    final buf = bufferListenable.value;
    final double clampedStart;
    final double clampedBuffer;
    if (buf.end > Duration.zero) {
      clampedStart = (buf.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
      clampedBuffer = (buf.end.inMilliseconds / totalMs).clamp(
        clampedStart,
        1.0,
      );
    } else {
      clampedStart = 0.0;
      clampedBuffer = 0.0;
    }

    final startX = size.width * clampedStart;
    final endX = size.width * clampedBuffer;

    // 1. Preload buffer ahead of playhead ([aheadStartX .. endX])
    final aheadStartX = startX.clamp(playheadX, size.width);
    if (endX > aheadStartX) {
      _paint.color = bufferedColor;
      canvas.drawRect(
        Rect.fromLTRB(aheadStartX, 0, endX, size.height),
        _paint,
      );
    }

    // 2. Evicted played history behind buffer start ([0 .. min(playheadX, startX)])
    final evictedEndX = playheadX.clamp(0.0, startX);
    if (evictedEndX > 0.0) {
      _paint.color = activeColor.withValues(alpha: 0.35);
      canvas.drawRect(
        Rect.fromLTRB(0, 0, evictedEndX, size.height),
        _paint,
      );
    }

    // 3. Buffered played section behind playhead ([startX .. min(playheadX, endX)])
    final backBufStartX = startX.clamp(0.0, playheadX);
    final backBufEndX = endX.clamp(backBufStartX, playheadX);
    if (backBufEndX > backBufStartX) {
      _paint.color = activeColor;
      canvas.drawRect(
        Rect.fromLTRB(backBufStartX, 0, backBufEndX, size.height),
        _paint,
      );
    }

    // 4. Played region beyond buffered end
    if (playheadX > endX) {
      _paint.color = endX > 0.0
          ? activeColor.withValues(alpha: 0.35)
          : activeColor;
      canvas.drawRect(
        Rect.fromLTRB(endX, 0, playheadX, size.height),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniProgressPainter oldDelegate) {
    return oldDelegate.positionListenable != positionListenable ||
        oldDelegate.bufferListenable != bufferListenable ||
        oldDelegate.isLiveStream != isLiveStream ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.bufferedColor != bufferedColor ||
        oldDelegate.trackColor != trackColor;
  }
}
