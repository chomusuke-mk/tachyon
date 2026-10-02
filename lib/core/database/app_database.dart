import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

abstract final class AppDatabaseSchema {
  static const String createArtistsTable = '''
    CREATE TABLE IF NOT EXISTS artists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      track_count INTEGER DEFAULT 0,
      album_count INTEGER DEFAULT 0
    );
  ''';

  static const String createAlbumsTable = '''
    CREATE TABLE IF NOT EXISTS albums (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
      artist_name TEXT,
      year INTEGER,
      track_count INTEGER DEFAULT 0,
      UNIQUE(name, artist_name)
    );
  ''';

  static const String createTracksTable = '''
    CREATE TABLE IF NOT EXISTS tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL,
      artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
      album_artist TEXT,
      track_number INTEGER,
      disc_number INTEGER DEFAULT 1,
      year INTEGER,
      duration_ms INTEGER NOT NULL,
      bitrate INTEGER,
      sample_rate INTEGER,
      channels INTEGER,
      codec TEXT,
      file_size INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      lyrics TEXT,
      has_cover INTEGER DEFAULT 0
    );
  ''';

  static const String createGenresTable = '''
    CREATE TABLE IF NOT EXISTS genres (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL
    );
  ''';

  static const String createTrackGenresTable = '''
    CREATE TABLE IF NOT EXISTS track_genres (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE,
      PRIMARY KEY(track_id, genre_id)
    );
  ''';

  static const String createPlaylistsTable = '''
    CREATE TABLE IF NOT EXISTS playlists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      is_special INTEGER DEFAULT 0
    );
  ''';

  static const String createPlaylistEntriesTable = '''
    CREATE TABLE IF NOT EXISTS playlist_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      track_id INTEGER REFERENCES tracks(id) ON DELETE CASCADE,
      file_path TEXT NOT NULL,
      custom_title TEXT,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    );
  ''';

  static const String createLyricsCacheTable = '''
    CREATE TABLE IF NOT EXISTS lyrics_cache (
      key_hash TEXT PRIMARY KEY,
      raw_lrc TEXT NOT NULL,
      source TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''';

  static const String createLyricsSourceCacheTable = '''
    CREATE TABLE IF NOT EXISTS lyrics_source_cache (
      key_hash TEXT NOT NULL,
      source TEXT NOT NULL,
      state TEXT NOT NULL,
      raw_lrc TEXT,
      is_synced INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (key_hash, source)
    );
  ''';

  static const String createLyricsTranslationsTable = '''
    CREATE TABLE IF NOT EXISTS lyrics_translations (
      key_hash TEXT NOT NULL,
      source TEXT NOT NULL,
      target_lang TEXT NOT NULL,
      translated_lines TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (key_hash, source, target_lang)
    );
  ''';

  static const List<String> indexes = [
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_file_path ON tracks(file_path);',
    'CREATE INDEX IF NOT EXISTS idx_tracks_album_id ON tracks(album_id);',
    'CREATE INDEX IF NOT EXISTS idx_tracks_artist_id ON tracks(artist_id);',
    'CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_albums_name ON albums(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artist_id);',
    'CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_genres_name ON genres(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_track_genres_genre_id ON track_genres(genre_id);',
    'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_pos ON playlist_entries(playlist_id, position);',
    'CREATE INDEX IF NOT EXISTS idx_playlist_entries_track_id ON playlist_entries(track_id);',
    'CREATE INDEX IF NOT EXISTS idx_lyrics_source_cache_key ON lyrics_source_cache(key_hash);',
    'CREATE INDEX IF NOT EXISTS idx_lyrics_translations_key ON lyrics_translations(key_hash);',
  ];
}

enum ConflictAlgorithm { ignore, replace }

class SqliteDatabase {
  SqliteDatabase(this._database);

  final Database _database;

  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _database.execute(sql, parameters);
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    return _database
        .select(sql, parameters)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    int? limit,
    String? orderBy,
  }) async {
    final selectedColumns = columns?.join(', ') ?? '*';
    final sql = StringBuffer('SELECT $selectedColumns FROM $table');
    if (where != null && where.isNotEmpty) sql.write(' WHERE $where');
    if (orderBy != null && orderBy.isNotEmpty) sql.write(' ORDER BY $orderBy');
    if (limit != null) sql.write(' LIMIT $limit');
    return rawQuery(sql.toString(), whereArgs ?? const []);
  }

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final columns = values.keys.toList();
    final conflict = switch (conflictAlgorithm) {
      ConflictAlgorithm.ignore => ' OR IGNORE',
      ConflictAlgorithm.replace => ' OR REPLACE',
      null => '',
    };
    final placeholders = List.filled(columns.length, '?').join(', ');
    _database.execute(
      'INSERT$conflict INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      values.values.toList(),
    );
    return _database.lastInsertRowId;
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final assignments = values.keys.map((column) => '$column = ?').join(', ');
    final sql = StringBuffer('UPDATE $table SET $assignments');
    if (where != null && where.isNotEmpty) sql.write(' WHERE $where');
    _database.execute(sql.toString(), [...values.values, ...?whereArgs]);
    return _database.updatedRows;
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final sql = StringBuffer('DELETE FROM $table');
    if (where != null && where.isNotEmpty) sql.write(' WHERE $where');
    _database.execute(sql.toString(), whereArgs ?? const []);
    return _database.updatedRows;
  }

  Future<int> rawUpdate(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _database.execute(sql, parameters);
    return _database.updatedRows;
  }

  Future<T> transaction<T>(
    Future<T> Function(SqliteDatabase txn) action,
  ) async {
    _database.execute('BEGIN');
    try {
      final result = await action(this);
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  SqliteBatch batch() => SqliteBatch(this);
}

class SqliteBatch {
  SqliteBatch(this._database);

  final SqliteDatabase _database;
  final List<FutureOr<Object?> Function()> _operations = [];

  void insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _operations.add(
      () =>
          _database.insert(table, values, conflictAlgorithm: conflictAlgorithm),
    );
  }

  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    _operations.add(
      () => _database.update(table, values, where: where, whereArgs: whereArgs),
    );
  }

  void delete(String table, {String? where, List<Object?>? whereArgs}) {
    _operations.add(
      () => _database.delete(table, where: where, whereArgs: whereArgs),
    );
  }

  Future<List<Object?>> commit({bool noResult = false}) async {
    final results = <Object?>[];
    for (final operation in _operations) {
      final result = await operation();
      if (!noResult) results.add(result);
    }
    return results;
  }
}

