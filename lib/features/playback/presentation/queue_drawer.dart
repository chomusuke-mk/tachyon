import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

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
class QueueView extends StatelessWidget {
  final ScrollController? scrollController;

  const QueueView({super.key, this.scrollController});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;
    final queue = playback.queue;

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
                  color: playback.isInfiniteMixEnabled
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
                  scrollController: scrollController,
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorderItem: (from, to) {
                    playback.reorderQueue(from, to);
                  },
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isCurrent = index == playback.currentIndex;

                    return Dismissible(
                      key: ValueKey('${item.uri}_$index'),
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
                                    uri: item.uri,
                                    fit: BoxFit.cover,
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
                                    playback.isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.play_arrow_rounded,
                                    color: colorScheme.primary,
                                    size: 24,
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            item.title,
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
                            item.artist,
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
                                _formatDuration(item.duration),
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
