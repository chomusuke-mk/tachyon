import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  group('Milestone 1 Empirical Domain Decoupling & Oracle Tests', () {
    test('Oracle 1: File lib/features/library/domain/lyrics.dart is completely deleted', () {
      final lyricsFile = File('lib/features/library/domain/lyrics.dart');
      expect(lyricsFile.existsSync(), isFalse, reason: 'lyrics.dart must be completely deleted');

      // Search all files under lib/
      final libDir = Directory('lib');
      final allDartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('lyrics.dart'))
          .toList();
      expect(allDartFiles, isEmpty, reason: 'No file named lyrics.dart should exist anywhere in lib/');
    });

    test('Oracle 2: Track has NO lyrics property, lyrics_id, or lyrics getter', () {
      const track = Track(
        id: 42,
        filePath: '/music/oracle_test.mp3',
        title: 'Oracle Song',
        durationMs: 180000,
        fileSize: 1024,
        modifiedAt: 1000,
        album: Album(id: 1, name: 'Oracle Album'),
        artists: [Artist(id: 1, name: 'Oracle Artist')],
        genres: [Genre(id: 1, name: 'Oracle Genre')],
      );

      final dynamic dynamicTrack = track;

      // 1. Assert NoSuchMethodError when trying to access lyrics-related getters/properties
      expect(() => dynamicTrack.lyrics, throwsNoSuchMethodError);
      expect(() => dynamicTrack.lyricsId, throwsNoSuchMethodError);
      expect(() => dynamicTrack.lyrics_id, throwsNoSuchMethodError);
      expect(() => dynamicTrack.rawLyrics, throwsNoSuchMethodError);

      // 2. Assert toMap() does not contain any lyrics keys
      final map = track.toMap();
      expect(map.containsKey('lyrics'), isFalse);
      expect(map.containsKey('lyrics_id'), isFalse);
      expect(map.containsKey('raw_lyrics'), isFalse);
      expect(map.containsKey('lyricsId'), isFalse);

      // 3. Assert fromMap() ignores any rogue lyrics keys without leaking them
      final rogueMap = Map<String, dynamic>.from(map);
      rogueMap['lyrics'] = 'Rogue Lyric Text';
      rogueMap['lyrics_id'] = 999;
      final reconstructed = Track.fromMap(rogueMap);
      final dynamic reconstructedDynamic = reconstructed;
      expect(() => reconstructedDynamic.lyrics, throwsNoSuchMethodError);
      expect(() => reconstructedDynamic.lyricsId, throwsNoSuchMethodError);
      expect(reconstructed.toMap().containsKey('lyrics'), isFalse);
    });

    test('Oracle 3: PlaylistEntry has NO lyrics leaks and preserves in-memory Track reference', () {
      const track = Track(
        id: 77,
        filePath: '/music/queue_leak_test.mp3',
        title: 'Queue Leak Song',
        durationMs: 240000,
        fileSize: 2048,
        modifiedAt: 2000,
        album: Album(id: 2, name: 'Queue Album'),
        artists: [Artist(id: 2, name: 'Queue Artist')],
      );

      final entry = PlaylistEntry.forQueue(id: 0, track: track);
      final dynamic dynamicItem = entry;

      // 1. Assert dynamic access throws NoSuchMethodError
      expect(() => dynamicItem.lyrics, throwsNoSuchMethodError);
      expect(() => dynamicItem.lyricsId, throwsNoSuchMethodError);
      expect(() => dynamicItem.lyrics_id, throwsNoSuchMethodError);
      expect(() => dynamicItem.extras, throwsNoSuchMethodError);

      // 2. Direct reference: PlaylistEntry.track holds in-memory Track
      expect(identical(entry.track, track), isTrue);
      expect(entry.track!.toMap().containsKey('lyrics'), isFalse);
    });

    test('Oracle 4: AppDatabase schema has zero lyrics column in tracks and cascades to lyrics/translations', () {
      final db = AppDatabase.inMemory();

      // Inspect tracks table columns via raw sqlite PRAGMA table_info
      final trackColumnsResult = db.db.select('PRAGMA table_info(tracks);');
      final columnNames = trackColumnsResult.map((r) => r['name'] as String).toSet();
      expect(columnNames.contains('lyrics'), isFalse, reason: 'tracks table MUST NOT contain lyrics column');

      // Verify obsolete tables do not exist
      final masterTables = db.db.select("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = masterTables.map((r) => r['name'] as String).toSet();
      expect(tableNames.contains('lyrics_cache'), isFalse, reason: 'lyrics_cache MUST be deleted');
      expect(tableNames.contains('lyrics_source_cache'), isFalse, reason: 'lyrics_source_cache MUST be deleted');

      // Verify new normalized tables exist
      expect(tableNames.contains('lyrics'), isTrue, reason: 'lyrics table must exist');
      expect(tableNames.contains('lyrics_translations'), isTrue, reason: 'lyrics_translations table must exist');

      // Verify foreign key ON DELETE CASCADE on lyrics table
      final lyricsFk = db.db.select('PRAGMA foreign_key_list(lyrics);');
      expect(lyricsFk.any((r) => r['table'] == 'tracks' && r['on_delete'] == 'CASCADE'), isTrue);

      // Verify foreign key ON DELETE CASCADE on lyrics_translations table
      final transFk = db.db.select('PRAGMA foreign_key_list(lyrics_translations);');
      expect(transFk.any((r) => r['table'] == 'lyrics' && r['on_delete'] == 'CASCADE'), isTrue);

      db.close();
    });
  });
}
