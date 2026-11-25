import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef StorageDirectory = io.Directory;
typedef StorageFileRef = io.File;

/// Native (`dart:io`) implementation of persistent binary storage for cover art,
/// temporary files, audio file discovery, and local image rendering.
abstract final class PersistentBinaryStorage {
  static io.Directory? tempDirectory;
  static io.Directory? thumbnailsDirectory;

  static final Set<String> _knownCoverHashes = <String>{};

  static int get processorCount => math.max(1, io.Platform.numberOfProcessors);

  static bool get isLinux => io.Platform.isLinux;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isMacOS => io.Platform.isMacOS;

  /// Always `false` on native platforms (`dart:io` resolves local paths directly).
  static bool isManagedWebAudioPath(String pathOrUrl) => false;

  static void init(String thumbnailsPath, String tempPath) {
    tempDirectory = io.Directory(tempPath);
    thumbnailsDirectory = io.Directory(thumbnailsPath);
    if (!thumbnailsDirectory!.existsSync()) {
      thumbnailsDirectory!.createSync(recursive: true);
    }
    if (!tempDirectory!.existsSync()) {
      tempDirectory!.createSync(recursive: true);
    }
    _knownCoverHashes.clear();
  }

  static Future<void> initAsync({
    String? thumbnailsPath,
    String? tempPath,
  }) async {
    if (thumbnailsPath != null && tempPath != null) {
      init(thumbnailsPath, tempPath);
    }
    final dir = thumbnailsDirectory;
    if (dir != null && await dir.exists()) {
      try {
        await for (final entity in dir.list(
          recursive: false,
          followLinks: false,
        )) {
          if (entity is io.File) {
            _knownCoverHashes.add(p.basename(entity.path));
          }
        }
      } catch (_) {}
    }
  }

  static void ensureInitialized() {
    if (tempDirectory == null || thumbnailsDirectory == null) {
      throw Exception(
        'MetadataUtils is not initialized. Call MetadataUtils.init() first.',
      );
    }
  }

  static Future<void> clearTempDirectory() async {
    ensureInitialized();
    try {
      if (await tempDirectory!.exists()) {
        await tempDirectory!.delete(recursive: true);
      }
      if (!await tempDirectory!.exists()) {
        await tempDirectory!.create(recursive: true);
      }
    } catch (_) {}
  }

  static bool hasCachedArtwork(String artworkUri, String resolvedArtworkPath) {
    ensureInitialized();
    final hash = p.basename(artworkUri);
    final f = io.File(artworkUri);
    if (f.existsSync() && f.lengthSync() > 0) {
      _knownCoverHashes.add(hash);
      return true;
    }
    final fallback = io.File(resolvedArtworkPath);
    if (fallback.existsSync() && fallback.lengthSync() > 0) {
      _knownCoverHashes.add(hash);
      return true;
    }
    return false;
  }

  static Future<void> saveCoverBytes(
    String hash,
    String targetFilePath,
    Uint8List bytes,
  ) async {
    ensureInitialized();
    final targetFile = io.File(targetFilePath);
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      _knownCoverHashes.add(hash);
      return;
    }

    final rand = math.Random().nextInt(1 << 30);
    final fileName = p.basename(targetFile.path);
    final tempFile = io.File(
      p.join(tempDirectory!.path, '${fileName}_${io.pid}_$rand.tmp'),
    );

