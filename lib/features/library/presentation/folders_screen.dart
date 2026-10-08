import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/shared/utils/file_picker_service.dart';

import 'library_controller.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
    final playback = context.read<PlaybackController>();
    final settings = context.watch<SettingsController>();

    final musicDirs = settings.musicDirectories;
    final isAtRoot = library.isAtFolderRoot;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.fTitle),
        actions: [
          IconButton(
            icon: Icon(
              library.isFolderGridView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            tooltip: library.isFolderGridView
                ? strings.fViewAsList
                : strings.fViewAsGrid,
            onPressed: library.toggleFolderGridView,
          ),
          if (!isAtRoot)
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: strings.fNavigateUp,
              onPressed: library.navigateUpFolder,
            ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: strings.fRescanAll,
            onPressed: library.isScanning ? null : library.scanDirectories,
          ),
        ],
      ),
      body: isAtRoot
          ? _buildRootView(context, strings, library, settings, musicDirs)
          : _buildFolderView(context, strings, library, playback, currentTrack),
    );
  }

  Widget _buildRootView(
    BuildContext context,
    AppStringKey strings,
    LibraryController library,
    SettingsController settings,
    List<String> musicDirs,
  ) {
    if (musicDirs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              strings.fEmptyFolder,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              strings.sBrowseFoldersDesc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.sAddFolder),
              onPressed: () async {
                final picked = await FilePickerService.pickDirectory(
                  dialogTitle: strings.sAddFolderTitle,
                );
                if (picked != null) {
                  final added = await settings.addMusicDirectory(picked);
                  if (context.mounted) {
                    if (!added) {
                      ToastUtils.showError(strings.sFolderErrorInvalid);
                    } else {
                      context.read<LibraryController>().scanDirectories();
                    }
                  }
                }
              },
            ),
          ],
        ),
      );
    }

    if (library.isFolderGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemCount: musicDirs.length,
        itemBuilder: (context, index) {
          final dirPath = musicDirs[index];
          return Card(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => library.navigateToFolder(dirPath),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_special_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.basename(dirPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dirPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: musicDirs.length,
      itemBuilder: (context, index) {
        final dirPath = musicDirs[index];
        return ListTile(
          leading: const Icon(Icons.folder_special_rounded),
          title: Text(p.basename(dirPath)),
          subtitle: Text(dirPath),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => library.navigateToFolder(dirPath),
        );
      },
    );
  }

  Widget _buildFolderView(
    BuildContext context,
    AppStringKey strings,
    LibraryController library,
    PlaybackController playback,
    Track? currentTrack,
  ) {
    final breadcrumbs = library.folderBreadcrumbs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Interactive Breadcrumbs header
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: library.resetFolderNavigation,
                  child: Row(
                    children: [
                      const Icon(Icons.home_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        strings.fBreadcrumbRoot,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
                for (int i = 0; i < breadcrumbs.length; i++) ...[
                  if (i == breadcrumbs.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        p.basename(breadcrumbs[i]),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  else
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => library.navigateToBreadcrumbIndex(i),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: Text(
                              p.basename(breadcrumbs[i]),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 16),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        // Folder contents with loader
        Expanded(
          child: library.isFolderLoading
              ? const Center(child: CircularProgressIndicator())
              : (library.currentFolderSubdirectories.isEmpty &&
                    library.currentFolderTracks.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        strings.fEmptyFolder,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    if (library.currentFolderSubdirectories.isNotEmpty)
                      if (library.isFolderGridView)
                        SliverPadding(
                          padding: const EdgeInsets.all(16.0),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 180,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final subDir =
                                    library.currentFolderSubdirectories[index];
                                return Card(
                                  elevation: 1,
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        library.navigateToFolder(subDir),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.folder_rounded,
                                            color: Colors.amber,
                                            size: 44,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            p.basename(subDir),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount:
                                  library.currentFolderSubdirectories.length,
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final subDir =
                                  library.currentFolderSubdirectories[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.folder_rounded,
                                  color: Colors.amber,
                                ),
                                title: Text(p.basename(subDir)),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => library.navigateToFolder(subDir),
                              );
                            },
                            childCount:
                                library.currentFolderSubdirectories.length,
                          ),
                        ),
                    if (library.currentFolderTracks.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final track = library.currentFolderTracks[index];
                          return TrackTile(
                            key: ValueKey(track.filePath),
                            track: track,
                            contextTracks: library.currentFolderTracks,
                          );
                        }, childCount: library.currentFolderTracks.length),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
