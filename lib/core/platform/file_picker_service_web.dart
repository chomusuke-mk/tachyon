import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';

/// Web implementation of file and media picking backed by persistent storage.
abstract final class FilePickerService {
  /// Returns `null` because directory selection is not supported on the web.
  static Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    return null;
  }

  /// Opens a file picker to select an image and saves it to binary storage.
  ///
  /// Uses [dialogTitle] for the picker prompt when supported, ignores
  /// [initialDirectory] on web, and returns the persisted storage URI or `null`
  /// if cancelled or empty.
  static Future<String?> pickImage({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: dialogTitle,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return await PersistentBinaryStorage.saveCustomBackgroundBytes(
        file.name,
        bytes,
      );
    } catch (e, stackTrace) {
      debugPrint('[FilePickerServiceWeb] Error picking image: $e\n$stackTrace');
      return null;
    }
  }

  /// Opens a file picker to select audio files and saves them to storage.
  ///
  /// Optionally filters by [allowedExtensions] and sets [dialogTitle], while
  /// ignoring [initialDirectory] on web. Returns the persisted storage URIs,
  /// or an empty list if cancelled or an error occurs.
  static Future<List<String>> pickAudioFiles({
    String? dialogTitle,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    try {
      final exts = allowedExtensions
          ?.map((e) => e.startsWith('.') ? e.substring(1) : e)
          .toList();
      final files = await FilePicker.pickFiles(
        type: (exts != null && exts.isNotEmpty)
            ? FileType.custom
            : FileType.audio,
        allowedExtensions: (exts != null && exts.isNotEmpty) ? exts : null,
        dialogTitle: dialogTitle,
      );
      final savedUris = <String>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final uri = await PersistentBinaryStorage.savePickedAudioFile(
          file.name,
          bytes,
        );
        if (uri != null && uri.isNotEmpty) {
          savedUris.add(uri);
        }
      }
      return savedUris;
    } catch (e, stackTrace) {
      debugPrint(
        '[FilePickerServiceWeb] Error picking audio files: $e\n$stackTrace',
      );
      return const [];
    }
  }
}
