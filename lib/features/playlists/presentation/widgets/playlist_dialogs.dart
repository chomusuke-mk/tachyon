import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';

/// Centralized modal dialogs for playlist CRUD operations (create, rename, delete).
abstract final class PlaylistDialogs {
  /// Displays the modal dialog to create a new user playlist.
  static Future<void> showCreate(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CreatePlaylistDialog(),
    );
  }

  /// Displays the modal dialog to rename an existing playlist.
  static Future<void> showRename(BuildContext context, Playlist playlist) {
    return showDialog<void>(
      context: context,
      builder: (_) => RenamePlaylistDialog(playlist: playlist),
    );
  }

  /// Displays confirmation dialog before deleting a playlist.
  static Future<void> showDelete(
    BuildContext context,
    Playlist playlist, {
    VoidCallback? onDeleted,
  }) {
    final strings = context.read<LocaleController>().localeStrings;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.plDelete),
          content: Text(strings.plDeleteConfirmFormatted(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.plCancelButton),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () {
                if (playlist.id != null) {
                  context.read<PlaylistsController>().deletePlaylist(
                        playlist.id!,
                      );
                  onDeleted?.call();
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(strings.plDelete),
            ),
          ],
        );
      },
    );
  }
}

/// Dialog widget for creating a new playlist with lifecycle-managed controller.
class CreatePlaylistDialog extends StatefulWidget {
  const CreatePlaylistDialog({super.key});

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      context.read<PlaylistsController>().createPlaylist(name);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.read<LocaleController>().localeStrings;
    return AlertDialog(
      title: Text(strings.plCreateNew),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: strings.plNewNameHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.plCancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.plCreateButton),
        ),
      ],
    );
  }
}

/// Dialog widget for renaming a playlist with lifecycle-managed controller.
class RenamePlaylistDialog extends StatefulWidget {
  final Playlist playlist;
  const RenamePlaylistDialog({super.key, required this.playlist});

  @override
  State<RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.playlist.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty && widget.playlist.id != null) {
      context.read<PlaylistsController>().renamePlaylist(
            widget.playlist.id!,
            name,
          );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.read<LocaleController>().localeStrings;
    return AlertDialog(
      title: Text(strings.plRename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: strings.plNewNameHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.plCancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.plRename),
        ),
      ],
    );
  }
}
