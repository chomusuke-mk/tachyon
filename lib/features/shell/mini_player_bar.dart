import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Service responsible for extracting and caching a harmonized background color
/// from a track's low-quality thumbnail image.
abstract final class MiniPlayerColorResolver {
  static final Map<String, Color> _cache = <String, Color>{};

  @visibleForTesting
  static Map<String, Color> get cache => _cache;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Computes a surface color harmonized with the extracted artwork color scheme,
  /// preserving readability and contrasting with [ThemeData.colorScheme].
  static Color computeColor({
    required ColorScheme extractedScheme,
    required ColorScheme themeScheme,
    required bool isDark,
    required bool isOled,
  }) {
    if (isOled) {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.28),
        themeScheme.surfaceContainerHigh,
      );
    } else if (isDark) {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.45),
        extractedScheme.surfaceContainerHigh,
      );
    } else {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.35),
        extractedScheme.surfaceContainerHigh,
      );
    }
  }

  /// Asynchronously loads the low-quality thumbnail and extracts
  /// a Material ColorScheme seeded from the artwork.
  static Future<Color?> resolveColor({
    required String thumbnailHash,
    required ThemeData theme,
  }) async {
    final isDark = theme.brightness == Brightness.dark;
    final isOled = isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$thumbnailHash:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final filePath = await AlbumArtImage.getThumbnail(
        thumbnailHash,
        quality: ThumbnailQuality.low,
      );
      if (filePath == null) return null;

      final file = File(filePath);
      if (!await file.exists() || await file.length() <= 0) return null;

      final scheme = await ColorScheme.fromImageProvider(
        provider: FileImage(file),
        brightness: theme.brightness,
      );

      final color = computeColor(
        extractedScheme: scheme,
        themeScheme: theme.colorScheme,
        isDark: isDark,
        isOled: isOled,
      );

      _cache[cacheKey] = color;
      return color;
    } catch (_) {
      return null;
    }
  }
}

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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _requestColorResolution(
    String thumbnailHash,
    ThemeData theme,
    String cacheKey,
  ) {
    if (_lastRequestedKey == cacheKey) return;
    _lastRequestedKey = cacheKey;
    _currentThumbnailHash = thumbnailHash;

    MiniPlayerColorResolver.resolveColor(
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
    final currentTrack = playback.currentTrack;

    if (currentTrack == null) return const SizedBox.shrink();

    final thumbnailHash =
        currentTrack.thumbnailHash ?? currentTrack.album?.thumbnailHash;

    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        (thumbnailHash != null && thumbnailHash.trim().isNotEmpty)
            ? '$thumbnailHash:${theme.brightness.name}:${isOled ? 'oled' : 'std'}'
            : null;

    final defaultBg = colorScheme.surfaceContainerHigh;
    final Color targetColor;

    if (cacheKey != null &&
        MiniPlayerColorResolver.cache.containsKey(cacheKey)) {
      targetColor = MiniPlayerColorResolver.cache[cacheKey]!;
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ValueListenableBuilder<Duration>(
                        valueListenable: playback.positionListenable,
                        builder: (context, pos, _) {
                          final totalMs = playback.duration.inMilliseconds;
                          final prog = totalMs > 0
                              ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                              : 0.0;
                          final progressBar = LinearProgressIndicator(
                            value: prog,
                            minHeight: widget.isDesktop ? 4.0 : 2.5,
                            backgroundColor:
                                colorScheme.onSurface.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary,
                            ),
                          );

                          if (!widget.isDesktop) return progressBar;

                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
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
                                child: progressBar,
                              ),
                            ),
                          );
                        },
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
                          tag: 'now_playing_art_${currentTrack.filePath}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: SizedBox(
                              width: widget.isDesktop ? 48 : 42,
                              height: widget.isDesktop ? 48 : 42,
                              child: AlbumArtImage(
                                thumbnailHash: thumbnailHash,
                                quality: ThumbnailQuality.low,
                                fit: BoxFit.cover,
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
                                currentTrack.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentTrack.artists
                                    .map((a) => a.name)
                                    .join(', '),
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
                          ValueListenableBuilder<Duration>(
                            valueListenable: playback.positionListenable,
                            builder: (context, pos, _) {
                              return Text(
                                '${_formatDuration(pos)} / ${_formatDuration(playback.duration)}',
                                style: theme.textTheme.bodySmall,
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  playback.loopMode != Loop.off
                                      ? (playback.loopMode == Loop.one
                                            ? Icons.repeat_one_rounded
                                            : Icons.repeat_rounded)
                                      : Icons.repeat_rounded,
                                  size: 24,
                                ),
                                if (playback.loopMode == Loop.all)
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
                            color: playback.loopMode != Loop.off
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            tooltip: playback.loopMode == Loop.one
                                ? strings.npRepeatOne
                                : (playback.loopMode == Loop.all
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
                                    bottom: 0,
                                    child: Container(
                                      width: 4,
                                      height: 4,
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
                          icon: Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 26,
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
