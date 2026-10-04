import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:tachyon/core/backend/services/metadata_service.dart'
    show ExtractedTrackData, TrackFileMeta;
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/playlist.dart' show PlaylistType;
import 'package:tachyon/features/playback/domain/lyric_source.dart';

abstract final class AppDatabaseSchema {
  static const List<String> createTables = [
    'CREATE TABLE IF NOT EXISTS artists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE);',
    'CREATE TABLE IF NOT EXISTS albums (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE, year INTEGER, artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL, UNIQUE(name COLLATE NOCASE, artist_id));',
    'CREATE TABLE IF NOT EXISTS tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, file_path TEXT UNIQUE NOT NULL, title TEXT NOT NULL, track_number INTEGER, disc_number INTEGER DEFAULT 1, year INTEGER, duration_ms INTEGER NOT NULL, bitrate INTEGER, sample_rate INTEGER, channels INTEGER, codec TEXT, file_size INTEGER NOT NULL, modified_at INTEGER NOT NULL, replay_gain_track_gain REAL, replay_gain_track_peak REAL, album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL, has_cover INTEGER DEFAULT 0, lyrics TEXT);',
    'CREATE TABLE IF NOT EXISTS genres (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE);',
    'CREATE TABLE IF NOT EXISTS track_genres (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE, PRIMARY KEY(track_id, genre_id));',
    'CREATE TABLE IF NOT EXISTS track_artists (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, artist_id INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE, PRIMARY KEY(track_id, artist_id));',
    'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at INTEGER NOT NULL, type INTEGER DEFAULT 0);',
    'CREATE TABLE IF NOT EXISTS playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, position INTEGER NOT NULL, added_at INTEGER NOT NULL, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id INTEGER REFERENCES tracks(id) ON DELETE CASCADE);',
    'CREATE TABLE IF NOT EXISTS lyrics_cache (key_hash TEXT PRIMARY KEY, raw_lrc TEXT NOT NULL, source TEXT NOT NULL, updated_at INTEGER NOT NULL);',
    'CREATE TABLE IF NOT EXISTS lyrics_source_cache (key_hash TEXT NOT NULL, source TEXT NOT NULL, state TEXT NOT NULL, raw_lrc TEXT, is_synced INTEGER DEFAULT 0, updated_at INTEGER NOT NULL, PRIMARY KEY (key_hash, source));',
    'CREATE TABLE IF NOT EXISTS lyrics_translations (key_hash TEXT NOT NULL, source TEXT NOT NULL, target_lang TEXT NOT NULL, translated_lines TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (key_hash, source, target_lang));',
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
  ];
}

class AppDatabase {
  static const int likedSongsPlaylistId = 1;
  static const int historyPlaylistId = 2;

  Database? _db;
  Database get db => _db ?? (throw StateError('AppDatabase is not initialized.'));

  AppDatabase();

  factory AppDatabase.inMemory() {
    final appDb = AppDatabase();
    appDb._initInMemory();
    return appDb;
  }

  factory AppDatabase.forTesting(Database db) {
    final appDb = AppDatabase().._db = db;
    db.execute('PRAGMA foreign_keys = ON;');
    appDb._executeSchema(db);
    return appDb;
  }

  void _initInMemory() {
    _db = sqlite3.openInMemory()..execute('PRAGMA foreign_keys = ON;');
    _executeSchema(_db!);
  }

  Future<void> initInMemory() async {
    if (_db == null) _initInMemory();
  }

  Future<void> init([String? dbPathOverride]) async {
    if (_db != null) return;
    final dbPath = dbPathOverride ?? p.join((await getApplicationSupportDirectory()).path, 'music.db');
    _db = sqlite3.open(dbPath, mode: OpenMode.readWriteCreate);
    _db!.execute('PRAGMA foreign_keys = ON;');
    _db!.execute('PRAGMA journal_mode = WAL;');
    _db!.execute('PRAGMA synchronous = NORMAL;');
    _db!.execute('PRAGMA cache_size = -64000;');
    _executeSchema(_db!);
  }

