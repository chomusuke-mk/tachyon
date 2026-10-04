import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

class FakeLrclib extends LrclibClient {
  LrclibResponse next = const LrclibNotFound();
  int calls = 0;

  @override
  Future<LrclibResponse> getLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
  }) async {
    calls++;
    return next;
  }
}

class FakeOvh extends LyricsOvhClient {
  LyricsOvhResponse next = const LyricsOvhResponse.notFound();
  int calls = 0;

  @override
  Future<LyricsOvhResponse> getLyrics({required String artist, required String title, Duration? timeout}) async {
    calls++;
    return next;
  }
}

class FakeTranslator extends LyricsTranslationClient {
  int calls = 0;
  TranslationResult Function(
    List<String> lines, {
    String? sourceLanguage,
    required String targetLanguage,
  })? customTranslate;

  @override
  Future<TranslationResult> translate(
    List<String> lines, {
    String? sourceLanguage,
    required String targetLanguage,
  }) async {
    calls++;
    if (customTranslate != null) {
      return customTranslate!(
        lines,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
    }
    return TranslationResult(
      originalLines: lines,
      translatedLines: lines.map((l) => '[$targetLanguage] $l').toList(),
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
    );
  }
}

/// Integration suite for the relational lyrics subsystem:
/// scan → `lyrics` rows → Phase 1 resolve → Phase 2 translate → cascades.
void main() {
  late AppDatabase db;
  late Directory dir;
  late FakeLrclib lrclib;
  late FakeOvh ovh;
  late FakeTranslator translator;
  late LyricsService service;

  setUp(() async {
    db = AppDatabase.inMemory();
    dir = await Directory.systemTemp.createTemp('tachyon_lyrics_');
    lrclib = FakeLrclib();
    ovh = FakeOvh();
    translator = FakeTranslator();
    service = LyricsService(
      database: db,
      lrclibClient: lrclib,
      lyricsOvhClient: ovh,
      cooldownManager: LyricsCooldownManager(),
      translationClient: translator,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  String audioPath([String name = 'song']) => p.join(dir.path, '$name.mp3');

  int scan({String? embedded, String name = 'song', int modifiedAt = 1}) {
    db.upsertTracks([
      ExtractedTrackData(
        filePath: audioPath(name),
        title: 'Title $name',
        artistNames: const ['Artist'],
        durationMs: 180000,
        fileSize: 1,
        modifiedAt: modifiedAt,
        embeddedLyrics: embedded,
      ),
    ]);
    return db.getCatalogSnapshot().tracks.firstWhere((t) => t.filePath == audioPath(name)).id;
  }

  Future<LyricsResult?> resolve(int trackId, {bool allowRemote = true, bool bypassCache = false, void Function(int)? onCountdown}) =>
      service.resolveLyrics(
        trackId: trackId,
        filePath: audioPath(),
        title: 'Title song',
        artist: 'Artist',
        durationMs: 180000,
        allowRemote: allowRemote,
        bypassCache: bypassCache,
        onThresholdCountdown: onCountdown,
      );

  String? rowState(int trackId, LyricsSource s) => db.getLyricsEntry(trackId: trackId, source: s.dbValue)?['state'] as String?;
  int translationCount() => db.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c'] as int;

  group('Scan-time embedded lyrics', () {
    test('rescan replaces changed embedded lyrics (purging translations) and removes them when the tag disappears', () async {
      final id = scan(embedded: '[00:01.00] v1');
      final first = await resolve(id, allowRemote: false);
      expect(first!.source, LyricsSource.embedded);
      db.saveLyricsTranslation(lyricsId: first.lyricsId!, lang: 'es', translatedLines: ['uno']);

      scan(embedded: '[00:01.00] v2', modifiedAt: 2);
      final second = await resolve(id, allowRemote: false);
      expect(second!.rawLrc, '[00:01.00] v2');
      expect(translationCount(), 0, reason: 'changed embedded lyrics must purge translations');

      scan(embedded: null, modifiedAt: 3);
      expect(rowState(id, LyricsSource.embedded), isNull);
      expect(await resolve(id, allowRemote: false), isNull);
    });

    test('embedded lyrics win by priority without touching the network, even on forced re-search', () async {
      final id = scan(embedded: 'plain embedded');
      lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] remote');

      expect((await resolve(id))!.source, LyricsSource.embedded);
      expect((await resolve(id, bypassCache: true))!.source, LyricsSource.embedded);
      expect(lrclib.calls + ovh.calls, 0);
    });
  });

  group('Contiguous .lrc file', () {
    test('file row mirrors the .lrc on disk: create, update, delete', () async {
      final id = scan();
      final lrc = File(p.join(dir.path, 'song.LRC'));

      await lrc.writeAsString('[00:01.00] file v1');
      expect((await resolve(id, allowRemote: false))!.source, LyricsSource.file);

      await lrc.writeAsString('[00:01.00] file v2');
      expect((await resolve(id, allowRemote: false))!.rawLrc, '[00:01.00] file v2');

      await lrc.delete();
      expect(await resolve(id, allowRemote: false), isNull);
      expect(rowState(id, LyricsSource.file), isNull, reason: 'a missing .lrc must not be cached as NOT_FOUND');
    });
  });

  group('Remote sources', () {
    test('visibility gate: allowRemote=false never hits the network', () async {
      final id = scan();
      expect(await resolve(id, allowRemote: false), isNull);
      expect(lrclib.calls + ovh.calls, 0);
    });

    test('lrclib FOUND is persisted and later served from SQLite without network', () async {
      final id = scan();
      lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] synced');

      final first = await resolve(id);
      expect(first!.source, LyricsSource.lrclib);
      expect(first.isSynced, isTrue);

      final second = await resolve(id);
      expect(second!.lyricsId, first.lyricsId);
      expect(lrclib.calls, 1);
    });

    test('NOT_FOUND is persisted per source and skipped afterwards; fallback goes to lyrics.ovh', () async {
      final id = scan();
      ovh.next = const LyricsOvhResponse.success('plain from ovh');

      expect((await resolve(id))!.source, LyricsSource.lyricsOvh);
      expect(rowState(id, LyricsSource.lrclib), 'NOT_FOUND');

      await resolve(id);
      expect(lrclib.calls, 1, reason: 'lrclib must not be re-queried after NOT_FOUND');
    });

    test('transient errors are never persisted, so the next request retries', () async {
      final id = scan();
      lrclib.next = const LrclibError(statusCode: 503, errorMessage: 'down');
      ovh.next = const LyricsOvhResponse.temporaryError(statusCode: 500);

      expect(await resolve(id), isNull);
      expect(rowState(id, LyricsSource.lrclib), isNull);
      expect(rowState(id, LyricsSource.lyricsOvh), isNull);

      await resolve(id);
      expect(lrclib.calls, 2);
    });

    test('HTTP 429 <=10s triggers the countdown; >10s activates cooldown and falls back to lyrics.ovh', () async {
      final id = scan();
      int? countdown;
      lrclib.next = const LrclibRateLimited(retryAfterSeconds: 4);
      expect(await resolve(id, onCountdown: (s) => countdown = s), isNull);
      expect(countdown, 4);
      expect(ovh.calls, 0);

      lrclib.next = const LrclibRateLimited(retryAfterSeconds: 180);
      ovh.next = const LyricsOvhResponse.success('fallback');
      expect((await resolve(id))!.source, LyricsSource.lyricsOvh);
      expect(service.cooldownManager.isCooldownActive, isTrue);
    });
  });

  group('Forced re-search', () {
    test('bypasses NOT_FOUND, keeps translations for unchanged lyrics and purges them when lyrics change', () async {
      final id = scan();
      lrclib.next = const LrclibNotFound();
      await resolve(id);
      expect(rowState(id, LyricsSource.lrclib), 'NOT_FOUND');

      lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] A');
      final found = await resolve(id, bypassCache: true);
      expect(found!.source, LyricsSource.lrclib);
      db.saveLyricsTranslation(lyricsId: found.lyricsId!, lang: 'es', translatedLines: ['A-es']);

      await resolve(id, bypassCache: true);
      expect(translationCount(), 1, reason: 'identical lyrics must keep their translation');

      lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] B');
      await resolve(id, bypassCache: true);
      expect(translationCount(), 0, reason: 'updated lyrics must purge the stale translation');
    });

    test('a failing re-search never destroys previously found lyrics', () async {
      final id = scan();
      lrclib.next = const LrclibSuccess(plainLyrics: 'keep me');
      await resolve(id);

      lrclib.next = const LrclibError(statusCode: 500, errorMessage: 'boom');
      final res = await resolve(id, bypassCache: true);
      expect(res!.rawLrc, 'keep me');

      lrclib.next = const LrclibNotFound();
      expect((await resolve(id, bypassCache: true))!.rawLrc, 'keep me');
      expect(rowState(id, LyricsSource.lrclib), 'FOUND');
    });
  });