class AppDatabase {
  Database? _db;
  static const int likedSongsPlaylistId = 1;
  static const int historyPlaylistId = 2;

  AppDatabase();

  /// Creates an in-memory database instance for isolated testing.
  factory AppDatabase.inMemory() {
    final appDb = AppDatabase();
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    appDb._executeSchemaSync(db);
    appDb._db = db;
    return appDb;
  }

  /// Wraps an existing sqlite3 [Database] instance.
  factory AppDatabase.forTesting(Database db) {
    final appDb = AppDatabase();
    appDb._db = db;
    db.execute('PRAGMA foreign_keys = ON;');
    appDb._executeSchemaSync(db);
    return appDb;
  }

  void _initInMemory() {
    _db = sqlite3.openInMemory();
    _db!.execute('PRAGMA foreign_keys = ON;');
    _executeSchemaSync(_db!);
  }

  Future<void> initInMemory() async {
    if (_db != null) return;
    _initInMemory();
  }

  SqliteDatabase get database {
    if (_db == null) {
      throw StateError('AppDatabase is not initialized. Call init() first.');
    }
    return SqliteDatabase(_db!);
  }

  Future<void> init([String? dbPathOverride]) async {
    if (_db != null) return;

    final String dbPath;
    if (dbPathOverride != null) {
      dbPath = dbPathOverride;
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      dbPath = p.join(appSupportDir.path, 'music.db');
    }

    _db = sqlite3.open(dbPath, mode: OpenMode.readWriteCreate);

    _db!.execute('PRAGMA foreign_keys = ON;');
    _db!.execute('PRAGMA journal_mode = WAL;');
    _db!.execute('PRAGMA synchronous = NORMAL;');
    _db!.execute('PRAGMA cache_size = -64000;'); // 64MB memory page cache

    _executeSchemaSync(_db!);
    await cleanOrphanAlbumsAndArtists();
  }

  void _executeSchemaSync(Database db) {
    // Migration: rename 'uri' column to 'file_path' in existing databases
    try {
      final trackCols = db
          .select("PRAGMA table_info(tracks)")
          .map((r) => r['name'] as String)
          .toSet();
      if (trackCols.contains('uri') && !trackCols.contains('file_path')) {
        db.execute('DROP INDEX IF EXISTS idx_tracks_uri;');
        db.execute('ALTER TABLE tracks RENAME COLUMN uri TO file_path;');
      }
    } catch (_) {}

    try {
      final entryCols = db
          .select("PRAGMA table_info(playlist_entries)")
          .map((r) => r['name'] as String)
          .toSet();
      if (entryCols.contains('uri') && !entryCols.contains('file_path')) {
        db.execute('ALTER TABLE playlist_entries RENAME COLUMN uri TO file_path;');
      }
    } catch (_) {}

    db.execute(AppDatabaseSchema.createArtistsTable);
    db.execute(AppDatabaseSchema.createAlbumsTable);
    db.execute(AppDatabaseSchema.createTracksTable);
    db.execute(AppDatabaseSchema.createGenresTable);
    db.execute(AppDatabaseSchema.createTrackGenresTable);
    db.execute(AppDatabaseSchema.createPlaylistsTable);
    db.execute(AppDatabaseSchema.createPlaylistEntriesTable);
    db.execute(AppDatabaseSchema.createLyricsCacheTable);
    db.execute(AppDatabaseSchema.createLyricsSourceCacheTable);
    db.execute(AppDatabaseSchema.createLyricsTranslationsTable);

    for (final sql in AppDatabaseSchema.indexes) {
      db.execute(sql);
    }

    // Seed special system playlists
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR IGNORE INTO playlists (id, name, created_at, is_special) VALUES (?, ?, ?, ?)',
      [
        AppDatabase.likedSongsPlaylistId,
        'Liked Songs',
        now,
        PlaylistType.liked.value,
      ],
    );

