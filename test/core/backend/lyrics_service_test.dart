import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lyrics/lrclib_client.dart';
import 'package:tachyon/core/lyrics/lyrics_ovh_client.dart';
import 'package:tachyon/core/lyrics/lyrics_rate_limiter.dart';
import 'package:tachyon/core/lyrics/lyrics_translation_client.dart';
import 'package:tachyon/core/lyrics/domain/lyric_source.dart';
import 'package:tachyon/core/store/library_store.dart';

class FakeLrclib extends LrclibClient {
  LrclibResponse next = const LrclibNotFound();
  int calls = 0;

  @override
  Future<LrclibResponse> getLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
    CancellationToken? cancellationToken,
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
  late LibraryStore store;
  late Directory dir;
  late FakeLrclib lrclib;
  late FakeOvh ovh;
  late FakeTranslator translator;
  late LyricsManager service;

  setUp(() async {
    db = AppDatabase.inMemory();
    store = LibraryStore(db);
    dir = await Directory.systemTemp.createTemp('tachyon_lyrics_');
    lrclib = FakeLrclib();
    ovh = FakeOvh();
    translator = FakeTranslator();
    service = LyricsManager(
      database: db,
      store: store,
      lrclibClient: lrclib,
      ovhClient: ovh,
      cooldownManager: LyricsCooldownManager(),
      translationClient: translator,
      debounceDuration: Duration.zero,
    );
  });

