import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/platform/file_picker_service.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/widgets/manage_music_files_dialog.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';

/// Returns `true` if [pathOrUrl] points to an HTTP or HTTPS audio stream/file.
bool isRemoteAudioSource(String pathOrUrl) {
  final lower = pathOrUrl.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// Formats a human-readable display filename for a local path or remote audio
/// URL, decoding percent-encoded URI segments safely.
String formatAudioSourceDisplayName(String pathOrUrl) {
  final clean = pathOrUrl.trim();
  if (isRemoteAudioSource(clean)) {
    final uri = Uri.tryParse(clean);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (last.isNotEmpty) return MetadataUtils.safeDecodePercent(last);
    }
    return MetadataUtils.safeDecodePercent(clean);
  }
  final base = p.basename(MetadataUtils.safeDecodePercent(clean));
  return base.isNotEmpty ? base : clean;
}

/// Shared section header + outlined card shell used across settings groups.
class SettingsSectionCard extends StatelessWidget {
  /// Section header title rendered above the card.
  final String title;

  /// Interior card widget tree.
  final Widget child;

  /// Creates a [SettingsSectionCard].
  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Settings section managing configured library directories, individual local
/// audio files, remote URLs, and library rescanning.
class MusicSourcesSection extends StatelessWidget {
  /// Active settings state supplying directories and individual music files.
  final SettingsController settings;

  /// Localized labels and messages.
  final AppStringKey strings;

  /// Creates a [MusicSourcesSection].
  const MusicSourcesSection({
    super.key,
    required this.settings,
    required this.strings,
  });

  Future<void> _showAddFolderDialog(BuildContext context) async {
    final library = context.read<LibraryController>();
    final picked = await FilePickerService.pickDirectory(
      dialogTitle: strings.sAddFolderTitle,
    );
    if (picked == null) return;

    final added = await settings.addMusicDirectory(picked);
    if (!added && context.mounted) {
      ToastUtils.showError(strings.sFolderErrorInvalid);
    } else if (added && context.mounted) {
      library.scanDirectories();
    }
  }

  Future<void> _showAddFileDialog(BuildContext context) async {
    final library = context.read<LibraryController>();
    final textController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.sAddFileTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('btn_pick_local_audio_files'),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(strings.sAddFileLocalOption),
                    onPressed: () async {
                      final picked = await FilePickerService.pickAudioFiles(
                        dialogTitle: strings.sAddFileTitle,
                        allowedExtensions:
                            AppDefaults.supportedAudioExtensions.toList(),
                      );
                      if (picked.isEmpty) return;
                      final count = await settings.addMusicFiles(picked);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (count > 0) {
                        library.scanDirectories();
                      } else if (context.mounted) {
                        ToastUtils.showError(strings.sFileErrorInvalid);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('input_music_file_or_url'),
                    controller: textController,
                    decoration: InputDecoration(
                      labelText: strings.sAddFileUrlLabel,
                      hintText: strings.sAddFileUrlHint,
                      prefixIcon: const Icon(Icons.link_rounded),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    autofocus: true,
                    onSubmitted: (value) async {
                      final clean = value.trim();
                      if (clean.isEmpty) return;
                      final added = await settings.addMusicFile(clean);
                      if (!added) {
                        ToastUtils.showError(strings.sFileErrorInvalid);
                        return;
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      library.scanDirectories();
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.sCancel),
            ),
            FilledButton(
              key: const Key('btn_confirm_add_music_file'),
              onPressed: () async {
                final clean = textController.text.trim();
                if (clean.isEmpty) {
                  ToastUtils.showError(strings.sFileErrorInvalid);
                  return;
                }
                final added = await settings.addMusicFile(clean);
                if (!added) {
                  ToastUtils.showError(strings.sFileErrorInvalid);
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                library.scanDirectories();
              },
              child: Text(strings.sAdd),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManageMusicFilesModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const ManageMusicFilesDialog(),
    );
  }

  Widget _buildFolderSourceTile(
    BuildContext context,
    String dir,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dir,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: strings.sRemoveFolder,
            onPressed: () {
              settings.removeMusicDirectory(dir);
              context.read<LibraryController>().scanDirectories();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileSourceTile(
    BuildContext context,
    String fileOrUrl,
    ColorScheme colorScheme,
  ) {
    final isUrl = isRemoteAudioSource(fileOrUrl);
    final displayName = formatAudioSourceDisplayName(fileOrUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUrl ? Icons.link_rounded : Icons.audiotrack_rounded,
            color: isUrl ? colorScheme.tertiary : colorScheme.secondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                if (displayName != fileOrUrl)
                  Text(
                    fileOrUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: strings.sRemoveFile,
            onPressed: () {
              settings.removeMusicFile(fileOrUrl);
              context.read<LibraryController>().scanDirectories();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      title: strings.sMusicFolders,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.sMusicFoldersDesc,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (settings.musicFiles.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${strings.sMusicFoldersHeader} (${settings.musicDirectories.length})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (settings.musicDirectories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                strings.sNoFoldersYet,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.outline,
                ),
              ),
            )
          else if (settings.musicDirectories.length > 4)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: settings.musicDirectories.length,
                itemBuilder: (context, index) => _buildFolderSourceTile(
                  context,
                  settings.musicDirectories[index],
                  colorScheme,
                ),
              ),
            )
          else
            ...settings.musicDirectories.map(
              (dir) => _buildFolderSourceTile(context, dir, colorScheme),
            ),
          if (settings.musicFiles.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(
                  Icons.library_music_outlined,
                  size: 16,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${strings.sMusicFilesHeader} (${settings.musicFiles.length})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  key: const Key('btn_view_all_music_files'),
                  icon: const Icon(Icons.list_alt_rounded, size: 16),
                  label: Text(
                    strings.sViewAllFilesFormatted(settings.musicFiles.length),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _showManageMusicFilesModal(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...settings.musicFiles.take(3).map(
                  (fileOrUrl) =>
                      _buildFileSourceTile(context, fileOrUrl, colorScheme),
                ),
            if (settings.musicFiles.length > 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('btn_more_music_files_modal'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(
                    strings.sViewAllFilesFormatted(settings.musicFiles.length),
                  ),
                  onPressed: () => _showManageMusicFilesModal(context),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.start,
            children: [
              FilledButton.tonalIcon(
                key: const Key('btn_add_music_folder'),
                icon: const Icon(Icons.add_rounded),
                label: Text(strings.sAddFolder),
                onPressed: () => _showAddFolderDialog(context),
              ),
              FilledButton.tonalIcon(
                key: const Key('btn_add_music_file'),
                icon: const Icon(Icons.note_add_outlined),
                label: Text(strings.sAddFile),
                onPressed: () => _showAddFileDialog(context),
              ),
              FilledButton.icon(
                key: const Key('btn_rescan_library'),
                icon: const Icon(Icons.sync_rounded),
                label: Text(strings.sRescanLibrary),
                onPressed: () {
                  context.read<LibraryController>().scanDirectories();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
