import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

/// Screen displaying and managing online radio stations and continuous HLS livestreams.
class RadiosScreen extends StatelessWidget {
  const RadiosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;
    final store = context.watch<LibraryStore>();
    final playback = context.watch<PlaybackController>();
    final stations = store.radioStations;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.rdTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: strings.rdAddStation,
            onPressed: () => _showAddEditStationDialog(context, null, strings),
          ),
        ],
      ),
      body: stations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.radio_rounded,
                      size: 72,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.rdEmptyTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.rdEmptySubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () =>
                          _showAddEditStationDialog(context, null, strings),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(strings.rdAddStation),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final station = stations[index];
                final isCurrent =
                    playback.currentPlayable?.filePath == station.streamUrl;
                final isPlaying = isCurrent && playback.isPlaying;

                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Center(
                      child: Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.radio_rounded,
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
                  ),
                  title: Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.w600,
                      color: isCurrent
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    station.genre?.isNotEmpty == true
                        ? station.genre!
                        : (station.country?.isNotEmpty == true
                            ? station.country!
                            : 'Online Radio'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          station.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: station.isFavorite
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
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
                            _showAddEditStationDialog(context, station, strings);
                          } else if (action == 'delete' && station.id != null) {
                            _confirmDelete(context, station, strings, store);
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
                    ],
                  ),
                  onTap: () {
                    playback.playTrack(station);
                  },
                );
              },
            ),
    );
  }

  static Future<void> _showAddEditStationDialog(
    BuildContext context,
    RadioStation? existingStation,
    AppStringKey strings,
  ) async {
    final nameController =
        TextEditingController(text: existingStation?.name ?? '');
    final urlController =
        TextEditingController(text: existingStation?.streamUrl ?? '');
    final genreController =
        TextEditingController(text: existingStation?.genre ?? '');
    final countryController =
        TextEditingController(text: existingStation?.country ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          existingStation == null
              ? strings.rdAddStation
              : strings.rdEditStation,
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: strings.rdStationName,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return strings.rdStationName;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: strings.rdStreamUrl,
                    hintText: 'https://...',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return strings.rdStreamUrl;
                    }
                    final uri = Uri.tryParse(val.trim());
                    if (uri == null || !uri.hasScheme) {
                      return strings.rdStreamUrl;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: genreController,
                  decoration: InputDecoration(
                    labelText: strings.rdGenre,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: countryController,
                  decoration: InputDecoration(
                    labelText: strings.rdCountry,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(strings.rdCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: Text(strings.rdSave),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final store = context.read<LibraryStore>();
      final station = RadioStation(
        id: existingStation?.id,
        name: nameController.text.trim(),
        streamUrl: urlController.text.trim(),
        genre: genreController.text.trim().isNotEmpty
            ? genreController.text.trim()
            : null,
        country: countryController.text.trim().isNotEmpty
            ? countryController.text.trim()
            : null,
        isFavorite: existingStation?.isFavorite ?? false,
        createdAt: existingStation?.createdAt ?? DateTime.now(),
      );
      await store.saveRadioStationInStore(station);
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    RadioStation station,
    AppStringKey strings,
    LibraryStore store,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(strings.rdDeleteStation),
        content: Text('${strings.rdDeleteConfirm}\n\n"${station.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(strings.rdCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(strings.rdDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && station.id != null) {
      await store.deleteRadioStationInStore(station.id!);
    }
  }
}