  tearDown(() async {
    service.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  String audioPath([String name = 'song']) => p.join(dir.path, '$name.mp3');

  Future<int> scan({
    String? embedded,
    String name = 'song',
    int modifiedAt = 1,
  }) async {
    await db.upsertTracks([
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
    await store.reloadFromDatabase();
    return store.tracks.firstWhere((t) => t.filePath == audioPath(name)).id!;
  }

  Future<LyricsResult?> resolve(
    int trackId, {
    bool allowRemote = true,
    bool bypassCache = false,
  }) async {
    final res = await service.getLyricsForTrack(
      trackId: trackId,
      filePath: audioPath(),
      title: 'Title song',
      artist: 'Artist',
      durationSeconds: 180,
      enableLocal: true,
      enableLrclib: allowRemote,
      enableLyricsOvh: allowRemote,
      forceRefresh: bypassCache,
    );
    if (res.isEmpty) return null;
    return res;
  }

  Future<String?> rowState(int trackId, LyricsSource s) async {
    final rows = await db.getLyricsForTrack(trackId);
    for (final r in rows) {
      if (r['source'] == s.dbValue) {
        return r['state'] as String?;
      }
    }
    return null;
  }

  int translationCount() =>
      db.db.select('SELECT count(*) AS c FROM lyrics_translations;').first['c']
          as int;

  group('Scan-time embedded lyrics', () {
    test(
      'rescan replaces changed embedded lyrics (purging translations) and removes them when the tag disappears',
      () async {
        final id = await scan(embedded: '[00:01.00] v1');
        final first = await resolve(id, allowRemote: false);
        expect(first!.source, LyricsSource.embedded);
        await db.saveLyricsTranslation(
          lyricsId: first.lyricsId!,
          lang: 'es',
          translatedLines: ['uno'],
        );

        await scan(embedded: '[00:01.00] v2', modifiedAt: 2);
        final second = await resolve(id, allowRemote: false);
        expect(second!.rawLrc, '[00:01.00] v2');
        expect(
          translationCount(),
          0,
          reason: 'changed embedded lyrics must purge translations',
        );

        await scan(embedded: null, modifiedAt: 3);
        expect(await rowState(id, LyricsSource.embedded), isNull);
        expect(await resolve(id, allowRemote: false), isNull);
      },
    );

    test(
      'embedded lyrics win by priority without touching the network, even on forced re-search',
      () async {
        final id = await scan(embedded: 'plain embedded');
        lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] remote');

        expect((await resolve(id))!.source, LyricsSource.embedded);
        expect(
          (await resolve(id, bypassCache: true))!.source,
          LyricsSource.embedded,
        );
        expect(lrclib.calls + ovh.calls, 0);
      },
    );
  });

  group('Contiguous .lrc file', () {
    test('file row mirrors the .lrc on disk: create, update, delete', () async {
      final id = await scan();
      final lrc = File(p.join(dir.path, 'song.LRC'));

      await lrc.writeAsString('[00:01.00] file v1');
      expect((await resolve(id, allowRemote: false))!.source, LyricsSource.file);

      await lrc.writeAsString('[00:01.00] file v2');
      expect(
        (await resolve(id, allowRemote: false))!.rawLrc,
        '[00:01.00] file v2',
      );

      await lrc.delete();
      expect(await resolve(id, allowRemote: false), isNull);
      expect(
        await rowState(id, LyricsSource.file),
        isNull,
        reason: 'a missing .lrc must not be cached as NOT_FOUND',
      );
    });
  });

  group('Remote sources', () {
    test('visibility gate: allowRemote=false never hits the network', () async {
      final id = await scan();
      expect(await resolve(id, allowRemote: false), isNull);
      expect(lrclib.calls + ovh.calls, 0);
    });

    test(
      'lrclib FOUND is persisted and later served from SQLite without network',
      () async {
        final id = await scan();
        lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] synced');

        final first = await resolve(id);
        expect(first!.source, LyricsSource.lrclib);
        expect(first.isSynced, isTrue);

        final second = await resolve(id);
        expect(second!.lyricsId, first.lyricsId);
        expect(lrclib.calls, 1);
      },
    );

    test(
      'NOT_FOUND is persisted per source and skipped afterwards; fallback goes to lyrics.ovh',
      () async {
        final id = await scan();
        ovh.next = const LyricsOvhResponse.success('plain from ovh');

        expect((await resolve(id))!.source, LyricsSource.lyricsOvh);
        expect(await rowState(id, LyricsSource.lrclib), 'NOT_FOUND');

        await resolve(id);
        expect(
          lrclib.calls,
          1,
          reason: 'lrclib must not be re-queried after NOT_FOUND',
        );
      },
    );

    test(
      'transient errors are never persisted, so the next request retries',
      () async {
        final id = await scan();
        lrclib.next = const LrclibError(statusCode: 503, errorMessage: 'down');
        ovh.next = const LyricsOvhResponse.temporaryError(statusCode: 500);

        expect(await resolve(id), isNull);
        expect(await rowState(id, LyricsSource.lrclib), isNull);
        expect(await rowState(id, LyricsSource.lyricsOvh), isNull);

        await resolve(id);
        expect(lrclib.calls, 2);
      },
    );

    test(
      'HTTP 429 <=10s triggers the countdown; >10s activates cooldown and falls back to lyrics.ovh',
      () async {
        final id = await scan();
        lrclib.next = const LrclibRateLimited(retryAfterSeconds: 4);
        final waitingRes = await service.getLyricsForTrack(
          trackId: id,
          filePath: audioPath(),
          title: 'Title song',
          artist: 'Artist',
          durationSeconds: 180,
        );
        expect(waitingRes.isEmpty, isTrue);
        expect(waitingRes.isThresholdWaiting, isTrue);
        expect(waitingRes.retryAfterSeconds, 4);
        expect(service.thresholdCountdownSeconds, 4);
        expect(ovh.calls, 0);
        service.cancelPending();

        lrclib.next = const LrclibRateLimited(retryAfterSeconds: 180);
        ovh.next = const LyricsOvhResponse.success('fallback');
        expect((await resolve(id))!.source, LyricsSource.lyricsOvh);
        expect(service.cooldownManager.isCooldownActive, isTrue);
      },
    );

    test(
      'concurrent getLyricsForTrack calls for the same trackId deduplicate into a single remote fetch',
      () async {
        final id = await scan();
        lrclib.next = const LrclibSuccess(
          syncedLyrics: '[00:01.00] Concurrent',
        );

        final results = await Future.wait([resolve(id), resolve(id)]);

        expect(results[0], isNotNull);
        expect(results[1], isNotNull);
        expect(results[0]!.lyricsId, equals(results[1]!.lyricsId));
        expect(
          lrclib.calls,
          1,
          reason:
              'Must deduplicate in-flight resolutions into a single fetch',
        );
      },
    );
  });

  group('Forced re-search', () {
    test(
      'bypasses NOT_FOUND, keeps translations for unchanged lyrics and purges them when lyrics change',
      () async {
        final id = await scan();
        lrclib.next = const LrclibNotFound();
        await resolve(id);
        expect(await rowState(id, LyricsSource.lrclib), 'NOT_FOUND');

        lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] A');
        final found = await resolve(id, bypassCache: true);
        expect(found!.source, LyricsSource.lrclib);
        await db.saveLyricsTranslation(
          lyricsId: found.lyricsId!,
          lang: 'es',
          translatedLines: ['A-es'],
        );

        await resolve(id, bypassCache: true);
        expect(
          translationCount(),
          1,
          reason: 'identical lyrics must keep their translation',
        );

        lrclib.next = const LrclibSuccess(syncedLyrics: '[00:01.00] B');
        await resolve(id, bypassCache: true);
        expect(
          translationCount(),
          0,
          reason: 'updated lyrics must purge the stale translation',
        );
      },
    );

    test(
      'a failing re-search never destroys previously found lyrics',
      () async {
        final id = await scan();
        lrclib.next = const LrclibSuccess(plainLyrics: 'keep me');
        await resolve(id);

        lrclib.next = const LrclibError(statusCode: 500, errorMessage: 'boom');
        final res = await resolve(id, bypassCache: true);
        expect(res!.rawLrc, 'keep me');

        lrclib.next = const LrclibNotFound();
        expect((await resolve(id, bypassCache: true))!.rawLrc, 'keep me');
        expect(await rowState(id, LyricsSource.lrclib), 'FOUND');
      },
    );
  });

  group('Phase 2 translation & cascades', () {
    test(
      'translation is fetched once, then served from SQLite; deleting the track cascades everything',
      () async {
        final id = await scan(embedded: '[00:01.00] Hello');
        final lyrics = await resolve(id, allowRemote: false);

        final t1 = await service.translateLyrics(
          lyricsId: lyrics!.lyricsId!,
          targetLanguage: 'es',
          lines: ['Hello'],
        );
        final t2 = await service.translateLyrics(
          lyricsId: lyrics.lyricsId!,
          targetLanguage: 'es',
          lines: ['Hello'],
        );
        expect(t1, ['[es] Hello']);
        expect(t2, t1);
        expect(translator.calls, 1);

        await db.deleteTracksAndPurgeOrphans([id]);
        expect(db.db.select('SELECT count(*) AS c FROM lyrics;').first['c'], 0);
        expect(translationCount(), 0);
      },
    );

    test(
      'same language detected via API caches result and returns original lines without throwing',
      () async {
        final id = await scan(embedded: '[00:01.00] Canción en español');
        final lyrics = await resolve(id, allowRemote: false);

        translator.customTranslate =
            (lines, {sourceLanguage, required targetLanguage}) {
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
          targetLanguage: 'es',
          lines: ['Canción en español'],
        );

        expect(res, ['Canción en español']);

        // Next translation request into 'es' should short-circuit from cache and NOT call the API
        final callsBefore = translator.calls;
        final res2 = await service.translateLyrics(
          lyricsId: lyrics.lyricsId!,
          targetLanguage: 'es',
          lines: ['Canción en español'],
        );
        expect(res2, ['Canción en español']);
        expect(
          translator.calls,
          callsBefore,
          reason: 'Must not call translator when cached',
        );
      },
    );

    test(
      'explicit identical source and target language returns original lines without API call',
      () async {
        final id = await scan(embedded: '[00:01.00] Hello world');
        final lyrics = await resolve(id, allowRemote: false);

        final callsBefore = translator.calls;
        final res = await service.translateLyrics(
          lyricsId: lyrics!.lyricsId!,
          targetLanguage: 'en',
          sourceLanguage: 'en',
          lines: ['Hello world'],
        );

        expect(res, ['Hello world']);
        expect(translator.calls, callsBefore);
      },
    );

    test('HTTP 429 rate limit throws LyricsTranslationException', () async {
      final id = await scan(embedded: '[00:01.00] Too many requests test');
      final lyrics = await resolve(id, allowRemote: false);

      translator.customTranslate =
          (lines, {sourceLanguage, required targetLanguage}) {
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
          targetLanguage: 'de',
          lines: ['Too many requests test'],
        ),
        throwsA(
          isA<LyricsTranslationException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );
    });

    test('getLyrics resolves track metadata in O(1) from LibraryStore by trackId', () async {
      final id = await scan(embedded: '[00:01.00] By trackId\n[00:02.00] Second line');
      final res = await service.getLyrics(id);
      expect(res.isNotEmpty, isTrue);
      expect(res.source, LyricsSource.embedded);
      expect(res.lrc.lines.length, 2);
      expect(res.isSynced, isTrue);
    });
  });
}
