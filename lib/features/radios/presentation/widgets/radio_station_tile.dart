import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/radios/presentation/controllers/radio_controller.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_logo_avatar.dart';

/// List tile displaying a radio station with playback state highlight and
/// favorite, save-to-library, edit, or delete actions.
class RadioStationListTile extends StatelessWidget {
  /// Station data displayed in this row.
  final RadioStation station;

  /// Localized strings for tooltips and menu labels.
  final AppStringKey strings;

  /// Library store used for toggling saved station favorites.
  final LibraryStore store;

  /// Radio controller used to check and save discovered stations.
  final RadioController radioController;

  /// Whether this item is shown inside the Saved Stations tab.
  final bool isSavedTab;

  /// Invoked when the tile itself is tapped to start playback.
  final VoidCallback onTap;

  /// Invoked when the user chooses to edit [station].
  final VoidCallback onEdit;

  /// Invoked when the user chooses to delete [station].
  final VoidCallback onDelete;

  /// Creates a [RadioStationListTile].
  const RadioStationListTile({
    super.key,
    required this.station,
    required this.strings,
    required this.store,
    required this.radioController,
    required this.isSavedTab,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSaved = radioController.isStationSaved(station);

    final subtitleParts = <String>[];
    if (station.genre?.isNotEmpty == true) {
      subtitleParts.add(station.genre!);
    }
    if (station.country?.isNotEmpty == true) {
      subtitleParts.add(station.country!);
    }
    if (station.bitrateKbps != null && station.bitrateKbps! > 0) {
      subtitleParts.add('${station.bitrateKbps} kbps');
    }
    final subtitleText = subtitleParts.isNotEmpty
        ? subtitleParts.join(' • ')
        : 'Online Radio';

    return RepaintBoundary(
      child: Builder(
        builder: (context) {
          final (isCurrent, isPlaying) = context
              .select<PlaybackController, (bool, bool)>((c) {
                final cur = c.currentPlayable?.filePath == station.streamUrl;
                return (cur, cur && c.isPlaying);
              });

          return ListTile(
            leading: RadioLogoAvatar(
              faviconUrl: station.faviconUrl,
              size: 46.0,
              isCurrent: isCurrent,
              isPlaying: isPlaying,
            ),
            title: Text(
              station.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSavedTab) ...[
                  IconButton(
                    icon: Icon(
                      station.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: station.isFavorite
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    tooltip: station.isFavorite
                        ? strings.npUnlike
                        : strings.npLike,
                    onPressed: station.id != null
                        ? () => store.toggleRadioStationFavoriteInStore(
                            station.id!,
                          )
                        : null,
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (action) {
                      if (action == 'edit') {
                        onEdit();
                      } else if (action == 'delete' && station.id != null) {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit_outlined, size: 20),
                            const SizedBox(width: 12),
                            Text(strings.rdEditStation),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              strings.rdDeleteStation,
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  IconButton(
                    icon: Icon(
                      isSaved
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      color: isSaved
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    tooltip: isSaved
                        ? strings.rdAlreadyInLibrary
                        : strings.rdSaveToLibrary,
                    onPressed: isSaved
                        ? null
                        : () => _saveStation(context, station, radioController, strings),
                  ),
                ],
              ],
            ),
            onTap: onTap,
          );
        },
      ),
    );
  }
}

/// Grid card displaying a radio station logo, title, genre/country metadata,
/// and quick favorite or bookmark toggle.
class RadioStationGridCard extends StatelessWidget {
  /// Station data rendered in this card.
  final RadioStation station;

  /// Localized strings used for snackbar feedback.
  final AppStringKey strings;

  /// Library store used for toggling saved station favorites.
  final LibraryStore store;

  /// Radio controller used to check and save discovered stations.
  final RadioController radioController;

  /// Whether this card is rendered inside the Saved Stations tab.
  final bool isSavedTab;

  /// Invoked when the card is tapped to play [station].
  final VoidCallback onTap;

  /// Creates a [RadioStationGridCard].
  const RadioStationGridCard({
    super.key,
    required this.station,
    required this.strings,
    required this.store,
    required this.radioController,
    required this.isSavedTab,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSaved = radioController.isStationSaved(station);

    return RepaintBoundary(
      child: Builder(
        builder: (context) {
          final (isCurrent, isPlaying) = context
              .select<PlaybackController, (bool, bool)>((c) {
                final cur = c.currentPlayable?.filePath == station.streamUrl;
                return (cur, cur && c.isPlaying);
              });

          return Card(
            elevation: isCurrent ? 3 : 0,
            color: isCurrent
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: isCurrent
                  ? BorderSide(color: colorScheme.primary, width: 1.5)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: RadioLogoAvatar(
                            faviconUrl: station.faviconUrl,
                            size: 130.0,
                            isCurrent: isCurrent,
                            isPlaying: isPlaying,
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w600,
                        fontSize: 13.5,
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            station.genre?.isNotEmpty == true
                                ? station.genre!
                                : (station.country?.isNotEmpty == true
                                      ? station.country!
                                      : 'Radio'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (isSavedTab)
                          InkResponse(
                            onTap: station.id != null
                                ? () => store.toggleRadioStationFavoriteInStore(
                                    station.id!,
                                  )
                                : null,
                            child: Icon(
                              station.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                              color: station.isFavorite
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          InkResponse(
                            onTap: isSaved
                                ? null
                                : () => _saveStation(
                                    context,
                                    station,
                                    radioController,
                                    strings,
                                  ),
                            child: Icon(
                              isSaved
                                  ? Icons.bookmark_added_rounded
                                  : Icons.bookmark_add_outlined,
                              size: 18,
                              color: isSaved
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _saveStation(
  BuildContext context,
  RadioStation station,
  RadioController radioController,
  AppStringKey strings,
) async {
  await radioController.saveToLibrary(station);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${station.name}: ${strings.rdSavedToLibrary}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
