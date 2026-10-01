import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

class MiniPlayerBar extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback? onTap;

  const MiniPlayerBar({super.key, required this.isDesktop, this.onTap});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;
    final playback = context.watch<PlaybackController>();
    final currentTrack = playback.currentTrack;

    if (currentTrack == null) return const SizedBox.shrink();

    final height = isDesktop ? 72.0 : 64.0;

    return RepaintBoundary(
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        elevation: isDesktop ? 2 : 4,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                // Top linear progress bar (2.5dp)
                RepaintBoundary(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: playback.positionListenable,
                    builder: (context, pos, _) {
                      final totalMs = playback.duration.inMilliseconds;
                      final prog = totalMs > 0
                          ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                          : 0.0;
                      return LinearProgressIndicator(
                        value: prog,
                        minHeight: 2.5,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colorScheme.primary),
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
                              width: isDesktop ? 48 : 42,
                              height: isDesktop ? 48 : 42,
                              child: AlbumArtImage(
                                filePath: currentTrack.filePath,
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
                                currentTrack.artist,
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
                        if (isDesktop) ...[
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
                          icon: Icon(
                            playback.loopMode != Loop.off
                                ? (playback.loopMode == Loop.one
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded)
                                : Icons.repeat_rounded,
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
                          icon: const Icon(Icons.shuffle_rounded),
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
