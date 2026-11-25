import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show DiagnosticsProperty, SynchronousFuture;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/logging/app_logger.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Virtual directory descriptor on Web (backed by OPFS).
class StorageDirectory {
  /// Virtual directory path.
  final String path;

  /// Creates a virtual directory descriptor for [path].
  const StorageDirectory(this.path);
}

/// Virtual file reference on Web (backed by OPFS).
class StorageFileRef {
  /// Virtual file path.
  final String path;

  /// Creates a virtual file reference for [path].
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
  static const _log = ScopedLogger('PersistentBinaryStorage');

  /// Virtual temporary directory descriptor.
  static StorageDirectory? tempDirectory;

  /// Virtual directory descriptor for cached cover art.
  static StorageDirectory? thumbnailsDirectory;

  static final Set<String> _knownCoverHashes = <String>{};
  static final Set<String> _knownBackgroundFiles = <String>{};
  static final Map<String, ({int size, int modifiedAt})> _audioMetaCache =
      <String, ({int size, int modifiedAt})>{};

  static web.FileSystemDirectoryHandle? _coversDirHandle;
  static web.FileSystemDirectoryHandle? _audioDirHandle;
  static web.FileSystemDirectoryHandle? _backgroundsDirHandle;
  static Future<void>? _opfsInitFuture;

  /// Estimated number of logical processor cores reported by the browser.
  static int get processorCount {
    try {
      final hc = web.window.navigator.hardwareConcurrency;
      return hc > 0 ? hc : 4;
    } catch (_) {
      return 4;
    }
  }

  /// Whether the current platform is Linux (always `false` on web).
  static bool get isLinux => false;

  /// Whether the current platform is Windows (always `false` on web).
  static bool get isWindows => false;

  /// Whether the current platform is Android (always `false` on web).
  static bool get isAndroid => false;

  /// Whether the current platform is iOS (always `false` on web).
  static bool get isIOS => false;

  /// Whether the current platform is macOS (always `false` on web).
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

  /// Sets [thumbnailsDirectory] and [tempDirectory] and triggers [initAsync].
  ///
  /// Uses [thumbnailsPath] and [tempPath] as virtual root paths.
  static void init(String thumbnailsPath, String tempPath) {
    tempDirectory = StorageDirectory(tempPath);
    thumbnailsDirectory = StorageDirectory(thumbnailsPath);
    unawaited(initAsync(thumbnailsPath: thumbnailsPath, tempPath: tempPath));
  }

  /// Initializes virtual storage paths and indexes existing OPFS directories.
  ///
  /// Optionally overrides [thumbnailsPath] and [tempPath] before opening OPFS
  /// handles.
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
      _log.e('OPFS init error', error: e);
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
      _log.e('OPFS write error ($fileName)', error: e);
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

  /// Ensures [tempDirectory] and [thumbnailsDirectory] have default descriptors.
  static void ensureInitialized() {
    tempDirectory ??= const StorageDirectory('/temp');
    thumbnailsDirectory ??= const StorageDirectory('/covers');
  }

  /// Ensures virtual storage descriptors are initialized (no-op on web).
  static Future<void> clearTempDirectory() async {
    ensureInitialized();
  }

  /// Returns whether the cover hash derived from [artworkUri] is indexed in OPFS.
  ///
  /// Ignores [resolvedArtworkPath] on web.
  static bool hasCachedArtwork(String artworkUri, String resolvedArtworkPath) {
    ensureInitialized();
    final hash = p.basename(artworkUri);
    return _knownCoverHashes.contains(hash);
  }

  /// Writes cover art [bytes] for [hash] into the OPFS `covers` directory.
  ///
  /// Ignores [targetFilePath] on web and skips writing if already cached.
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

  /// Resolves cached cover bytes for [artworkUri] as an inline `data:` URI.
  static Future<Uri?> resolveCoverDataUriAsync(String artworkUri) async {
    final hash = p.basename(artworkUri.trim());
    if (hash.isEmpty) return null;
    final bytes = await _readOpfsImageBytes('covers', hash);
    if (bytes == null || bytes.isEmpty) return null;
    return Uri.dataFromBytes(bytes, mimeType: 'image/jpeg');
  }

  /// Returns virtual [StorageFileRef] entries for all indexed cached covers.
  static List<StorageFileRef> listCachedCoverFiles() {
    ensureInitialized();
    final base = thumbnailsDirectory!.path;
    return [
      for (final hash in _knownCoverHashes)
        StorageFileRef(p.join(base, hash)),
    ];
  }

  /// Evicts and deletes OPFS cover entries whose names are not in [validFileNames].
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

  /// Writes picked audio [bytes] under a sanitized [fileName] into OPFS `audio/`.
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

  /// Deletes a browser-picked audio file at [uriOrPath] from OPFS `audio/`.
  static Future<void> removeWebAudioFile(String uriOrPath) async {
    final parsed = _parseOpfsPath(uriOrPath);
    if (parsed?.dir == 'audio') {
      _audioMetaCache.remove('/audio/${parsed!.fileName}');
      await (_opfsInitFuture ??= _initOpfsHandles());
      await _deleteOpfsFile(_audioDirHandle, parsed.fileName);
    }
  }

  /// Writes custom background [bytes] under a sanitized [fileName] into OPFS `backgrounds/`.
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

  /// Returns [sourceImagePath] if it exists in OPFS or is an HTTP(S) URL, or `null`.
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

  /// Always returns `false` because local filesystem directories do not exist at [path] on web.
  static bool directoryExistsSync(String path) => false;

  /// Always returns `false` because local filesystem directories do not exist at [path] on web.
  static Future<bool> directoryExists(String path) async => false;

  /// Synchronously checks whether [path] is an HTTP(S) URL or an indexed OPFS entry.
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

  /// Asynchronously checks whether [path] is an HTTP(S) URL or exists in OPFS.
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

  /// Returns cached or queried byte size and modification timestamp for an OPFS audio [path].
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

  /// Always returns an empty list because local subdirectories of [dirPath] are unavailable on web.
  static List<String> listSubdirectoriesSync(String dirPath) => const [];

  /// Emits an empty stream because scanning [directories] for [supportedExtensions] is unsupported on web.
  ///
  /// Ignores [isCancelled] because no scan is performed.
  static Stream<({String path, int size, int modifiedAt})>
  discoverAudioFilesStream(
    List<String> directories,
    Set<String> supportedExtensions, {
    bool Function()? isCancelled,
  }) async* {}

  /// Always returns `null` because adjacent local files for [audioFilePath] are unavailable on web.
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

  /// Resolves an OPFS-backed [ImageProvider] for [pathOrUri].
  ///
  /// Optionally resizes the decoded image to [maxWidth] and [maxHeight], or
  /// returns `null` if the resolved filename is empty.
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

  /// Builds an OPFS-backed image widget for [pathOrUri], or returns [fallback].
  ///
  /// Applies optional layout dimensions ([width], [height]), decode hints
  /// ([cacheWidth], [cacheHeight]), and box [fit].
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

  /// Parses [value] as an ISO-8601 timestamp, returning `null` if invalid.
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