  void _executeSchema(Database db) {
    for (final sql in AppDatabaseSchema.createTables) { db.execute(sql); }
    for (final c in ['replay_gain_track_gain REAL', 'replay_gain_track_peak REAL', 'lyrics TEXT']) {
      try { db.execute('ALTER TABLE tracks ADD COLUMN $c;'); } catch (_) {}
    }
    for (final sql in AppDatabaseSchema.indexes) { db.execute(sql); }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('INSERT OR IGNORE INTO playlists (id, name, created_at, type) VALUES (?, ?, ?, ?);', [likedSongsPlaylistId, 'Liked Songs', now, PlaylistType.liked.value]);
    db.execute('INSERT OR IGNORE INTO playlists (id, name, created_at, type) VALUES (?, ?, ?, ?);', [historyPlaylistId, 'History', now, PlaylistType.history.value]);
  }

  CatalogSnapshot getCatalogSnapshot() {
    db.execute('BEGIN TRANSACTION;');
    try {
      final artists = db.select('SELECT id, name FROM artists ORDER BY name COLLATE NOCASE;')
          .map((r) => RawArtistDto(id: r['id'] as int, name: r['name'] as String)).toList();

      final albums = db.select('SELECT id, name, year, artist_id FROM albums ORDER BY name COLLATE NOCASE;')
          .map((r) => RawAlbumDto(id: r['id'] as int, name: r['name'] as String, year: r['year'] as int?, artistId: r['artist_id'] as int?)).toList();

      final genres = db.select('SELECT id, name FROM genres ORDER BY name COLLATE NOCASE;')
          .map((r) => RawGenreDto(id: r['id'] as int, name: r['name'] as String)).toList();

      final tracks = db.select('SELECT id, file_path, title, track_number, disc_number, year, duration_ms, bitrate, sample_rate, channels, codec, file_size, modified_at, replay_gain_track_gain, replay_gain_track_peak, album_id FROM tracks ORDER BY title COLLATE NOCASE;')
          .map((r) => RawTrackDto(
            id: r['id'] as int, filePath: r['file_path'] as String, title: r['title'] as String,
            trackNumber: r['track_number'] as int?, discNumber: r['disc_number'] as int?, year: r['year'] as int?,
            durationMs: r['duration_ms'] as int, bitrate: r['bitrate'] as int?, sampleRate: r['sample_rate'] as int?,
            channels: r['channels'] as int?, codec: r['codec'] as String?, fileSize: r['file_size'] as int,
            modifiedAt: r['modified_at'] as int,
            replayGainTrackGain: (r['replay_gain_track_gain'] as num?)?.toDouble(),
            replayGainTrackPeak: (r['replay_gain_track_peak'] as num?)?.toDouble(),
            albumId: r['album_id'] as int?,
          )).toList();

      final trackArtists = db.select('SELECT track_id, artist_id FROM track_artists;')
          .map((r) => TrackArtistPair(trackId: r['track_id'] as int, artistId: r['artist_id'] as int)).toList();

      final trackGenres = db.select('SELECT track_id, genre_id FROM track_genres;')
          .map((r) => TrackGenrePair(trackId: r['track_id'] as int, genreId: r['genre_id'] as int)).toList();

      final playlists = db.select('SELECT id, name, created_at, type FROM playlists ORDER BY type DESC, created_at ASC;')
          .map((r) => RawPlaylistDto(id: r['id'] as int, name: r['name'] as String, createdAt: r['created_at'] as int, type: r['type'] as int? ?? 0)).toList();

      final playlistEntries = db.select('SELECT id, playlist_id, track_id, position, added_at FROM playlist_entries ORDER BY playlist_id, position ASC;')
          .map((r) => RawPlaylistEntryDto(id: r['id'] as int, playlistId: r['playlist_id'] as int, trackId: r['track_id'] as int, position: r['position'] as int, addedAt: r['added_at'] as int)).toList();

      db.execute('COMMIT;');
      return CatalogSnapshot(
        tracks: tracks, albums: albums, artists: artists, genres: genres,
        playlists: playlists, playlistEntries: playlistEntries,
        trackArtists: trackArtists, trackGenres: trackGenres,
      );
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void upsertTracks(List<ExtractedTrackData> tracks) {
    if (tracks.isEmpty) return;
    db.execute('BEGIN TRANSACTION;');
    final stmts = <PreparedStatement>[];
    try {
      final artistCache = <String, int>{};
      final albumCache = <String, int>{};
      final genreCache = <String, int>{};

      final stmtInsertArtist = db.prepare('INSERT OR IGNORE INTO artists (name) VALUES (?);'); stmts.add(stmtInsertArtist);
      final stmtSelectArtist = db.prepare('SELECT id FROM artists WHERE name = ? COLLATE NOCASE LIMIT 1;'); stmts.add(stmtSelectArtist);
      final stmtInsertAlbum = db.prepare('INSERT OR IGNORE INTO albums (name, artist_id, year) VALUES (?, ?, ?);'); stmts.add(stmtInsertAlbum);
      final stmtSelectAlbum = db.prepare('SELECT id FROM albums WHERE name = ? COLLATE NOCASE AND (artist_id = ? OR (? IS NULL AND artist_id IS NULL)) LIMIT 1;'); stmts.add(stmtSelectAlbum);
      final stmtInsertGenre = db.prepare('INSERT OR IGNORE INTO genres (name) VALUES (?);'); stmts.add(stmtInsertGenre);
      final stmtSelectGenre = db.prepare('SELECT id FROM genres WHERE name = ? COLLATE NOCASE LIMIT 1;'); stmts.add(stmtSelectGenre);

      final stmtUpsertTrack = db.prepare('INSERT INTO tracks (file_path, title, track_number, disc_number, year, duration_ms, bitrate, sample_rate, channels, codec, file_size, modified_at, replay_gain_track_gain, replay_gain_track_peak, album_id, lyrics) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(file_path) DO UPDATE SET title = excluded.title, track_number = excluded.track_number, disc_number = excluded.disc_number, year = excluded.year, duration_ms = excluded.duration_ms, bitrate = excluded.bitrate, sample_rate = excluded.sample_rate, channels = excluded.channels, codec = excluded.codec, file_size = excluded.file_size, modified_at = excluded.modified_at, replay_gain_track_gain = excluded.replay_gain_track_gain, replay_gain_track_peak = excluded.replay_gain_track_peak, album_id = excluded.album_id, lyrics = COALESCE(excluded.lyrics, tracks.lyrics) RETURNING id;');
      stmts.add(stmtUpsertTrack);

      final stmtDeleteTrackArtists = db.prepare('DELETE FROM track_artists WHERE track_id = ?;'); stmts.add(stmtDeleteTrackArtists);
      final stmtInsertTrackArtist = db.prepare('INSERT OR IGNORE INTO track_artists (track_id, artist_id) VALUES (?, ?);'); stmts.add(stmtInsertTrackArtist);
      final stmtDeleteTrackGenres = db.prepare('DELETE FROM track_genres WHERE track_id = ?;'); stmts.add(stmtDeleteTrackGenres);
      final stmtInsertTrackGenre = db.prepare('INSERT OR IGNORE INTO track_genres (track_id, genre_id) VALUES (?, ?);'); stmts.add(stmtInsertTrackGenre);

      int? resolveArtist(String name) {
        final clean = name.trim();
        if (clean.isEmpty) return null;
        final lower = clean.toLowerCase();
        var id = artistCache[lower];
        if (id == null) {
          final rows = stmtSelectArtist.select([clean]);
          if (rows.isNotEmpty) {
            id = rows.first['id'] as int;
          } else {
            stmtInsertArtist.execute([clean]);
            final ins = stmtSelectArtist.select([clean]);
            if (ins.isNotEmpty) id = ins.first['id'] as int;
          }
          if (id != null) artistCache[lower] = id;
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
          final aId = resolveArtist(aName);
          if (aId != null && !resolvedArtistIds.contains(aId)) resolvedArtistIds.add(aId);
        }

        int? resolvedAlbumId;
        if (t.albumName != null && t.albumName!.trim().isNotEmpty) {
          final alClean = t.albumName!.trim();
          final albumArtistId = (t.albumArtistName != null && t.albumArtistName!.trim().isNotEmpty)
              ? resolveArtist(t.albumArtistName!)
              : null;
          final primaryArtistId = albumArtistId ?? resolvedArtistIds.firstOrNull;
          final cacheKey = '${alClean.toLowerCase()}|$primaryArtistId';
          resolvedAlbumId = albumCache[cacheKey];
          if (resolvedAlbumId == null) {
            final rows = stmtSelectAlbum.select([alClean, primaryArtistId, primaryArtistId]);
            if (rows.isNotEmpty) {
              resolvedAlbumId = rows.first['id'] as int;
            } else {
              stmtInsertAlbum.execute([alClean, primaryArtistId, t.year]);
              final ins = stmtSelectAlbum.select([alClean, primaryArtistId, primaryArtistId]);
              if (ins.isNotEmpty) resolvedAlbumId = ins.first['id'] as int;
            }
            if (resolvedAlbumId != null) albumCache[cacheKey] = resolvedAlbumId;
          }
        }

        final trackRes = stmtUpsertTrack.select([
          t.filePath, t.title, t.trackNumber, t.discNumber ?? 1, t.year, t.durationMs,
          t.bitrate, t.sampleRate, t.channels, t.codec, t.fileSize, t.modifiedAt,
          t.replayGainTrackGain, t.replayGainTrackPeak, resolvedAlbumId, t.embeddedLyrics,
        ]);
        final trackId = trackRes.first['id'] as int;

        stmtDeleteTrackArtists.execute([trackId]);
        for (final aId in resolvedArtistIds) { stmtInsertTrackArtist.execute([trackId, aId]); }

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
      for (final s in stmts) { s.close(); }
    }
  }

  Map<String, TrackFileMeta> getExistingTrackMetas() {
    final rows = db.select('SELECT file_path, modified_at, file_size FROM tracks;');
    final map = <String, TrackFileMeta>{};
    for (final r in rows) {
      map[r['file_path'] as String] = (modifiedAt: r['modified_at'] as int, fileSize: r['file_size'] as int);
    }
    return map;
  }

  void updateTrackCoverStatus(String filePath, bool hasCover) {
    db.execute('UPDATE tracks SET has_cover = ? WHERE file_path = ?;', [hasCover ? 1 : 0, filePath]);
  }

  void deleteTrack(int trackId) {
    db.execute('DELETE FROM tracks WHERE id = ?;', [trackId]);
  }

  void deleteTracksInFolder(String folderPath) {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    db.execute("DELETE FROM tracks WHERE file_path LIKE ? ESCAPE '\\';", ['${prefix.replaceAll('%', r'\%').replaceAll('_', r'\_')}%']);
  }

  String? getTrackLyricsByFilePath(String filePath) {
    final rows = db.select('SELECT lyrics FROM tracks WHERE file_path = ? LIMIT 1;', [filePath]);
    return rows.isEmpty ? null : rows.first['lyrics'] as String?;
  }

  String? getTrackLyrics(int trackId) {
    final rows = db.select('SELECT lyrics FROM tracks WHERE id = ? LIMIT 1;', [trackId]);
    return rows.isEmpty ? null : rows.first['lyrics'] as String?;
  }

  int createPlaylist(String name) {
    db.execute('INSERT INTO playlists (name, created_at, type) VALUES (?, ?, ?);', [name.trim(), DateTime.now().millisecondsSinceEpoch, PlaylistType.user.value]);
    return db.lastInsertRowId;
  }

  void deletePlaylist(int playlistId) {
    db.execute('DELETE FROM playlists WHERE id = ? AND type = ?;', [playlistId, PlaylistType.user.value]);
  }

  void renamePlaylist(int playlistId, String name) {
    db.execute('UPDATE playlists SET name = ? WHERE id = ?;', [name.trim(), playlistId]);
  }

  void addTrackToPlaylist(int playlistId, int trackId, [String? filePath]) {
    final posRes = db.select('SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_entries WHERE playlist_id = ?;', [playlistId]);
    final nextPos = (posRes.first['next_pos'] as int?) ?? 0;
    db.execute('INSERT INTO playlist_entries (playlist_id, track_id, position, added_at) VALUES (?, ?, ?, ?);', [playlistId, trackId, nextPos, DateTime.now().millisecondsSinceEpoch]);
  }

  void addTracksToPlaylist(int playlistId, List<int> trackIds) {
    db.execute('BEGIN TRANSACTION;');
    try {
      for (final id in trackIds) { addTrackToPlaylist(playlistId, id); }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void removeTrackFromPlaylist(int playlistId, int trackId) {
    db.execute('BEGIN TRANSACTION;');
    try {
      db.execute('DELETE FROM playlist_entries WHERE playlist_id = ? AND track_id = ?;', [playlistId, trackId]);
      final remaining = db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? ORDER BY position ASC;', [playlistId]);
      final stmt = db.prepare('UPDATE playlist_entries SET position = ? WHERE id = ?;');
      try {
        for (var i = 0; i < remaining.length; i++) { stmt.execute([i, remaining[i]['id']]); }
      } finally {
        stmt.close();
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void reorderPlaylistEntries(int playlistId, int fromIndex, int toIndex) {
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
        for (var i = 0; i < ids.length; i++) { stmt.execute([i, ids[i]]); }
      } finally {
        stmt.close();
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void toggleLikeTrack(int trackId, [String? filePath]) {
    final rows = db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? AND track_id = ? LIMIT 1;', [likedSongsPlaylistId, trackId]);
    if (rows.isNotEmpty) {
      removeTrackFromPlaylist(likedSongsPlaylistId, trackId);
    } else {
      addTrackToPlaylist(likedSongsPlaylistId, trackId, filePath);
    }
  }

  void clearHistory() {
    db.execute('DELETE FROM playlist_entries WHERE playlist_id = ?;', [historyPlaylistId]);
  }

  List<int> getTrackIdsForPlaylist(int playlistId) {
    return db.select('SELECT track_id FROM playlist_entries WHERE playlist_id = ? ORDER BY position ASC;', [playlistId]).map((r) => r['track_id'] as int).toList();
  }

  bool isTrackLiked(int trackId) {
    return db.select('SELECT id FROM playlist_entries WHERE playlist_id = ? AND track_id = ? LIMIT 1;', [likedSongsPlaylistId, trackId]).isNotEmpty;
  }

  void saveLyricsSourceEntry(LyricsSourceEntry entry) {
    final ts = entry.updatedAt > 0 ? entry.updatedAt : DateTime.now().millisecondsSinceEpoch;
    db.execute('INSERT INTO lyrics_source_cache (key_hash, source, state, raw_lrc, is_synced, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(key_hash, source) DO UPDATE SET state = excluded.state, raw_lrc = excluded.raw_lrc, is_synced = excluded.is_synced, updated_at = excluded.updated_at;', [entry.keyHash, entry.source.dbValue, entry.state.dbValue, entry.rawLrc, entry.isSynced ? 1 : 0, ts]);
    if (entry.state == LyricsSourceState.found && entry.rawLrc != null) {
      db.execute('INSERT INTO lyrics_cache (key_hash, raw_lrc, source, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(key_hash) DO UPDATE SET raw_lrc = excluded.raw_lrc, source = excluded.source, updated_at = excluded.updated_at;', [entry.keyHash, entry.rawLrc, entry.source.dbValue, ts]);
    }
  }

  void saveLyricsSourceEntries(List<LyricsSourceEntry> entries) {
    if (entries.isEmpty) return;
    db.execute('BEGIN TRANSACTION;');
    try {
      for (final e in entries) { saveLyricsSourceEntry(e); }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  LyricsSourceEntry? getLyricsSourceEntry(String keyHash, LyricsSource source) {
    final rows = db.select('SELECT key_hash, source, state, raw_lrc, is_synced, updated_at FROM lyrics_source_cache WHERE key_hash = ? AND source = ? LIMIT 1;', [keyHash, source.dbValue]);
    return rows.isEmpty ? null : LyricsSourceEntry.fromDbMap(rows.first);
  }

  Map<LyricsSource, LyricsSourceEntry> getAllLyricsSourceEntries(String keyHash) {
    final rows = db.select('SELECT key_hash, source, state, raw_lrc, is_synced, updated_at FROM lyrics_source_cache WHERE key_hash = ?;', [keyHash]);
    final map = <LyricsSource, LyricsSourceEntry>{};
    for (final r in rows) {
      final entry = LyricsSourceEntry.fromDbMap(r);
      map[entry.source] = entry;
    }
    return map;
  }

  int clearLyricsSourceEntries(String keyHash) {
    db.execute('DELETE FROM lyrics_cache WHERE key_hash = ?;', [keyHash]);
    db.execute('DELETE FROM lyrics_translations WHERE key_hash = ?;', [keyHash]);
    db.execute('DELETE FROM lyrics_source_cache WHERE key_hash = ?;', [keyHash]);
    return db.updatedRows;
  }

  int deleteLyricsSourceEntry(String keyHash, LyricsSource source) {
    db.execute('DELETE FROM lyrics_source_cache WHERE key_hash = ? AND source = ?;', [keyHash, source.dbValue]);
    return db.updatedRows;
  }

  void saveLyrics(String keyHash, String rawLrc, String source) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('INSERT INTO lyrics_cache (key_hash, raw_lrc, source, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(key_hash) DO UPDATE SET raw_lrc = excluded.raw_lrc, source = excluded.source, updated_at = excluded.updated_at;', [keyHash, rawLrc, source, now]);
    final parsed = LyricsSource.tryParse(source) ?? LyricsSource.embedded;
    final isSynced = RegExp(r'\[\d{1,}:\d{2}\.\d{2,3}\]').hasMatch(rawLrc);
    db.execute('INSERT INTO lyrics_source_cache (key_hash, source, state, raw_lrc, is_synced, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(key_hash, source) DO UPDATE SET state = excluded.state, raw_lrc = excluded.raw_lrc, is_synced = excluded.is_synced, updated_at = excluded.updated_at;', [keyHash, parsed.dbValue, LyricsSourceState.found.dbValue, rawLrc, isSynced ? 1 : 0, now]);
  }

  String? getLyrics(String keyHash) {
    final rows = db.select('SELECT raw_lrc FROM lyrics_cache WHERE key_hash = ? LIMIT 1;', [keyHash]);
    if (rows.isNotEmpty) return rows.first['raw_lrc'] as String?;
    final sourceRows = db.select('SELECT key_hash, source, state, raw_lrc, is_synced, updated_at FROM lyrics_source_cache WHERE key_hash = ? AND state = ? AND raw_lrc IS NOT NULL;', [keyHash, LyricsSourceState.found.dbValue]);
    if (sourceRows.isEmpty) return null;
    LyricsSourceEntry? best;
    for (final r in sourceRows) {
      final entry = LyricsSourceEntry.fromDbMap(r);
      if (best == null || entry.source.priority < best.source.priority) best = entry;
    }
    return best?.rawLrc;
  }

  void saveLyricsTranslation({required String keyHash, required String source, required String targetLang, required List<String> translatedLines}) {
    db.execute('INSERT INTO lyrics_translations (key_hash, source, target_lang, translated_lines, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(key_hash, source, target_lang) DO UPDATE SET translated_lines = excluded.translated_lines, updated_at = excluded.updated_at;', [keyHash, source, targetLang, jsonEncode(translatedLines), DateTime.now().millisecondsSinceEpoch]);
  }

  List<String>? getLyricsTranslation({required String keyHash, required String source, required String targetLang}) {
    final rows = db.select('SELECT translated_lines FROM lyrics_translations WHERE key_hash = ? AND source = ? AND target_lang = ? LIMIT 1;', [keyHash, source, targetLang]);
    if (rows.isEmpty) return null;
    try {
      return (jsonDecode(rows.first['translated_lines'] as String) as List<dynamic>).map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  int clearLyricsTranslations(String keyHash) {
    db.execute('DELETE FROM lyrics_translations WHERE key_hash = ?;', [keyHash]);
    return db.updatedRows;
  }

  Future<void> close() async {
    _db?.close();
    _db = null;
  }
}