    db.execute(
      'INSERT OR IGNORE INTO playlists (id, name, created_at, is_special) VALUES (?, ?, ?, ?)',
      [
        AppDatabase.historyPlaylistId,
        'History',
        now,
        PlaylistType.history.value,
      ],
    );
  }

  Future<void> insertOrUpdateTrack(Track track) async {
    await database.transaction((txn) async {
      int? artistId = track.artistId;
      final arName = track.artist?.trim();
      if (arName != null && arName.isNotEmpty) {
        final existingArtist = await txn.query(
          'artists',
          columns: ['id'],
          where: 'LOWER(name) = LOWER(?)',
          whereArgs: [arName],
          limit: 1,
        );
        if (existingArtist.isNotEmpty) {
          artistId = existingArtist.first['id'] as int;
        } else {
          artistId = await txn.insert('artists', {
            'name': arName,
            'track_count': 0,
            'album_count': 0,
          });
        }
      }

      int? albumId = track.albumId;
      final alName = track.album?.trim();
      final canonicalAlbumArtist = (track.albumArtist != null && track.albumArtist!.trim().isNotEmpty)
          ? track.albumArtist!.trim()
          : arName;
      if (alName != null && alName.isNotEmpty) {
        final existingAlbum = await txn.query(
          'albums',
          columns: ['id', 'artist_name'],
          where: canonicalAlbumArtist != null
              ? "LOWER(name) = LOWER(?) AND (LOWER(artist_name) = LOWER(?) OR artist_name IS NULL OR artist_name = '')"
              : "LOWER(name) = LOWER(?) AND (artist_name IS NULL OR artist_name = '')",
          whereArgs: canonicalAlbumArtist != null ? [alName, canonicalAlbumArtist] : [alName],
          limit: 1,
        );
        if (existingAlbum.isNotEmpty) {
          albumId = existingAlbum.first['id'] as int;
          if (existingAlbum.first['artist_name'] == null && canonicalAlbumArtist != null) {
            await txn.update(
              'albums',
              {'artist_name': canonicalAlbumArtist, 'artist_id': artistId},
              where: 'id = ?',
              whereArgs: [albumId],
            );
          }
        } else {
          albumId = await txn.insert('albums', {
            'name': alName,
            'artist_id': artistId,
            'artist_name': canonicalAlbumArtist,
            'year': track.year,
            'track_count': 0,
          });
        }
      }

      final existingTrack = await txn.query(
        'tracks',
        columns: ['id', 'artist_id', 'album_id'],
        where: 'file_path = ?',
        whereArgs: [track.filePath],
        limit: 1,
      );

      final int? oldArtistId = existingTrack.isNotEmpty
          ? existingTrack.first['artist_id'] as int?
          : null;
      final int? oldAlbumId = existingTrack.isNotEmpty
          ? existingTrack.first['album_id'] as int?
          : null;
      final int? resolvedTrackId =
          track.id ??
          (existingTrack.isNotEmpty ? existingTrack.first['id'] as int : null);

      int trackId;
      if (existingTrack.isNotEmpty) {
        trackId = resolvedTrackId!;
        final updateMap = {
          'file_path': track.filePath,
          'title': track.title,
          'album_id': albumId,
          'artist_id': artistId,
          'album_artist': track.albumArtist,
          'track_number': track.trackNumber,
          'disc_number': track.discNumber ?? 1,
          'year': track.year,
          'duration_ms': track.durationMs,
          'bitrate': track.bitrate,
          'sample_rate': track.sampleRate,
          'channels': track.channels,
          'codec': track.codec,
          'file_size': track.fileSize,
          'modified_at': track.modifiedAt,
          'lyrics': track.lyrics,
        };
        await txn.update(
          'tracks',
          updateMap,
          where: 'id = ?',
          whereArgs: [trackId],
        );
      } else {
        final trackMap = {
          'id': ?resolvedTrackId,
          'file_path': track.filePath,
          'title': track.title,
          'album_id': albumId,
          'artist_id': artistId,
          'album_artist': track.albumArtist,
          'track_number': track.trackNumber,
          'disc_number': track.discNumber ?? 1,
          'year': track.year,
          'duration_ms': track.durationMs,
          'bitrate': track.bitrate,
          'sample_rate': track.sampleRate,
          'channels': track.channels,
          'codec': track.codec,
          'file_size': track.fileSize,
          'modified_at': track.modifiedAt,
          'lyrics': track.lyrics,
        };
        trackId = await txn.insert('tracks', trackMap);
      }

      // Sync genres
      if (track.genres.isNotEmpty) {
        await txn.delete(
          'track_genres',
          where: 'track_id = ?',
          whereArgs: [trackId],
        );
        for (final genreName in track.genres) {
          final cleanGenre = genreName.trim();
          if (cleanGenre.isEmpty) continue;
          int genreId;
          final existingGenre = await txn.query(
            'genres',
            columns: ['id'],
            where: 'name = ?',
            whereArgs: [cleanGenre],
            limit: 1,
          );
          if (existingGenre.isNotEmpty) {
            genreId = existingGenre.first['id'] as int;
          } else {
            genreId = await txn.insert('genres', {'name': cleanGenre});
          }
          await txn.insert('track_genres', {
            'track_id': trackId,
            'genre_id': genreId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      // Update counters
      final artistsToUpdate = {artistId, oldArtistId}.whereType<int>().toSet();
      for (final aId in artistsToUpdate) {
        await txn.rawUpdate(
          'UPDATE artists SET track_count = (SELECT COUNT(*) FROM tracks WHERE artist_id = ?), album_count = (SELECT COUNT(*) FROM albums WHERE artist_id = ?) WHERE id = ?',
          [aId, aId, aId],
        );
      }
      final albumsToUpdate = {albumId, oldAlbumId}.whereType<int>().toSet();
      for (final alId in albumsToUpdate) {
        await txn.rawUpdate(
          'UPDATE albums SET track_count = (SELECT COUNT(*) FROM tracks WHERE album_id = ?) WHERE id = ?',
          [alId, alId],
        );
      }
    });
  }

  Future<void> batchInsertTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    const chunkSize = 20;
    for (int i = 0; i < tracks.length; i += chunkSize) {
      final chunk = tracks.sublist(
        i,
        (i + chunkSize < tracks.length) ? i + chunkSize : tracks.length,
      );
      await database.transaction((txn) async {
        final Map<String, int> artistCache = {};
        final Map<String, int> albumCache = {};
        final Map<String, int> genreCache = {};

        for (final t in chunk) {
          final arName = t.artist?.trim();
          if (arName != null &&
              arName.isNotEmpty &&
              !artistCache.containsKey(arName.toLowerCase())) {
            final res = await txn.query(
              'artists',
              columns: ['id'],
              where: 'LOWER(name) = LOWER(?)',
              whereArgs: [arName],
              limit: 1,
            );
            if (res.isNotEmpty) {
              artistCache[arName.toLowerCase()] = res.first['id'] as int;
            } else {
              artistCache[arName.toLowerCase()] = await txn.insert('artists', {
                'name': arName,
                'track_count': 0,
                'album_count': 0,
              });
            }
          }

          final alName = t.album?.trim();
          final canonicalArtist = (t.albumArtist != null && t.albumArtist!.trim().isNotEmpty)
              ? t.albumArtist!.trim()
              : arName;
          if (alName != null && alName.isNotEmpty) {
            final cacheKey = '${alName.toLowerCase()}|${canonicalArtist?.toLowerCase() ?? ''}';
            if (!albumCache.containsKey(cacheKey)) {
              final res = await txn.query(
                'albums',
                columns: ['id'],
                where: canonicalArtist != null
                    ? "LOWER(name) = LOWER(?) AND (LOWER(artist_name) = LOWER(?) OR artist_name IS NULL OR artist_name = '')"
                    : "LOWER(name) = LOWER(?) AND (artist_name IS NULL OR artist_name = '')",
                whereArgs: canonicalArtist != null ? [alName, canonicalArtist] : [alName],
                limit: 1,
              );
              if (res.isNotEmpty) {
                albumCache[cacheKey] = res.first['id'] as int;
              } else {
                final artistId = canonicalArtist != null
                    ? artistCache[canonicalArtist.toLowerCase()]
                    : (arName != null ? artistCache[arName.toLowerCase()] : null);
                albumCache[cacheKey] = await txn.insert('albums', {
                  'name': alName,
                  'artist_id': artistId,
                  'artist_name': canonicalArtist,
                  'year': t.year,
                  'track_count': 0,
                });
              }
            }
          }
        }

        // 1. Resolve and cache genres
        final Set<String> chunkGenres = {};
        for (final t in chunk) {
          for (final g in t.genres) {
            final clean = g.trim();
            if (clean.isNotEmpty) {
              chunkGenres.add(clean);
            }
          }
        }

        if (chunkGenres.isNotEmpty) {
          final genreList = chunkGenres.toList();
          for (int gIdx = 0; gIdx < genreList.length; gIdx += 500) {
            final subGenres = genreList.sublist(
              gIdx,
              (gIdx + 500 < genreList.length) ? gIdx + 500 : genreList.length,
            );
            final placeholders = List.filled(subGenres.length, '?').join(',');
            final existingGenreRows = await txn.query(
              'genres',
              columns: ['id', 'name'],
              where: 'name IN ($placeholders)',
              whereArgs: subGenres,
            );
            for (final row in existingGenreRows) {
              genreCache[row['name'] as String] = row['id'] as int;
            }
          }

          for (final gName in chunkGenres) {
            if (!genreCache.containsKey(gName)) {
              final newId = await txn.insert('genres', {'name': gName});
              genreCache[gName] = newId;
            }
          }
        }

        // 2. Query existing tracks in chunk by filePath to preserve IDs and avoid CASCADE deletion
        final Map<String, int> existingTrackMap = {};
        final filePaths = chunk.map((t) => t.filePath).toList();
        for (int u = 0; u < filePaths.length; u += 500) {
          final subFilePaths = filePaths.sublist(
            u,
            (u + 500 < filePaths.length) ? u + 500 : filePaths.length,
          );
          final placeholders = List.filled(subFilePaths.length, '?').join(',');
          final rows = await txn.query(
            'tracks',
            columns: ['id', 'file_path'],
            where: 'file_path IN ($placeholders)',
            whereArgs: subFilePaths,
          );
          for (final row in rows) {
            existingTrackMap[row['file_path'] as String] = row['id'] as int;
          }
        }

        // 3. Batch insert/update tracks
        final List<int?> trackIds = List.filled(chunk.length, null);
        final batch = txn.batch();
        for (int idx = 0; idx < chunk.length; idx++) {
          final t = chunk[idx];
          final arId = (t.artist != null && t.artist!.trim().isNotEmpty)
              ? artistCache[t.artist!.trim().toLowerCase()]
              : null;
          final canonicalArtist = (t.albumArtist != null && t.albumArtist!.trim().isNotEmpty)
              ? t.albumArtist!.trim()
              : (t.artist != null && t.artist!.trim().isNotEmpty ? t.artist!.trim() : null);
          final alKey = '${t.album?.trim().toLowerCase() ?? ''}|${canonicalArtist?.toLowerCase() ?? ''}';
          final alId = (t.album != null && t.album!.trim().isNotEmpty)
              ? albumCache[alKey]
              : null;

          final existingId = existingTrackMap[t.filePath];
          final trackValues = {
            'file_path': t.filePath,
            'title': t.title,
            'album_id': alId,
            'artist_id': arId,
            'album_artist': t.albumArtist,
            'track_number': t.trackNumber,
            'disc_number': t.discNumber ?? 1,
            'year': t.year,
            'duration_ms': t.durationMs,
            'bitrate': t.bitrate,
            'sample_rate': t.sampleRate,
            'channels': t.channels,
            'codec': t.codec,
            'file_size': t.fileSize,
            'modified_at': t.modifiedAt,
            'lyrics': t.lyrics,
          };

          if (existingId != null) {
            trackIds[idx] = existingId;
            batch.update(
              'tracks',
              trackValues,
              where: 'id = ?',
              whereArgs: [existingId],
            );
          } else {
            batch.insert('tracks', trackValues);
          }
        }
        final results = await batch.commit(noResult: false);

        for (int idx = 0; idx < chunk.length; idx++) {
          if (trackIds[idx] == null) {
            trackIds[idx] = results[idx] as int;
          }
        }

        // 4. Batch link track_genres
        final genreBatch = txn.batch();
        for (int idx = 0; idx < chunk.length; idx++) {
          final t = chunk[idx];
          final trackId = trackIds[idx]!;
          if (t.genres.isNotEmpty) {
            genreBatch.delete(
              'track_genres',
              where: 'track_id = ?',
              whereArgs: [trackId],
            );
            for (final g in t.genres) {
              final clean = g.trim();
              if (clean.isEmpty) continue;
              final gId = genreCache[clean];
              if (gId != null) {
                genreBatch.insert('track_genres', {
                  'track_id': trackId,
                  'genre_id': gId,
                }, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            }
          }
        }
        await genreBatch.commit(noResult: true);
      });
    }

    // Refresh aggregated counts and purge orphans / duplicates
    await cleanOrphanAlbumsAndArtists();
  }

  /// Cleans up orphan albums (0 tracks), orphan artists (0 tracks), and deduplicates
  /// duplicate album entries (e.g. from case variations or NULL artist names).
  Future<void> cleanOrphanAlbumsAndArtists() async {
    await database.transaction((txn) async {
      // 1. Deduplicate albums with the same (case-insensitive name, artist_name)
      final duplicateGroups = await txn.rawQuery('''
        SELECT LOWER(name) as low_name, LOWER(COALESCE(artist_name, '')) as low_artist, COUNT(*) as cnt
        FROM albums
        GROUP BY LOWER(name), LOWER(COALESCE(artist_name, ''))
        HAVING COUNT(*) > 1
      ''');

      for (final group in duplicateGroups) {
        final lowName = group['low_name'] as String;
        final lowArtist = group['low_artist'] as String;
        final rows = await txn.rawQuery(
          '''
          SELECT id FROM albums 
          WHERE LOWER(name) = ? AND LOWER(COALESCE(artist_name, '')) = ?
          ORDER BY id ASC
        ''',
          [lowName, lowArtist],
        );
        if (rows.length > 1) {
          final canonicalId = rows.first['id'] as int;
          final duplicateIds = rows.skip(1).map((r) => r['id'] as int).toList();
          final placeholders = List.filled(duplicateIds.length, '?').join(',');

          // Re-link tracks pointing to duplicate album IDs to the canonical album ID
          await txn.rawUpdate(
            'UPDATE tracks SET album_id = ? WHERE album_id IN ($placeholders)',
            [canonicalId, ...duplicateIds],
          );

          // Delete the duplicate album rows
          await txn.execute(
            'DELETE FROM albums WHERE id IN ($placeholders)',
            duplicateIds,
          );
        }
      }

      // 2. Remove orphan albums that have no tracks referencing them
      await txn.execute('''
        DELETE FROM albums 
        WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL);
      ''');

      // 3. Remove orphan artists that have no tracks or albums
      await txn.execute('''
        DELETE FROM artists 
        WHERE id NOT IN (SELECT DISTINCT artist_id FROM tracks WHERE artist_id IS NOT NULL)
          AND id NOT IN (SELECT DISTINCT artist_id FROM albums WHERE artist_id IS NOT NULL);
      ''');

      // 4. Remove orphan genres
      await txn.execute('''
        DELETE FROM genres 
        WHERE id NOT IN (SELECT DISTINCT genre_id FROM track_genres);
      ''');

      // 5. Update counts
      await txn.execute('''
        UPDATE artists SET 
          track_count = (SELECT COUNT(*) FROM tracks WHERE tracks.artist_id = artists.id),
          album_count = (SELECT COUNT(*) FROM albums WHERE albums.artist_id = artists.id);
      ''');
      await txn.execute('''
        UPDATE albums SET 
          track_count = (SELECT COUNT(*) FROM tracks WHERE tracks.album_id = albums.id);
      ''');
    });
  }

  Future<void> deleteTrack(int trackId) async {
    await database.delete(
      'tracks',
      where: 'id = ?',
      whereArgs: [trackId],
    );
    await cleanOrphanAlbumsAndArtists();
  }

  Future<void> deleteTracksInFolder(String folderPath) async {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    await database.delete(
      'tracks',
      where: "file_path LIKE ?",
      whereArgs: ['${prefix.replaceAll('%', r'\%').replaceAll('_', r'\_')}%'],
    );
    await cleanOrphanAlbumsAndArtists();
  }

  Future<List<Track>> getAllTracks({
    String? sortBy,
    bool ascending = true,
  }) async {
    final dir = ascending ? 'ASC' : 'DESC';
    String orderClause;
    switch (sortBy?.toLowerCase()) {
      case 'artist':
        orderClause =
            'ar.name COLLATE NOCASE $dir, t.year ASC, t.track_number ASC';
        break;
      case 'album':
        orderClause =
            'al.name COLLATE NOCASE $dir, t.disc_number ASC, t.track_number ASC';
        break;
      case 'year':
        orderClause = 't.year $dir, t.title COLLATE NOCASE ASC';
        break;
      case 'duration':
        orderClause = 't.duration_ms $dir';
        break;
      case 'dateadded':
      case 'modified':
        orderClause = 't.modified_at $dir';
        break;
      case 'title':
      default:
        orderClause = 't.title COLLATE NOCASE $dir';
        break;
    }

    final rows = await database.rawQuery('''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        NULL AS lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name
      FROM tracks t
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      ORDER BY $orderClause
    ''');

    final tracks = rows.map((r) => Track.fromJson(r)).toList();
    try {
      final genreRows = await database.rawQuery('''
        SELECT tg.track_id, g.name AS genre_name
        FROM track_genres tg
        JOIN genres g ON tg.genre_id = g.id
      ''');
      final trackGenreMap = <int, List<String>>{};
      for (final row in genreRows) {
        final tId = row['track_id'] as int;
        final gName = row['genre_name'] as String;
        (trackGenreMap[tId] ??= []).add(gName);
      }
      return tracks.map((t) {
        if (t.id != null && trackGenreMap.containsKey(t.id)) {
          return t.copyWith(genres: trackGenreMap[t.id]);
        }
        return t;
      }).toList();
    } catch (_) {
      return tracks;
    }
  }

  /// Retrieves raw embedded lyrics for a track by its [filePath] on-demand.
  /// Prevents loading heavy lyric blobs into memory during full catalog scans.
  Future<String?> getTrackLyricsByFilePath(String filePath) async {
    String cleanPath = filePath;
    if (cleanPath.startsWith('file://')) {
      try {
        cleanPath = Uri.parse(cleanPath).toFilePath();
      } catch (_) {}
    }
    final rows = await database.query(
      'tracks',
      columns: ['lyrics'],
      where: 'file_path = ? OR file_path = ?',
      whereArgs: [cleanPath, filePath],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['lyrics'] as String?;
    }
    return null;
  }

  /// Retrieves a full [Track] by its [filePath].
  Future<Track?> getTrackByFilePath(String filePath) async {
    String cleanPath = filePath;
    if (cleanPath.startsWith('file://')) {
      try {
        cleanPath = Uri.parse(cleanPath).toFilePath();
      } catch (_) {}
    }
    final rows = await database.rawQuery('''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        t.lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name
      FROM tracks t
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      WHERE t.file_path = ? OR t.file_path = ?
      LIMIT 1
    ''', [cleanPath, filePath]);

    if (rows.isNotEmpty) {
      return Track.fromJson(rows.first);
    }
    return null;
  }

  /// Updates the `has_cover` flag for a track identified by its [filePath].
  Future<void> updateTrackCoverStatus(String filePath, bool hasCover) async {
    String cleanPath = filePath;
    if (cleanPath.startsWith('file://')) {
      try {
        cleanPath = Uri.parse(cleanPath).toFilePath();
      } catch (_) {}
    }
    await database.execute(
      'UPDATE tracks SET has_cover = ? WHERE file_path = ? OR file_path = ?',
      [hasCover ? 1 : 0, cleanPath, filePath],
    );
  }

  /// Retrieves raw embedded lyrics for a track by its [trackId] on-demand.
  Future<String?> getTrackLyrics(int trackId) async {
    final rows = await database.query(
      'tracks',
      columns: ['lyrics'],
      where: 'id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['lyrics'] as String?;
    }
    return null;
  }

  /// Returns a map of `filePath` -> `(modifiedAt, fileSize)` for all tracks currently in the database.
  /// Used by `MetadataExtractor` to perform incremental scans without re-reading unchanged files.
  Future<Map<String, ({int modifiedAt, int fileSize})>> getExistingTrackMetas() async {
    final rows = await database.query(
      'tracks',
      columns: ['file_path', 'modified_at', 'file_size'],
    );
    final result = <String, ({int modifiedAt, int fileSize})>{};
    for (final row in rows) {
      final filePath = row['file_path'] as String?;
      final modifiedAt = row['modified_at'] as int?;
      final fileSize = row['file_size'] as int?;
      if (filePath != null && modifiedAt != null && fileSize != null) {
        result[filePath] = (modifiedAt: modifiedAt, fileSize: fileSize);
      }
    }
    return result;
  }

  Future<List<Album>> getAllAlbums() async {
    final rows = await database.rawQuery('''
      SELECT 
        al.id, al.name, al.artist_id, al.artist_name, al.year,
        COUNT(t.id) AS track_count
      FROM albums al
      LEFT JOIN tracks t ON t.album_id = al.id
      GROUP BY al.id
      HAVING COUNT(t.id) > 0
      ORDER BY al.name COLLATE NOCASE ASC
    ''');
    return rows.map((r) => Album.fromJson(r)).toList();
  }

  Future<List<Artist>> getAllArtists() async {
    final rows = await database.rawQuery('''
      SELECT 
        ar.id, ar.name,
        COUNT(DISTINCT t.id) AS track_count,
        COUNT(DISTINCT al.id) AS album_count
      FROM artists ar
      LEFT JOIN tracks t ON t.artist_id = ar.id
      LEFT JOIN albums al ON al.artist_id = ar.id
      GROUP BY ar.id
      HAVING COUNT(DISTINCT t.id) > 0
      ORDER BY ar.name COLLATE NOCASE ASC
    ''');
    return rows.map((r) => Artist.fromJson(r)).toList();
  }

  Future<List<Genre>> getAllGenres() async {
    final rows = await database.rawQuery('''
      SELECT 
        g.id, g.name,
        COUNT(tg.track_id) AS track_count
      FROM genres g
      LEFT JOIN track_genres tg ON g.id = tg.genre_id
      GROUP BY g.id
      HAVING COUNT(tg.track_id) > 0
      ORDER BY g.name COLLATE NOCASE ASC
    ''');
    return rows.map((r) => Genre.fromJson(r)).toList();
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final rows = await database.rawQuery('''
      SELECT 
        p.id, p.name, p.created_at, p.is_special,
        COUNT(pe.id) AS track_count
      FROM playlists p
      LEFT JOIN playlist_entries pe ON p.id = pe.playlist_id
      GROUP BY p.id
      ORDER BY p.is_special DESC, p.created_at ASC
    ''');
    return rows.map((r) => Playlist.fromJson(r)).toList();
  }

  Future<List<Track>> getTracksForPlaylist(int playlistId) async {
    final rows = await database.rawQuery(
      '''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        t.lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name,
        pe.position, pe.added_at
      FROM playlist_entries pe
      JOIN tracks t ON pe.track_id = t.id
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      WHERE pe.playlist_id = ?
      ORDER BY pe.position ASC
    ''',
      [playlistId],
    );
    return rows.map((r) => Track.fromJson(r)).toList();
  }

  /// Returns the set of track IDs in the given [playlistId].
  /// Directly queries the `playlist_entries` table without joining or instantiating [Track] models.
  Future<Set<int>> getTrackIdsForPlaylist(int playlistId) async {
    final rows = await database.query(
      'playlist_entries',
      columns: ['track_id'],
      where: 'playlist_id = ? AND track_id IS NOT NULL',
      whereArgs: [playlistId],
    );
    return rows.map((r) => r['track_id'] as int).toSet();
  }

  Future<int> createPlaylist(String name) async {
    return await database.insert('playlists', {
      'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_special': PlaylistType.user.value,
    });
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId, [String? filePath]) async {
    await database.transaction((txn) async {
      final trackRow = await txn.query(
        'tracks',
        columns: ['file_path', 'title'],
        where: 'id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      if (trackRow.isEmpty) return;

      final resolvedFilePath = filePath ?? (trackRow.first['file_path'] as String);
      final title = trackRow.first['title'] as String;

      final posRes = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_entries WHERE playlist_id = ?',
        [playlistId],
      );
      final nextPos = (posRes.first['next_pos'] as int?) ?? 0;

      await txn.insert('playlist_entries', {
        'playlist_id': playlistId,
        'track_id': trackId,
        'file_path': resolvedFilePath,
        'custom_title': title,
        'position': nextPos,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await database.transaction((txn) async {
      await txn.delete(
        'playlist_entries',
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [playlistId, trackId],
      );

      final remaining = await txn.query(
        'playlist_entries',
        columns: ['id'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );

      final batch = txn.batch();
      for (int i = 0; i < remaining.length; i++) {
        batch.update(
          'playlist_entries',
          {'position': i},
          where: 'id = ?',
          whereArgs: [remaining[i]['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> reorderPlaylistEntries(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    await database.transaction((txn) async {
      final entries = await txn.query(
        'playlist_entries',
        columns: ['id'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );

      if (fromIndex < 0 || fromIndex >= entries.length) return;
      if (toIndex < 0 || toIndex >= entries.length) return;

      final entryIds = entries.map((e) => e['id'] as int).toList();
      final movedId = entryIds.removeAt(fromIndex);
      entryIds.insert(toIndex, movedId);

      final batch = txn.batch();
      for (int i = 0; i < entryIds.length; i++) {
        batch.update(
          'playlist_entries',
          {'position': i},
          where: 'id = ?',
          whereArgs: [entryIds[i]],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Track>> searchTracks(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final wildcard = '%$clean%';
    final prefix = '$clean%';

    final rows = await database.rawQuery(
      '''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        NULL AS lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name
      FROM tracks t
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      WHERE t.title LIKE ? OR ar.name LIKE ? OR al.name LIKE ?
      ORDER BY 
        CASE 
          WHEN t.title LIKE ? THEN 1
          WHEN ar.name LIKE ? THEN 2
          WHEN al.name LIKE ? THEN 3
          ELSE 4
        END,
        t.title COLLATE NOCASE ASC
      LIMIT ${100}
    ''',
      [wildcard, wildcard, wildcard, prefix, prefix, prefix],
    );

    return rows.map((r) => Track.fromJson(r)).toList();
  }

  Future<void> deletePlaylist(int playlistId) async {
    // Only user-created playlists (is_special = 0) can be deleted
    await database.delete(
      'playlists',
      where: 'id = ? AND is_special = 0',
      whereArgs: [playlistId],
    );
  }

  Future<void> renamePlaylist(int playlistId, String name) async {
    await database.update(
      'playlists',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    for (final trackId in trackIds) {
      await addTrackToPlaylist(playlistId, trackId);
    }
  }

  /// Convenience alias for [insertOrUpdateTrack].
  Future<void> insertTrack(Track track) => insertOrUpdateTrack(track);

  /// Retrieves tracks belonging to a given [albumId].
  Future<List<Track>> getTracksByAlbumId(int albumId) async {
    final rows = await database.rawQuery('''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        NULL AS lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name
      FROM tracks t
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      WHERE t.album_id = ?
      ORDER BY t.disc_number ASC, t.track_number ASC
    ''', [albumId]);
    return rows.map((r) => Track.fromJson(r)).toList();
  }

  /// Retrieves tracks belonging to a given [artistId].
  Future<List<Track>> getTracksByArtistId(int artistId) async {
    final rows = await database.rawQuery('''
      SELECT 
        t.id, t.file_path, t.title, t.album_id, t.artist_id, t.album_artist,
        t.track_number, t.disc_number, t.year, t.duration_ms, t.bitrate,
        t.sample_rate, t.channels, t.codec, t.file_size, t.modified_at,
        NULL AS lyrics, t.has_cover,
        al.name AS album_name,
        ar.name AS artist_name
      FROM tracks t
      LEFT JOIN albums al ON t.album_id = al.id
      LEFT JOIN artists ar ON t.artist_id = ar.id
      WHERE t.artist_id = ?
      ORDER BY t.title COLLATE NOCASE ASC
    ''', [artistId]);
    return rows.map((r) => Track.fromJson(r)).toList();
  }

  /// Searches albums by name or artist matching [query].
  Future<List<Album>> searchAlbums(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    final wildcard = '%$clean%';
    final rows = await database.rawQuery('''
      SELECT 
        al.id, al.name, al.artist_id, al.artist_name, al.year,
        COUNT(t.id) AS track_count
      FROM albums al
      LEFT JOIN tracks t ON t.album_id = al.id
      WHERE al.name LIKE ? OR al.artist_name LIKE ?
      GROUP BY al.id
      HAVING COUNT(t.id) > 0
      ORDER BY al.name COLLATE NOCASE ASC
    ''', [wildcard, wildcard]);
    return rows.map((r) => Album.fromJson(r)).toList();
  }

  /// Searches artists by name matching [query].
  Future<List<Artist>> searchArtists(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    final wildcard = '%$clean%';
    final rows = await database.rawQuery('''
      SELECT 
        ar.id, ar.name,
        COUNT(DISTINCT t.id) AS track_count,
        COUNT(DISTINCT al.id) AS album_count
      FROM artists ar
      LEFT JOIN tracks t ON t.artist_id = ar.id
      LEFT JOIN albums al ON al.artist_id = ar.id
      WHERE ar.name LIKE ?
      GROUP BY ar.id
      HAVING COUNT(DISTINCT t.id) > 0
      ORDER BY ar.name COLLATE NOCASE ASC
    ''', [wildcard]);
    return rows.map((r) => Artist.fromJson(r)).toList();
  }

  /// Persists or updates a [LyricsSourceEntry] in SQLite.
  /// Overwrites existing entries matching (key_hash, source).
  /// If entry is found with lyrics, also mirrors to legacy [lyrics_cache].
  Future<void> saveLyricsSourceEntry(LyricsSourceEntry entry) async {
    await database.insert(
      'lyrics_source_cache',
      entry.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (entry.state == LyricsSourceState.found && entry.rawLrc != null) {
      await database.insert(
        'lyrics_cache',
        {
          'key_hash': entry.keyHash,
          'raw_lrc': entry.rawLrc!,
          'source': entry.source.dbValue,
          'updated_at': entry.updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Bulk-persists multiple [LyricsSourceEntry] instances within an atomic transaction.
  Future<void> saveLyricsSourceEntries(List<LyricsSourceEntry> entries) async {
    if (entries.isEmpty) return;
    await database.transaction((txn) async {
      for (final entry in entries) {
        await txn.insert(
          'lyrics_source_cache',
          entry.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (entry.state == LyricsSourceState.found && entry.rawLrc != null) {
          await txn.insert(
            'lyrics_cache',
            {
              'key_hash': entry.keyHash,
              'raw_lrc': entry.rawLrc!,
              'source': entry.source.dbValue,
              'updated_at': entry.updatedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// Retrieves the cached [LyricsSourceEntry] for a given [keyHash] and [source].
  Future<LyricsSourceEntry?> getLyricsSourceEntry(
    String keyHash,
    LyricsSource source,
  ) async {
    final rows = await database.query(
      'lyrics_source_cache',
      where: 'key_hash = ? AND source = ?',
      whereArgs: [keyHash, source.dbValue],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LyricsSourceEntry.fromDbMap(rows.first);
  }

  /// Retrieves all cached entries for [keyHash] across all sources.
  Future<Map<LyricsSource, LyricsSourceEntry>> getAllLyricsSourceEntries(
    String keyHash,
  ) async {
    final rows = await database.query(
      'lyrics_source_cache',
      where: 'key_hash = ?',
      whereArgs: [keyHash],
    );
    final map = <LyricsSource, LyricsSourceEntry>{};
    for (final row in rows) {
      final entry = LyricsSourceEntry.fromDbMap(row);
      map[entry.source] = entry;
    }
    return map;
  }

  /// Clears all cached source entries and legacy cache for a given song [keyHash] (used by "Volver a buscar").
  Future<int> clearLyricsSourceEntries(String keyHash) async {
    await database.delete(
      'lyrics_cache',
      where: 'key_hash = ?',
      whereArgs: [keyHash],
    );
    await database.delete(
      'lyrics_translations',
      where: 'key_hash = ?',
      whereArgs: [keyHash],
    );
    return database.delete(
      'lyrics_source_cache',
      where: 'key_hash = ?',
      whereArgs: [keyHash],
    );
  }

  /// Persists a translated version of lyrics for [keyHash], [source], and [targetLang].
  Future<void> saveLyricsTranslation({
    required String keyHash,
    required String source,
    required String targetLang,
    required List<String> translatedLines,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert(
      'lyrics_translations',
      {
        'key_hash': keyHash,
        'source': source,
        'target_lang': targetLang,
        'translated_lines': jsonEncode(translatedLines),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves cached translated lines for [keyHash], [source], and [targetLang].
  Future<List<String>?> getLyricsTranslation({
    required String keyHash,
    required String source,
    required String targetLang,
  }) async {
    final rows = await database.query(
      'lyrics_translations',
      columns: ['translated_lines'],
      where: 'key_hash = ? AND source = ? AND target_lang = ?',
      whereArgs: [keyHash, source, targetLang],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final jsonStr = rows.first['translated_lines'] as String;
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  /// Deletes all cached translations for a specific song [keyHash].
  Future<int> clearLyricsTranslations(String keyHash) async {
    return database.delete(
      'lyrics_translations',
      where: 'key_hash = ?',
      whereArgs: [keyHash],
    );
  }

  /// Deletes the cached entry for a specific [source] of [keyHash].
  Future<int> deleteLyricsSourceEntry(
    String keyHash,
    LyricsSource source,
  ) async {
    return database.delete(
      'lyrics_source_cache',
      where: 'key_hash = ? AND source = ?',
      whereArgs: [keyHash, source.dbValue],
    );
  }

  Future<void> saveLyrics(String keyHash, String rawLrc, String source) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert('lyrics_cache', {
      'key_hash': keyHash,
      'raw_lrc': rawLrc,
      'source': source,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final parsedSource = LyricsSource.tryParse(source) ?? LyricsSource.embedded;
    await database.insert(
      'lyrics_source_cache',
      {
        'key_hash': keyHash,
        'source': parsedSource.dbValue,
        'state': LyricsSourceState.found.dbValue,
        'raw_lrc': rawLrc,
        'is_synced': RegExp(r'\[\d{1,}:\d{2}\.\d{2,3}\]').hasMatch(rawLrc) ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getLyrics(String keyHash) async {
    final rows = await database.query(
      'lyrics_cache',
      columns: ['raw_lrc'],
      where: 'key_hash = ?',
      whereArgs: [keyHash],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['raw_lrc'] as String?;
    }

    final sourceRows = await database.query(
      'lyrics_source_cache',
      where: 'key_hash = ? AND state = ? AND raw_lrc IS NOT NULL',
      whereArgs: [keyHash, LyricsSourceState.found.dbValue],
    );
    if (sourceRows.isEmpty) return null;

    LyricsSourceEntry? best;
    for (final row in sourceRows) {
      final entry = LyricsSourceEntry.fromDbMap(row);
      if (best == null || entry.source.priority < best.source.priority) {
        best = entry;
      }
    }
    return best?.rawLrc;
  }

  Future<bool> isTrackLiked(int trackId) async {
    final res = await database.query(
      'playlist_entries',
      columns: ['id'],
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [AppDatabase.likedSongsPlaylistId, trackId],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  Future<void> toggleLikeTrack(int trackId, [String? filePath]) async {
    final liked = await isTrackLiked(trackId);
    if (liked) {
      await removeTrackFromPlaylist(AppDatabase.likedSongsPlaylistId, trackId);
    } else {
      await addTrackToPlaylist(AppDatabase.likedSongsPlaylistId, trackId, filePath);
    }
  }

  Future<void> clearHistory() async {
    await database.delete(
      'playlist_entries',
      where: 'playlist_id = ?',
      whereArgs: [AppDatabase.historyPlaylistId],
    );
  }

  Future<void> close() async {
    if (_db != null) {
      _db!.close();
      _db = null;
    }
  }
}
