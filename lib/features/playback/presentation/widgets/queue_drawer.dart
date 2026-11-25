import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';

import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';

import 'package:tachyon/shared/utils/duration_formatter.dart';
import 'package:tachyon/shared/widgets/track_action_helper.dart';

import 'package:tachyon/core/playback/playback_controller.dart';

/// Modal bottom sheet representation of the playback queue on Mobile.
class QueueDrawerSheet extends StatelessWidget {
  /// Creates a [QueueDrawerSheet].
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
  /// Optional external scroll controller shared with a modal sheet.
  final ScrollController? scrollController;

  /// Creates a [QueueView].
  const QueueView({super.key, this.scrollController});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  static const double _itemExtent = 72.0;
  bool _autoScroll = true;
  int? lastIndexScrolledTo;

  ScrollController? _internalController;
  ScrollController get _effectiveController =>
      widget.scrollController ??
      (_internalController ??= _createInternalController());

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
    final targetOffset =
        ((index * _itemExtent) - (viewportHeight / 2) + (_itemExtent / 2))
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
    lastIndexScrolledTo = index;
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        playback.queueListenable,
        playback.transportListenable,
        playback.trackListenable,
      ]),
      builder: (context, _) {
        final queue = playback.queue;
        final currentIndex = playback.currentIndex;
        final isPlaying = playback.isPlaying;
        final isInfiniteMixEnabled = playback.isInfiniteMixEnabled;

        if (_autoScroll && lastIndexScrolledTo != currentIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToCurrentIndex(animated: true);
          });
        }

        return Column(
          children: [
            // Queue Header Actions
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
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
                    maxCount: 9999,
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
                    tooltip: strings.npInfiniteMix,
                    onPressed: playback.toggleInfiniteMix,
                  ),

                  // Add Queue to Playlist
                  IconButton(
                    icon: const Icon(Icons.playlist_add_rounded),
                    tooltip: strings.npQueueAddToPlaylist,
                    onPressed: queue.isNotEmpty
                        ? () => TrackActionHelper.showAddQueueToPlaylistDialog(
                            context,
                            queue,
                          )
                        : null,
                  ),

                  // Clear Queue with confirmation
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded),
                    tooltip: strings.npQueueClear,
                    onPressed:
                        (queue.length > 1 ||
                            (queue.length == 1 && currentIndex == -1))
                        ? () => _confirmClearQueue(context, playback, strings)
                        : null,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is UserScrollNotification) {
                          if (!_autoScroll) return false;
                          setState(() {
                            _autoScroll = false;
                          });
                        }
                        return false;
                      },
                      child: queue.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.queue_music_rounded,
                                    size: 56,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    strings.npQueueEmpty,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            )
                          : ReorderableListView.builder(
                              scrollController: _effectiveController,
                              buildDefaultDragHandles: false,
                              itemExtent: _itemExtent,
                              scrollCacheExtent: const ScrollCacheExtent.pixels(
                                720.0,
                              ),
                              itemCount: queue.length,
                              onReorderItem: (from, to) {
                                playback.reorderQueue(from, to);
                              },
                              itemBuilder: (context, index) {
                                final item = queue[index];
                                final rawTrack = item.track;
                                final track = rawTrack != null
                                    ? playback.resolvePlayable(rawTrack)
                                    : null;
                                final isCurrent = index == currentIndex;
                                final displayMeta = isCurrent
                                    ? playback.currentDisplayMetadata
                                    : null;
                                final rowTitle =
                                    displayMeta?.title ?? track?.title ?? '';
                                final rowSubtitle = displayMeta?.subtitle ??
                                    (track?.artistNames.join(', ') ?? '');
                                final rowArtworkUri = displayMeta?.artworkUri ??
                                    track?.artworkUri;
                                final rowArtworkBytes =
                                    displayMeta?.artworkBytes;

                                return Dismissible(
                                  key: ValueKey(
                                    item.id ?? identityHashCode(item),
                                  ),
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
                                  onDismissed: (_) =>
                                      playback.removeFromQueue(index),
                                  child: Material(
                                    color: isCurrent
                                        ? colorScheme.primaryContainer
                                              .withValues(alpha: 0.28)
                                        : Colors.transparent,
                                    child: ListTile(
                                      leading: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              6.0,
                                            ),
                                            child: SizedBox(
                                              width: 42,
                                              height: 42,
                                              child: AlbumArtImage(
                                                playable: track,
                                                artworkUri: rowArtworkUri,
                                                artworkBytes: rowArtworkBytes,
                                                width: 42,
                                                height: 42,
                                                quality: ThumbnailQuality.low,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          if (isCurrent)
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.55,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6.0),
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
                                        rowTitle,
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
                                        rowSubtitle,
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
                                            track?.isStream == true
                                                ? 'LIVE'
                                                : (track?.duration ??
                                                          Duration.zero)
                                                      .toFormattedString(
                                                        padMinutes: true,
                                                      ),
                                            style: track?.isStream == true
                                                ? Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Colors.redAccent,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      )
                                                : Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(width: 8),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color: colorScheme
                                                  .onSurfaceVariant
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
                  ),
                  if (!_autoScroll)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton.small(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        tooltip: strings.npLyricsResumeSync,
                        onPressed: () {
                          setState(() {
                            _autoScroll = true;
                          });
                          _scrollToCurrentIndex(animated: true);
                        },
                        child: const Icon(Icons.sync_rounded, size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
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
        content: Text(strings.npQueueClearConfirm),
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
