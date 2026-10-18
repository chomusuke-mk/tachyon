import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';

void main() {
  group('AppDatabase Empirical Stress Tests (Milestone 1 Challenger)', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    group('1. Empty list handling', () {
      test('upsertTracks with empty list on empty database does not fail', () async {
        await expectLater(database.upsertTracks([]), completes);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks, isEmpty);
        expect(snapshot.albums, isEmpty);
        expect(snapshot.artists, isEmpty);
        expect(snapshot.genres, isEmpty);
        expect(snapshot.trackArtists, isEmpty);
        expect(snapshot.trackGenres, isEmpty);
        expect(snapshot.playlistEntries, isEmpty);
        expect(snapshot.playlists.length, 2);
      });

      test('upsertTracks with empty list on populated database preserves data', () async {
        final track = ExtractedTrackData(
          filePath: '/music/track.mp3',
          title: 'Track One',
          artistNames: ['Artist 1'],
          albumName: 'Album 1',
          genreNames: ['Rock'],
          durationMs: 120000,
          fileSize: 1000,
          modifiedAt: 100,
        );
        await database.upsertTracks([track]);

        expect((await database.getCatalogSnapshot()).tracks.length, 1);

        await database.upsertTracks([]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        expect(snapshot.artists.length, 1);
        expect(snapshot.albums.length, 1);
        expect(snapshot.genres.length, 1);
      });
    });

    group('2. Large batch handling (250+ tracks)', () {
      test('upserts 250 tracks with shared artists, albums, genres atomically', () async {
        final tracks = <ExtractedTrackData>[];
        for (var i = 1; i <= 250; i++) {
          final albumIndex = (i % 10) + 1;
          final primaryArtist = 'Artist $albumIndex';
          final guestArtist = 'Guest ${((i + 3) % 15) + 11}';
          final genreIndex = (i % 5) + 1;

          tracks.add(ExtractedTrackData(
            filePath: '/music/album_$albumIndex/track_$i.flac',
            title: 'Track Title #$i',
            artistNames: [primaryArtist, guestArtist],
            albumName: 'Album $albumIndex',
            albumArtistName: primaryArtist,
            genreNames: ['Genre $genreIndex'],
            trackNumber: (i % 25) + 1,
            discNumber: 1,
            year: 2020 + (albumIndex % 5),
            durationMs: 150000 + (i * 100),
            bitrate: 320,
            sampleRate: 44100,
            channels: 2,
            codec: 'flac',
            fileSize: 1024 * 1024 * (3 + (i % 5)),
            modifiedAt: 1700000000 + i,
            replayGainTrackGain: -6.5,
            replayGainTrackPeak: 0.98,
            embeddedLyrics: i % 10 == 0 ? '[00:00.00] Lyrics for track $i' : null,
          ));
        }

        final stopwatch = Stopwatch()..start();
        await database.upsertTracks(tracks);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(3000));

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 250);
        expect(snapshot.artists.length, 25);
        expect(snapshot.albums.length, 10);
        expect(snapshot.genres.length, 5);

        expect(snapshot.trackArtists.length, 250 * 2);
        expect(snapshot.trackGenres.length, 250);

        for (final t in snapshot.tracks) {
          expect(t.filePath.startsWith('/music/album_'), isTrue);
          expect(t.title.startsWith('Track Title #'), isTrue);
          expect(t.albumId, isNotNull);
        }
      });
    });

    group('3. Updating existing tracks (upsert semantics)', () {
      test('updates existing track and replaces artist/genre relations without zombie links', () async {
        const filePath = '/music/mutable_song.mp3';

        final initial = ExtractedTrackData(
          filePath: filePath,
          title: 'Initial Title',
          artistNames: ['Artist Alpha', 'Artist Beta'],
          albumName: 'Album Alpha',
          genreNames: ['Rock', 'Metal'],
          trackNumber: 1,
          durationMs: 100000,
          fileSize: 2000000,
          modifiedAt: 1000,
          embeddedLyrics: '[00:01.00] Original lyrics',
        );
        await database.upsertTracks([initial]);

        var snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        final initialTrack = snapshot.tracks.first;
        final initialTrackId = initialTrack.id;
        expect(initialTrack.title, 'Initial Title');
        expect(initialTrack.durationMs, 100000);

        final initialArtistIds = snapshot.trackArtists
            .where((ta) => ta.trackId == initialTrackId)
            .map((ta) => ta.artistId)
            .toList();
        expect(initialArtistIds.length, 2);

        final initialGenreIds = snapshot.trackGenres
            .where((tg) => tg.trackId == initialTrackId)
            .map((tg) => tg.genreId)
            .toList();
        expect(initialGenreIds.length, 2);

        final update = ExtractedTrackData(
          filePath: filePath,
          title: 'Updated Title',
          artistNames: ['Artist Gamma'],
          albumName: 'Album Gamma',
          genreNames: ['Jazz'],
          trackNumber: 5,
          durationMs: 250000,
          fileSize: 4000000,
          modifiedAt: 2000,
          embeddedLyrics: null,
        );
        await database.upsertTracks([update]);

        snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        final updatedTrack = snapshot.tracks.first;
        expect(updatedTrack.id, initialTrackId, reason: 'Track ID must be preserved on update');
        expect(updatedTrack.title, 'Updated Title');
        expect(updatedTrack.durationMs, 250000);
        expect(updatedTrack.trackNumber, 5);

        final albumGamma = snapshot.albums.firstWhere((a) => a.name == 'Album Gamma');
        expect(updatedTrack.albumId, albumGamma.id);

        final artistGamma = snapshot.artists.firstWhere((a) => a.name == 'Artist Gamma');
        final updatedTrackArtists = snapshot.trackArtists
            .where((ta) => ta.trackId == initialTrackId)
            .map((ta) => ta.artistId)
            .toList();
        expect(updatedTrackArtists, [artistGamma.id], reason: 'Old artist links must be cleared');

        final genreJazz = snapshot.genres.firstWhere((g) => g.name == 'Jazz');
        final updatedTrackGenres = snapshot.trackGenres
            .where((tg) => tg.trackId == initialTrackId)
            .map((tg) => tg.genreId)
            .toList();
        expect(updatedTrackGenres, [genreJazz.id], reason: 'Old genre links must be cleared');

        Future<String?> embeddedRaw() async {
          final rows = await database.getLyricsForTrack(initialTrackId);
          for (final r in rows) {
            if (r['source'] == 'embedded') return r['raw_lrc'] as String?;
          }
          return null;
        }
        expect(await embeddedRaw(), isNull, reason: 'Re-scan without embedded tag must remove stale embedded lyrics');

        final updateLyrics = ExtractedTrackData(
          filePath: filePath,
          title: 'Updated Title',
          artistNames: ['Artist Gamma'],
          albumName: 'Album Gamma',
          genreNames: ['Jazz'],
          durationMs: 250000,
          fileSize: 4000000,
          modifiedAt: 3000,
          embeddedLyrics: '[00:05.00] Overwritten lyrics',
        );
        await database.upsertTracks([updateLyrics]);

        expect(await embeddedRaw(), '[00:05.00] Overwritten lyrics');
      });
    });

    group('4. Special characters & adversarial inputs', () {
      test('handles quotes, SQL injection payloads, multiline strings, emojis, and unicode', () async {
        final specialTracks = <ExtractedTrackData>[
          ExtractedTrackData(
            filePath: "/music/inject'; DROP TABLE tracks; --.mp3",
            title: "Robert'); DROP TABLE tracks;--",
            artistNames: ["1' OR '1'='1", "Admin'--"],
            albumName: "Exploit'; DELETE FROM albums;--",
            genreNames: ["Genre' OR 1=1--"],
            durationMs: 120000,
            fileSize: 1000,
            modifiedAt: 1,
          ),
          ExtractedTrackData(
            filePath: '/music/🎵/track_🔥_✨.mp3',
            title: '🔥 Fire & Ice ❄️ (feat. 🎤 Singer)',
            artistNames: ['🎧 DJ Awesome 🎶', '✨ Starlight ⭐'],
            albumName: '🌈 Neon Dreams 🛸',
            genreNames: ['Electronic ⚡', 'Synthwave 🌆'],
            durationMs: 210000,
            fileSize: 2000,
            modifiedAt: 2,
          ),
          ExtractedTrackData(
            filePath: '/music/日本語/夜に駆ける/01. 怪物 (Monster) [2024 Remaster].flac',
            title: '夜に駆ける (Racing into the Night)',
            artistNames: ['YOASOBI (ヨアソビ)', 'Ayase'],
            albumName: 'THE BOOK ２',
            genreNames: ['J-Pop', 'Anime (アニメ)'],
            durationMs: 260000,
            fileSize: 3000,
            modifiedAt: 3,
          ),
          ExtractedTrackData(
            filePath: '/music/russian/Чайковский - Щелкунчик.mp3',
            title: 'Танец Феи Драже',
            artistNames: ['Пётр Ильич Чайковский'],
            albumName: 'Щелкунчик',
            genreNames: ['Классическая'],
            durationMs: 135000,
            fileSize: 4000,
            modifiedAt: 4,
          ),
          ExtractedTrackData(
            filePath: '/music/spanish/Canción de cuna para un niño.mp3',
            title: '¿Dónde está el corazón? ¡Aquí!',
            artistNames: ['Los Ángeles Azules', 'Niño & Niña'],
            albumName: 'Álbum Clásico (Edición Especial)',
            genreNames: ['Cumbia'],
            durationMs: 190000,
            fileSize: 5000,
            modifiedAt: 5,
          ),
        ];

        await expectLater(database.upsertTracks(specialTracks), completes);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 5);

        final sqlInjTrack = snapshot.tracks.firstWhere(
          (t) => t.filePath == "/music/inject'; DROP TABLE tracks; --.mp3",
        );
        expect(sqlInjTrack.title, "Robert'); DROP TABLE tracks;--");

        final sqlInjArtist = snapshot.artists.firstWhere((a) => a.name == "1' OR '1'='1");
        expect(sqlInjArtist, isNotNull);

        final sqlInjAlbum = snapshot.albums.firstWhere(
          (a) => a.name == "Exploit'; DELETE FROM albums;--",
        );
        expect(sqlInjAlbum, isNotNull);

        final jpnTrack = snapshot.tracks.firstWhere(
          (t) => t.filePath.contains('夜に駆ける'),
        );
        expect(jpnTrack.title, '夜に駆ける (Racing into the Night)');

        final emojiTrack = snapshot.tracks.firstWhere(
          (t) => t.filePath == '/music/🎵/track_🔥_✨.mp3',
        );
        expect(emojiTrack.title, '🔥 Fire & Ice ❄️ (feat. 🎤 Singer)');
      });

      test('handles whitespace trimming, empty strings, and missing optional fields', () async {
        final edgeCaseTrack = ExtractedTrackData(
          filePath: '/music/sparse_track.mp3',
          title: 'Sparse Track',
          artistNames: ['', '   ', 'Valid Artist', '   Valid Artist   '],
          albumName: '   ',
          genreNames: ['', '  ', 'Pop', 'Pop'],
          trackNumber: null,
          discNumber: null,
          year: null,
          durationMs: 0,
          bitrate: null,
          sampleRate: null,
          channels: null,
          codec: null,
          fileSize: 0,
          modifiedAt: 0,
          replayGainTrackGain: null,
          replayGainTrackPeak: null,
          embeddedLyrics: null,
        );

        await expectLater(database.upsertTracks([edgeCaseTrack]), completes);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 1);
        final track = snapshot.tracks.first;
        expect(track.albumId, isNull);
        expect(track.trackNumber, isNull);
        expect(track.discNumber, 1);
        expect(track.durationMs, 0);

        expect(snapshot.artists.length, 1);
        expect(snapshot.artists.first.name, 'Valid Artist');

        expect(snapshot.genres.length, 1);
        expect(snapshot.genres.first.name, 'Pop');

        expect(snapshot.trackArtists.length, 1);
        expect(snapshot.trackGenres.length, 1);
      });
    });

    group('5. Case insensitivity in artists, albums, genres', () {
      test('case variations in artist names across batches', () async {
        final track1 = ExtractedTrackData(
          filePath: '/music/t1.mp3',
          title: 'Track 1',
          artistNames: ['Queen'],
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        await database.upsertTracks([track1]);

        final track2 = ExtractedTrackData(
          filePath: '/music/t2.mp3',
          title: 'Track 2',
          artistNames: ['QUEEN'],
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 2,
        );
        await database.upsertTracks([track2]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 2);
        expect(snapshot.artists.length, 1, reason: 'Artist names should be case-insensitive (Queen vs QUEEN)');
      });

      test('case variations in genre names across batches', () async {
        final track1 = ExtractedTrackData(
          filePath: '/music/g1.mp3',
          title: 'Track 1',
          artistNames: ['Artist 1'],
          genreNames: ['Rock'],
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        await database.upsertTracks([track1]);

        final track2 = ExtractedTrackData(
          filePath: '/music/g2.mp3',
          title: 'Track 2',
          artistNames: ['Artist 1'],
          genreNames: ['ROCK'],
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 2,
        );
        await database.upsertTracks([track2]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.genres.length, 1, reason: 'Genre names should be case-insensitive (Rock vs ROCK)');
      });

      test('case variations in album names across batches', () async {
        final track1 = ExtractedTrackData(
          filePath: '/music/a1.mp3',
          title: 'Track 1',
          artistNames: ['Artist 1'],
          albumName: 'Greatest Hits',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        await database.upsertTracks([track1]);

        final track2 = ExtractedTrackData(
          filePath: '/music/a2.mp3',
          title: 'Track 2',
          artistNames: ['Artist 1'],
          albumName: 'GREATEST HITS',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 2,
        );
        await database.upsertTracks([track2]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.albums.length, 1, reason: 'Album names should be case-insensitive (Greatest Hits vs GREATEST HITS)');
      });

      test('tracks in same album with different artists but same albumArtistName resolve to single album', () async {
        final track1 = ExtractedTrackData(
          filePath: '/music/comp1.mp3',
          title: 'Track One',
          artistNames: ['Artist One'],
          albumArtistName: 'Various Artists',
          albumName: 'Summer Hits 2024',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 1,
        );

        final track2 = ExtractedTrackData(
          filePath: '/music/comp2.mp3',
          title: 'Track Two',
          artistNames: ['Artist Two'],
          albumArtistName: 'Various Artists',
          albumName: 'Summer Hits 2024',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 2,
        );

        await database.upsertTracks([track1, track2]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 2);
        expect(snapshot.albums.length, 1, reason: 'Album with same albumArtistName should not be split across tracks');
        expect(snapshot.tracks[0].albumId, snapshot.tracks[1].albumId);
      });

      test('multiple tracks with null artist_id for same album name do not create duplicate album rows across batches', () async {
        final track1 = ExtractedTrackData(
          filePath: '/music/no_artist1.mp3',
          title: 'Track One',
          artistNames: [],
          albumName: 'Orphan Album',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 1,
        );
        await database.upsertTracks([track1]);

        final track2 = ExtractedTrackData(
          filePath: '/music/no_artist2.mp3',
          title: 'Track Two',
          artistNames: [],
          albumName: 'Orphan Album',
          durationMs: 1000,
          fileSize: 1000,
          modifiedAt: 2,
        );
        await database.upsertTracks([track2]);

        final snapshot = await database.getCatalogSnapshot();
        expect(snapshot.tracks.length, 2);
        expect(snapshot.albums.length, 1, reason: 'Multiple tracks with null artist_id for same album should not duplicate album');
        expect(snapshot.albums.first.artistId, isNull);
        expect(snapshot.tracks[0].albumId, snapshot.albums.first.id);
        expect(snapshot.tracks[1].albumId, snapshot.albums.first.id);
      });
    });
  });
}
