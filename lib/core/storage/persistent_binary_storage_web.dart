import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show DiagnosticsProperty, SynchronousFuture, debugPrint;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Virtual directory descriptor on Web (backed by OPFS).
class StorageDirectory {
  final String path;
  const StorageDirectory(this.path);
}

/// Virtual file reference on Web (backed by OPFS).
class StorageFileRef {
  final String path;
  const StorageFileRef(this.path);
}

/// Web implementation of persistent binary storage backed directly by the
/// browser's **Origin Private File System (OPFS)** (`navigator.storage.getDirectory()`).
///
/// Only lightweight filename/stat indices are retained in RAM; audio files are
/// streamed/analyzed directly by `miniaudio_player` from OPFS in O(1) RAM, and
/// images are read and decoded asynchronously on demand into Flutter's
/// `PaintingBinding.instance.imageCache`.
abstract final class PersistentBinaryStorage {
  static StorageDirectory? tempDirectory;
  static StorageDirectory? thumbnailsDirectory;

  static final Set<String> _knownCoverHashes = <String>{};
  static final Set<String> _knownBackgroundFiles = <String>{};
  static final Map<String, ({int size, int modifiedAt})> _audioMetaCache =
      <String, ({int size, int modifiedAt})>{};

  static web.FileSystemDirectoryHandle? _coversDirHandle;
  static web.FileSystemDirectoryHandle? _audioDirHandle;
  static web.FileSystemDirectoryHandle? _backgroundsDirHandle;
  static Future<void>? _opfsInitFuture;

  static int get processorCount {
    try {
      final hc = web.window.navigator.hardwareConcurrency;
      return hc > 0 ? hc : 4;
    } catch (_) {
      return 4;
    }
  }

  static bool get isLinux => false;
  static bool get isWindows => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;

