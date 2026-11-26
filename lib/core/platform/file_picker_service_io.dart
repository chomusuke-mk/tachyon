import 'package:file_picker/file_picker.dart';
import 'package:tachyon/core/logging/app_logger.dart';

/// Service for opening native file and directory picker dialogs.
abstract final class FilePickerService {
  static const _log = ScopedLogger('FilePicker');

  /// Opens the native system folder picker to select a directory.
  /// Returns the absolute path string, or null if cancelled or error.
  static Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    try {
      final uri = await FilePicker.pickDirectory(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      return uri?.toFilePath();
    } catch (e, stackTrace) {
      _log.e('Error picking directory', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Opens the native system image picker to select a background image.
  /// Returns the absolute path string, or null if cancelled or error.
  static Future<String?> pickImage({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      return file?.path;
    } catch (e, stackTrace) {
      _log.e('Error picking image', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Opens the native system file picker to select one or more audio files.
  /// Returns the selected file paths, or an empty list if cancelled.
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
        initialDirectory: initialDirectory,
      );
      return files.map((f) => f.path).whereType<String>().toList();
    } catch (e, stackTrace) {
      _log.e('Error picking audio files', error: e, stackTrace: stackTrace);
      return const [];
    }
  }
}
