import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/genre.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';

void main() {
  group('Milestone 1 Empirical Domain Decoupling & Oracle Tests', () {
    test('Oracle 1: File lyrics.dart does not exist in domain models', () {
      final legacyLyricsFile = File('lib/features/library/domain/lyrics.dart');
      final storeLyricsFile = File('lib/core/store/domain/lyrics.dart');
      expect(legacyLyricsFile.existsSync(), isFalse);
      expect(storeLyricsFile.existsSync(), isFalse);

      final libDir = Directory('lib');
      final allDartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('lyrics.dart'))
          .toList();
      expect(allDartFiles, isEmpty, reason: 'No file named lyrics.dart should exist anywhere in lib/');
    });

    test('Oracle 2: Track has NO lyrics property, lyrics_id, or lyrics getter', () {
      final track = Track(
        id: 42,
        filePath: '/music/oracle_test.mp3',
        title: 'Oracle Song',
        durationMs: 180000,
        fileSize: 1024,
        modifiedAt: 1000,
        album: const Album(id: 1, name: 'Oracle Album'),
        artists: const [Artist(id: 1, name: 'Oracle Artist')],
        genres: [Genre(id: 1, name: 'Oracle Genre')],
      );

      final dynamic dynamicTrack = track;

      expect(() => dynamicTrack.lyrics, throwsNoSuchMethodError);
      expect(() => dynamicTrack.lyricsId, throwsNoSuchMethodError);
      expect(() => dynamicTrack.lyrics_id, throwsNoSuchMethodError);
      expect(() => dynamicTrack.rawLyrics, throwsNoSuchMethodError);
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

      final entry = PlaylistEntry(id: 0, position: 0, addedAt: 0, track: track);
      final dynamic dynamicItem = entry;

      expect(() => dynamicItem.lyrics, throwsNoSuchMethodError);
      expect(() => dynamicItem.lyricsId, throwsNoSuchMethodError);
      expect(() => dynamicItem.lyrics_id, throwsNoSuchMethodError);
      expect(() => dynamicItem.extras, throwsNoSuchMethodError);

      expect(identical(entry.track, track), isTrue);
    });

    test('Oracle 4: AppDatabase schema has zero lyrics column in tracks and cascades to lyrics/translations', () async {
      final db = AppDatabase.inMemory();

      final trackColumnsResult = db.db.select('PRAGMA table_info(tracks);');
      final columnNames = trackColumnsResult.map((r) => r['name'] as String).toSet();
      expect(columnNames.contains('lyrics'), isFalse, reason: 'tracks table MUST NOT contain lyrics column');

      final masterTables = db.db.select("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = masterTables.map((r) => r['name'] as String).toSet();
      expect(tableNames.contains('lyrics_cache'), isFalse, reason: 'lyrics_cache MUST be deleted');
      expect(tableNames.contains('lyrics_source_cache'), isFalse, reason: 'lyrics_source_cache MUST be deleted');

      expect(tableNames.contains('lyrics'), isTrue, reason: 'lyrics table must exist');
      expect(tableNames.contains('lyrics_translations'), isTrue, reason: 'lyrics_translations table must exist');

      final lyricsFk = db.db.select('PRAGMA foreign_key_list(lyrics);');
      expect(lyricsFk.any((r) => r['table'] == 'tracks' && r['on_delete'] == 'CASCADE'), isTrue);

      final transFk = db.db.select('PRAGMA foreign_key_list(lyrics_translations);');
      expect(transFk.any((r) => r['table'] == 'lyrics' && r['on_delete'] == 'CASCADE'), isTrue);

      await db.close();
    });
  });
}
