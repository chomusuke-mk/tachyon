import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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

/// Web implementation of persistent binary storage backed by the browser's
/// **Origin Private File System (OPFS)** (`navigator.storage.getDirectory()`)
/// with a write-through in-memory cache for zero-latency UI rendering.
abstract final class PersistentBinaryStorage {
  static StorageDirectory? tempDirectory;
  static StorageDirectory? thumbnailsDirectory;

  static final Map<String, Uint8List> _coverBytesCache = <String, Uint8List>{};
  static final Set<String> _knownCoverHashes = <String>{};
  static final Map<String, Uint8List> _audioBytesCache = <String, Uint8List>{};
  static final Map<String, ({int size, int modifiedAt})> _audioMetaCache =
      <String, ({int size, int modifiedAt})>{};
  static final Map<String, Uint8List> _backgroundBytesCache =
      <String, Uint8List>{};

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
    tempDirectory ??= const StorageDirectory('/opfs/temp');
    thumbnailsDirectory ??= const StorageDirectory('/opfs/covers');
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

      await _hydrateFromOpfsDirectory(
        _coversDirHandle!,
        onFile: (name, bytes, lastModified) {
          _knownCoverHashes.add(name);
          _coverBytesCache[name] = bytes;
        },
      );
      await _hydrateFromOpfsDirectory(
        _audioDirHandle!,
        onFile: (name, bytes, lastModified) {
          final uri = 'opfs://audio/$name';
          _audioBytesCache[uri] = bytes;
          _audioMetaCache[uri] = (
            size: bytes.length,
            modifiedAt: lastModified > 0 ? lastModified : 1,
          );
        },
      );
      await _hydrateFromOpfsDirectory(
        _backgroundsDirHandle!,
        onFile: (name, bytes, lastModified) {
          final uri = 'opfs://backgrounds/$name';
          _backgroundBytesCache[uri] = bytes;
        },
      );
    } catch (e) {
      debugPrint('[PersistentBinaryStorage] OPFS init note (fallback RAM): $e');
    }
  }

  static Future<void> _hydrateFromOpfsDirectory(
    web.FileSystemDirectoryHandle dirHandle, {
    required void Function(String name, Uint8List bytes, int lastModified)
    onFile,
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
        final fileHandle = handle as web.FileSystemFileHandle;
        final file = await fileHandle.getFile().toDart;
        final arrayBuf = await file.arrayBuffer().toDart;
        final bytes = arrayBuf.toDart.asUint8List();
        if (bytes.isNotEmpty) {
          onFile(file.name, bytes, file.lastModified);
        }
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
    tempDirectory ??= const StorageDirectory('/opfs/temp');
    thumbnailsDirectory ??= const StorageDirectory('/opfs/covers');
  }

  static Future<void> clearTempDirectory() async {
    ensureInitialized();
  }

  static bool hasCachedArtwork(String artworkUri, String resolvedArtworkPath) {
    ensureInitialized();
    final hash = p.basename(artworkUri);
    return _knownCoverHashes.contains(hash) ||
        _coverBytesCache.containsKey(hash);
  }

  static Uint8List? getCachedCoverBytesSync(String hashOrUri) {
    final hash = p.basename(hashOrUri);
    return _coverBytesCache[hash];
  }

  static Future<Uint8List?> readCoverBytesAsync(
    String hashOrUri,
    String resolvedArtworkPath,
  ) async {
    ensureInitialized();
    final hash = p.basename(hashOrUri);
    final cached = _coverBytesCache[hash];
    if (cached != null) return cached;
    await (_opfsInitFuture ??= _initOpfsHandles());
    final loaded = await _readOpfsFile(_coversDirHandle, hash);
    if (loaded != null && loaded.isNotEmpty) {
      _coverBytesCache[hash] = loaded;
      _knownCoverHashes.add(hash);
    }
    return loaded;
  }

  static Future<void> saveCoverBytes(
    String hash,
    String targetFilePath,
    Uint8List bytes,
  ) async {
    ensureInitialized();
    final cleanHash = p.basename(hash);
    _coverBytesCache[cleanHash] = bytes;
    if (_knownCoverHashes.contains(cleanHash)) {
      return;
    }
    _knownCoverHashes.add(cleanHash);
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_coversDirHandle, cleanHash, bytes);
  }

  static Uint8List? getCoverBytesSync(String hashOrPath) =>
      _coverBytesCache[p.basename(hashOrPath)];

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
      _coverBytesCache.remove(hash);
      await _deleteOpfsFile(_coversDirHandle, hash);
    }
  }

  // ---------------------------------------------------------------------------
  // Picked Web/Local Audio & Background Files (OPFS)
  // ---------------------------------------------------------------------------

  static Future<String?> savePickedAudioFile(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final uri = 'opfs://audio/$safeName';
    final now = DateTime.now().millisecondsSinceEpoch;
    _audioBytesCache[uri] = bytes;
    _audioMetaCache[uri] = (size: bytes.length, modifiedAt: now);
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_audioDirHandle, safeName, bytes);
    return uri;
  }

  static Uint8List? getAudioBytesSync(String uriOrPath) =>
      _audioBytesCache[uriOrPath];

  static Future<Uint8List?> readAudioBytesAsync(String uriOrPath) async {
    final cached = _audioBytesCache[uriOrPath];
    if (cached != null) return cached;
    if (uriOrPath.startsWith('opfs://audio/')) {
      final safeName = uriOrPath.substring('opfs://audio/'.length);
      await (_opfsInitFuture ??= _initOpfsHandles());
      final loaded = await _readOpfsFile(_audioDirHandle, safeName);
      if (loaded != null) {
        _audioBytesCache[uriOrPath] = loaded;
        _audioMetaCache.putIfAbsent(
          uriOrPath,
          () => (size: loaded.length, modifiedAt: 1),
        );
      }
      return loaded;
    }
    return null;
  }

  static Future<void> removeWebAudioFile(String uriOrPath) async {
    _audioBytesCache.remove(uriOrPath);
    _audioMetaCache.remove(uriOrPath);
    if (uriOrPath.startsWith('opfs://audio/')) {
      final safeName = uriOrPath.substring('opfs://audio/'.length);
      await _deleteOpfsFile(_audioDirHandle, safeName);
    }
  }

  static Future<String?> saveCustomBackgroundBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final uri = 'opfs://backgrounds/$safeName';
    _backgroundBytesCache[uri] = bytes;
    await (_opfsInitFuture ??= _initOpfsHandles());
    await _writeOpfsFile(_backgroundsDirHandle, safeName, bytes);
    return uri;
  }

  static Uint8List? getBackgroundBytesSync(String pathOrUri) =>
      _backgroundBytesCache[pathOrUri];

  static Future<Uint8List?> readBackgroundBytesAsync(String pathOrUri) async {
    final cached = _backgroundBytesCache[pathOrUri];
    if (cached != null) return cached;
    if (pathOrUri.startsWith('opfs://backgrounds/')) {
      final safeName = pathOrUri.substring('opfs://backgrounds/'.length);
      await (_opfsInitFuture ??= _initOpfsHandles());
      final loaded = await _readOpfsFile(_backgroundsDirHandle, safeName);
      if (loaded != null) {
        _backgroundBytesCache[pathOrUri] = loaded;
      }
      return loaded;
    }
    return null;
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
    return _audioBytesCache.containsKey(path) ||
        _audioMetaCache.containsKey(path) ||
        _backgroundBytesCache.containsKey(path);
  }

  static Future<bool> fileExists(String path) async {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    if (fileExistsSync(path)) return true;
    if (path.startsWith('opfs://audio/')) {
      final bytes = await readAudioBytesAsync(path);
      return bytes != null && bytes.isNotEmpty;
    }
    if (path.startsWith('opfs://backgrounds/')) {
      final bytes = await readBackgroundBytesAsync(path);
      return bytes != null && bytes.isNotEmpty;
    }
    return false;
  }

  static ({int size, int modifiedAt})? statFileSync(String path) {
    final meta = _audioMetaCache[path];
    if (meta != null) return meta;
    final bytes = _audioBytesCache[path];
    if (bytes != null) return (size: bytes.length, modifiedAt: 1);
    return null;
  }

  static Future<({int size, int modifiedAt})?> statFile(String path) async {
    final syncStat = statFileSync(path);
    if (syncStat != null) return syncStat;
    if (path.startsWith('opfs://audio/')) {
      final bytes = await readAudioBytesAsync(path);
      if (bytes != null && bytes.isNotEmpty) {
        return _audioMetaCache[path] ?? (size: bytes.length, modifiedAt: 1);
      }
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
  // Image Provider & Widget Builders (OPFS + RAM Cache)
  // ---------------------------------------------------------------------------

  static Future<ImageProvider?> resolveLocalOrOpfsImageProvider(
    String pathOrUri, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (pathOrUri.startsWith('opfs://backgrounds/')) {
      final bgBytes = await readBackgroundBytesAsync(pathOrUri);
      if (bgBytes != null && bgBytes.isNotEmpty) {
        return ResizeImage.resizeIfNeeded(
          maxWidth,
          maxHeight,
          MemoryImage(bgBytes),
        );
      }
      return null;
    }
    final hash = p.basename(pathOrUri);
    final bytes = await readCoverBytesAsync(
      hash,
      thumbnailsDirectory != null
          ? p.join(thumbnailsDirectory!.path, hash)
          : hash,
    );
    if (bytes == null || bytes.isEmpty) return null;
    return ResizeImage.resizeIfNeeded(maxWidth, maxHeight, MemoryImage(bytes));
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
    final syncBytes = pathOrUri.startsWith('opfs://backgrounds/')
        ? _backgroundBytesCache[pathOrUri]
        : _coverBytesCache[p.basename(pathOrUri)];
    if (syncBytes != null && syncBytes.isNotEmpty) {
      return Image.memory(
        syncBytes,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        fit: fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return _OpfsAsyncImage(
      pathOrUri: pathOrUri,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fit: fit,
      fallback: fallback,
    );
  }

  static DateTime? tryParseHttpDate(String value) => DateTime.tryParse(value);
}

class _OpfsAsyncImage extends StatefulWidget {
  final String pathOrUri;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit fit;
  final Widget fallback;

  const _OpfsAsyncImage({
    required this.pathOrUri,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    required this.fit,
    required this.fallback,
  });

  @override
  State<_OpfsAsyncImage> createState() => _OpfsAsyncImageState();
}

class _OpfsAsyncImageState extends State<_OpfsAsyncImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _OpfsAsyncImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathOrUri != widget.pathOrUri) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final uri = widget.pathOrUri;
    final bytes = uri.startsWith('opfs://backgrounds/')
        ? await PersistentBinaryStorage.readBackgroundBytesAsync(uri)
        : await PersistentBinaryStorage.readCoverBytesAsync(uri, uri);
    if (mounted && widget.pathOrUri == uri && bytes != null) {
      setState(() {
        _bytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null || b.isEmpty) return widget.fallback;
    return Image.memory(
      b,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}
