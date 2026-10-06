import 'package:file_picker/file_picker.dart';

abstract final class FilePickerService {
  /// Opens the native system folder picker to select a directory.
  /// Returns the absolute path string, or null if cancelled or error.
  static Future<String?> pickDirectory({String? dialogTitle}) async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Opens the native system image picker to select a background image.
  /// Returns the absolute path string, or null if cancelled or error.
  static Future<String?> pickImage({String? dialogTitle}) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: dialogTitle,
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }
}
