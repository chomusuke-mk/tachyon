// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart' show ExtractedTrackData;
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/playlist.dart' show PlaylistType;

export 'package:tachyon/core/metadata/metadata_utils.dart' show ExtractedTrackData;
export 'package:tachyon/core/playback/domain/radio_station.dart';

abstract final class AppDatabaseSchema {
  static const List<String> createTables = [
    'CREATE TABLE IF NOT EXISTS artists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE, thumbnail_hash TEXT);',
    'CREATE TABLE IF NOT EXISTS albums (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE, year INTEGER, artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL, thumbnail_hash TEXT, UNIQUE(name COLLATE NOCASE, artist_id));',
    'CREATE TABLE IF NOT EXISTS tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, file_path TEXT UNIQUE NOT NULL, title TEXT NOT NULL, track_number INTEGER, disc_number INTEGER DEFAULT 1, year INTEGER, duration_ms INTEGER NOT NULL, bitrate INTEGER, sample_rate INTEGER, channels INTEGER, codec TEXT, file_size INTEGER NOT NULL, modified_at INTEGER NOT NULL, replay_gain_track_gain REAL, replay_gain_track_peak REAL, waveform_data TEXT, album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL, thumbnail_hash TEXT);',
    'CREATE TABLE IF NOT EXISTS genres (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE);',
    'CREATE TABLE IF NOT EXISTS track_genres (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE, PRIMARY KEY(track_id, genre_id));',
    'CREATE TABLE IF NOT EXISTS track_artists (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, artist_id INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE, PRIMARY KEY(track_id, artist_id));',
    'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at INTEGER NOT NULL, type INTEGER DEFAULT 0);',
    'CREATE TABLE IF NOT EXISTS playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, position INTEGER NOT NULL, added_at INTEGER NOT NULL, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id INTEGER REFERENCES tracks(id) ON DELETE CASCADE);',
    'CREATE TABLE IF NOT EXISTS lyrics (id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, source TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'FOUND\', raw_lrc TEXT, is_synced INTEGER DEFAULT 0, lang TEXT, updated_at INTEGER NOT NULL, UNIQUE(track_id, source));',
    'CREATE TABLE IF NOT EXISTS lyrics_translations (id INTEGER PRIMARY KEY AUTOINCREMENT, lyrics_id INTEGER NOT NULL REFERENCES lyrics(id) ON DELETE CASCADE, lang TEXT NOT NULL, translated_lines TEXT NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(lyrics_id, lang));',
    'CREATE TABLE IF NOT EXISTS radio_stations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, stream_url TEXT NOT NULL UNIQUE, homepage_url TEXT, favicon_url TEXT, genre TEXT, country TEXT, bitrate_kbps INTEGER, codec TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);',
  ];

  static const List<String> indexes = [
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_file_path ON tracks(file_path);',
    'CREATE INDEX IF NOT EXISTS idx_tracks_album_id ON tracks(album_id);',
    'CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_albums_name ON albums(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artist_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_albums_name_null_artist ON albums(name COLLATE NOCASE) WHERE artist_id IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_genres_name ON genres(name COLLATE NOCASE);',
    'CREATE INDEX IF NOT EXISTS idx_track_genres_genre_id ON track_genres(genre_id);',
    'CREATE INDEX IF NOT EXISTS idx_track_artists_artist_id ON track_artists(artist_id);',
    'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_pos ON playlist_entries(playlist_id, position);',
    'CREATE INDEX IF NOT EXISTS idx_playlist_entries_track_id ON playlist_entries(track_id);',
    'CREATE INDEX IF NOT EXISTS idx_lyrics_track_source ON lyrics(track_id, source);',
    'CREATE INDEX IF NOT EXISTS idx_lyrics_translations_lookup ON lyrics_translations(lyrics_id, lang);',
    'CREATE INDEX IF NOT EXISTS idx_radio_stations_favorite ON radio_stations(is_favorite);',
  ];
}

/// Concise, centralized SQLite persistence service using an asynchronous FIFO
/// serialization queue and ephemeral [Isolate.run] workers on disk.
class AppDatabase {
  static const int likedSongsPlaylistId = 1;
  static const int historyPlaylistId = 2;