  static ({String dir, String fileName})? _parseOpfsPath(String pathOrUri) {
    final clean = pathOrUri.trim().replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty) return null;
    final slashIdx = clean.indexOf('/');
    if (slashIdx <= 0 || slashIdx == clean.length - 1) return null;
    final dir = clean.substring(0, slashIdx);
    final fileName = clean.substring(slashIdx + 1);
    if (fileName.isEmpty) return null;
    return (dir: dir, fileName: fileName);
  }

  /// Whether [pathOrUrl] points to a browser-picked audio file stored inside OPFS `audio/`.
  static bool isManagedWebAudioPath(String pathOrUrl) =>
      _parseOpfsPath(pathOrUrl)?.dir == 'audio';

  static void init(String thumbnailsPath, String tempPath) {
    tempDirectory = StorageDirectory(tempPath);
    thumbnailsDirectory = StorageDirectory(thumbnailsPath);
    unawaited(initAsync(thumbnailsPath: thumbnailsPath, tempPath: tempPath));
  }

  static Future<void> initAsync({
    String? thumbnailsPath,
    String? tempPath,
  }) async {
    if (thumbnailsPath != null) {
      thumbnailsDirectory = StorageDirectory(thumbnailsPath);
    }
    if (tempPath != null) {
      tempDirectory = StorageDirectory(tempPath);
    }
    tempDirectory ??= const StorageDirectory('/temp');
    thumbnailsDirectory ??= const StorageDirectory('/covers');
    await (_opfsInitFuture ??= _initOpfsHandles());
  }

  static Future<void> _initOpfsHandles() async {
    try {
      final storage = web.window.navigator.storage;
      final root = await storage.getDirectory().toDart;
      _coversDirHandle = await root
          .getDirectoryHandle(
            'covers',
            web.FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
      _audioDirHandle = await root
          .getDirectoryHandle(
            'audio',
            web.FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
      _backgroundsDirHandle = await root
          .getDirectoryHandle(
            'backgrounds',
            web.FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;

      await _indexOpfsDirectory(
        _coversDirHandle!,
        onFile: (fileHandle) async {
          _knownCoverHashes.add(fileHandle.name);
        },
      );
      await _indexOpfsDirectory(
        _audioDirHandle!,
        onFile: (fileHandle) async {
          final file = await fileHandle.getFile().toDart;
          final stat = _statFromWebFile(file);
          if (stat != null) {
            _audioMetaCache['/audio/${file.name}'] = stat;
          }
        },
      );
      await _indexOpfsDirectory(
        _backgroundsDirHandle!,
        onFile: (fileHandle) async {
          _knownBackgroundFiles.add(fileHandle.name);
        },
      );
    } catch (e) {
      debugPrint('[PersistentBinaryStorage] OPFS init error: $e');
    }
  }

  static Future<void> _indexOpfsDirectory(
    web.FileSystemDirectoryHandle dirHandle, {
    required Future<void> Function(web.FileSystemFileHandle fileHandle) onFile,
  }) async {
    try {
      final jsDir = dirHandle as JSObject;
      if (!jsDir.has('values')) return;
      final iterator = jsDir.callMethod<JSObject>('values'.toJS);
      while (true) {
        final nextPromise = iterator.callMethod<JSPromise<JSObject>>('next'.toJS);
        final nextResult = await nextPromise.toDart;
        final done = (nextResult['done'] as JSBoolean?)?.toDart ?? true;
        if (done) break;
        final handle = nextResult['value'] as web.FileSystemHandle?;
        if (handle == null || handle.kind != 'file') continue;
        await onFile(handle as web.FileSystemFileHandle);
      }
    } catch (_) {}
  }

  static Future<void> _writeOpfsFile(
    web.FileSystemDirectoryHandle? dirHandle,
    String fileName,
    Uint8List bytes,
  ) async {
    if (dirHandle == null) return;
    try {
      final fileHandle = await dirHandle
          .getFileHandle(fileName, web.FileSystemGetFileOptions(create: true))
          .toDart;
      final writable = await fileHandle.createWritable().toDart;
      await writable.write(bytes.toJS).toDart;
      await writable.close().toDart;
    } catch (e) {
      debugPrint('[PersistentBinaryStorage] OPFS write error ($fileName): $e');
    }
  }

  static Future<Uint8List?> _readOpfsFile(
    web.FileSystemDirectoryHandle? dirHandle,
    String fileName,
  ) async {
    if (dirHandle == null) return null;
    try {
      final fileHandle = await dirHandle
          .getFileHandle(fileName, web.FileSystemGetFileOptions(create: false))
          .toDart;
      final file = await fileHandle.getFile().toDart;
      final arrayBuf = await file.arrayBuffer().toDart;
      final bytes = arrayBuf.toDart.asUint8List();
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _opfsFileExists(
    web.FileSystemDirectoryHandle? dirHandle,
    String fileName,
  ) async {
    if (dirHandle == null) return false;
    try {
      await dirHandle
          .getFileHandle(fileName, web.FileSystemGetFileOptions(create: false))
          .toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  static ({int size, int modifiedAt})? _statFromWebFile(web.File file) {
    if (file.size <= 0) return null;
    return (
      size: file.size,
      modifiedAt: file.lastModified > 0 ? file.lastModified : 1,
    );
  }

  static Future<({int size, int modifiedAt})?> _statOpfsFile(
    web.FileSystemDirectoryHandle? dirHandle,
    String fileName,
  ) async {
    if (dirHandle == null) return null;
    try {
      final fileHandle = await dirHandle
          .getFileHandle(fileName, web.FileSystemGetFileOptions(create: false))
          .toDart;
      final file = await fileHandle.getFile().toDart;
      return _statFromWebFile(file);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteOpfsFile(
    web.FileSystemDirectoryHandle? dirHandle,
    String fileName,
  ) async {
    if (dirHandle == null) return;
    try {
      await dirHandle.removeEntry(fileName).toDart;
    } catch (_) {}
  }

  static void ensureInitialized() {
    tempDirectory ??= const StorageDirectory('/temp');
    thumbnailsDirectory ??= const StorageDirectory('/covers');
  }

  static Future<void> clearTempDirectory() async {
    ensureInitialized();
  }

  static bool hasCachedArtwork(String artworkUri, String resolvedArtworkPath) {
    ensureInitialized();
    final hash = p.basename(artworkUri);
    return _knownCoverHashes.contains(hash);
  }

  static Future<void> saveCoverBytes(
    String hash,
    String targetFilePath,
    Uint8List bytes,
  ) async {
    ensureInitialized();
    final cleanHash = p.basename(hash);
    if (_knownCoverHashes.contains(cleanHash)) {
      return;
    }
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_coversDirHandle, cleanHash, bytes);
    _knownCoverHashes.add(cleanHash);
  }

  static Future<Uri?> resolveCoverDataUriAsync(String artworkUri) async {
    final hash = p.basename(artworkUri.trim());
    if (hash.isEmpty) return null;
    final bytes = await _readOpfsImageBytes('covers', hash);
    if (bytes == null || bytes.isEmpty) return null;
    return Uri.dataFromBytes(bytes, mimeType: 'image/jpeg');
  }

  static List<StorageFileRef> listCachedCoverFiles() {
    ensureInitialized();
    final base = thumbnailsDirectory!.path;
    return [
      for (final hash in _knownCoverHashes)
        StorageFileRef(p.join(base, hash)),
    ];
  }

  static Future<void> purgeUnusedCovers(Set<String> validFileNames) async {
    final toRemove = <String>[
      for (final hash in _knownCoverHashes)
        if (!validFileNames.contains(hash)) hash,
    ];
    for (final hash in toRemove) {
      _knownCoverHashes.remove(hash);
      PaintingBinding.instance.imageCache.evict(
        _OpfsImageProvider(directoryKind: 'covers', fileName: hash),
        includeLive: true,
      );
      await _deleteOpfsFile(_coversDirHandle, hash);
    }
  }

  // ---------------------------------------------------------------------------
  // Picked Web Audio & Background Files (Direct OPFS)
  // ---------------------------------------------------------------------------

  static Future<String?> savePickedAudioFile(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final canonicalPath = '/audio/$safeName';
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_audioDirHandle, safeName, bytes);
    final stat = await _statOpfsFile(_audioDirHandle, safeName);
    _audioMetaCache[canonicalPath] =
        stat ?? (size: bytes.length, modifiedAt: 1);
    return canonicalPath;
  }

  static Future<void> removeWebAudioFile(String uriOrPath) async {
    final parsed = _parseOpfsPath(uriOrPath);
    if (parsed?.dir == 'audio') {
      _audioMetaCache.remove('/audio/${parsed!.fileName}');
      await (_opfsInitFuture ??= _initOpfsHandles());
      await _deleteOpfsFile(_audioDirHandle, parsed.fileName);
    }
  }

  static Future<String?> saveCustomBackgroundBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final canonicalPath = '/backgrounds/$safeName';
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_backgroundsDirHandle, safeName, bytes);
    _knownBackgroundFiles.add(safeName);
    PaintingBinding.instance.imageCache.evict(
      _OpfsImageProvider(directoryKind: 'backgrounds', fileName: safeName),
      includeLive: true,
    );
    return canonicalPath;
  }

  static Future<String?> copyCustomBackgroundFile(
    String sourceImagePath,
  ) async {
    if (await fileExists(sourceImagePath)) {
      return sourceImagePath;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Filesystem Inspection & Discovery on Web
  // ---------------------------------------------------------------------------

  static bool directoryExistsSync(String path) => false;
  static Future<bool> directoryExists(String path) async => false;

  static bool fileExistsSync(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    final parsed = _parseOpfsPath(path);
    if (parsed != null) {
      return switch (parsed.dir) {
        'audio' => _audioMetaCache.containsKey('/audio/${parsed.fileName}'),
        'backgrounds' => _knownBackgroundFiles.contains(parsed.fileName),
        'covers' => _knownCoverHashes.contains(parsed.fileName),
        _ => false,
      };
    }
    return _knownCoverHashes.contains(p.basename(path));
  }

  static Future<bool> fileExists(String path) async {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    if (fileExistsSync(path)) return true;
    await (_opfsInitFuture ??= _initOpfsHandles());
    final parsed = _parseOpfsPath(path);
    if (parsed != null) {
      switch (parsed.dir) {
        case 'audio':
          final st = await _statOpfsFile(_audioDirHandle, parsed.fileName);
          if (st != null) {
            _audioMetaCache['/audio/${parsed.fileName}'] = st;
            return true;
          }
          return false;
        case 'backgrounds':
          final exists = await _opfsFileExists(
            _backgroundsDirHandle,
            parsed.fileName,
          );
          if (exists) {
            _knownBackgroundFiles.add(parsed.fileName);
          }
          return exists;
        case 'covers':
          final exists = await _opfsFileExists(
            _coversDirHandle,
            parsed.fileName,
          );
          if (exists) {
            _knownCoverHashes.add(parsed.fileName);
          }
          return exists;
      }
    }
    final hash = p.basename(path);
    if (hash.isNotEmpty && await _opfsFileExists(_coversDirHandle, hash)) {
      _knownCoverHashes.add(hash);
      return true;
    }
    return false;
  }

  static Future<({int size, int modifiedAt})?> statFile(String path) async {
    final parsed = _parseOpfsPath(path);
    if (parsed?.dir == 'audio') {
      final key = '/audio/${parsed!.fileName}';
      final cached = _audioMetaCache[key];
      if (cached != null) return cached;
      await (_opfsInitFuture ??= _initOpfsHandles());
      final st = await _statOpfsFile(_audioDirHandle, parsed.fileName);
      if (st != null) {
        _audioMetaCache[key] = st;
      }
      return st;
    }
    return null;
  }

  static List<String> listSubdirectoriesSync(String dirPath) => const [];

  static Stream<({String path, int size, int modifiedAt})>
  discoverAudioFilesStream(
    List<String> directories,
    Set<String> supportedExtensions, {
    bool Function()? isCancelled,
  }) async* {}

  static Future<String?> readLocalLrcFile(String audioFilePath) async => null;

  // ---------------------------------------------------------------------------
  // On-Demand OPFS Image Provider & Widget Builder
  // ---------------------------------------------------------------------------

  static ({String dir, String fileName}) _resolveImageTarget(String pathOrUri) {
    final parsed = _parseOpfsPath(pathOrUri);
    if (parsed != null && parsed.dir == 'backgrounds') {
      return (dir: 'backgrounds', fileName: parsed.fileName);
    }
    return (dir: 'covers', fileName: p.basename(pathOrUri));
  }

  static Future<Uint8List?> _readOpfsImageBytes(
    String directoryKind,
    String fileName,
  ) async {
    if (fileName.isEmpty) return null;
    await (_opfsInitFuture ??= _initOpfsHandles());
    final handle = directoryKind == 'backgrounds'
        ? _backgroundsDirHandle
        : _coversDirHandle;
    return _readOpfsFile(handle, fileName);
  }

  static Future<ImageProvider?> resolveLocalOrOpfsImageProvider(
    String pathOrUri, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    final target = _resolveImageTarget(pathOrUri);
    if (target.fileName.isEmpty) return null;
    return ResizeImage.resizeIfNeeded(
      maxWidth,
      maxHeight,
      _OpfsImageProvider(
        directoryKind: target.dir,
        fileName: target.fileName,
      ),
    );
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
    final target = _resolveImageTarget(pathOrUri);
    if (target.fileName.isEmpty) return fallback;

    final provider = ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      _OpfsImageProvider(
        directoryKind: target.dir,
        fileName: target.fileName,
      ),
    );
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return fallback;
      },
      errorBuilder: (_, _, _) => fallback,
    );
  }

  static DateTime? tryParseHttpDate(String value) => DateTime.tryParse(value);
}

@immutable
class _OpfsImageProvider extends ImageProvider<_OpfsImageProvider> {
  final String directoryKind;
  final String fileName;

  const _OpfsImageProvider({
    required this.directoryKind,
    required this.fileName,
  });

  @override
  Future<_OpfsImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_OpfsImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _OpfsImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: 'OpfsImage(${key.directoryKind}/${key.fileName})',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<_OpfsImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    _OpfsImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    try {
      final bytes = await PersistentBinaryStorage._readOpfsImageBytes(
        key.directoryKind,
        key.fileName,
      );
      if (bytes == null || bytes.isEmpty) {
        PaintingBinding.instance.imageCache.evict(key);
        throw StateError(
          'Cannot load OPFS image "${key.directoryKind}/${key.fileName}": empty or missing.',
        );
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _OpfsImageProvider &&
        other.directoryKind == directoryKind &&
        other.fileName == fileName;
  }

  @override
  int get hashCode => Object.hash(directoryKind, fileName);

  @override
  String toString() => 'OpfsImage("$directoryKind/$fileName")';
}
