import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';

void main() {
  group('Milestone 1 Adversarial & Stress Verification', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('FK CASCADE: Deleting tracks or folder cascades to all child lyrics and translations', () async {
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
      await database.upsertTracks(tracks);

      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks.length, 10);

      final sources = ['embedded', 'file', 'lrclib', 'lyrics_ovh'];
      final langs = ['es', 'de', 'ja'];

      for (final t in snapshot.tracks) {
        for (final src in sources) {
          final lyricsId = await database.saveLyricsEntry(
            trackId: t.id,
            source: src,
            state: 'FOUND',
            rawLrc: '[00:01.00] $src for ${t.title}',
            isSynced: true,
          );
          for (final lang in langs) {
            await database.saveLyricsTranslation(
              lyricsId: lyricsId,
              lang: lang,
              translatedLines: ['[00:01.00] Translation $lang for $src of ${t.title}'],
            );
          }
        }
      }

      final initialLyricsCount = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final initialTransCount = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(initialLyricsCount, 40);
      expect(initialTransCount, 120);

      final track1 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/folderA/song1.mp3');
      await database.deleteTracksAndPurgeOrphans([track1.id]);

      final postTrack1Lyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postTrack1Trans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(postTrack1Lyrics, 36);
      expect(postTrack1Trans, 108);

      final orphanLyrics1 = database.db.select('SELECT count(*) AS c FROM lyrics WHERE track_id = ?;', [track1.id]).first['c'] as int;
      expect(orphanLyrics1, 0);

      final folderATrackIds = (await database.getCatalogSnapshot())
          .tracks
          .where((t) => t.filePath.startsWith('/music/folderA'))
          .map((t) => t.id)
          .toList();
      await database.deleteTracksAndPurgeOrphans(folderATrackIds);

      final postFolderALyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postFolderATrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(postFolderALyrics, 20);
      expect(postFolderATrans, 60);

      Future<Map<String, dynamic>?> findEntry(AppDatabase db, int tId, String src) async {
        final rows = await db.getLyricsForTrack(tId);
        for (final r in rows) {
          if (r['source'] == src) return r;
        }
        return null;
      }

      final track6 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/folderB/song6.mp3');
      final track6Embedded = await findEntry(database, track6.id, 'embedded');
      expect(track6Embedded, isNotNull);
      final track6EmbeddedId = track6Embedded!['id'] as int;

      await database.deleteLyrics(track6EmbeddedId);

      final postLyricsDeleteLyrics = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final postLyricsDeleteTrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(postLyricsDeleteLyrics, 19);
      expect(postLyricsDeleteTrans, 57);

      expect(await findEntry(database, track6.id, 'file'), isNotNull);
      expect(await findEntry(database, track6.id, 'lrclib'), isNotNull);
      expect(await findEntry(database, track6.id, 'lyrics_ovh'), isNotNull);

      await expectLater(
        database.saveLyricsEntry(trackId: 999999, source: 'file', state: 'FOUND'),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        database.saveLyricsTranslation(lyricsId: 999999, lang: 'es', translatedLines: ['test']),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Priority Resolution: hierarchy, mixed states, and invalid/empty text handling', () async {
      Future<Map<String, dynamic>?> getBest(AppDatabase db, int tId) async {
        final rows = await db.getLyricsForTrack(tId);
        const order = {'embedded': 1, 'file': 2, 'lrclib': 3, 'lyrics_ovh': 4};
        final found = rows.where((r) => r['state'] == 'FOUND' && r['raw_lrc'] != null).toList();
        if (found.isEmpty) return null;
        found.sort((a, b) => (order[a['source']] ?? 5).compareTo(order[b['source']] ?? 5));
        return found.first;
      }
      Future<Map<String, dynamic>?> getEntry(AppDatabase db, int tId, String src) async {
        final rows = await db.getLyricsForTrack(tId);
        for (final r in rows) {
          if (r['source'] == src) return r;
        }
        return null;
      }

      final track = ExtractedTrackData(
        filePath: '/music/priority_stress.mp3',
        title: 'Priority Stress',
        artistNames: ['Challenger Artist'],
        durationMs: 180000,
        fileSize: 5000000,
        modifiedAt: 1000,
      );
      await database.upsertTracks([track]);
      final trackId = (await database.getCatalogSnapshot()).tracks.first.id;

      expect(await getBest(database, trackId), isNull);

      await database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'NOT_FOUND', rawLrc: null);
      await database.saveLyricsEntry(trackId: trackId, source: 'file', state: 'NOT_FOUND', rawLrc: null);
      await database.saveLyricsEntry(trackId: trackId, source: 'lrclib', state: 'FOUND', rawLrc: '[00:01.00] LRCLIB lyric');
      await database.saveLyricsEntry(trackId: trackId, source: 'lyrics_ovh', state: 'FOUND', rawLrc: 'OVH lyric');

      var best = await getBest(database, trackId);
      expect(best, isNotNull);
      expect(best!['source'], 'lrclib');
      expect(best['raw_lrc'], '[00:01.00] LRCLIB lyric');

      await database.saveLyricsEntry(trackId: trackId, source: 'file', state: 'FOUND', rawLrc: '[00:01.00] File lyric');
      best = await getBest(database, trackId);
      expect(best!['source'], 'file');

      await database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'FOUND', rawLrc: '[00:01.00] Embedded lyric');
      best = await getBest(database, trackId);
      expect(best!['source'], 'embedded');

      await database.saveLyricsEntry(trackId: trackId, source: 'embedded', state: 'FOUND', rawLrc: null);
      best = await getBest(database, trackId);
      expect(best!['source'], 'file');

      await database.saveLyricsEntry(trackId: trackId, source: 'unknown_service', state: 'FOUND', rawLrc: 'Unknown lyrics');
      await database.deleteLyrics((await getEntry(database, trackId, 'embedded'))!['id'] as int);
      await database.deleteLyrics((await getEntry(database, trackId, 'file'))!['id'] as int);
      await database.deleteLyrics((await getEntry(database, trackId, 'lrclib'))!['id'] as int);
      await database.deleteLyrics((await getEntry(database, trackId, 'lyrics_ovh'))!['id'] as int);

      best = await getBest(database, trackId);
      expect(best, isNotNull);
      expect(best!['source'], 'unknown_service');
    });

    test('Translation purge on update in saveLyricsEntry: strict isolation across tracks and sources', () async {
      final t1 = ExtractedTrackData(filePath: '/music/iso1.mp3', title: 'Iso 1', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      final t2 = ExtractedTrackData(filePath: '/music/iso2.mp3', title: 'Iso 2', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      await database.upsertTracks([t1, t2]);
      final tracks = (await database.getCatalogSnapshot()).tracks;
      final t1Id = tracks.firstWhere((t) => t.filePath == '/music/iso1.mp3').id;
      final t2Id = tracks.firstWhere((t) => t.filePath == '/music/iso2.mp3').id;

      final t1LrclibId = await database.saveLyricsEntry(trackId: t1Id, source: 'lrclib', state: 'FOUND', rawLrc: 't1 lrclib');
      final t1OvhId = await database.saveLyricsEntry(trackId: t1Id, source: 'lyrics_ovh', state: 'FOUND', rawLrc: 't1 ovh');
      final t2LrclibId = await database.saveLyricsEntry(trackId: t2Id, source: 'lrclib', state: 'FOUND', rawLrc: 't2 lrclib');

      await database.saveLyricsTranslation(lyricsId: t1LrclibId, lang: 'es', translatedLines: ['t1 lrclib es']);
      await database.saveLyricsTranslation(lyricsId: t1LrclibId, lang: 'fr', translatedLines: ['t1 lrclib fr']);
      await database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'es', translatedLines: ['t1 ovh es']);
      await database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'de', translatedLines: ['t1 ovh de']);
      await database.saveLyricsTranslation(lyricsId: t2LrclibId, lang: 'es', translatedLines: ['t2 lrclib es']);
      await database.saveLyricsTranslation(lyricsId: t2LrclibId, lang: 'it', translatedLines: ['t2 lrclib it']);

      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 6);

      final updatedId = await database.saveLyricsEntry(trackId: t1Id, source: 'lrclib', state: 'FOUND', rawLrc: 't1 lrclib updated');
      expect(updatedId, t1LrclibId);

      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 4);

      expect(await database.getLyricsTranslation(lyricsId: t1LrclibId, lang: 'es'), isNull);
      expect(await database.getLyricsTranslation(lyricsId: t1LrclibId, lang: 'fr'), isNull);

      expect(await database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'es'), ['t1 ovh es']);
      expect(await database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'de'), ['t1 ovh de']);

      expect(await database.getLyricsTranslation(lyricsId: t2LrclibId, lang: 'es'), ['t2 lrclib es']);
      expect(await database.getLyricsTranslation(lyricsId: t2LrclibId, lang: 'it'), ['t2 lrclib it']);

      await database.saveLyricsTranslation(lyricsId: t1OvhId, lang: 'es', translatedLines: ['t1 ovh es overwritten']);
      expect(await database.getLyricsTranslation(lyricsId: t1OvhId, lang: 'es'), ['t1 ovh es overwritten']);
      expect(database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int, 4);
    });

    test('Translation serialization resilience: Unicode, emojis, empty lists, and corrupt data handling', () async {
      final t = ExtractedTrackData(filePath: '/music/unicode.mp3', title: 'Unicode', artistNames: ['A'], durationMs: 1000, fileSize: 1000, modifiedAt: 1);
      await database.upsertTracks([t]);
      final trackId = (await database.getCatalogSnapshot()).tracks.first.id;
      final lyricsId = await database.saveLyricsEntry(trackId: trackId, source: 'lrclib', state: 'FOUND', rawLrc: 'lyrics');

      final complexLines = [
        'Line 1 with quotes: "hello" and \'world\'',
        'Line 2 with emojis: 🎶 🎤 🎸 🔥',
        'Line 3 with unicode: ¿Cómo estás? Voilà, déjà vu. 日本語テスト, 🎵',
        'Line 4 with special escapes: \\n \\t \\r \\" \' ; -- DROP TABLE',
      ];
      await database.saveLyricsTranslation(lyricsId: lyricsId, lang: 'ja', translatedLines: complexLines);
      final retrieved = await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'ja');
      expect(retrieved, complexLines);

      await database.saveLyricsTranslation(lyricsId: lyricsId, lang: 'empty', translatedLines: []);
      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'empty'), <String>[]);

      database.db.execute("INSERT INTO lyrics_translations (lyrics_id, lang, translated_lines, updated_at) VALUES (?, 'corrupt', 'NOT_JSON_DATA', 12345);", [lyricsId]);
      expect(await database.getLyricsTranslation(lyricsId: lyricsId, lang: 'corrupt'), isNull);
    });

    test('Schema purity: old tables lyrics_cache, lyrics_source_cache and column tracks.lyrics are absent', () async {
      expect(
        () => database.db.select('SELECT lyrics FROM tracks;'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.db.select('SELECT * FROM lyrics_cache;'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.db.select('SELECT * FROM lyrics_source_cache;'),
        throwsA(isA<SqliteException>()),
      );

      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks, isEmpty);
    });

    test('Domain purity: Track and PlaylistEntry do not contain lyrics properties', () {
      const track = Track(
        id: 1,
        filePath: '/path/song.mp3',
        title: 'Title',
        durationMs: 180000,
        fileSize: 1024,
        modifiedAt: 123456789,
      );

      final entry = PlaylistEntry.forQueue(id: 0, track: track);

      final dynamic dynamicTrack = track;
      expect(() => dynamicTrack.lyrics, throwsNoSuchMethodError);

      final dynamic dynamicItem = entry;
      expect(() => dynamicItem.lyrics, throwsNoSuchMethodError);
      expect(() => dynamicItem.extras, throwsNoSuchMethodError);

      expect(entry.track?.id, 1);
      expect(entry.track?.title, 'Title');
    });

    test('upsertTracks auto-detects synced embedded lyrics and ignores empty lyrics', () async {
      Future<Map<String, dynamic>?> findEmbedded(int tId) async {
        final rows = await database.getLyricsForTrack(tId);
        for (final r in rows) {
          if (r['source'] == 'embedded') return r;
        }
        return null;
      }

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

      await database.upsertTracks([syncedTrack, unsyncedTrack, emptyLyricsTrack]);
      final tracks = (await database.getCatalogSnapshot()).tracks;

      final syncedId = tracks.firstWhere((t) => t.filePath == '/music/synced.mp3').id;
      final unsyncedId = tracks.firstWhere((t) => t.filePath == '/music/unsynced.mp3').id;
      final emptyId = tracks.firstWhere((t) => t.filePath == '/music/empty_lyrics.mp3').id;

      final syncedEntry = await findEmbedded(syncedId);
      expect(syncedEntry, isNotNull);
      expect(syncedEntry!['is_synced'], 1);
      expect(syncedEntry['state'], 'FOUND');

      final unsyncedEntry = await findEmbedded(unsyncedId);
      expect(unsyncedEntry, isNotNull);
      expect(unsyncedEntry!['is_synced'], 0);
      expect(unsyncedEntry['state'], 'FOUND');

      final emptyEntry = await findEmbedded(emptyId);
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
        await diskDb.upsertTracks([track]);
        final trackId = (await diskDb.getCatalogSnapshot()).tracks.first.id;

        final lyricsId = await diskDb.saveLyricsEntry(
          trackId: trackId,
          source: 'lrclib',
          state: 'FOUND',
          rawLrc: '[00:01.00] Disk lyric',
          isSynced: true,
        );
        await diskDb.saveLyricsTranslation(
          lyricsId: lyricsId,
          lang: 'es',
          translatedLines: ['[00:01.00] Letra en disco'],
        );

        expect(await diskDb.getLyricsForTrack(trackId), isNotEmpty);
        expect(await diskDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), ['[00:01.00] Letra en disco']);

        await diskDb.close();

        final reopenedDb = AppDatabase();
        await reopenedDb.init(dbFile);

        expect(await reopenedDb.getLyricsForTrack(trackId), isNotEmpty);
        expect(await reopenedDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), ['[00:01.00] Letra en disco']);

        await reopenedDb.deleteTracksAndPurgeOrphans([trackId]);

        expect(await reopenedDb.getLyricsForTrack(trackId), isEmpty);
        expect(await reopenedDb.getLyricsTranslation(lyricsId: lyricsId, lang: 'es'), isNull);

        await reopenedDb.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('High-volume stress test: 50 tracks, multiple sources and translations, bulk cascade', () async {
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

      await database.upsertTracks(tracks);
      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks.length, 50);

      final initialEmbedded = database.db.select("SELECT count(*) AS c FROM lyrics WHERE source = 'embedded';").first['c'] as int;
      expect(initialEmbedded, 25);

      for (final t in snapshot.tracks) {
        final lrclibId = await database.saveLyricsEntry(
          trackId: t.id,
          source: 'lrclib',
          state: 'FOUND',
          rawLrc: '[00:01.00] LRCLIB ${t.id}',
          isSynced: true,
        );
        await database.saveLyricsTranslation(lyricsId: lrclibId, lang: 'es', translatedLines: ['Spanish ${t.id}']);
        await database.saveLyricsTranslation(lyricsId: lrclibId, lang: 'fr', translatedLines: ['French ${t.id}']);
      }

      final totalTrans = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;
      expect(totalTrans, 100);

      final bulkTrackIds = (await database.getCatalogSnapshot())
          .tracks
          .where((t) => t.filePath.startsWith('/music/bulk'))
          .map((t) => t.id)
          .toList();
      await database.deleteTracksAndPurgeOrphans(bulkTrackIds);

      final remainingTracks = (await database.getCatalogSnapshot()).tracks.length;
      expect(remainingTracks, 0);

      final finalLyricsCount = database.db.select('SELECT count(*) AS c FROM lyrics;').first['c'] as int;
      final finalTransCount = database.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;

      expect(finalLyricsCount, 0);
      expect(finalTransCount, 0);
    });
  });
}
