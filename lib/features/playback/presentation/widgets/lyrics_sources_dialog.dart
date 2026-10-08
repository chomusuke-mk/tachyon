import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

enum LyricsDialogTab { sources, translation }

/// Modal dialog for configuring active lyrics sources (Local, lrclib.net, lyrics.ovh)
/// and lyrics translation (source language, target language).
class LyricsSourcesDialog extends StatefulWidget {
  const LyricsSourcesDialog({super.key});

  /// Displays the [LyricsSourcesDialog] as an adaptive Material 3 dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const LyricsSourcesDialog(),
    );
  }

  @override
  State<LyricsSourcesDialog> createState() => _LyricsSourcesDialogState();
}

class _LyricsSourcesDialogState extends State<LyricsSourcesDialog> {
  LyricsDialogTab _selectedTab = LyricsDialogTab.sources;
  late bool _enableLocal;
  late bool _enableLrclib;
  late bool _enableLyricsOvh;

  @override
  void initState() {
    super.initState();
    final controller = context.read<LyricsController>();
    _enableLocal = controller.enableLocalSources;
    _enableLrclib = controller.enableLrclib;
    _enableLyricsOvh = controller.enableLyricsOvh;
  }

  void _updateLocal(bool value) {
    // Invariant: At least one source must remain enabled
    if (!value && !_enableLrclib && !_enableLyricsOvh) return;
    setState(() => _enableLocal = value);
    context.read<LyricsController>().setSourcesConfig(local: value);
  }

  void _updateLrclib(bool value) {
    if (!value && !_enableLocal && !_enableLyricsOvh) return;
    setState(() => _enableLrclib = value);
    context.read<LyricsController>().setSourcesConfig(lrclib: value);
  }

  void _updateLyricsOvh(bool value) {
    if (!value && !_enableLocal && !_enableLrclib) return;
    setState(() => _enableLyricsOvh = value);
    context.read<LyricsController>().setSourcesConfig(lyricsOvh: value);
  }

  Future<void> _handleReSearch() async {
    final controller = context.read<LyricsController>();
    controller.setSourcesConfig(
      local: _enableLocal,
      lrclib: _enableLrclib,
      lyricsOvh: _enableLyricsOvh,
    );
    Navigator.of(context).pop();
    await controller.forceReSearch();
  }

