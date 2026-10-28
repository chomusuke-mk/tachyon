import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';
import 'package:tachyon/shared/utils/duration_formatter.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/text_link.dart';

class MiniPlayerBar extends StatefulWidget {
  final bool isDesktop;
  final VoidCallback? onTap;

  const MiniPlayerBar({super.key, required this.isDesktop, this.onTap});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  String? _lastRequestedKey;
  String? _currentThumbnailHash;
  Color? _extractedColor;
  int? _lastFormattedSecond;
  Duration? _lastTotalDuration;
  TextStyle? _lastDurationStyle;
  Widget? _cachedDurationText;

  Widget _buildProgressBar(
    PlaybackController playback,
    ColorScheme colorScheme,
  ) {
    if (playback.isLiveStream) {
      return LinearProgressIndicator(
        value: 1.0,
        minHeight: widget.isDesktop ? 4.0 : 2.5,
        backgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
      );
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: playback.positionListenable,
      builder: (context, pos, _) {
        final totalMs = playback.duration.inMilliseconds;
        final prog = totalMs > 0
            ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;
        return LinearProgressIndicator(
          value: prog,
          minHeight: widget.isDesktop ? 4.0 : 2.5,
          backgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        );
      },
    );
  }

  Widget _buildDesktopDurationCounter(
    PlaybackController playback,
    TextStyle? style,
  ) {
    if (playback.isLiveStream) {
      return Row(
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
          ValueListenableBuilder<Duration>(
            valueListenable: playback.positionListenable,
            builder: (context, pos, _) {
              return Text(
                'LIVE ${pos.toFormattedString(padMinutes: true)}',
                style: style?.copyWith(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ],
      );
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: playback.positionListenable,
      builder: (context, pos, _) {
        final sec = pos.inSeconds;
        final dur = playback.duration;
        if (_cachedDurationText != null &&
            _lastFormattedSecond == sec &&
            _lastTotalDuration == dur &&
            _lastDurationStyle == style) {
          return _cachedDurationText!;
        }
        final textWidget = Text(
          '${pos.toFormattedString(padMinutes: true)} / ${dur.toFormattedString(padMinutes: true)}',
          style: style,
        );
        _lastFormattedSecond = sec;
        _lastTotalDuration = dur;
        _lastDurationStyle = style;
        _cachedDurationText = textWidget;
        return textWidget;
      },
    );
  }

  void _requestColorResolution(
    String thumbnailHash,
    ThemeData theme,
    String cacheKey,
  ) {
    if (_lastRequestedKey == cacheKey) return;
    _lastRequestedKey = cacheKey;
    _currentThumbnailHash = thumbnailHash;

    ArtworkColorResolver.resolveColor(
      thumbnailHash: thumbnailHash,
      theme: theme,
    ).then((color) {
      if (!mounted) return;
      if (_currentThumbnailHash != thumbnailHash) return;
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
    final playback = context.watch<PlaybackController>();
    final currentPlayable = playback.currentPlayable;

    if (currentPlayable == null) return const SizedBox.shrink();

    final thumbnailHash = currentPlayable.thumbnailHash;

    final isDark = theme.brightness == Brightness.dark;
    final isOled = isDark && colorScheme.surface == const Color(0xFF000000);
    final cacheKey = (thumbnailHash != null && thumbnailHash.trim().isNotEmpty)
        ? '$thumbnailHash:${theme.brightness.name}:${isOled ? 'oled' : 'std'}'
        : null;

    final defaultBg = colorScheme.surfaceContainerHigh;
    final Color targetColor;

    if (cacheKey != null &&
        ArtworkColorResolver.cache.containsKey(cacheKey)) {
      targetColor = ArtworkColorResolver.cache[cacheKey]!;
    } else if (_extractedColor != null &&
        _currentThumbnailHash == thumbnailHash) {
      targetColor = _extractedColor!;
    } else {
      targetColor = defaultBg;
      if (thumbnailHash != null && thumbnailHash.trim().isNotEmpty) {
        _requestColorResolution(thumbnailHash, theme, cacheKey!);
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
                // Top linear progress bar (2.5dp / interactive click-to-seek in desktop mode)
                RepaintBoundary(
                  child: !widget.isDesktop
                      ? _buildProgressBar(playback, colorScheme)
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
                                      (details.localPosition.dx / width).clamp(
                                        0.0,
                                        1.0,
                                      );
                                  final seekTarget = Duration(
                                    milliseconds: (totalMs * fraction).round(),
                                  );
                                  playback.seek(seekTarget);
                                },
                                child: Container(
                                  height: 8.0,
                                  alignment: Alignment.topCenter,
                                  child: _buildProgressBar(
                                    playback,
                                    colorScheme,
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
                          tag: 'now_playing_art_${currentPlayable.filePath}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: SizedBox(
                              width: widget.isDesktop ? 48 : 42,
                              height: widget.isDesktop ? 48 : 42,
                              child: AlbumArtImage(
                                thumbnailHash: thumbnailHash,
                                quality: ThumbnailQuality.low,
                                fit: BoxFit.cover,
                                fallback: currentPlayable.isStream
                                    ? Center(
                                        child: Icon(
                                          Icons.radio_rounded,
                                          size: widget.isDesktop ? 24 : 20,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title & Artist
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentPlayable.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (widget.isDesktop &&
                                  currentPlayable is Track &&
                                  currentPlayable.artists.isNotEmpty)
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (
                                        int i = 0;
                                        i < currentPlayable.artists.length;
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
                                          text: currentPlayable.artists[i].name,
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
                                                        artist: currentPlayable
                                                            .artists[i],
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
                                  currentPlayable.artistNames.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Desktop Extra Controls (Duration & Repeat/Shuffle/Prev)
                        if (widget.isDesktop) ...[
                          _buildDesktopDurationCounter(
                            playback,
                            theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  playback.loopMode != LoopMode.off
                                      ? (playback.loopMode == LoopMode.one
                                            ? Icons.repeat_one_rounded
                                            : Icons.repeat_rounded)
                                      : Icons.repeat_rounded,
                                  size: 24,
                                ),
                                if (playback.loopMode == LoopMode.all)
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
                            color: playback.loopMode != LoopMode.off
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            tooltip: playback.loopMode == LoopMode.one
                                ? strings.npRepeatOne
                                : (playback.loopMode == LoopMode.all
                                      ? strings.npRepeatAll
                                      : strings.npRepeatOff),
                            onPressed: playback.toggleLoopMode,
                          ),
                          IconButton(
                            icon: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.shuffle_rounded, size: 24),
                                if (playback.isShuffled)
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
                            color: playback.isShuffled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            tooltip: playback.isShuffled
                                ? strings.npShuffleOn
                                : strings.npShuffleOff,
                            onPressed: playback.toggleShuffle,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            tooltip: strings.npPrevious,
                            onPressed: playback.hasPrevious
                                ? playback.previous
                                : null,
                          ),
                        ],

                        // Play / Pause Button
                        IconButton.filledTonal(
                          icon: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
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
                                playback.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey<bool>(playback.isPlaying),
                                size: 26,
                              ),
                            ),
                          ),
                          tooltip: playback.isPlaying
                              ? strings.npPause
                              : strings.npPlay,
                          onPressed: playback.playOrPause,
                        ),

                        // Next Button
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          tooltip: strings.npNext,
                          onPressed: playback.hasNext ? playback.next : null,
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
  }
}