  String? _dbPath;
  Database? _inMemoryDb;
  Future<void>? _queue;

  AppDatabase({String? dbPath}) : _dbPath = dbPath;
  factory AppDatabase.inMemory() => AppDatabase.forTesting(sqlite3.openInMemory());
  factory AppDatabase.forTesting(Database db) {
    final appDb = AppDatabase();
    _configurePragmas(db);
    _executeSchema(db);
    appDb._inMemoryDb = db;
    return appDb;
  }

  /// Exposes the in-memory [Database] handle for unit test assertions.
  Database get db => _inMemoryDb ?? (throw StateError('AppDatabase is not in-memory.'));

  Future<String> _resolveDbPath() async {
    if (_dbPath != null) return _dbPath!;
    final dir = await getApplicationSupportDirectory();
    return _dbPath = p.join(dir.path, 'music.db');
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() task) {
    final completer = Completer<T>();
    final prev = _queue;
    Future<void> run() async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }

    final next = prev == null ? Future<void>.sync(run) : prev.then((_) => run());
    late final Future<void> tail;
    tail = next.catchError((Object _) {}).whenComplete(() {
      if (identical(_queue, tail)) {
        _queue = null;
      }
    });
    _queue = tail;
    return completer.future;
  }

  Future<T> _runTask<T>(T Function(Database db) action) => _enqueue<T>(() async {
        final mem = _inMemoryDb;
        if (mem != null) return action(mem);
        final path = await _resolveDbPath();
        return _executeInIsolate(path, action);
      });

  static Future<T> _executeInIsolate<T>(String dbPath, T Function(Database db) action) =>
      Isolate.run<T>(() {
        final db = sqlite3.open(dbPath, mode: OpenMode.readWriteCreate);
        try {
          _configurePragmas(db);
          return action(db);
        } finally {
          db.close();
        }
      });

  static void _configurePragmas(Database db) {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA cache_size = -500;');
    db.execute('PRAGMA mmap_size = 0;');
  }

  static void _executeSchema(Database db) {
    for (final sql in AppDatabaseSchema.createTables) {
      db.execute(sql);
    }
    for (final sql in AppDatabaseSchema.indexes) {
      db.execute(sql);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR IGNORE INTO playlists (id, name, created_at, type) VALUES (?, ?, ?, ?);',
      [likedSongsPlaylistId, 'Liked Songs', now, PlaylistType.liked.value],
    );
    db.execute(
      'INSERT OR IGNORE INTO playlists (id, name, created_at, type) VALUES (?, ?, ?, ?);',
      [historyPlaylistId, 'History', now, PlaylistType.history.value],
    );
  }

  Future<void> init([String? dbPathOverride]) async {
    if (_inMemoryDb != null) return;
    if (dbPathOverride != null) _dbPath = dbPathOverride;
    await _runTask(_executeSchema);
  }

  Future<void> close() => _enqueue(() {
        _inMemoryDb?.close();
        _inMemoryDb = null;
      });

  Future<CatalogSnapshot> getCatalogSnapshot() => _runTask(_getCatalogSnapshotSync);

  static CatalogSnapshot _getCatalogSnapshotSync(Database db) {
    db.execute('BEGIN TRANSACTION;');
    try {
      final artists = db
          .select('SELECT id, name, thumbnail_hash FROM artists ORDER BY name COLLATE NOCASE;')
          .map((r) => RawArtistDto(id: r['id'] as int, name: r['name'] as String, thumbnailHash: r['thumbnail_hash'] as String?))
          .toList();
      final albums = db
          .select('SELECT id, name, year, artist_id, thumbnail_hash FROM albums ORDER BY name COLLATE NOCASE;')
          .map((r) => RawAlbumDto(id: r['id'] as int, name: r['name'] as String, year: r['year'] as int?, artistId: r['artist_id'] as int?, thumbnailHash: r['thumbnail_hash'] as String?))
          .toList();
      final genres = db
          .select('SELECT id, name FROM genres ORDER BY name COLLATE NOCASE;')
          .map((r) => RawGenreDto(id: r['id'] as int, name: r['name'] as String))
          .toList();
      final tracks = db
          .select('SELECT id, file_path, title, track_number, disc_number, year, duration_ms, bitrate, sample_rate, channels, codec, file_size, modified_at, replay_gain_track_gain, replay_gain_track_peak, waveform_data, album_id, thumbnail_hash FROM tracks ORDER BY title COLLATE NOCASE;')
          .map((r) => RawTrackDto(
                id: r['id'] as int,
                filePath: r['file_path'] as String,
                title: r['title'] as String,
                trackNumber: r['track_number'] as int?,
                discNumber: r['disc_number'] as int?,
                year: r['year'] as int?,
                durationMs: r['duration_ms'] as int,
                bitrate: r['bitrate'] as int?,
                sampleRate: r['sample_rate'] as int?,
                channels: r['channels'] as int?,
                codec: r['codec'] as String?,
                fileSize: r['file_size'] as int,
                modifiedAt: r['modified_at'] as int,
                replayGainTrackGain: (r['replay_gain_track_gain'] as num?)?.toDouble(),
                replayGainTrackPeak: (r['replay_gain_track_peak'] as num?)?.toDouble(),
                waveformData: r['waveform_data'] as String?,
                albumId: r['album_id'] as int?,
                thumbnailHash: r['thumbnail_hash'] as String?,
              ))
          .toList();
      final trackArtists = db
          .select('SELECT track_id, artist_id FROM track_artists;')
          .map((r) => TrackArtistPair(trackId: r['track_id'] as int, artistId: r['artist_id'] as int))
          .toList();
      final trackGenres = db
          .select('SELECT track_id, genre_id FROM track_genres;')
          .map((r) => TrackGenrePair(trackId: r['track_id'] as int, genreId: r['genre_id'] as int))
          .toList();
      final playlists = db
          .select('SELECT id, name, created_at, type FROM playlists ORDER BY type DESC, created_at ASC;')
          .map((r) => RawPlaylistDto(id: r['id'] as int, name: r['name'] as String, createdAt: r['created_at'] as int, type: r['type'] as int? ?? 0))
          .toList();
      final playlistEntries = db
          .select('SELECT id, playlist_id, track_id, position, added_at FROM playlist_entries ORDER BY playlist_id, position ASC;')
          .map((r) => RawPlaylistEntryDto(id: r['id'] as int, playlistId: r['playlist_id'] as int, trackId: r['track_id'] as int, position: r['position'] as int, addedAt: r['added_at'] as int))
          .toList();
      db.execute('COMMIT;');
      return CatalogSnapshot(
        tracks: tracks,
        albums: albums,
        artists: artists,
        genres: genres,
        playlists: playlists,
        playlistEntries: playlistEntries,
        trackArtists: trackArtists,
        trackGenres: trackGenres,
      );
    } catch (e) {
      try { db.execute('ROLLBACK;'); } catch (_) {}
      debugPrint('[AppDatabase] Error in getCatalogSnapshot: $e');
      return const CatalogSnapshot.empty();
    }
  }

  /// Atomically applies track upserts and stale track deletions.
  Future<void> applyScanMutations({
    List<ExtractedTrackData> toUpsert = const [],
    List<int> trackIdsToDelete = const [],
  }) {
    if (toUpsert.isEmpty && trackIdsToDelete.isEmpty) return Future.value();
    return _runTask((db) {
      if (toUpsert.isNotEmpty) _upsertTracksSync(db, toUpsert);
      if (trackIdsToDelete.isNotEmpty) _deleteTracksAndPurgeOrphansSync(db, trackIdsToDelete);
    });
  }

  Future<void> upsertTracks(List<ExtractedTrackData> tracks) =>
      tracks.isEmpty ? Future.value() : _runTask((db) => _upsertTracksSync(db, tracks));

  static void _upsertTracksSync(Database db, List<ExtractedTrackData> tracks) {
    if (tracks.isEmpty) return;
    db.execute('BEGIN TRANSACTION;');
    final stmts = <PreparedStatement>[];
    PreparedStatement prep(String sql) {
      final s = db.prepare(sql);
      stmts.add(s);
      return s;
    }

    try {
      final artistCache = <String, int>{};
      final albumCache = <String, int>{};
      final genreCache = <String, int>{};

      final stmtInsertArtist = prep('INSERT OR IGNORE INTO artists (name, thumbnail_hash) VALUES (?, ?);');
      final stmtSelectArtist = prep('SELECT id, thumbnail_hash FROM artists WHERE name = ? COLLATE NOCASE LIMIT 1;');
      final stmtUpdateArtistThumbnail = prep('UPDATE artists SET thumbnail_hash = ? WHERE id = ? AND thumbnail_hash IS NULL;');
      final stmtInsertAlbum = prep('INSERT OR IGNORE INTO albums (name, artist_id, year, thumbnail_hash) VALUES (?, ?, ?, ?);');
      final stmtSelectAlbum = prep('SELECT id, thumbnail_hash FROM albums WHERE name = ? COLLATE NOCASE AND (artist_id = ? OR (? IS NULL AND artist_id IS NULL)) LIMIT 1;');
      final stmtUpdateAlbumThumbnail = prep('UPDATE albums SET thumbnail_hash = ? WHERE id = ? AND thumbnail_hash IS NULL;');
      final stmtInsertGenre = prep('INSERT OR IGNORE INTO genres (name) VALUES (?);');
      final stmtSelectGenre = prep('SELECT id FROM genres WHERE name = ? COLLATE NOCASE LIMIT 1;');
      final stmtUpsertTrack = prep(
        'INSERT INTO tracks (file_path, title, track_number, disc_number, year, duration_ms, bitrate, sample_rate, channels, codec, file_size, modified_at, replay_gain_track_gain, replay_gain_track_peak, waveform_data, album_id, thumbnail_hash) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(file_path) DO UPDATE SET title = excluded.title, track_number = excluded.track_number, disc_number = excluded.disc_number, year = excluded.year, duration_ms = excluded.duration_ms, bitrate = excluded.bitrate, sample_rate = excluded.sample_rate, channels = excluded.channels, codec = excluded.codec, file_size = excluded.file_size, modified_at = excluded.modified_at, replay_gain_track_gain = excluded.replay_gain_track_gain, replay_gain_track_peak = excluded.replay_gain_track_peak, waveform_data = excluded.waveform_data, album_id = excluded.album_id, thumbnail_hash = excluded.thumbnail_hash '
        'RETURNING id;',
      );
      final stmtDeleteEmbeddedLyrics = prep("DELETE FROM lyrics WHERE track_id = ? AND source = 'embedded';");
      final stmtInsertEmbeddedLyrics = prep("INSERT INTO lyrics (track_id, source, state, raw_lrc, is_synced, updated_at) VALUES (?, 'embedded', 'FOUND', ?, ?, ?);");
      final stmtDeleteTrackArtists = prep('DELETE FROM track_artists WHERE track_id = ?;');
      final stmtInsertTrackArtist = prep('INSERT OR IGNORE INTO track_artists (track_id, artist_id) VALUES (?, ?);');
      final stmtDeleteTrackGenres = prep('DELETE FROM track_genres WHERE track_id = ?;');
      final stmtInsertTrackGenre = prep('INSERT OR IGNORE INTO track_genres (track_id, genre_id) VALUES (?, ?);');

      int? resolveArtist(String name, {String? artistThumbnailHash}) {
        final clean = name.trim();
        if (clean.isEmpty) return null;
        final lower = clean.toLowerCase();
        var id = artistCache[lower];
        if (id == null) {
          final rows = stmtSelectArtist.select([clean]);
          if (rows.isNotEmpty) {
            id = rows.first['id'] as int;
            if (rows.first['thumbnail_hash'] == null && artistThumbnailHash != null) {
              stmtUpdateArtistThumbnail.execute([artistThumbnailHash, id]);
            }
          } else {
            stmtInsertArtist.execute([clean, artistThumbnailHash]);
            final ins = stmtSelectArtist.select([clean]);
            if (ins.isNotEmpty) id = ins.first['id'] as int;
          }
          if (id != null) artistCache[lower] = id;
        } else if (artistThumbnailHash != null) {
          stmtUpdateArtistThumbnail.execute([artistThumbnailHash, id]);
        }
        return id;
      }

      int? resolveGenre(String name) {
        final clean = name.trim();
        if (clean.isEmpty) return null;
        final lower = clean.toLowerCase();
        var id = genreCache[lower];
        if (id == null) {
          final rows = stmtSelectGenre.select([clean]);
          if (rows.isNotEmpty) {
            id = rows.first['id'] as int;
          } else {
            stmtInsertGenre.execute([clean]);
            final ins = stmtSelectGenre.select([clean]);
            if (ins.isNotEmpty) id = ins.first['id'] as int;
          }
          if (id != null) genreCache[lower] = id;
        }
        return id;
      }

      for (final t in tracks) {
        final resolvedArtistIds = <int>[];
        for (final aName in t.artistNames) {
          final aId = resolveArtist(aName, artistThumbnailHash: t.artistThumbnailHash);
          if (aId != null && !resolvedArtistIds.contains(aId)) resolvedArtistIds.add(aId);
        }

        int? resolvedAlbumId;
        if (t.albumName != null && t.albumName!.trim().isNotEmpty) {
          final alClean = t.albumName!.trim();
          final albumArtistId = (t.albumArtistName != null && t.albumArtistName!.trim().isNotEmpty)
              ? resolveArtist(t.albumArtistName!, artistThumbnailHash: t.artistThumbnailHash)
              : null;
          final primaryArtistId = albumArtistId ?? resolvedArtistIds.firstOrNull;
          final albumThumb = t.albumThumbnailHash ?? t.thumbnailHash;
          final cacheKey = '${alClean.toLowerCase()}|$primaryArtistId';
          resolvedAlbumId = albumCache[cacheKey];
          if (resolvedAlbumId == null) {
            final rows = stmtSelectAlbum.select([alClean, primaryArtistId, primaryArtistId]);
            if (rows.isNotEmpty) {
              resolvedAlbumId = rows.first['id'] as int;
              if (rows.first['thumbnail_hash'] == null && albumThumb != null) {
                stmtUpdateAlbumThumbnail.execute([albumThumb, resolvedAlbumId]);
              }
            } else {
              stmtInsertAlbum.execute([alClean, primaryArtistId, t.year, albumThumb]);
              final ins = stmtSelectAlbum.select([alClean, primaryArtistId, primaryArtistId]);
              if (ins.isNotEmpty) resolvedAlbumId = ins.first['id'] as int;
            }
            if (resolvedAlbumId != null) albumCache[cacheKey] = resolvedAlbumId;
          } else if (albumThumb != null) {
            stmtUpdateAlbumThumbnail.execute([albumThumb, resolvedAlbumId]);
          }
        }

        final trackRes = stmtUpsertTrack.select([
          t.filePath, t.title, t.trackNumber, t.discNumber ?? 1, t.year, t.durationMs,
          t.bitrate, t.sampleRate, t.channels, t.codec, t.fileSize, t.modifiedAt,
          t.replayGainTrackGain, t.replayGainTrackPeak, t.waveformData, resolvedAlbumId, t.thumbnailHash,
        ]);
        final trackId = trackRes.first['id'] as int;

        stmtDeleteEmbeddedLyrics.execute([trackId]);
        if (t.embeddedLyrics != null && t.embeddedLyrics!.trim().isNotEmpty) {
          final isSynced = RegExp(r'\[\d{1,}:\d{2}\.\d{2,3}\]').hasMatch(t.embeddedLyrics!);
          stmtInsertEmbeddedLyrics.execute([trackId, t.embeddedLyrics, isSynced ? 1 : 0, DateTime.now().millisecondsSinceEpoch]);
        }

        stmtDeleteTrackArtists.execute([trackId]);
        for (final aId in resolvedArtistIds) {
          stmtInsertTrackArtist.execute([trackId, aId]);
        }

        stmtDeleteTrackGenres.execute([trackId]);
        for (final gName in t.genreNames) {
          final gId = resolveGenre(gName);
          if (gId != null) stmtInsertTrackGenre.execute([trackId, gId]);
        }
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    } finally {
      for (final s in stmts) {
        s.close();
      }
    }
  }

  Future<void> deleteTracksAndPurgeOrphans(List<int> trackIds) =>
      _runTask((db) => _deleteTracksAndPurgeOrphansSync(db, trackIds));

  static void _deleteTracksAndPurgeOrphansSync(Database db, List<int> trackIds) {
    db.execute('BEGIN TRANSACTION;');
    try {
      if (trackIds.isNotEmpty) {
        const chunkSize = 500;
        for (var i = 0; i < trackIds.length; i += chunkSize) {
          final end = (i + chunkSize < trackIds.length) ? i + chunkSize : trackIds.length;
          final chunk = trackIds.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          db.execute('DELETE FROM tracks WHERE id IN ($placeholders);', chunk);
        }
      }
      db.execute('DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL);');
      db.execute('DELETE FROM artists WHERE id NOT IN (SELECT DISTINCT artist_id FROM track_artists);');
      db.execute('DELETE FROM genres WHERE id NOT IN (SELECT DISTINCT genre_id FROM track_genres);');
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> clearAllData() => _runTask(_clearAllDataSync);

  static void _clearAllDataSync(Database db) {
    db.execute('BEGIN TRANSACTION;');
    try {
      for (final table in [
        'lyrics_translations', 'lyrics', 'playlist_entries', 'track_genres',
        'track_artists', 'tracks', 'albums', 'artists', 'genres', 'radio_stations',
      ]) {
        db.execute('DELETE FROM $table;');
      }
      db.execute('DELETE FROM playlists WHERE type = ?;', [PlaylistType.user.value]);
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<int> createPlaylist(String name) => _runTask((db) {
        try {
          db.execute(
            'INSERT INTO playlists (name, created_at, type) VALUES (?, ?, ?);',
            [name.trim(), DateTime.now().millisecondsSinceEpoch, PlaylistType.user.value],
          );
          return db.lastInsertRowId;
        } catch (e) {
          debugPrint('[AppDatabase] Ignored error in createPlaylist: $e');
          return -1;
        }
      });

  Future<void> deletePlaylist(int playlistId) => _runTask((db) {
        try {
          db.execute('DELETE FROM playlists WHERE id = ? AND type = ?;', [playlistId, PlaylistType.user.value]);
        } catch (e) {
          debugPrint('[AppDatabase] Ignored error in deletePlaylist: $e');
        }
      });

  Future<void> renamePlaylist(int playlistId, String name) => _runTask((db) {
        try {
          db.execute('UPDATE playlists SET name = ? WHERE id = ?;', [name.trim(), playlistId]);
        } catch (e) {
          debugPrint('[AppDatabase] Ignored error in renamePlaylist: $e');
        }
      });

  Future<void> addTrackToPlaylist(int playlistId, int trackId) =>
      _runTask((db) => _addTrackToPlaylistSync(db, playlistId, trackId));

  static void _addTrackToPlaylistSync(Database db, int playlistId, int trackId) {
    try {
      if (db.select('SELECT 1 FROM tracks WHERE id = ? LIMIT 1;', [trackId]).isEmpty) return;
      if (db.select('SELECT 1 FROM playlists WHERE id = ? LIMIT 1;', [playlistId]).isEmpty) return;
      final posRes = db.select('SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_entries WHERE playlist_id = ?;', [playlistId]);
      final nextPos = (posRes.first['next_pos'] as int?) ?? 0;
      db.execute(
        'INSERT INTO playlist_entries (playlist_id, track_id, position, added_at) VALUES (?, ?, ?, ?);',
        [playlistId, trackId, nextPos, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('[AppDatabase] Ignored error in addTrackToPlaylist: $e');
    }
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) =>
      trackIds.isEmpty ? Future.value() : _runTask((db) => _addTracksToPlaylistSync(db, playlistId, trackIds));

  static void _addTracksToPlaylistSync(Database db, int playlistId, List<int> trackIds) {
    try {
      db.execute('BEGIN TRANSACTION;');
      try {
        for (final id in trackIds) {
          _addTrackToPlaylistSync(db, playlistId, id);
        }
        db.execute('COMMIT;');
      } catch (e) {
        try { db.execute('ROLLBACK;'); } catch (_) {}
        debugPrint('[AppDatabase] Ignored error in addTracksToPlaylist: $e');
      }
    } catch (e) {
      debugPrint('[AppDatabase] Failed transaction in addTracksToPlaylist: $e');
    }
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) =>
      _runTask((db) => _removeTrackFromPlaylistSync(db, playlistId, trackId));

  static void _removeTrackFromPlaylistSync(Database db, int playlistId, int trackId) {
    try {
      db.execute('BEGIN TRANSACTION;');
      try {
        db.execute('DELETE FROM playlist_entries WHERE playlist_id = ? AND track_id = ?;', [playlistId, trackId]);
        final remaining = db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? ORDER BY position ASC;', [playlistId]);
        final stmt = db.prepare('UPDATE playlist_entries SET position = ? WHERE id = ?;');
        try {
          for (var i = 0; i < remaining.length; i++) {
            stmt.execute([i, remaining[i]['id']]);
          }
        } finally {
          stmt.close();
        }
        db.execute('COMMIT;');
      } catch (e) {
        try { db.execute('ROLLBACK;'); } catch (_) {}
        debugPrint('[AppDatabase] Ignored error in removeTrackFromPlaylist: $e');
      }
    } catch (e) {
      debugPrint('[AppDatabase] Failed transaction in removeTrackFromPlaylist: $e');
    }
  }

  Future<void> reorderPlaylistEntries(int playlistId, int fromIndex, int toIndex) =>
      _runTask((db) => _reorderPlaylistEntriesSync(db, playlistId, fromIndex, toIndex));

  static void _reorderPlaylistEntriesSync(Database db, int playlistId, int fromIndex, int toIndex) {
    try {
      db.execute('BEGIN TRANSACTION;');
      try {
        final entries = db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? ORDER BY position ASC;', [playlistId]);
        if (fromIndex < 0 || fromIndex >= entries.length || toIndex < 0 || toIndex >= entries.length) {
          db.execute('COMMIT;');
          return;
        }
        final ids = entries.map((e) => e['id'] as int).toList();
        ids.insert(toIndex, ids.removeAt(fromIndex));
        final stmt = db.prepare('UPDATE playlist_entries SET position = ? WHERE id = ?;');
        try {
          for (var i = 0; i < ids.length; i++) {
            stmt.execute([i, ids[i]]);
          }
        } finally {
          stmt.close();
        }
        db.execute('COMMIT;');
      } catch (e) {
        try { db.execute('ROLLBACK;'); } catch (_) {}
        debugPrint('[AppDatabase] Ignored error in reorderPlaylistEntries: $e');
      }
    } catch (e) {
      debugPrint('[AppDatabase] Failed transaction in reorderPlaylistEntries: $e');
    }
  }

  Future<void> toggleLikeTrack(int trackId) => _runTask((db) {
        try {
          final rows = db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? AND track_id = ? LIMIT 1;', [likedSongsPlaylistId, trackId]);
          if (rows.isNotEmpty) {
            _removeTrackFromPlaylistSync(db, likedSongsPlaylistId, trackId);
          } else {
            _addTrackToPlaylistSync(db, likedSongsPlaylistId, trackId);
          }
        } catch (e) {
          debugPrint('[AppDatabase] Ignored error in toggleLikeTrack: $e');
        }
      });

  Future<void> clearHistory() => _runTask((db) {
        try {
          db.execute('DELETE FROM playlist_entries WHERE playlist_id = ?;', [historyPlaylistId]);
        } catch (e) {
          debugPrint('[AppDatabase] Ignored error in clearHistory: $e');
        }
      });

  Future<List<Map<String, dynamic>>> getLyricsForTrack(int trackId) => _runTask((db) {
        final rows = db.select('SELECT id, track_id, source, state, raw_lrc, is_synced, lang, updated_at FROM lyrics WHERE track_id = ?;', [trackId]);
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      });

  Future<int> saveLyricsEntry({
    required int trackId,
    required String source,
    required String state,
    String? rawLrc,
    bool isSynced = false,
    String? lang,
    int? updatedAt,
  }) =>
      _runTask((db) {
        final ts = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
        final res = db.select(
          'INSERT INTO lyrics (track_id, source, state, raw_lrc, is_synced, lang, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(track_id, source) DO UPDATE SET state = excluded.state, raw_lrc = excluded.raw_lrc, '
          'is_synced = excluded.is_synced, lang = COALESCE(excluded.lang, lyrics.lang), updated_at = excluded.updated_at RETURNING id;',
          [trackId, source, state, rawLrc, isSynced ? 1 : 0, lang, ts],
        );
        final lyricsId = res.first['id'] as int;
        db.execute('DELETE FROM lyrics_translations WHERE lyrics_id = ?;', [lyricsId]);
        return lyricsId;
      });

  Future<void> deleteLyrics(int lyricsId) => _runTask((db) => db.execute('DELETE FROM lyrics WHERE id = ?;', [lyricsId]));

  Future<List<String>?> getLyricsTranslation({required int lyricsId, required String lang}) => _runTask((db) {
        final rows = db.select('SELECT translated_lines FROM lyrics_translations WHERE lyrics_id = ? AND lang = ? LIMIT 1;', [lyricsId, lang]);
        if (rows.isEmpty) return null;
        try {
          return (jsonDecode(rows.first['translated_lines'] as String) as List<dynamic>).map((e) => e.toString()).toList();
        } catch (_) {
          return null;
        }
      });

  Future<void> saveLyricsTranslation({
    required int lyricsId,
    required String lang,
    required List<String> translatedLines,
  }) =>
      _runTask((db) {
        db.execute(
          'INSERT INTO lyrics_translations (lyrics_id, lang, translated_lines, updated_at) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(lyrics_id, lang) DO UPDATE SET translated_lines = excluded.translated_lines, updated_at = excluded.updated_at;',
          [lyricsId, lang, jsonEncode(translatedLines), DateTime.now().millisecondsSinceEpoch],
        );
      });

  Future<List<RadioStation>> getRadioStations() => _runTask((db) {
        final rows = db.select(
          'SELECT id, name, stream_url, homepage_url, favicon_url, genre, country, bitrate_kbps, codec, is_favorite, created_at '
          'FROM radio_stations ORDER BY is_favorite DESC, name COLLATE NOCASE ASC;',
        );
        return rows.map((r) => RadioStation(
          id: r['id'] as int,
          name: r['name'] as String,
          streamUrl: r['stream_url'] as String,
          homepageUrl: r['homepage_url'] as String?,
          faviconUrl: r['favicon_url'] as String?,
          genre: r['genre'] as String?,
          country: r['country'] as String?,
          bitrateKbps: r['bitrate_kbps'] as int?,
          codec: r['codec'] as String?,
          isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        )).toList();
      });

  Future<RadioStation> saveRadioStation(RadioStation station) => _runTask((db) {
        final ts = station.createdAt.millisecondsSinceEpoch;
        final res = db.select(
          'INSERT INTO radio_stations (name, stream_url, homepage_url, favicon_url, genre, country, bitrate_kbps, codec, is_favorite, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(stream_url) DO UPDATE SET name = excluded.name, homepage_url = excluded.homepage_url, favicon_url = excluded.favicon_url, '
          'genre = excluded.genre, country = excluded.country, bitrate_kbps = excluded.bitrate_kbps, codec = excluded.codec, '
          'is_favorite = excluded.is_favorite RETURNING id;',
          [
            station.name,
            station.streamUrl,
            station.homepageUrl,
            station.faviconUrl,
            station.genre,
            station.country,
            station.bitrateKbps,
            station.codec,
            station.isFavorite ? 1 : 0,
            ts,
          ],
        );
        final id = res.first['id'] as int;
        return station.copyWith(id: id);
      });

  Future<void> deleteRadioStation(int id) => _runTask((db) {
        db.execute('DELETE FROM radio_stations WHERE id = ?;', [id]);
      });

  Future<void> setRadioStationFavorite(int id, bool isFavorite) => _runTask((db) {
        db.execute('UPDATE radio_stations SET is_favorite = ? WHERE id = ?;', [isFavorite ? 1 : 0, id]);
      });
}
