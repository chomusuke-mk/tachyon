import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  group('Milestone 1 Adversarial & Stress Verification', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('FK CASCADE: Deleting tracks or folder cascades to all child lyrics and translations', () {
      // 1. Create 10 tracks across 2 folders
      final tracks = <ExtractedTrackData>[];
      for (var i = 1; i <= 10; i++) {
        final folder = i <= 5 ? '/music/folderA' : '/music/folderB';
        tracks.add(ExtractedTrackData(
          filePath: '$folder/song$i.mp3',
          title: 'Track $i',
          artistNames: ['Artist ${i % 3}'],
          durationMs: 120000 + i * 1000,
          fileSize: 3000000 + i * 100,
          modifiedAt: 1000 + i,
        ));
      }
      database.upsertTracks(tracks);

      final snapshot = database.getCatalogSnapshot();
      expect(snapshot.tracks.length, 10);

      // 2. Add 4 lyrics sources to EACH track, and 3 translations to EACH lyrics entry
      // Total = 10 * 4 = 40 lyrics rows; 40 * 3 = 120 translations
      final sources = ['embedded', 'file', 'lrclib', 'lyrics_ovh'];
      final langs = ['es', 'de', 'ja'];

      for (final t in snapshot.tracks) {
        for (final src in sources) {
          final lyricsId = database.saveLyricsEntry(
            trackId: t.id,
            source: src,
            state: 'FOUND',
            rawLrc: '[00:01.00] $src for ${t.title}',
            isSynced: true,
          );
          for (final lang in langs) {
            database.saveLyricsTranslation(
              lyricsId: lyricsId,
              lang: lang,
              translatedLines: ['[00:01.00] Translation $lang for $src of ${t.title}'],
            );
          }
        }
      }

      // Verify baseline counts via direct SQL count
      final initialLyricsCount = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final initialTransCount = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(initialLyricsCount, 40);
      expect(initialTransCount, 120);

      // 3. Delete single track 1
      final track1 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/folderA/song1.mp3');
      database.deleteTrack(track1.id);

      final postTrack1Lyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postTrack1Trans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      // Exactly 4 lyrics and 12 translations deleted
      expect(postTrack1Lyrics, 36);
      expect(postTrack1Trans, 108);

      // Verify no orphan lyrics or translations for track 1
      final orphanLyrics1 = database.db.select('SELECT count(*) AS c FROM lyrics WHERE track_id = ?;', [track1.id]).first['c'] as int;
      expect(orphanLyrics1, 0);

      // 4. Delete folderA (contains 4 remaining tracks: song2, song3, song4, song5)
      // 4 tracks * 4 lyrics = 16 lyrics; 16 * 3 = 48 translations deleted
      database.deleteTracksInFolder('/music/folderA');

      final postFolderALyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postFolderATrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      // 36 - 16 = 20 lyrics; 108 - 48 = 60 translations
      expect(postFolderALyrics, 20);
      expect(postFolderATrans, 60);

      // 5. Delete a single lyrics entry for a track in folderB
      final track6 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/folderB/song6.mp3');
      final track6Embedded = database.getLyricsEntry(trackId: track6.id, source: 'embedded');
      expect(track6Embedded, isNotNull);
      final track6EmbeddedId = track6Embedded!['id'] as int;

      database.deleteLyrics(track6EmbeddedId);

      // Only 1 lyrics and 3 translations deleted
      final postLyricsDeleteLyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postLyricsDeleteTrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(postLyricsDeleteLyrics, 19);
      expect(postLyricsDeleteTrans, 57);

      // Track 6 still exists, and its remaining 3 sources still exist
      expect(database.getLyricsEntry(trackId: track6.id, source: 'file'), isNotNull);
      expect(database.getLyricsEntry(trackId: track6.id, source: 'lrclib'), isNotNull);
      expect(database.getLyricsEntry(trackId: track6.id, source: 'lyrics_ovh'), isNotNull);

      // 6. Direct FK enforcement: inserting invalid track_id or lyrics_id throws SqliteException
      expect(
        () => database.saveLyricsEntry(trackId: 999999, source: 'file', state: 'FOUND'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.saveLyricsTranslation(lyricsId: 999999, lang: 'es', translatedLines: ['test']),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Priority Resolution: hierarchy, mixed states, and invalid/empty text handling', () {
      final track = ExtractedTrackData(
        filePath: '/music/priority_stress.mp3',
        title: 'Priority Stress',
        artistNames: ['Challenger Artist'],
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 1000,
      );
      database.upsertTracks([track]);
      final trackId = database.getCatalogSnapshot().tracks.first.id;

      // Initial state: no lyrics
      expect(database.getBestLyricsForTrack(trackId), isNull);

      // 1. Higher priority exists but NOT_FOUND -> must pick lower priority with FOUND
      database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'NOT_FOUND', rawLrc: null);
      database.saveLyricsEntry(trackId: trackId, source: 'file', state: 'NOT_FOUND', rawLrc: null);
      database.saveLyricsEntry(trackId: trackId, source: 'lrclib', state: 'FOUND', rawLrc: '[00:01.00] LRCLIB lyric');
      database.saveLyricsEntry(trackId: trackId, source: 'lyrics_ovh', state: 'FOUND', rawLrc: 'OVH lyric');

      var best = database.getBestLyricsForTrack(trackId);
      expect(best, isNotNull);
      expect(best!['source'], 'lrclib');
      expect(best['raw_lrc'], '[00:01.00] LRCLIB lyric');

      // 2. Now file becomes FOUND -> must override lrclib
      database.saveLyricsEntry(trackId: trackId, source: 'file', state: 'FOUND', rawLrc: '[00:01.00] File lyric');
      best = database.getBestLyricsForTrack(trackId);
      expect(best!['source'], 'file');

      // 3. Now embedded becomes FOUND -> must override file
      database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'FOUND', rawLrc: '[00:01.00] Embedded lyric');
      best = database.getBestLyricsForTrack(trackId);
      expect(best!['source'], 'embedded');

      // 4. Source with state = 'FOUND' but raw_lrc is null -> must be ignored by getBestLyricsForTrack
      database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'FOUND', rawLrc: null);
      best = database.getBestLyricsForTrack(trackId);
      expect(best!['source'], 'file'); // falls back to file

      // 5. Custom / unknown source falls to priority 5
      database.saveLyricsEntry(trackId: trackId, source: 'unknown_service', state: 'FOUND', rawLrc: 'Unknown lyrics');
      // Delete all official sources
      database.deleteLyrics(database.getLyricsEntry(trackId: trackId, source: 'embedded')!['id'] as int);
      database.deleteLyrics(database.getLyricsEntry(trackId: trackId, source: 'file')!['id'] as int);
      database.deleteLyrics(database.getLyricsEntry(trackId: trackId, source: 'lrclib')!['id'] as int);
      database.deleteLyrics(database.getLyricsEntry(trackId: trackId, source: 'lyrics_ovh')!['id'] as int);

      best = database.getBestLyricsForTrack(trackId);
      expect(best, isNotNull);
      expect(best!['source'], 'unknown_service');
    });

    test('Translation purge on update in saveLyricsEntry: strict isolation across tracks and sources', () {
      final t1 = ExtractedTrackData(filePath: '/music/iso1.mp3', title: 'Iso 1', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      final t2 = ExtractedTrackData(filePath: '/music/iso2.mp3', title: 'Iso 2', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      database.upsertTracks([t1, t2]);
      final tracks = database.getCatalogSnapshot().tracks;
      final t1Id = tracks.firstWhere((t) => t.filePath == '/music/iso1.mp3').id;
      final t2Id = tracks.firstWhere((t) => t.filePath == '/music/iso2.mp3').id;

      // Track 1, Source lrclib
      final t1LrclibId = database.saveLyricsEntry(trackId: t1Id, source: 'lrclib', state: 'FOUND', rawLrc: 't1 lrclib');
      // Track 1, Source lyrics_ovh
      final t1OvhId = database.saveLyricsEntry(trackId: t1Id, source: 'lyrics_ovh', state: 'FOUND', rawLrc: 't1 ovh');
      // Track 2, Source lrclib
      final t2LrclibId = database.saveLyricsEntry(trackId: t2Id, source: 'lrclib', state: 'FOUND', rawLrc: 't2 lrclib');

      // Add translations
      database.saveLyricsTranslation(lyricsId: t1LrclibId, lang: 'es', translatedLines: ['t1 lrclib es']);
      database.saveLyricsTranslation(lyricsId: t1LrclibId, lang: 'fr', translatedLines: ['t1 lrclib fr']);

      database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'es', translatedLines: ['t1 ovh es']);
      database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'de', translatedLines: ['t1 ovh de']);

      database.saveLyricsTranslation(lyricsId: t2LrclibId, lang: 'es', translatedLines: ['t2 lrclib es']);
      database.saveLyricsTranslation(lyricsId: t2LrclibId, lang: 'it', translatedLines: ['t2 lrclib it']);

      // Total translations before update = 6
      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 6);

      // Now UPDATE t1 lrclib lyrics
      final updatedId = database.saveLyricsEntry(trackId: t1Id, source: 'lrclib', state: 'FOUND', rawLrc: 't1 lrclib updated');
      expect(updatedId, t1LrclibId);

      // Total translations after update must be 4 (exactly 2 translations for t1 lrclib purged)
      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 4);

      // Verify t1 lrclib translations are purged
      expect(database.getLyricsTranslation(lyricsId: t1LrclibId, lang: 'es'), isNull);
      expect(database.getLyricsTranslation(lyricsId: t1LrclibId, lang: 'fr'), isNull);

      // CRITICAL ISOLATION CHECK: t1 ovh translations are completely intact
      expect(database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'es'), ['t1 ovh es']);
      expect(database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'de'), ['t1 ovh de']);

      // CRITICAL ISOLATION CHECK: t2 lrclib translations are completely intact
      expect(database.getLyricsTranslation(lyricsId: t2LrclibId, lang: 'es'), ['t2 lrclib es']);
      expect(database.getLyricsTranslation(lyricsId: t2LrclibId, lang: 'it'), ['t2 lrclib it']);

      // Translation update idempotency: updating an existing translation in place
      database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'es', translatedLines: ['t1 ovh es overwritten']);
      expect(database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'es'), ['t1 ovh es overwritten']);
      // Still 4 translations
      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 4);
    });

    test('Translation serialization resilience: Unicode, emojis, empty lists, and corrupt data handling', () {
      final t = ExtractedTrackData(filePath: '/music/unicode.mp3', title: 'Unicode', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      database.upsertTracks([t]);
      final trackId = database.getCatalogSnapshot().tracks.first.id;
      final lyricsId = database.saveLyricsEntry(trackId: trackId, source: 'lrclib', state: 'FOUND', rawLrc: 'lyrics');

      // Emojis, quotes, newlines, UTF-8
      final complexLines = [
        'Line 1 with quotes: "hello" and \'world\'',
        'Line 2 with emojis: 🎶 🎤 🎸 🔥',
        'Line 3 with unicode: ¿Cómo estás? Voilà, déjà vu. 日本語テスト, 🎵',
        'Line 4 with special escapes: \\n \\t \\r \\" \' ; -- DROP TABLE',
      ];
      database.saveLyricsTranslation(lyricsId: lyricsId, lang: 'ja', translatedLines: complexLines);
      final retrieved = database.getLyricsTranslation(lyricsId: lyricsId, lang: 'ja');
      expect(retrieved, complexLines);

      // Empty list
      database.saveLyricsTranslation(lyricsId: lyricsId, lang: 'empty', translatedLines: []);
      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'empty'), <String>[]);

      // Corrupt database JSON data gracefully handled
      database.db.execute("INSERT INTO lyrics_translations (lyrics_id, lang, translated_lines, updated_at) VALUES (?, 'corrupt', 'NOT_JSON_DATA', 12345);", [lyricsId]);
      expect(database.getLyricsTranslation(lyricsId: lyricsId, lang: 'corrupt'), isNull);
    });

    test('Schema purity: old tables lyrics_cache, lyrics_source_cache and column tracks.lyrics are absent', () {
      // 1. Verify tracks does not have lyrics column
      expect(
        () => database.db.select('SELECT lyrics FROM tracks;'),
        throwsA(isA<SqliteException>()),
      );

      // 2. Verify lyrics_cache does not exist
      expect(
        () => database.db.select('SELECT * FROM lyrics_cache;'),
        throwsA(isA<SqliteException>()),
      );

      // 3. Verify lyrics_source_cache does not exist
      expect(
        () => database.db.select('SELECT * FROM lyrics_source_cache;'),
        throwsA(isA<SqliteException>()),
      );

      // 4. Verify CatalogSnapshot has zero lyrics
      final snapshot = database.getCatalogSnapshot();
      expect(snapshot.tracks, isEmpty);
    });

    test('Domain purity: Track and QueueItem do not contain lyrics properties', () {
      final track = Track(
        id: 1,
        filePath: '/path/song.mp3',
        title: 'Title',
        durationMs: 180000,
        fileSize: 1024,
        modifiedAt: 123456789,
      );

      final queueItem = QueueItem.fromTrack(track);

      // Ensure QueueItem extras does not contain 'lyrics'
      expect(queueItem.extras.containsKey('lyrics'), isFalse);

      final trackRoundTrip = queueItem.toTrack();
      expect(trackRoundTrip.id, 1);
      expect(trackRoundTrip.title, 'Title');
    });

    test('upsertTracks auto-detects synced embedded lyrics and ignores empty lyrics', () {
      final syncedTrack = ExtractedTrackData(
        filePath: '/music/synced.mp3',
        title: 'Synced Song',
        artistNames: ['Artist'],
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 1,
        embeddedLyrics: '[00:01.00] Line one\n[00:05.50] Line two',
      );

      final unsyncedTrack = ExtractedTrackData(
        filePath: '/music/unsynced.mp3',
        title: 'Unsynced Song',
        artistNames: ['Artist'],
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 1,
        embeddedLyrics: 'Line one without timestamps\nLine two',
      );

      final emptyLyricsTrack = ExtractedTrackData(
        filePath: '/music/empty_lyrics.mp3',
        title: 'Empty Song',
        artistNames: ['Artist'],
        durationMs: 1000,
        fileSize: 1000,
        modifiedAt: 1,
        embeddedLyrics: '   \n  \t  ',
      );

      database.upsertTracks([syncedTrack, unsyncedTrack, emptyLyricsTrack]);
      final tracks = database.getCatalogSnapshot().tracks;

      final syncedId = tracks.firstWhere((t) => t.filePath == '/music/synced.mp3').id;
      final unsyncedId = tracks.firstWhere((t) => t.filePath == '/music/unsynced.mp3').id;
      final emptyId = tracks.firstWhere((t) => t.filePath == '/music/empty_lyrics.mp3').id;

      final syncedEntry = database.getLyricsEntry(trackId: syncedId, source: 'embedded');
      expect(syncedEntry, isNotNull);
      expect(syncedEntry!['is_synced'], 1);
      expect(syncedEntry['state'], 'FOUND');

      final unsyncedEntry = database.getLyricsEntry(trackId: unsyncedId, source: 'embedded');
      expect(unsyncedEntry, isNotNull);
      expect(unsyncedEntry!['is_synced'], 0);
      expect(unsyncedEntry['state'], 'FOUND');

      final emptyEntry = database.getLyricsEntry(trackId: emptyId, source: 'embedded');
      expect(emptyEntry, isNull);
    });

    test('On-disk WAL mode persistence and cascade survives database close and reopen', () async {
      final tempDir = await io.Directory.systemTemp.createTemp('tachyon_lyrics_test_');
      final dbFile = '${tempDir.path}/test_music.db';

      try {
        final diskDb = AppDatabase();
        await diskDb.init(dbFile);

        final track = ExtractedTrackData(
          filePath: '/disk/song.mp3',
          title: 'Disk Track',
          artistNames: ['Disk Artist'],
          durationMs: 200000,
          fileSize: 4000000,
          modifiedAt: 1000,
        );
        diskDb.upsertTracks([track]);
        final trackId = diskDb.getCatalogSnapshot().tracks.first.id;

        final lyricsId = diskDb.saveLyricsEntry(
          trackId: trackId,
          source: 'lrclib',
          state: 'FOUND',
          rawLrc: '[00:01.00] Disk lyric',
          isSynced: true,
        );
        diskDb.saveLyricsTranslation(
          lyricsId: lyricsId,
          lang: 'es',
          translatedLines: ['[00:01.00] Letra en disco'],
        );

        // Verify data before close
        expect(diskDb.getBestLyricsForTrack(trackId), isNotNull);
        expect(diskDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), ['[00:01.00] Letra en disco']);

        await diskDb.close();

        // Reopen database from disk file
        final reopenedDb = AppDatabase();
        await reopenedDb.init(dbFile);

        expect(reopenedDb.getBestLyricsForTrack(trackId), isNotNull);
        expect(reopenedDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), ['[00:01.00] Letra en disco']);

        // Delete track on reopened disk DB -> CASCADE must work on disk!
        reopenedDb.deleteTrack(trackId);

        expect(reopenedDb.getBestLyricsForTrack(trackId), isNull);
        expect(reopenedDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);

        final lCount = reopenedDb.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
        final tCount = reopenedDb.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
        expect(lCount, 0);
        expect(tCount, 0);

        await reopenedDb.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('High-volume stress test: 50 tracks, multiple sources and translations, bulk cascade', () {
      final tracks = List.generate(50, (i) => ExtractedTrackData(
        filePath: '/music/bulk/song_$i.mp3',
        title: 'Bulk Song $i',
        artistNames: ['Artist ${i % 5}'],
        albumName: 'Album ${i % 3}',
        genreNames: ['Genre ${i % 2}'],
        durationMs: 150000 + i,
        fileSize: 1000000 + i,
        modifiedAt: 1000 + i,
        embeddedLyrics: (i % 2 == 0) ? '[00:01.00] Embedded $i' : null,
      ));

      database.upsertTracks(tracks);
      final snapshot = database.getCatalogSnapshot();
      expect(snapshot.tracks.length, 50);

      // 25 tracks had embedded lyrics from upsertTracks
      final initialEmbedded = database.db.select("SELECT count(*) AS c FROM lyrics WHERE source = 'embedded';").first['c'] as int;
      expect(initialEmbedded, 25);

      // Add remote sources and translations
      for (final t in snapshot.tracks) {
        final lrclibId = database.saveLyricsEntry(
          trackId: t.id,
          source: 'lrclib',
          state: 'FOUND',
          rawLrc: '[00:01.00] LRCLIB ${t.id}',
          isSynced: true,
        );
        database.saveLyricsTranslation(lyricsId: lrclibId, lang: 'es', translatedLines: ['Spanish ${t.id}']);
        database.saveLyricsTranslation(lyricsId: lrclibId, lang: 'fr', translatedLines: ['French ${t.id}']);
      }

      // Check total translations: 50 * 2 = 100
      final totalTrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(totalTrans, 100);

      // Bulk delete all tracks in folder
      database.deleteTracksInFolder('/music/bulk');

      final remainingTracks = database.getCatalogSnapshot().tracks.length;
      expect(remainingTracks, 0);

      final finalLyricsCount = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final finalTransCount = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;

      expect(finalLyricsCount, 0);
      expect(finalTransCount, 0);
    });
  });
}

