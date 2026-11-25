/// SQLite DDL schema statements and index definitions for `AppDatabase`.
abstract final class AppDatabaseSchema {
  /// Ordered table creation DDL statements.
  static const List<String> createTables = [
    'CREATE TABLE IF NOT EXISTS artists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE, artwork_uri TEXT);',
    'CREATE TABLE IF NOT EXISTS albums (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE, year INTEGER, artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL, artwork_uri TEXT, UNIQUE(name COLLATE NOCASE, artist_id));',
    'CREATE TABLE IF NOT EXISTS tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, file_path TEXT UNIQUE NOT NULL, title TEXT NOT NULL, track_number INTEGER, disc_number INTEGER DEFAULT 1, year INTEGER, duration_ms INTEGER NOT NULL, bitrate INTEGER, sample_rate INTEGER, channels INTEGER, codec TEXT, file_size INTEGER NOT NULL, modified_at INTEGER NOT NULL, replay_gain_track_gain REAL, replay_gain_track_peak REAL, waveform_data TEXT, album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL, artwork_uri TEXT);',
    'CREATE TABLE IF NOT EXISTS genres (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE);',
    'CREATE TABLE IF NOT EXISTS track_genres (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE, PRIMARY KEY(track_id, genre_id));',
    'CREATE TABLE IF NOT EXISTS track_artists (track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, artist_id INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE, PRIMARY KEY(track_id, artist_id));',
    'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at INTEGER NOT NULL, type INTEGER DEFAULT 0);',
    'CREATE TABLE IF NOT EXISTS playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, position INTEGER NOT NULL, added_at INTEGER NOT NULL, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id INTEGER REFERENCES tracks(id) ON DELETE CASCADE);',
    'CREATE TABLE IF NOT EXISTS lyrics (id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, source TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'FOUND\', raw_lrc TEXT, is_synced INTEGER DEFAULT 0, lang TEXT, updated_at INTEGER NOT NULL, UNIQUE(track_id, source));',
    'CREATE TABLE IF NOT EXISTS lyrics_translations (id INTEGER PRIMARY KEY AUTOINCREMENT, lyrics_id INTEGER NOT NULL REFERENCES lyrics(id) ON DELETE CASCADE, lang TEXT NOT NULL, translated_lines TEXT NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(lyrics_id, lang));',
    'CREATE TABLE IF NOT EXISTS radio_stations (id INTEGER PRIMARY KEY AUTOINCREMENT, station_uuid TEXT, name TEXT NOT NULL, stream_url TEXT NOT NULL UNIQUE, homepage_url TEXT, favicon_url TEXT, genre TEXT, country TEXT, bitrate_kbps INTEGER, codec TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);',
  ];

  /// Ordered secondary index creation DDL statements.
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
    'CREATE INDEX IF NOT EXISTS idx_radio_stations_uuid ON radio_stations(station_uuid);',
    'CREATE INDEX IF NOT EXISTS idx_radio_stations_favorite ON radio_stations(is_favorite);',
  ];
}
