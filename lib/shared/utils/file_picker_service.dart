import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

abstract final class FilePickerService {
  /// Opens the native system folder picker to select a directory.
  /// Returns the absolute path string, or null if cancelled or error.
  static Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        return _pickDirectoryWindows(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
        );
      }

      final path = await FilePicker.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      return path;
    } catch (e, stackTrace) {
      debugPrint('[FilePickerService] Error picking directory: $e\n$stackTrace');
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
      if (!kIsWeb && Platform.isWindows) {
        return _pickImageWindows(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
        );
      }

      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      return file?.path;
    } catch (e, stackTrace) {
      debugPrint('[FilePickerService] Error picking image: $e\n$stackTrace');
      return null;
    }
  }

  /// Uses Win32 IFileOpenDialog on the UI thread to pick a folder on Windows,
  /// avoiding COM threading apartment conflicts (RPC_E_CHANGED_MODE) caused
  /// by worker isolates.
  static String? _pickDirectoryWindows({
    String? dialogTitle,
    String? initialDirectory,
  }) {
    debugPrint('[FilePickerService] Launching Win32 IFileOpenDialog for directory on main UI thread...');
    return using((arena) {
      final fileDialog = arena.com<IFileOpenDialog>(FileOpenDialog);

      final options = fileDialog.getOptions() |
          FOS_PICKFOLDERS |
          FOS_FORCEFILESYSTEM |
          FOS_NOCHANGEDIR;
      fileDialog.setOptions(options);

      if (dialogTitle != null && dialogTitle.isNotEmpty) {
        fileDialog.setTitle(arena.pcwstr(dialogTitle));
      }

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        try {
          final item = arena.adopt(
            SHCreateItemFromParsingName<IShellItem>(
              arena.pcwstr(initialDirectory),
              null,
            ),
          );
          fileDialog.setFolder(item);
        } catch (e) {
          debugPrint('[FilePickerService] Note: Failed to set initial directory "$initialDirectory": $e');
        }
      }

      try {
        final parentHwnd = GetForegroundWindow();
        debugPrint('[FilePickerService] Showing folder dialog with parent HWND: $parentHwnd');
        fileDialog.show(parentHwnd);
      } on WindowsException catch (e) {
        if (e.hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
          debugPrint('[FilePickerService] User cancelled folder picker dialog.');
          return null;
        }
        debugPrint('[FilePickerService] WindowsException while showing dialog: $e (HRESULT: 0x${e.hr.toRadixString(16)})');
        rethrow;
      }

      final selectedItem = fileDialog.getResult();
      if (selectedItem == null) {
        debugPrint('[FilePickerService] No item was returned from fileDialog.getResult()');
        return null;
      }

      final item = arena.adopt(selectedItem);
      final pathPtr = item.getDisplayName(SIGDN_FILESYSPATH);
      try {
        final selectedPath = pathPtr.toDartString();
        debugPrint('[FilePickerService] Selected directory path: $selectedPath');
        return selectedPath;
      } finally {
        CoTaskMemFree(pathPtr);
      }
    });
  }

  /// Uses Win32 IFileOpenDialog on the UI thread to pick an image file on Windows.
  static String? _pickImageWindows({
    String? dialogTitle,
    String? initialDirectory,
  }) {
    debugPrint('[FilePickerService] Launching Win32 IFileOpenDialog for image on main UI thread...');
    return using((arena) {
      final fileDialog = arena.com<IFileOpenDialog>(FileOpenDialog);

      final options = fileDialog.getOptions() |
          FOS_FORCEFILESYSTEM |
          FOS_FILEMUSTEXIST |
          FOS_NOCHANGEDIR;
      fileDialog.setOptions(options);

      if (dialogTitle != null && dialogTitle.isNotEmpty) {
        fileDialog.setTitle(arena.pcwstr(dialogTitle));
      }

      // Filter images
      final specs = arena<COMDLG_FILTERSPEC>(2);
      specs[0]
        ..pszName = arena.pwstr('Image Files (*.jpg; *.jpeg; *.png; *.webp; *.bmp)')
        ..pszSpec = arena.pwstr('*.jpg;*.jpeg;*.png;*.webp;*.bmp');
      specs[1]
        ..pszName = arena.pwstr('All Files (*.*)')
        ..pszSpec = arena.pwstr('*.*');
      fileDialog.setFileTypes(2, specs);

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        try {
          final item = arena.adopt(
            SHCreateItemFromParsingName<IShellItem>(
              arena.pcwstr(initialDirectory),
              null,
            ),
          );
          fileDialog.setFolder(item);
        } catch (e) {
          debugPrint('[FilePickerService] Note: Failed to set initial image directory "$initialDirectory": $e');
        }
      }

      try {
        final parentHwnd = GetForegroundWindow();
        debugPrint('[FilePickerService] Showing image dialog with parent HWND: $parentHwnd');
        fileDialog.show(parentHwnd);
      } on WindowsException catch (e) {
        if (e.hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
          debugPrint('[FilePickerService] User cancelled image picker dialog.');
          return null;
        }
        debugPrint('[FilePickerService] WindowsException while showing image dialog: $e (HRESULT: 0x${e.hr.toRadixString(16)})');
        rethrow;
      }

      final selectedItem = fileDialog.getResult();
      if (selectedItem == null) {
        debugPrint('[FilePickerService] No item was returned from fileDialog.getResult()');
        return null;
      }

      final item = arena.adopt(selectedItem);
      final pathPtr = item.getDisplayName(SIGDN_FILESYSPATH);
      try {
        final selectedPath = pathPtr.toDartString();
        debugPrint('[FilePickerService] Selected image path: $selectedPath');
        return selectedPath;
      } finally {
        CoTaskMemFree(pathPtr);
      }
    });
  }
}
