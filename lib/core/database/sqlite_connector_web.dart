import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/wasm.dart';

WasmSqlite3? _wasmSqlite;
IndexedDbFileSystem? _indexedDbFs;
bool _vfsRegistered = false;

Future<WasmSqlite3> _ensureWasmSqlite() async {
  if (_wasmSqlite != null) return _wasmSqlite!;
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  if (!_vfsRegistered) {
    try {
      final fs = await IndexedDbFileSystem.open(dbName: 'tachyon_music_db');
      sqlite.registerVirtualFileSystem(fs, makeDefault: true);
      _indexedDbFs = fs;
    } catch (e) {
      debugPrint(
        '[SqliteConnectorWeb] IndexedDbFileSystem fallback to InMemoryFileSystem: $e',
      );
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
    }
    _vfsRegistered = true;
  }
  _wasmSqlite = sqlite;
  return sqlite;
}

/// Flushes pending persistent IndexedDB filesystem writes on Web.
Future<void> flushPersistentDatabase() async {
  await _indexedDbFs?.flush();
}

/// Opens a new in-memory SQLite database via WebAssembly on Web.
///
/// Throws a [StateError] if [openPersistentDatabase] has not initialized
/// `WasmSqlite3` yet.
CommonDatabase openInMemoryDatabase() {
  final sqlite = _wasmSqlite;
  if (sqlite == null) {
    throw StateError(
      'WasmSqlite3 is not initialized synchronously. Call openPersistentDatabase first on Web.',
    );
  }
  return sqlite.openInMemory();
}

/// Opens or creates a persistent SQLite database at [dbPath] on Web.
///
/// Initializes `WasmSqlite3` and registers IndexedDB storage (falling back
/// to an in-memory virtual filesystem) before opening [dbPath], defaulting
/// to `/database` when omitted or empty.
Future<CommonDatabase> openPersistentDatabase(String? dbPath) async {
  final sqlite = await _ensureWasmSqlite();
  final target = (dbPath != null && dbPath.isNotEmpty) ? dbPath : '/database';
  return sqlite.open(target);
}
