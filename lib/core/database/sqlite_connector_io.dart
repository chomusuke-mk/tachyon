import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

CommonDatabase openInMemoryDatabase() => sqlite3.openInMemory();

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

Future<void> flushPersistentDatabase() async {}
