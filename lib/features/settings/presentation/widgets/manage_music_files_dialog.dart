import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/widgets/music_sources_section.dart';

enum _MusicFilesFilter { all, local, links }

/// Searchable and filterable modal dialog managing individual local audio
/// files and HTTP/HTTPS stream links added to the user library.
class ManageMusicFilesDialog extends StatefulWidget {
  /// Creates a [ManageMusicFilesDialog].
  const ManageMusicFilesDialog({super.key});

  @override
  State<ManageMusicFilesDialog> createState() => _ManageMusicFilesDialogState();
}

class _ManageMusicFilesDialogState extends State<ManageMusicFilesDialog> {
  final TextEditingController _searchController = TextEditingController();
  _MusicFilesFilter _filter = _MusicFilesFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final settings = context.watch<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;
    final allFiles = settings.musicFiles;

    final filtered = allFiles.where((item) {
      final isUrl = isRemoteAudioSource(item);
      if (_filter == _MusicFilesFilter.local && isUrl) return false;
      if (_filter == _MusicFilesFilter.links && !isUrl) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return item.toLowerCase().contains(q) ||
          formatAudioSourceDisplayName(item).toLowerCase().contains(q);
    }).toList();

    return Dialog(
      key: const Key('modal_manage_music_files'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.library_music_rounded,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${strings.sManageFilesTitle} (${allFiles.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('input_filter_music_files'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: strings.sSearchFilesHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (val) => setState(() => _query = val.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const Key('chip_filter_all_files'),
                    label: Text(strings.sFilterAll),
                    selected: _filter == _MusicFilesFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _MusicFilesFilter.all),
                  ),
                  ChoiceChip(
                    key: const Key('chip_filter_local_files'),
                    label: Text(strings.sFilterLocalFiles),
                    selected: _filter == _MusicFilesFilter.local,
                    onSelected: (_) =>
                        setState(() => _filter = _MusicFilesFilter.local),
                  ),
                  ChoiceChip(
                    key: const Key('chip_filter_link_files'),
                    label: Text(strings.sFilterLinks),
                    selected: _filter == _MusicFilesFilter.links,
                    onSelected: (_) =>
                        setState(() => _filter = _MusicFilesFilter.links),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          strings.sNoFilesYet,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: colorScheme.outline,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isUrl = isRemoteAudioSource(item);
                          final displayName = formatAudioSourceDisplayName(
                            item,
                          );
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            leading: Icon(
                              isUrl
                                  ? Icons.link_rounded
                                  : Icons.audiotrack_rounded,
                              color: isUrl
                                  ? colorScheme.tertiary
                                  : colorScheme.secondary,
                            ),
                            title: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: displayName != item
                                ? Text(
                                    item,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                              ),
                              tooltip: strings.sRemoveFile,
                              onPressed: () {
                                settings.removeMusicFile(item);
                                context
                                    .read<LibraryController>()
                                    .scanDirectories();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