    try {
      await tempFile.writeAsBytes(bytes, flush: false);
      await tempFile.rename(targetFile.path);
      _knownCoverHashes.add(hash);
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      if (await targetFile.exists() && await targetFile.length() > 0) {
        _knownCoverHashes.add(hash);
        return;
      }
      try {
        await targetFile.writeAsBytes(bytes, flush: false);
        _knownCoverHashes.add(hash);
      } catch (_) {}
    }
  }

  static Future<Uri?> resolveCoverDataUriAsync(String artworkUri) async => null;

  static List<io.File> listCachedCoverFiles() {
    ensureInitialized();
    if (!thumbnailsDirectory!.existsSync()) {
      return [];
    }
    final files = thumbnailsDirectory!.listSync(
      recursive: true,
      followLinks: false,
    );
    return files.whereType<io.File>().toList();
  }

  static Future<void> purgeUnusedCovers(Set<String> validFileNames) async {
    final dir = thumbnailsDirectory;
    if (dir == null || !await dir.exists()) return;
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is io.File) {
        final fileName = p.basename(entity.path);
        if (!validFileNames.contains(fileName)) {
          try {
            await entity.delete();
            _knownCoverHashes.remove(fileName);
          } catch (_) {}
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Picked Audio & Background Files
  // ---------------------------------------------------------------------------

  static Future<String?> savePickedAudioFile(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final baseDir = tempDirectory?.parent ?? io.Directory.systemTemp;
    final audioDir = io.Directory(p.join(baseDir.path, 'audio'));
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    final target = io.File(p.join(audioDir.path, safeName));
    await target.writeAsBytes(bytes, flush: false);
    return target.path;
  }

  static Future<void> removeWebAudioFile(String uriOrPath) async {}

  static Future<String?> saveCustomBackgroundBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final baseDir = thumbnailsDirectory?.parent ?? io.Directory.systemTemp;
    final bgDir = io.Directory(p.join(baseDir.path, 'backgrounds'));
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }
    final target = io.File(p.join(bgDir.path, safeName));
    await target.writeAsBytes(bytes, flush: false);
    return target.path;
  }

  static Future<String?> copyCustomBackgroundFile(
    String sourceImagePath,
  ) async {
    final sourceFile = io.File(sourceImagePath);
    if (!await sourceFile.exists()) return null;

    final supportDir = await getApplicationSupportDirectory();
    final bgDir = io.Directory('${supportDir.path}/backgrounds');
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }

    final rawExt = p.extension(sourceImagePath);
    final ext = rawExt.isNotEmpty ? rawExt : '.jpg';
    final targetPath = p.join(bgDir.path, 'custom_bg$ext');
    final targetFile = await sourceFile.copy(targetPath);
    return targetFile.path;
  }

  // ---------------------------------------------------------------------------
  // Filesystem Inspection & Discovery
  // ---------------------------------------------------------------------------

  static bool directoryExistsSync(String path) {
    if (path.isEmpty) return false;
    return io.Directory(path).existsSync();
  }

  static Future<bool> directoryExists(String path) async {
    if (path.isEmpty) return false;
    return io.Directory(path).exists();
  }

  static bool fileExistsSync(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return true;
    }
    return io.File(path).existsSync();
  }

  static Future<bool> fileExists(String path) async {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return true;
    }
    return io.File(path).exists();
  }

  static Future<({int size, int modifiedAt})?> statFile(String path) async {
    try {
      final f = io.File(path);
      if (!await f.exists()) return null;
      final stat = await f.stat();
      if (stat.size <= 0) return null;
      return (
        size: stat.size,
        modifiedAt: stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> listSubdirectoriesSync(String dirPath) {
    final subDirs = <String>[];
    try {
      final dir = io.Directory(dirPath);
      if (!dir.existsSync()) return subDirs;
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is io.Directory) {
          final base = p.basename(entity.path);
          if (!base.startsWith('.')) {
            subDirs.add(p.normalize(entity.path));
          }
        }
      }
      subDirs.sort(
        (a, b) =>
            p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()),
      );
    } catch (_) {}
    return subDirs;
  }

  static Stream<({String path, int size, int modifiedAt})>
  discoverAudioFilesStream(
    List<String> directories,
    Set<String> supportedExtensions, {
    bool Function()? isCancelled,
  }) async* {
    await Future<void>.delayed(Duration.zero);
    int processedSinceYield = 0;

    for (final dirPath in directories) {
      if (isCancelled?.call() ?? false) break;

      final dir = io.Directory(dirPath);
      if (!dir.existsSync()) continue;

      Stream<io.FileSystemEntity> entityStream;
      try {
        entityStream = dir.list(recursive: true, followLinks: false);
      } catch (_) {
        continue;
      }

      await for (final entity in entityStream.handleError((Object _) {})) {
        if (isCancelled?.call() ?? false) break;
        if (entity is! io.File) continue;

        final path = entity.path;
        final filename = p.basename(path);
        if (filename.startsWith('.')) continue;

        final dotIndex = filename.lastIndexOf('.');
        if (dotIndex <= 0 || dotIndex == filename.length - 1) continue;
        final ext = filename.substring(dotIndex + 1).toLowerCase();
        if (!supportedExtensions.contains(ext)) continue;

        try {
          final stat = await entity.stat();
          if (stat.size <= 0) continue;
          yield (
            path: path,
            size: stat.size,
            modifiedAt: stat.modified.millisecondsSinceEpoch,
          );
        } catch (_) {
          continue;
        }

        processedSinceYield++;
        if (processedSinceYield >= 64) {
          processedSinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
  }

  static Future<String?> readLocalLrcFile(String audioFilePath) async {
    if (audioFilePath.startsWith('http://') ||
        audioFilePath.startsWith('https://')) {
      return null;
    }
    try {
      final dir = p.dirname(audioFilePath);
      final baseName = p.basenameWithoutExtension(audioFilePath);
      for (final ext in const ['.lrc', '.LRC', '.txt', '.TXT']) {
        final candidate = io.File(p.join(dir, '$baseName$ext'));
        if (await candidate.exists()) {
          final content = await candidate.readAsString();
          if (content.trim().isNotEmpty) {
            return content;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Image Provider & Widget Builders
  // ---------------------------------------------------------------------------

  static Future<ImageProvider?> resolveLocalOrOpfsImageProvider(
    String pathOrUri, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    final cleanPath = pathOrUri.startsWith('file://')
        ? pathOrUri.replaceFirst('file://', '')
        : pathOrUri;
    io.File file = io.File(cleanPath);
    if (!await file.exists() && thumbnailsDirectory != null) {
      file = io.File(p.join(thumbnailsDirectory!.path, p.basename(cleanPath)));
    }
    if (!await file.exists() || await file.length() <= 0) return null;
    return ResizeImage.resizeIfNeeded(maxWidth, maxHeight, FileImage(file));
  }

  static Widget buildLocalOrOpfsImage(
    String pathOrUri, {
    double? width,
    double? height,
    int? cacheWidth,
    int? cacheHeight,
    BoxFit fit = BoxFit.cover,
    required Widget fallback,
  }) {
    final cleanPath = pathOrUri.startsWith('file://')
        ? pathOrUri.replaceFirst('file://', '')
        : pathOrUri;
    io.File file = io.File(cleanPath);
    if (!file.existsSync() && thumbnailsDirectory != null) {
      file = io.File(p.join(thumbnailsDirectory!.path, p.basename(cleanPath)));
    }
    if (!file.existsSync()) return fallback;

    return Image.file(
      file,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fit: fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return fallback;
      },
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  static DateTime? tryParseHttpDate(String value) {
    try {
      return io.HttpDate.parse(value);
    } catch (_) {
      return DateTime.tryParse(value);
    }
  }
}