  group('Phase 2 translation & cascades', () {
    test('translation is fetched once, then served from SQLite; deleting the track cascades everything', () async {
      final id = scan(embedded: '[00:01.00] Hello');
      final lyrics = await resolve(id, allowRemote: false);

      final t1 = await service.translateLyrics(lyricsId: lyrics!.lyricsId!, targetLang: 'es', rawLines: ['Hello']);
      final t2 = await service.translateLyrics(lyricsId: lyrics.lyricsId!, targetLang: 'es', rawLines: ['Hello']);
      expect(t1, ['[es] Hello']);
      expect(t2, t1);
      expect(translator.calls, 1);

      db.deleteTrack(id);
      expect(db.db.select('SELECT count(*) AS c FROM lyrics;').first['c'], 0);
      expect(translationCount(), 0);
    });

    test('same language detected via API updates DB lang and returns original lines without throwing', () async {
      final id = scan(embedded: '[00:01.00] Canción en español');
      final lyrics = await resolve(id, allowRemote: false);

      translator.customTranslate = (lines, {sourceLanguage, required targetLanguage}) {
        return TranslationResult(
          originalLines: lines,
          translatedLines: lines,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          isSameLanguage: true,
        );
      };

      final res = await service.translateLyrics(
        lyricsId: lyrics!.lyricsId!,
        targetLang: 'es',
        rawLines: ['Canción en español'],
      );

      expect(res, ['Canción en español']);
      expect(db.getLyricsLang(lyrics.lyricsId!), 'es');

      // Next translation request into 'es' should short-circuit and NOT call the API
      final callsBefore = translator.calls;
      final res2 = await service.translateLyrics(
        lyricsId: lyrics.lyricsId!,
        targetLang: 'es',
        rawLines: ['Canción en español'],
      );
      expect(res2, ['Canción en español']);
      expect(translator.calls, callsBefore, reason: 'Must not call translator when lyrics.lang == targetLang');
    });

    test('explicit identical source and target language returns original lines without API call', () async {
      final id = scan(embedded: '[00:01.00] Hello world');
      final lyrics = await resolve(id, allowRemote: false);

      final callsBefore = translator.calls;
      final res = await service.translateLyrics(
        lyricsId: lyrics!.lyricsId!,
        targetLang: 'en',
        sourceLang: 'en',
        rawLines: ['Hello world'],
      );

      expect(res, ['Hello world']);
      expect(translator.calls, callsBefore);
      expect(db.getLyricsLang(lyrics.lyricsId!), 'en');
    });

    test('HTTP 429 rate limit throws LyricsTranslationException', () async {
      final id = scan(embedded: '[00:01.00] Too many requests test');
      final lyrics = await resolve(id, allowRemote: false);

      translator.customTranslate = (lines, {sourceLanguage, required targetLanguage}) {
        return TranslationResult.failure(
          originalLines: lines,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          statusCode: 429,
          errorMessage: 'Rate limit exceeded (Too many requests)',
        );
      };

      expect(
        () => service.translateLyrics(
          lyricsId: lyrics!.lyricsId!,
          targetLang: 'de',
          rawLines: ['Too many requests test'],
        ),
        throwsA(isA<LyricsTranslationException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
    });

    test('LyricsResult survives the RPC map round-trip', () {
      final original = LyricsResult.fromMap(const {
        'lyricsId': 7,
        'source': 'lrclib',
        'state': 'FOUND',
        'rawLrc': '[00:01.00] a\n[00:02.00] b',
        'isSynced': true,
        'lang': 'ja',
      });
      final copy = LyricsResult.fromMap(original.toMap());
      expect(copy.lyricsId, 7);
      expect(copy.source, LyricsSource.lrclib);
      expect(copy.lines.length, 2);
      expect(copy.lang, 'ja');
    });
  });
}
