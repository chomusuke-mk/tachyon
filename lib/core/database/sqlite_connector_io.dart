import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens a new in-memory SQLite database on native platforms.
CommonDatabase openInMemoryDatabase() => sqlite3.openInMemory();

/// Opens or creates a persistent SQLite database at [dbPath] on native platforms.
///
/// When [dbPath] is `null` or empty, defaults to `music.db` inside the
/// application support directory.
Future<CommonDatabase> openPersistentDatabase(String? dbPath) async {
  String resolvedPath;
  if (dbPath != null && dbPath.isNotEmpty) {
    resolvedPath = dbPath;
  } else {
    final dir = await getApplicationSupportDirectory();
    resolvedPath = p.join(dir.path, 'music.db');
  }
  return sqlite3.open(resolvedPath, mode: OpenMode.readWriteCreate);
}

/// Flushes pending persistent database writes to storage.
///
/// This is a no-op on native platforms because `sqlite3` writes directly to disk.
Future<void> flushPersistentDatabase() async {}
