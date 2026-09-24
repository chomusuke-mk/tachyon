import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';

/// Modal dialog for configuring active lyrics sources (Local, lrclib.net, lyrics.ovh)
/// and initiating manual re-search.
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

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasAnySource = _enableLocal || _enableLrclib || _enableLyricsOvh;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 28),
      title: Text(
        strings.npLyricsSourcesTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Local Sources Switch
            SwitchListTile.adaptive(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              secondary: Icon(
                Icons.audio_file_outlined,
                color: _enableLocal ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              title: Text(
                strings.npLyricsSourceLocal,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                strings.npLyricsSourceLocalDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: _enableLocal,
              onChanged: _updateLocal,
            ),
            const Divider(height: 8, indent: 16, endIndent: 16),

            // 2. Primary Remote API (lrclib.net) Switch
            SwitchListTile.adaptive(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              secondary: Icon(
                Icons.cloud_sync_outlined,
                color: _enableLrclib ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              title: Text(
                strings.npLyricsSourceLrclib,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                strings.npLyricsSourceLrclibDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: _enableLrclib,
              onChanged: _updateLrclib,
            ),
            const Divider(height: 8, indent: 16, endIndent: 16),

            // 3. Fallback Remote API (lyrics.ovh) Switch
            SwitchListTile.adaptive(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              secondary: Icon(
                Icons.cloud_outlined,
                color: _enableLyricsOvh ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              title: Text(
                strings.npLyricsSourceOvh,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                strings.npLyricsSourceOvhDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: _enableLyricsOvh,
              onChanged: _updateLyricsOvh,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.npLyricsSourcesCloseBtn),
        ),
        FilledButton.icon(
          onPressed: hasAnySource ? _handleReSearch : null,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.npLyricsSourcesResearchBtn),
        ),
      ],
    );
  }
}
