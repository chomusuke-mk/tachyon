import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

import 'package:tachyon/features/library/domain/playlist.dart';
import 'playback_controller.dart';

/// Modal bottom sheet representation of the playback queue on Mobile.
class QueueDrawerSheet extends StatelessWidget {
  const QueueDrawerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle Pill
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Queue View Body
              Expanded(child: QueueView(scrollController: scrollController)),
            ],
          ),
        );
      },
    );
  }
}

/// Reusable queue list view widget usable both inside modal bottom sheet and desktop side-panel.
class QueueView extends StatefulWidget {
  final ScrollController? scrollController;

  const QueueView({super.key, this.scrollController});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  static const double _itemExtent = 72.0;

  ScrollController? _internalController;
  ScrollController get _effectiveController =>
      widget.scrollController ?? (_internalController ??= _createInternalController());

  ScrollController _createInternalController() {
    final playback = context.read<PlaybackController>();
    final index = playback.currentIndex;
    final initialOffset = (index > 0 && index < playback.queue.length)
        ? (index * _itemExtent - 200.0).clamp(0.0, double.infinity)
        : 0.0;
    return ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentIndex(animated: false);
    });
  }

  void _scrollToCurrentIndex({bool animated = true}) {
    if (!mounted) return;
    if (!_effectiveController.hasClients) return;
    final playback = context.read<PlaybackController>();
    final index = playback.currentIndex;
    if (index <= 0 || index >= playback.queue.length) return;

    final viewportHeight = _effectiveController.position.viewportDimension;
    final targetOffset = ((index * _itemExtent) - (viewportHeight / 2) + (_itemExtent / 2))
        .clamp(0.0, _effectiveController.position.maxScrollExtent);

    if (animated) {
      _effectiveController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _effectiveController.jumpTo(targetOffset);
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.select<PlaybackController, List<PlaylistEntry>>((c) => c.queue);
    final currentIndex = context.select<PlaybackController, int>((c) => c.currentIndex);
    final isPlaying = context.select<PlaybackController, bool>((c) => c.isPlaying);
    final isInfiniteMixEnabled =
        context.select<PlaybackController, bool>((c) => c.isInfiniteMixEnabled);
    final playback = context.read<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Queue Header Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                strings.npQueue,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Badge.count(
                count: queue.length,
                backgroundColor: colorScheme.primaryContainer,
                textColor: colorScheme.onPrimaryContainer,
              ),
              const Spacer(),

              // Infinite Library Mix Toggle
              IconButton(
                icon: Icon(
                  Icons.all_inclusive_rounded,
                  color: isInfiniteMixEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Infinite Library Mix',
                onPressed: playback.toggleInfiniteMix,
              ),

              // Clear Queue with confirmation
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                tooltip: strings.npQueueClear,
                onPressed: queue.isNotEmpty
                    ? () => _confirmClearQueue(context, playback, strings)
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Queue Items List or Empty State
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.queue_music_rounded,
                        size: 56,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strings.npQueueEmpty,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: _effectiveController,
                  buildDefaultDragHandles: false,
                  itemExtent: _itemExtent,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(720.0),
                  itemCount: queue.length,
                  onReorderItem: (from, to) {
                    playback.reorderQueue(from, to);
                  },
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final track = item.track;
                    final isCurrent = index == currentIndex;

                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: colorScheme.errorContainer,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      onDismissed: (_) => playback.removeFromQueue(index),
                      child: Material(
                        color: isCurrent
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.28,
                              )
                            : Colors.transparent,
                        child: ListTile(
                          leading: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6.0),
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: AlbumArtImage(
                                    thumbnailHash: track?.thumbnailHash ??
                                        track?.album?.thumbnailHash,
                                    quality: ThumbnailQuality.low,
                                    fit: BoxFit.cover,
                                    cacheWidth: 100,
                                    cacheHeight: 100,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.play_arrow_rounded,
                                    color: colorScheme.primary,
                                    size: 24,
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            track?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            track?.artists.map((a) => a.name).join(', ') ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDuration(track?.duration ?? Duration.zero),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            playback.skipToQueueIndex(index);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmClearQueue(
    BuildContext context,
    PlaybackController playback,
    AppStringKey strings,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.npQueueClear),
        content: const Text(
          'Are you sure you want to clear the entire playback queue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.plCancelButton),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              playback.clearQueue();
            },
            child: Text(strings.npQueueClear),
          ),
        ],
      ),
    );
  }
}