  Future<void> _showLanguagePicker({
    required BuildContext context,
    required String title,
    required String currentCode,
    required bool includeAuto,
    bool includeDefault = false,
    required ValueChanged<String> onSelected,
  }) async {
    final strings = context.read<LocaleController>().localeStrings;
    var searchQuery = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            final query = searchQuery.toLowerCase().trim();

            final filteredEntries = languagesEndonyms.entries.where((e) {
              if (query.isEmpty) return true;
              return e.key.toLowerCase().contains(query) ||
                  e.value.toLowerCase().contains(query);
            }).toList();

            final showAuto =
                includeAuto &&
                (query.isEmpty ||
                    'autodetect'.contains(query) ||
                    strings.npLyricsLangAuto.toLowerCase().contains(query));

            final showDefault =
                includeDefault &&
                (query.isEmpty ||
                    'default'.contains(query) ||
                    strings.sTranslationLangDefault.toLowerCase().contains(query));

            final hasSpecialItem = showAuto || showDefault;
            final itemCount = filteredEntries.length + (hasSpecialItem ? 1 : 0);

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: strings.sLanguageSearchHint,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (hasSpecialItem && index == 0) {
                            if (showDefault) {
                              final isSelected = currentCode == 'defaultOption';
                              final currentLocale =
                                  context.read<LocaleController>().currentLocaleCode;
                              final resolvedName =
                                  languagesEndonyms[currentLocale] ??
                                  currentLocale;
                              return ListTile(
                                leading: Icon(
                                  Icons.auto_awesome_rounded,
                                  color: isSelected ? colorScheme.primary : null,
                                ),
                                title: Text(
                                  strings.sTranslationLangDefault,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(resolvedName),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: colorScheme.primary,
                                      )
                                    : null,
                                onTap: () {
                                  onSelected('defaultOption');
                                  Navigator.of(dialogCtx).pop();
                                },
                              );
                            }
                            final isSelected = currentCode == 'autodetect';
                            return ListTile(
                              leading: Icon(
                                Icons.auto_awesome_rounded,
                                color: isSelected ? colorScheme.primary : null,
                              ),
                              title: Text(
                                strings.npLyricsLangAuto,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: colorScheme.primary,
                                    )
                                  : null,
                              onTap: () {
                                onSelected('autodetect');
                                Navigator.of(dialogCtx).pop();
                              },
                            );
                          }

                          final itemIndex = hasSpecialItem ? index - 1 : index;
                          final item = filteredEntries[itemIndex];
                          final isSelected = currentCode == item.key;

                          return ListTile(
                            title: Text(
                              item.value,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(item.key),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: colorScheme.primary,
                                  )
                                : null,
                            onTap: () {
                              onSelected(item.key);
                              Navigator.of(dialogCtx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(strings.npLyricsSourcesCloseBtn),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeController = context.watch<LocaleController>();
    final strings = localeController.localeStrings;
    final currentLocale = localeController.currentLocaleCode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsController>();
    final lyricsController = context.watch<LyricsController>();

    final hasAnySource = _enableLocal || _enableLrclib || _enableLyricsOvh;

    final sourceCode = settings.lyricsTranslationSourceLang;
    final sourceLangDisplay = (sourceCode == 'autodetect')
        ? strings.npLyricsLangAuto
        : (languagesEndonyms[sourceCode] ?? sourceCode);

    final targetCode = settings.lyricsTranslationTargetLang;
    final isTargetDefault = targetCode == 'defaultOption';
    final effectiveTarget = isTargetDefault ? currentLocale : targetCode;
    final targetLangDisplay = isTargetDefault
        ? '${strings.sTranslationLangDefault} (${languagesEndonyms[effectiveTarget] ?? effectiveTarget})'
        : (languagesEndonyms[targetCode] ?? targetCode);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      title: SizedBox(
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SegmentedButton<LyricsDialogTab>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment<LyricsDialogTab>(
                value: LyricsDialogTab.sources,
                label: Text(strings.npLyricsTabSources),
                icon: const Icon(Icons.tune_rounded, size: 18),
              ),
              ButtonSegment<LyricsDialogTab>(
                value: LyricsDialogTab.translation,
                label: Text(strings.npLyricsTabTranslation),
                icon: const Icon(Icons.translate_rounded, size: 18),
              ),
            ],
            selected: {_selectedTab},
            onSelectionChanged: (newSelection) {
              setState(() => _selectedTab = newSelection.first);
            },
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedTab == LyricsDialogTab.sources
                ? Column(
                    key: const ValueKey('sources_tab'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Local Sources Switch
                      SwitchListTile.adaptive(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        secondary: Icon(
                          Icons.audio_file_outlined,
                          size: 22,
                          color: _enableLocal
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          strings.npLyricsSourceLocal,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          strings.npLyricsSourceLocalDesc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _enableLocal,
                        onChanged: _updateLocal,
                      ),
                      const Divider(height: 8, indent: 8, endIndent: 8),

                      // 2. Primary Remote API (lrclib.net) Switch
                      SwitchListTile.adaptive(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        secondary: Icon(
                          Icons.cloud_sync_outlined,
                          size: 22,
                          color: _enableLrclib
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          strings.npLyricsSourceLrclib,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          strings.npLyricsSourceLrclibDesc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _enableLrclib,
                        onChanged: _updateLrclib,
                      ),
                      const Divider(height: 8, indent: 8, endIndent: 8),

                      // 3. Fallback Remote API (lyrics.ovh) Switch
                      SwitchListTile.adaptive(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        secondary: Icon(
                          Icons.cloud_outlined,
                          size: 22,
                          color: _enableLyricsOvh
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          strings.npLyricsSourceOvh,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          strings.npLyricsSourceOvhDesc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _enableLyricsOvh,
                        onChanged: _updateLyricsOvh,
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('translation_tab'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      // Source Language Tile
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        tileColor: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: Icon(
                          Icons.language_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          strings.npLyricsSourceLang,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          sourceLangDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_drop_down_rounded),
                        onTap: () => _showLanguagePicker(
                          context: context,
                          title: strings.npLyricsSourceLang,
                          currentCode: sourceCode,
                          includeAuto: true,
                          includeDefault: false,
                          onSelected: (code) async {
                            await settings.setLyricsTranslationSourceLang(code);
                            if (lyricsController.isTranslated &&
                                lyricsController.hasLyrics) {
                              final effectiveTarget = (targetCode == 'defaultOption')
                                  ? currentLocale
                                  : targetCode;
                              await lyricsController.translateLyrics(
                                sourceLanguage: code,
                                targetLanguage: effectiveTarget,
                                force: true,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Target Language Tile
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        tileColor: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: Icon(
                          Icons.translate_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          strings.npLyricsTargetLang,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          targetLangDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_drop_down_rounded),
                        onTap: () => _showLanguagePicker(
                          context: context,
                          title: strings.npLyricsTargetLang,
                          currentCode: targetCode,
                          includeAuto: false,
                          includeDefault: true,
                          onSelected: (code) async {
                            await settings.setLyricsTranslationTargetLang(code);
                            if (lyricsController.isTranslated &&
                                lyricsController.hasLyrics) {
                              final effectiveTarget = (code == 'defaultOption')
                                  ? currentLocale
                                  : code;
                              await lyricsController.translateLyrics(
                                targetLanguage: effectiveTarget,
                                force: true,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionsOverflowButtonSpacing: 8,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.npLyricsSourcesCloseBtn),
        ),
        if (_selectedTab == LyricsDialogTab.sources)
          FilledButton.icon(
            onPressed: hasAnySource ? _handleReSearch : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(strings.npLyricsSourcesResearchBtn),
          )
        else if (lyricsController.hasLyrics)
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              final effectiveTarget = (targetCode == 'defaultOption')
                  ? currentLocale
                  : targetCode;
              await lyricsController.translateLyrics(
                targetLanguage: effectiveTarget,
                force: true,
              );
            },
            icon: const Icon(Icons.translate_rounded, size: 18),
            label: Text(strings.npLyricsRetranslateBtn),
          ),
      ],
    );
  }
}
