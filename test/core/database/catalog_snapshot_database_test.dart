import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/backend/backend_protocol.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

void main() {
  group('CatalogSnapshot & Database Relational Mapping Empirical Challenger Tests', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    // =========================================================================
    // FOCUS 1: ZERO LYRICS IN CatalogSnapshot
    // =========================================================================
    group('Focus 1: Strict Zero Lyrics in CatalogSnapshot', () {
      test('AppDatabase.getCatalogSnapshot strictly contains ZERO lyrics data across all DTOs', () {
        const secretLyric1 = '[00:01.00] Secret Lyric Line 1\n[00:04.50] Secret Chorus';
        const secretLyric2 = 'Plain text un-synced lyrics without timestamps';
        const secretLyric3 = 'Special symbols lyrics 🎵 🔥 "quotes" and \'apostrophes\'';

        final tracks = [
          ExtractedTrackData(
            filePath: '/music/song_with_lrc1.mp3',
            title: 'Song With LRC 1',
            artistNames: ['Artist One'],
            albumName: 'Album One',
            genreNames: ['Rock'],
            durationMs: 180000,
            fileSize: 5000000,
            modifiedAt: 1000,
            embeddedLyrics: secretLyric1,
          ),
          ExtractedTrackData(
            filePath: '/music/song_with_lrc2.mp3',
            title: 'Song With LRC 2',
            artistNames: ['Artist Two'],
            albumName: 'Album One',
            genreNames: ['Pop'],
            durationMs: 200000,
            fileSize: 6000000,
            modifiedAt: 2000,
            embeddedLyrics: secretLyric2,
          ),
          ExtractedTrackData(
            filePath: '/music/song_with_lrc3.mp3',
            title: 'Song With LRC 3',
            artistNames: ['Artist Three'],
            albumName: 'Album Two',
            genreNames: ['Jazz'],
            durationMs: 220000,
            fileSize: 7000000,
            modifiedAt: 3000,
            embeddedLyrics: secretLyric3,
          ),
          ExtractedTrackData(
            filePath: '/music/song_empty_lrc.mp3',
            title: 'Song Empty LRC',
            artistNames: ['Artist One'],
            albumName: 'Album Two',
            genreNames: ['Rock'],
            durationMs: 150000,
            fileSize: 4000000,
            modifiedAt: 4000,
            embeddedLyrics: '',
          ),
          ExtractedTrackData(
            filePath: '/music/song_null_lrc.mp3',
            title: 'Song Null LRC',
            artistNames: ['Artist Four'],
            albumName: null,
            genreNames: [],
            durationMs: 160000,
            fileSize: 4500000,
            modifiedAt: 5000,
            embeddedLyrics: null,
          ),
        ];

        database.upsertTracks(tracks);

        // 1. Verify embedded lyrics were persisted in the relational `lyrics` table
        final t1Row = database.getCatalogSnapshot().tracks.firstWhere((t) => t.filePath == '/music/song_with_lrc1.mp3');
        final best = database.getBestLyricsForTrack(t1Row.id);
        expect(best, isNotNull, reason: 'Embedded lyrics must be stored in the lyrics table');
        expect(best!['raw_lrc'], secretLyric1);
        expect(best['source'], LyricsSource.embedded.dbValue);

        // Also add a translation bound to the lyrics row
        database.saveLyricsTranslation(
          lyricsId: best['id'] as int,
          lang: 'es',
          translatedLines: ['[00:01.00] Letra secreta traducida'],
        );

        // 2. Fetch CatalogSnapshot and thoroughly verify ZERO lyrics
        final snapshot = database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 5);

        final forbiddenSnippets = [
          'Secret Lyric Line',
          'Secret Chorus',
          'Plain text un-synced',
          'Special symbols lyrics',
          'Letra secreta traducida',
          secretLyric1,
          secretLyric2,
          secretLyric3,
        ];

        for (final trackDto in snapshot.tracks) {
          expect(trackDto.filePath, isNot(contains('Secret')));
          expect(trackDto.title, isNot(contains('Secret')));

          // RawTrackDto has only 16 fields: id, filePath, title, trackNumber,
          // discNumber, year, durationMs, bitrate, sampleRate, channels, codec,
          // fileSize, modifiedAt, replayGainTrackGain, replayGainTrackPeak, albumId.
          for (final snippet in forbiddenSnippets) {
            expect(trackDto.filePath.contains(snippet), isFalse);
            expect(trackDto.title.contains(snippet), isFalse);
            expect(trackDto.codec?.contains(snippet) ?? false, isFalse);
          }
        }

        // Verify across entire snapshot structure that no lyrics snippet leaked into names
        for (final a in snapshot.albums) {
          for (final snippet in forbiddenSnippets) {
            expect(a.name.contains(snippet), isFalse);
          }
        }
        for (final ar in snapshot.artists) {
          for (final snippet in forbiddenSnippets) {
            expect(ar.name.contains(snippet), isFalse);
          }
        }
        for (final g in snapshot.genres) {
          for (final snippet in forbiddenSnippets) {
            expect(g.name.contains(snippet), isFalse);
          }
        }
        for (final p in snapshot.playlists) {
          for (final snippet in forbiddenSnippets) {
            expect(p.name.contains(snippet), isFalse);
          }
        }
      });
    });

    // =========================================================================
    // FOCUS 2: RELATIONAL MAPPING OF trackArtists AND trackGenres
    // =========================================================================
    group('Focus 2: Relational Mapping (trackArtists and trackGenres)', () {
      test('correctly maps single, multiple, and shared artists and genres across tracks', () {
        final tracks = [
          // Track 1: Artists [Alpha, Beta], Genres [Rock]
          ExtractedTrackData(
            filePath: '/music/t1.mp3',
            title: 'Track 1',
            artistNames: ['Artist Alpha', 'Artist Beta'],
            albumName: 'Album One',
            genreNames: ['Rock'],
            durationMs: 100000,
            fileSize: 1000,
            modifiedAt: 1,
          ),
          // Track 2: Artists [Beta, Gamma], Genres [Rock, Metal]
          ExtractedTrackData(
            filePath: '/music/t2.mp3',
            title: 'Track 2',
            artistNames: ['Artist Beta', 'Artist Gamma'],
            albumName: 'Album One',
            genreNames: ['Rock', 'Metal'],
            durationMs: 120000,
            fileSize: 1000,
            modifiedAt: 2,
          ),
          // Track 3: Artists [Gamma], Genres [Pop]
          ExtractedTrackData(
            filePath: '/music/t3.mp3',
            title: 'Track 3',
            artistNames: ['Artist Gamma'],
            albumName: 'Album Two',
            genreNames: ['Pop'],
            durationMs: 130000,
            fileSize: 1000,
            modifiedAt: 3,
          ),
          // Track 4: Artists [Alpha, Beta, Gamma, Delta], Genres [Rock, Metal, Jazz]
          ExtractedTrackData(
            filePath: '/music/t4.mp3',
            title: 'Track 4',
            artistNames: ['Artist Alpha', 'Artist Beta', 'Artist Gamma', 'Artist Delta'],
            albumName: null,
            genreNames: ['Rock', 'Metal', 'Jazz'],
            durationMs: 140000,
            fileSize: 1000,
            modifiedAt: 4,
          ),
          // Track 5: No artists, No genres
          ExtractedTrackData(
            filePath: '/music/t5.mp3',
            title: 'Track 5',
            artistNames: [],
            albumName: null,
            genreNames: [],
            durationMs: 150000,
            fileSize: 1000,
            modifiedAt: 5,
          ),
        ];

        database.upsertTracks(tracks);
        final snapshot = database.getCatalogSnapshot();

        // 1. Verify artists table deduplication
        expect(snapshot.artists.length, 4);
        final artistAlpha = snapshot.artists.firstWhere((a) => a.name == 'Artist Alpha');
        final artistBeta = snapshot.artists.firstWhere((a) => a.name == 'Artist Beta');
        final artistGamma = snapshot.artists.firstWhere((a) => a.name == 'Artist Gamma');
        final artistDelta = snapshot.artists.firstWhere((a) => a.name == 'Artist Delta');

        // 2. Verify genres table deduplication
        expect(snapshot.genres.length, 4); // Rock, Metal, Pop, Jazz
        final genreRock = snapshot.genres.firstWhere((g) => g.name == 'Rock');
        final genreMetal = snapshot.genres.firstWhere((g) => g.name == 'Metal');
        final genrePop = snapshot.genres.firstWhere((g) => g.name == 'Pop');
        final genreJazz = snapshot.genres.firstWhere((g) => g.name == 'Jazz');

        // 3. Verify tracks
        expect(snapshot.tracks.length, 5);
        final t1 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/t1.mp3');
        final t2 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/t2.mp3');
        final t3 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/t3.mp3');
        final t4 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/t4.mp3');
        final t5 = snapshot.tracks.firstWhere((t) => t.filePath == '/music/t5.mp3');

        // 4. Verify trackArtists relational mapping
        // Total pairs: 2 + 2 + 1 + 4 + 0 = 9
        expect(snapshot.trackArtists.length, 9);

        final t1ArtistIds = snapshot.trackArtists.where((p) => p.trackId == t1.id).map((p) => p.artistId).toSet();
        expect(t1ArtistIds, {artistAlpha.id, artistBeta.id});

        final t2ArtistIds = snapshot.trackArtists.where((p) => p.trackId == t2.id).map((p) => p.artistId).toSet();
        expect(t2ArtistIds, {artistBeta.id, artistGamma.id});

        final t3ArtistIds = snapshot.trackArtists.where((p) => p.trackId == t3.id).map((p) => p.artistId).toSet();
        expect(t3ArtistIds, {artistGamma.id});

        final t4ArtistIds = snapshot.trackArtists.where((p) => p.trackId == t4.id).map((p) => p.artistId).toSet();
        expect(t4ArtistIds, {artistAlpha.id, artistBeta.id, artistGamma.id, artistDelta.id});

        final t5ArtistIds = snapshot.trackArtists.where((p) => p.trackId == t5.id).map((p) => p.artistId).toSet();
        expect(t5ArtistIds, isEmpty);

        // 5. Verify trackGenres relational mapping
        // Total pairs: 1 + 2 + 1 + 3 + 0 = 7
        expect(snapshot.trackGenres.length, 7);

        final t1GenreIds = snapshot.trackGenres.where((p) => p.trackId == t1.id).map((p) => p.genreId).toSet();
        expect(t1GenreIds, {genreRock.id});

        final t2GenreIds = snapshot.trackGenres.where((p) => p.trackId == t2.id).map((p) => p.genreId).toSet();
        expect(t2GenreIds, {genreRock.id, genreMetal.id});

        final t3GenreIds = snapshot.trackGenres.where((p) => p.trackId == t3.id).map((p) => p.genreId).toSet();
        expect(t3GenreIds, {genrePop.id});

        final t4GenreIds = snapshot.trackGenres.where((p) => p.trackId == t4.id).map((p) => p.genreId).toSet();
        expect(t4GenreIds, {genreRock.id, genreMetal.id, genreJazz.id});

        final t5GenreIds = snapshot.trackGenres.where((p) => p.trackId == t5.id).map((p) => p.genreId).toSet();
        expect(t5GenreIds, isEmpty);
      });

      test('deduplicates duplicate artist and genre entries in input list without duplicate relational pairs', () {
        final track = ExtractedTrackData(
          filePath: '/music/dedup.mp3',
          title: 'Dedup Track',
          artistNames: ['Daft Punk', 'Daft Punk', '  Daft Punk  '],
          albumName: 'Discovery',
          genreNames: ['Electronic', 'Electronic', '  Electronic  '],
          durationMs: 240000,
          fileSize: 5000000,
          modifiedAt: 1,
        );

        database.upsertTracks([track]);
        final snapshot = database.getCatalogSnapshot();

        expect(snapshot.tracks.length, 1);
        expect(snapshot.artists.length, 1);
        expect(snapshot.artists.first.name, 'Daft Punk');
        expect(snapshot.genres.length, 1);
        expect(snapshot.genres.first.name, 'Electronic');

        // Exactly 1 pair in trackArtists and trackGenres
        expect(snapshot.trackArtists.length, 1);
        expect(snapshot.trackArtists.first.trackId, snapshot.tracks.first.id);
        expect(snapshot.trackArtists.first.artistId, snapshot.artists.first.id);

        expect(snapshot.trackGenres.length, 1);
        expect(snapshot.trackGenres.first.trackId, snapshot.tracks.first.id);
        expect(snapshot.trackGenres.first.genreId, snapshot.genres.first.id);
      });

      test('Referential Integrity Oracle: all relational pairs and foreign keys link to valid existing entities', () {
        final generatedTracks = <ExtractedTrackData>[];
        for (var i = 1; i <= 60; i++) {
          final a1 = (i % 8) + 1;
          final a2 = ((i + 2) % 8) + 1;
          final g1 = (i % 5) + 1;
          final g2 = ((i + 1) % 5) + 1;
          final albumNum = (i % 6) + 1;

          generatedTracks.add(ExtractedTrackData(
            filePath: '/music/track_$i.mp3',
            title: 'Generated Track $i',
            artistNames: ['Artist $a1', 'Artist $a2'],
            albumName: 'Album $albumNum',
            genreNames: ['Genre $g1', 'Genre $g2'],
            durationMs: 180000 + i,
            fileSize: 1024 * 1024,
            modifiedAt: 1700000000 + i,
          ));
        }

        database.upsertTracks(generatedTracks);
        final snapshot = database.getCatalogSnapshot();

        final trackIdSet = snapshot.tracks.map((t) => t.id).toSet();
        final artistIdSet = snapshot.artists.map((a) => a.id).toSet();
        final genreIdSet = snapshot.genres.map((g) => g.id).toSet();
        final albumIdSet = snapshot.albums.map((al) => al.id).toSet();

        expect(trackIdSet.length, 60);

        // 1. Check all trackArtists pairs
        final seenTrackArtistPairs = <String>{};
        for (final pair in snapshot.trackArtists) {
          expect(trackIdSet.contains(pair.trackId), isTrue,
              reason: 'trackArtists trackId ${pair.trackId} must exist in tracks');
          expect(artistIdSet.contains(pair.artistId), isTrue,
              reason: 'trackArtists artistId ${pair.artistId} must exist in artists');

          final key = '${pair.trackId}:${pair.artistId}';
          expect(seenTrackArtistPairs.contains(key), isFalse,
              reason: 'trackArtists must not contain duplicate pairs');
          seenTrackArtistPairs.add(key);
        }

        // 2. Check all trackGenres pairs
        final seenTrackGenrePairs = <String>{};
        for (final pair in snapshot.trackGenres) {
          expect(trackIdSet.contains(pair.trackId), isTrue,
              reason: 'trackGenres trackId ${pair.trackId} must exist in tracks');
          expect(genreIdSet.contains(pair.genreId), isTrue,
              reason: 'trackGenres genreId ${pair.genreId} must exist in genres');

          final key = '${pair.trackId}:${pair.genreId}';
          expect(seenTrackGenrePairs.contains(key), isFalse,
              reason: 'trackGenres must not contain duplicate pairs');
          seenTrackGenrePairs.add(key);
        }

        // 3. Check track album foreign keys
        for (final t in snapshot.tracks) {
          if (t.albumId != null) {
            expect(albumIdSet.contains(t.albumId!), isTrue,
                reason: 'track.albumId ${t.albumId} must exist in albums');
          }
        }

        // 4. Check album artist foreign keys
        for (final al in snapshot.albums) {
          if (al.artistId != null) {
            expect(artistIdSet.contains(al.artistId!), isTrue,
                reason: 'album.artistId ${al.artistId} must exist in artists');
          }
        }
      });

      test('deleting a track cascades deletion of its trackArtists and trackGenres pairs', () {
        final track = ExtractedTrackData(
          filePath: '/music/to_delete.mp3',
          title: 'To Delete',
          artistNames: ['Artist X', 'Artist Y'],
          albumName: 'Album Z',
          genreNames: ['Genre G'],
          durationMs: 100000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        database.upsertTracks([track]);

        var snapshot = database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        final trackId = snapshot.tracks.first.id;
        expect(snapshot.trackArtists.where((ta) => ta.trackId == trackId).length, 2);
        expect(snapshot.trackGenres.where((tg) => tg.trackId == trackId).length, 1);

        // Delete track
        database.deleteTrack(trackId);

        snapshot = database.getCatalogSnapshot();
        expect(snapshot.tracks, isEmpty);
        // Cascade deleted in SQLite
        expect(snapshot.trackArtists.where((ta) => ta.trackId == trackId), isEmpty,
            reason: 'Cascade delete must clear trackArtists');
        expect(snapshot.trackGenres.where((tg) => tg.trackId == trackId), isEmpty,
            reason: 'Cascade delete must clear trackGenres');
      });

      test('deleteTracksAndPurgeOrphans cascades deletion of relational pairs for all deleted tracks', () {
        final t1 = ExtractedTrackData(
          filePath: '/music/folder/t1.mp3',
          title: 'T1',
          artistNames: ['Artist F'],
          genreNames: ['Genre F'],
          durationMs: 100000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        final t2 = ExtractedTrackData(
          filePath: '/music/folder/t2.mp3',
          title: 'T2',
          artistNames: ['Artist F'],
          genreNames: ['Genre F'],
          durationMs: 100000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        final t3 = ExtractedTrackData(
          filePath: '/music/other/t3.mp3',
          title: 'T3',
          artistNames: ['Artist O'],
          genreNames: ['Genre O'],
          durationMs: 100000,
          fileSize: 1000,
          modifiedAt: 1,
        );

        database.upsertTracks([t1, t2, t3]);
        expect(database.getCatalogSnapshot().tracks.length, 3);

        final toDelete = database
            .getCatalogSnapshot()
            .tracks
            .where((t) => t.filePath.startsWith('/music/folder'))
            .map((t) => t.id)
            .toList();
        database.deleteTracksAndPurgeOrphans(toDelete);

        final snapshot = database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        expect(snapshot.tracks.first.filePath, '/music/other/t3.mp3');
        expect(snapshot.trackArtists.length, 1);
        expect(snapshot.trackGenres.length, 1);
      });

      test('BUG REPRODUCTION: multi-batch upsert with case-varying artist names creates duplicate artists in DB', () {
        final trackBatch1 = ExtractedTrackData(
          filePath: '/music/queen1.mp3',
          title: 'Bohemian Rhapsody',
          artistNames: ['Queen'],
          durationMs: 354000,
          fileSize: 5000000,
          modifiedAt: 1,
        );
        database.upsertTracks([trackBatch1]);

        final snapshot1 = database.getCatalogSnapshot();
        expect(snapshot1.artists.length, 1);
        expect(snapshot1.artists.first.name, 'Queen');

        // Batch 2 has the exact same artist with different casing ('QUEEN')
        final trackBatch2 = ExtractedTrackData(
          filePath: '/music/queen2.mp3',
          title: 'Radio Ga Ga',
          artistNames: ['QUEEN'],
          durationMs: 343000,
          fileSize: 5000000,
          modifiedAt: 2,
        );
        database.upsertTracks([trackBatch2]);

        final snapshot2 = database.getCatalogSnapshot();
        // In a properly normalized music catalog, Queen and QUEEN must be the SAME artist entity!
        expect(snapshot2.artists.length, 1, reason: 'Case-varying artist names across batches must resolve to single artist');
      });
    });

    // =========================================================================
    // FOCUS 3: BACKEND PROTOCOL SPECIFICATIONS
    // =========================================================================
    group('Focus 3: Backend Protocol Specification & DTOs', () {
      test('Backend protocol topic and method constants adhere to specifications', () {
        expect(BackendMethods.libraryGetCatalogSnapshot, 'library.getCatalogSnapshot');
        expect(BackendTopics.catalogUpdated, 'catalog.updated');

        const event = BackendEvent(topic: BackendTopics.catalogUpdated);
        expect(event.topic, 'catalog.updated');
        expect(event.payload, isNull);

        const request = BackendRequest(
          requestId: 42,
          method: BackendMethods.libraryGetCatalogSnapshot,
        );
        expect(request.requestId, 42);
        expect(request.method, 'library.getCatalogSnapshot');
      });
    });
  });
}
