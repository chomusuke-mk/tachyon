import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/radios/presentation/widgets/radio_logo_avatar.dart';

/// Shows an add/edit dialog for a custom [RadioStation] with live artwork URL
/// preview and persists changes to [store].
Future<void> showAddEditRadioStationDialog(
  BuildContext context, {
  RadioStation? existingStation,
  required AppStringKey strings,
  required LibraryStore store,
}) async {
  final nameController = TextEditingController(
    text: existingStation?.name ?? '',
  );
  final urlController = TextEditingController(
    text: existingStation?.streamUrl ?? '',
  );
  final imageController = TextEditingController(
    text: existingStation?.faviconUrl ?? '',
  );
  final genreController = TextEditingController(
    text: existingStation?.genre ?? '',
  );
  final countryController = TextEditingController(
    text: existingStation?.country ?? '',
  );
  final formKey = GlobalKey<FormState>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final imageUrl = imageController.text.trim();
        final hasValidImage =
            imageUrl.isNotEmpty && Uri.tryParse(imageUrl)?.hasScheme == true;

        return AlertDialog(
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
                  if (hasValidImage) ...[
                    Center(
                      child: RadioLogoAvatar(
                        faviconUrl: imageUrl,
                        size: 64.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                    controller: imageController,
                    decoration: InputDecoration(
                      labelText: strings.rdImageUrl,
                      hintText: 'https://... (logo/favicon)',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setDialogState(() {}),
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
        );
      },
    ),
  );

  if (confirmed == true && context.mounted) {
    final station = RadioStation(
      id: existingStation?.id,
      stationUuid: existingStation?.stationUuid,
      name: nameController.text.trim(),
      streamUrl: urlController.text.trim(),
      faviconUrl: imageController.text.trim().isNotEmpty
          ? imageController.text.trim()
          : null,
      genre: genreController.text.trim().isNotEmpty
          ? genreController.text.trim()
          : null,
      country: countryController.text.trim().isNotEmpty
          ? countryController.text.trim()
          : null,
      codec: existingStation?.codec,
      bitrateKbps: existingStation?.bitrateKbps,
      isFavorite: existingStation?.isFavorite ?? false,
      createdAt: existingStation?.createdAt ?? DateTime.now(),
    );
    await store.saveRadioStationInStore(station);
  }
}

/// Shows a confirmation dialog before removing [station] from [store].
Future<void> showDeleteRadioStationDialog(
  BuildContext context, {
  required RadioStation station,
  required AppStringKey strings,
  required LibraryStore store,
}) async {
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
