import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/shared/utils/file_picker_service.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';
import 'package:tachyon/shared/widgets/app_icon.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

import 'settings_controller.dart';
import 'widgets/language_picker_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static bool _isRemoteUrl(String pathOrUrl) {
    final lower = pathOrUrl.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static String _displaySourceName(String pathOrUrl) {
    final clean = pathOrUrl.trim();
    if (_isRemoteUrl(clean)) {
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

  void _showAddFolderDialog(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final strings = context.read<LocaleController>().localeStrings;

    final picked = await FilePickerService.pickDirectory(
      dialogTitle: strings.sAddFolderTitle,
    );
    if (picked == null) {
      return;
    }

    final added = await settings.addMusicDirectory(picked);
    if (!added && context.mounted) {
      ToastUtils.showError(strings.sFolderErrorInvalid);
    } else if (added && context.mounted) {
      context.read<LibraryController>().scanDirectories();
    }
  }

  Future<void> _showAddFileDialog(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    final strings = context.read<LocaleController>().localeStrings;
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
      builder: (dialogContext) => const _ManageMusicFilesDialog(),
    );
  }

  Widget _buildFolderSourceTile({
    required BuildContext context,
    required String dir,
    required SettingsController settings,
    required AppStringKey strings,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            color: colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dir,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 20,
            ),
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

  Widget _buildFileSourceTile({
    required BuildContext context,
    required String fileOrUrl,
    required SettingsController settings,
    required AppStringKey strings,
    required ColorScheme colorScheme,
  }) {
    final isUrl = _isRemoteUrl(fileOrUrl);
    final displayName = _displaySourceName(fileOrUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: 0.25,
          ),
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
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 20,
            ),
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
    final localeController = context.watch<LocaleController>();
    final strings = localeController.localeStrings;
    final currentLocale = localeController.currentLocaleCode;
    final settings = context.watch<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [if (!isDesktop) AppIcon(), Text(strings.sTitle)]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Music Sources (Folders + Individual Files / Links)
          _buildSectionHeader(context, strings.sMusicFolders),
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
                          context: context,
                          dir: settings.musicDirectories[index],
                          settings: settings,
                          strings: strings,
                          colorScheme: colorScheme,
                        ),
                      ),
                    )
                  else
                    ...settings.musicDirectories.map(
                      (dir) => _buildFolderSourceTile(
                        context: context,
                        dir: dir,
                        settings: settings,
                        strings: strings,
                        colorScheme: colorScheme,
                      ),
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
                            strings.sViewAllFilesFormatted(
                              settings.musicFiles.length,
                            ),
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
                          (fileOrUrl) => _buildFileSourceTile(
                            context: context,
                            fileOrUrl: fileOrUrl,
                            settings: settings,
                            strings: strings,
                            colorScheme: colorScheme,
                          ),
                        ),
                    if (settings.musicFiles.length > 3)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('btn_more_music_files_modal'),
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: Text(
                            strings.sViewAllFilesFormatted(
                              settings.musicFiles.length,
                            ),
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
            ),
          ),
          const SizedBox(height: 20),

          // Section: Audio Playback
          _buildSectionHeader(context, strings.sAudioSection),
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
              child: Column(
                children: [
                  SettingRow(
                    title: strings.npCrossfadeAuto,
                    description: '${settings.crossfadeDuration}s',
                    type: ControllerType.slider,
                    child: Slider(
                      value: settings.crossfadeDuration.toDouble().clamp(
                        AppDefaults.crossfadeMinDuration.toDouble(),
                        AppDefaults.crossfadeMaxDuration.toDouble(),
                      ),
                      min: AppDefaults.crossfadeMinDuration.toDouble(),
                      max: AppDefaults.crossfadeMaxDuration.toDouble(),
                      divisions:
                          AppDefaults.crossfadeMaxDuration -
                          AppDefaults.crossfadeMinDuration,
                      label: '${settings.crossfadeDuration}s',
                      onChanged: (val) =>
                          settings.setCrossfadeDuration(val.round()),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.npCrossfadeManual,
                    description: '${settings.crossfadeManualDuration}s',
                    type: ControllerType.slider,
                    child: Slider(
                      value: settings.crossfadeManualDuration.toDouble().clamp(
                        AppDefaults.crossfadeManualMinDuration.toDouble(),
                        AppDefaults.crossfadeManualMaxDuration.toDouble(),
                      ),
                      min: AppDefaults.crossfadeManualMinDuration.toDouble(),
                      max: AppDefaults.crossfadeManualMaxDuration.toDouble(),
                      divisions:
                          AppDefaults.crossfadeManualMaxDuration -
                          AppDefaults.crossfadeManualMinDuration,
                      label: '${settings.crossfadeManualDuration}s',
                      onChanged: (val) =>
                          settings.setCrossfadeManualDuration(val.round()),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCrossfadeCurve,
                    description: strings.sCrossfadeCurveDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SegmentedButton<CrossfadeCurve>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment<CrossfadeCurve>(
                            value: CrossfadeCurve.equalPower,
                            label: Text(
                              strings.sCrossfadeCurveEqualPower,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          ButtonSegment<CrossfadeCurve>(
                            value: CrossfadeCurve.linear,
                            label: Text(
                              strings.sCrossfadeCurveLinear,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        selected: {settings.crossfadeCurve},
                        onSelectionChanged: (newSelection) =>
                            settings.setCrossfadeCurve(newSelection.first),
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sReplayGainMode,
                    description: strings.sReplayGainModeDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.volumeNormalization,
                      onChanged: (val) => settings.setVolumeNormalization(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sSkipSilence,
                    description: strings.sSkipSilenceDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.skipSilence,
                      onChanged: (val) => settings.setSkipSilence(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sLimiter,
                    description: strings.sLimiterDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.limiterEnabled,
                      onChanged: (val) => settings.setLimiter(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sMonoAudio,
                    description: strings.sMonoAudioDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.mono,
                      onChanged: (val) => settings.setMono(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sGaplessPlayback,
                    description: strings.sGaplessPlaybackDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(value: true, onChanged: null),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sPauseOnDeviceChange,
                    description: strings.sPauseOnDeviceChangeDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.pauseOnDeviceChange,
                      onChanged: (val) => settings.setPauseOnDeviceChange(val),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Appearance
          _buildSectionHeader(context, strings.sAppearanceSection),
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
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sThemeMode,
                    description: strings.sThemeModeDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final showLabels = constraints.maxWidth >= 360;
                          return SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.system,
                                icon: const Icon(
                                  Icons.brightness_auto_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeSystem)
                                    : null,
                                tooltip: showLabels
                                    ? null
                                    : strings.sThemeSystem,
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.light,
                                icon: const Icon(
                                  Icons.light_mode_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeLight)
                                    : null,
                                tooltip: showLabels
                                    ? null
                                    : strings.sThemeLight,
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                icon: const Icon(
                                  Icons.dark_mode_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeDark)
                                    : null,
                                tooltip: showLabels ? null : strings.sThemeDark,
                              ),
                            ],
                            selected: {settings.themeMode},
                            onSelectionChanged: (newSelection) {
                              settings.setThemeMode(newSelection.first);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sThemeOled,
                    description: strings.sThemeOledDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.isOledMode,
                      onChanged: settings.themeMode == ThemeMode.light
                          ? null
                          : (val) => settings.setIsOledMode(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sAccentColor,
                    description: strings.sAccentColorDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Wrap(
                        key: const Key('accent_colors_wrap'),
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final color
                              in TachyonColors.predefinedAccentColors)
                            _buildColorCircle(
                              context: context,
                              color: color,
                              isSelected:
                                  settings.accentColorValue == color.toARGB32(),
                              onTap: () =>
                                  settings.setAccentColor(color.toARGB32()),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCustomBackground,
                    description: strings.sCustomBackgroundDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (settings.customBackgroundPath == null) ...[
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.image_outlined),
                              label: Text(strings.sSelectBackgroundImage),
                              onPressed: () async {
                                final picked =
                                    await FilePickerService.pickImage(
                                      dialogTitle:
                                          strings.sSelectBackgroundImage,
                                    );
                                if (picked != null) {
                                  final success = await settings
                                      .setCustomBackground(picked);
                                  if (!success && context.mounted) {
                                    ToastUtils.showError(
                                      strings.sCustomBackgroundFileError,
                                    );
                                  }
                                }
                              },
                            ),
                          ] else ...[
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child:
                                        PersistentBinaryStorage.buildLocalOrOpfsImage(
                                          settings.customBackgroundPath!,
                                          width: 52,
                                          height: 52,
                                          cacheWidth: 104,
                                          fit: BoxFit.cover,
                                          fallback: const Icon(
                                            Icons.broken_image_rounded,
                                            size: 32,
                                          ),
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: Text(strings.sChangeBackgroundImage),
                                  onPressed: () async {
                                    final picked =
                                        await FilePickerService.pickImage(
                                          dialogTitle:
                                              strings.sChangeBackgroundImage,
                                        );
                                    if (picked != null) {
                                      await settings.setCustomBackground(
                                        picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  tooltip: strings.sRemoveBackgroundImage,
                                  color: colorScheme.error,
                                  onPressed: () =>
                                      settings.setCustomBackground(null),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (settings.customBackgroundPath != null) ...[
                    const Divider(),
                    SettingRow(
                      title: strings.sBackgroundBlur,
                      description: '${settings.backgroundBlurSigma.round()} px',
                      type: ControllerType.slider,
                      child: Slider(
                        value: settings.backgroundBlurSigma,
                        min: 0.0,
                        max: 50.0,
                        divisions: 50,
                        label: '${settings.backgroundBlurSigma.round()} px',
                        onChanged: (val) =>
                            settings.setBackgroundBlurSigma(val),
                      ),
                    ),
                    const Divider(),
                    SettingRow(
                      title: strings.sBackgroundDim,
                      description:
                          '${(settings.backgroundDimOpacity * 100).round()}%',
                      type: ControllerType.slider,
                      child: Slider(
                        value: settings.backgroundDimOpacity,
                        min: 0.20,
                        max: 0.95,
                        divisions: 15,
                        label:
                            '${(settings.backgroundDimOpacity * 100).round()}%',
                        onChanged: (val) =>
                            settings.setBackgroundDimOpacity(val),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Language
          _buildSectionHeader(context, strings.sLanguageSection),
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
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sLanguage,
                    description: strings.sLanguageDesc,
                    type: ControllerType.dropdown,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => LanguagePickerDialog.show(
                        context,
                        title: strings.sLanguage,
                        currentSelectedValue: settings.appLanguage,
                        strings: strings,
                        onSelected: settings.setAppLanguage,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                (settings.appLanguage == 'defaultOption')
                                    ? '${strings.sTranslationLangDefault} (${languagesEndonyms[currentLocale] ?? currentLocale})'
                                    : (languagesEndonyms[settings
                                              .appLanguage] ??
                                          settings.appLanguage),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sTranslationTargetLang,
                    description: strings.sTranslationTargetLangDesc,
                    type: ControllerType.dropdown,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => LanguagePickerDialog.show(
                        context,
                        title: strings.sTranslationTargetLang,
                        currentSelectedValue:
                            settings.lyricsTranslationTargetLang,
                        strings: strings,
                        onSelected: settings.setLyricsTranslationTargetLang,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                settings.lyricsTranslationTargetLang ==
                                        'defaultOption'
                                    ? '${strings.sTranslationLangDefault} (${languagesEndonyms[currentLocale] ?? currentLocale})'
                                    : (languagesEndonyms[settings
                                              .lyricsTranslationTargetLang] ??
                                          settings.lyricsTranslationTargetLang),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: About & Maintenance
          _buildSectionHeader(context, strings.sAboutSection),
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
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.sAppVersion),
                    trailing: const Text(
                      '0.1.0',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildColorCircle({
    required BuildContext context,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isLightColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    final checkColor = isLightColor ? Colors.black : Colors.white;

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Center(
                  child: Icon(Icons.check_rounded, size: 20, color: checkColor),
                )
              : null,
        ),
      ),
    );
  }
}

enum _MusicFilesFilter { all, local, links }

class _ManageMusicFilesDialog extends StatefulWidget {
  const _ManageMusicFilesDialog();

  @override
  State<_ManageMusicFilesDialog> createState() =>
      _ManageMusicFilesDialogState();
}

class _ManageMusicFilesDialogState extends State<_ManageMusicFilesDialog> {
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
      final isUrl = SettingsScreen._isRemoteUrl(item);
      if (_filter == _MusicFilesFilter.local && isUrl) return false;
      if (_filter == _MusicFilesFilter.links && !isUrl) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return item.toLowerCase().contains(q) ||
          SettingsScreen._displaySourceName(item).toLowerCase().contains(q);
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
                          final isUrl = SettingsScreen._isRemoteUrl(item);
                          final displayName =
                              SettingsScreen._displaySourceName(item);
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
