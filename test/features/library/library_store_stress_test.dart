import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';

void main() {
  group('LibraryStore Adversarial Stress Tests (Milestone 2 Challenger)', () {
    test('1. Massive Scale Benchmark: 5,000 tracks hydrate in < 100ms with strict pointer identity', () {
      const artistCount = 250;
      const albumCount = 500;
      const genreCount = 50;
      const trackCount = 5000;

      final artists = List.generate(
        artistCount,
        (i) => RawArtistDto(id: i + 1, name: 'Artist ${i + 1}'),
      );

      final albums = List.generate(
        albumCount,
        (i) => RawAlbumDto(
          id: i + 1,
          name: 'Album ${i + 1}',
          year: 2000 + (i % 25),
          artistId: (i % artistCount) + 1,
        ),
      );

      final genres = List.generate(
        genreCount,
        (i) => RawGenreDto(id: i + 1, name: 'Genre ${i + 1}'),
      );

      final tracks = List.generate(
        trackCount,
        (i) => RawTrackDto(
          id: i + 1,
          filePath: '/music/track_${i + 1}.mp3',
          title: 'Track ${i + 1}',
          trackNumber: (i % 10) + 1,
          discNumber: 1,
          year: 2000 + (i % 25),
          durationMs: 180000 + (i % 60000),
          fileSize: 5000000,
          modifiedAt: 1000000 + i,
          albumId: (i % albumCount) + 1,
        ),
      );

      final trackArtists = <TrackArtistPair>[];
      final trackGenres = <TrackGenrePair>[];

      for (var i = 1; i <= trackCount; i++) {
        // Each track has 1-2 artists
        trackArtists.add(TrackArtistPair(trackId: i, artistId: ((i - 1) % artistCount) + 1));
        if (i % 3 == 0) {
          trackArtists.add(TrackArtistPair(trackId: i, artistId: ((i * 2) % artistCount) + 1));
        }
        // Each track has 1 genre
        trackGenres.add(TrackGenrePair(trackId: i, genreId: ((i - 1) % genreCount) + 1));
      }

      final playlists = [
        const RawPlaylistDto(id: 1, name: 'Liked Songs', createdAt: 100, type: 1),
        const RawPlaylistDto(id: 2, name: 'History', createdAt: 100, type: 2),
        const RawPlaylistDto(id: 3, name: 'Mega Playlist', createdAt: 200, type: 0),
      ];

      final playlistEntries = List.generate(
        1000,
        (i) => RawPlaylistEntryDto(
          id: i + 1,
          playlistId: 3,
          trackId: (i % trackCount) + 1,
          position: i,
          addedAt: 1000 + i,
        ),
      );

      final snapshot = CatalogSnapshot(
        tracks: tracks,
        albums: albums,
        artists: artists,
        genres: genres,
        playlists: playlists,
        playlistEntries: playlistEntries,
        trackArtists: trackArtists,
        trackGenres: trackGenres,
      );

      final stopwatch = Stopwatch()..start();
      final store = LibraryStore.fromSnapshot(snapshot);
      stopwatch.stop();

      // Hydration time must be fast (O(N) single-pass)
      expect(stopwatch.elapsedMilliseconds, lessThan(250),
          reason: 'Hydration of 5,000 tracks took ${stopwatch.elapsedMilliseconds}ms');

      // Instance counts must match snapshot exactly (zero duplication)
      expect(store.tracks.length, equals(trackCount));
      expect(store.albums.length, equals(albumCount));
      expect(store.artists.length, equals(artistCount));
      expect(store.genres.length, equals(genreCount));

      // 100% Pointer identity check across multiple samples
      final track1 = store.getTrackById(1)!;
      final track251 = store.getTrackById(251)!; // (251 - 1) % 250 + 1 = 1 -> Same artist as track 1
      expect(identical(track1.artists.first, track251.artists.first), isTrue);
      expect(identical(track1.artists.first, store.getArtistById(1)), isTrue);

      final track501 = store.getTrackById(501)!; // (501 - 1) % 500 + 1 = 1 -> Same album as track 1
      expect(identical(track1.album, track501.album), isTrue);
      expect(identical(track1.album, store.getAlbumById(1)), isTrue);

      // Verify playlist entries point to the same track instances
      final megaPlaylist = store.getPlaylistById(3)!;
      expect(megaPlaylist.entries.length, equals(1000));
      expect(identical(megaPlaylist.entries[0].track, store.getTrackById(1)), isTrue);
      expect(identical(megaPlaylist.entries[999].track, store.getTrackById(1000)), isTrue);
    });

    test('2. Dangling references & null tolerance: non-existent foreign keys hydrate safely without exceptions', () {
      final snapshot = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/music/dangling.mp3',
            title: 'Dangling Track',
            durationMs: 100000,
            fileSize: 2000000,
            modifiedAt: 100,
            albumId: 99999, // Non-existent album
          ),
          RawTrackDto(
            id: 2,
            filePath: '/music/orphan.mp3',
            title: 'Orphan Track',
            durationMs: 120000,
            fileSize: 2000000,
            modifiedAt: 100,
            albumId: null, // Null album
          ),
        ],
        albums: const [
          RawAlbumDto(
            id: 10,
            name: 'Orphan Album',
            artistId: 88888, // Non-existent artist
          ),
        ],
        artists: const [], // No artists in catalog
        genres: const [], // No genres in catalog
        playlists: const [
          RawPlaylistDto(id: 1, name: 'Liked', createdAt: 100, type: 1),
          RawPlaylistDto(id: 5, name: 'Broken Playlist', createdAt: 100, type: 0),
        ],
        playlistEntries: const [
          RawPlaylistEntryDto(
            id: 1,
            playlistId: 5,
            trackId: 77777, // Non-existent track
            position: 0,
            addedAt: 100,
          ),
        ],
        trackArtists: const [
          TrackArtistPair(trackId: 1, artistId: 66666), // Non-existent artist
          TrackArtistPair(trackId: 99999, artistId: 66666), // Non-existent track and artist
        ],
        trackGenres: const [
          TrackGenrePair(trackId: 1, genreId: 55555), // Non-existent genre
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);

      // Track 1 album must be null
      final track1 = store.getTrackById(1);
      expect(track1, isNotNull);
      expect(track1!.album, isNull);
      expect(track1.artists, isEmpty);
      expect(track1.genres, isEmpty);

      // Album 10 artist must be null
      final album10 = store.getAlbumById(10);
      expect(album10, isNotNull);
      expect(album10!.artist, isNull);
      expect(album10.tracks, isEmpty);

      // Playlist 5 entry track must be null
      final playlist5 = store.getPlaylistById(5);
      expect(playlist5, isNotNull);
      expect(playlist5!.entries.length, equals(1));
      expect(playlist5.entries.first.track, isNull);
    });

    test('3. Graph Mutation Stress: Cascading deletion and playlist reordering boundary cases', () {
      final snapshot = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/music/t1.mp3',
            title: 'Track 1',
            durationMs: 1000,
            fileSize: 1000,
            modifiedAt: 100,
            albumId: 10,
          ),
          RawTrackDto(
            id: 2,
            filePath: '/music/t2.mp3',
            title: 'Track 2',
            durationMs: 1000,
            fileSize: 1000,
            modifiedAt: 100,
            albumId: 10,
          ),
        ],
        albums: const [
          RawAlbumDto(id: 10, name: 'Album 10', artistId: 100),
        ],
        artists: const [
          RawArtistDto(id: 100, name: 'Artist 100'),
        ],
        genres: const [
          RawGenreDto(id: 50, name: 'Genre 50'),
        ],
        playlists: const [
          RawPlaylistDto(id: 1, name: 'Liked', createdAt: 100, type: 1),
          RawPlaylistDto(id: 20, name: 'User Playlist', createdAt: 100, type: 0),
        ],
        playlistEntries: const [
          RawPlaylistEntryDto(id: 1, playlistId: 1, trackId: 1, position: 0, addedAt: 100),
          RawPlaylistEntryDto(id: 2, playlistId: 20, trackId: 1, position: 0, addedAt: 100),
          RawPlaylistEntryDto(id: 3, playlistId: 20, trackId: 2, position: 1, addedAt: 100),
        ],
        trackArtists: const [
          TrackArtistPair(trackId: 1, artistId: 100),
          TrackArtistPair(trackId: 2, artistId: 100),
        ],
        trackGenres: const [
          TrackGenrePair(trackId: 1, genreId: 50),
          TrackGenrePair(trackId: 2, genreId: 50),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);

      // Verify initial state
      expect(store.isTrackLiked(1), isTrue);
      final album = store.getAlbumById(10)!;
      final artist = store.getArtistById(100)!;
      final genre = store.getGenreById(50)!;
      final userPl = store.getPlaylistById(20)!;

      expect(album.tracks.length, equals(2));
      expect(artist.tracks.length, equals(2));
      expect(genre.tracks.length, equals(2));
      expect(userPl.entries.length, equals(2));

      // Reorder playlist out-of-bounds does not crash or corrupt
      store.reorderPlaylistEntries(20, -1, 0); // Invalid fromIndex
      expect(userPl.entries.length, equals(2));
      store.reorderPlaylistEntries(20, 0, 99); // Invalid toIndex
      expect(userPl.entries.length, equals(2));

      // Valid reorder: swap index 0 and 1
      store.reorderPlaylistEntries(20, 0, 1);
      expect(userPl.entries[0].track?.id, equals(2));
      expect(userPl.entries[1].track?.id, equals(1));
      expect(userPl.entries[0].position, equals(0));
      expect(userPl.entries[1].position, equals(1));

      // Remove Track 1 completely from the graph
      store.removeTrack(1);

      // Verify cascading removal
      expect(store.getTrackById(1), isNull);
      expect(store.getTrackByPath('/music/t1.mp3'), isNull);
      expect(store.isTrackLiked(1), isFalse);
      expect(album.tracks.map((t) => t.id).toList(), equals([2]));
      expect(artist.tracks.map((t) => t.id).toList(), equals([2]));
      expect(genre.tracks.map((t) => t.id).toList(), equals([2]));
      expect(userPl.entries.map((e) => e.track?.id).toList(), equals([2]));
      expect(store.likedSongsPlaylist!.entries, isEmpty);

      // Deleting a non-existent track ID does not crash
      store.removeTrack(99999);
    });

    test('4. Query & Search Stress: Regex payloads, special characters, and sorting resilience', () {
      final snapshot = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/music/a.mp3',
            title: 'Song with (Special) [Characters] & * + ? ^ \$',
            durationMs: 30000,
            fileSize: 1000,
            modifiedAt: 100,
            albumId: 1,
          ),
          RawTrackDto(
            id: 2,
            filePath: '/music/b.mp3',
            title: '🔥 Emoji Track 日本語',
            durationMs: 60000,
            fileSize: 2000,
            modifiedAt: 200,
            albumId: 2,
          ),
          RawTrackDto(
            id: 3,
            filePath: '/music/c.mp3',
            title: 'SQL Injection " OR ""=" ; DROP TABLE tracks; --',
            durationMs: 90000,
            fileSize: 3000,
            modifiedAt: 300,
          ),
        ],
        albums: const [
          RawAlbumDto(id: 1, name: 'Album [Regex] *', artistId: 1),
          RawAlbumDto(id: 2, name: '✨ Magical Album', artistId: 2),
        ],
        artists: const [
          RawArtistDto(id: 1, name: 'Artist with (Parentheses)'),
          RawArtistDto(id: 2, name: '🎤 Vocalist 🎧'),
        ],
        genres: const [
          RawGenreDto(id: 1, name: 'Rock / Pop'),
        ],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [
          TrackArtistPair(trackId: 1, artistId: 1),
          TrackArtistPair(trackId: 2, artistId: 2),
        ],
        trackGenres: const [
          TrackGenrePair(trackId: 1, genreId: 1),
        ],
      );

      final store = LibraryStore.fromSnapshot(snapshot);

      // Search with regex characters must NOT throw FormatException
      final regexResults = store.searchTracks('[Characters]');
      expect(regexResults.length, equals(1));
      expect(regexResults.first.id, equals(1));

      final starResults = store.searchTracks('* + ?');
      expect(starResults.length, equals(1));

      // Search with unicode and emojis
      final emojiResults = store.searchTracks('🔥');
      expect(emojiResults.length, equals(1));
      expect(emojiResults.first.id, equals(2));

      final kanjiResults = store.searchTracks('日本語');
      expect(kanjiResults.length, equals(1));

      // Search with SQL injection payload
      final sqlResults = store.searchTracks('DROP TABLE');
      expect(sqlResults.length, equals(1));
      expect(sqlResults.first.id, equals(3));

      // Sort with missing album and artist (Track 3 has null album and no artists)
      final sortedByAlbum = store.sortTracks(store.allTracks, TrackSortOption.album);
      expect(sortedByAlbum.length, equals(3));
      // Missing album name falls back to empty string, so Track 3 comes first in ascending sort
      expect(sortedByAlbum.first.id, equals(3));

      final sortedByArtist = store.sortTracks(store.allTracks, TrackSortOption.artist);
      expect(sortedByArtist.length, equals(3));
      expect(sortedByArtist.first.id, equals(3));
    });

    test('5. Re-hydration on same LibraryStore completely purges old state', () {
      final snapshot1 = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 1,
            filePath: '/music/t1.mp3',
            title: 'Track 1',
            durationMs: 1000,
            fileSize: 1000,
            modifiedAt: 100,
          ),
        ],
        albums: const [],
        artists: const [],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final snapshot2 = CatalogSnapshot(
        tracks: const [
          RawTrackDto(
            id: 2,
            filePath: '/music/t2.mp3',
            title: 'Track 2',
            durationMs: 2000,
            fileSize: 2000,
            modifiedAt: 200,
          ),
        ],
        albums: const [],
        artists: const [],
        genres: const [],
        playlists: const [],
        playlistEntries: const [],
        trackArtists: const [],
        trackGenres: const [],
      );

      final store = LibraryStore.fromSnapshot(snapshot1);
      expect(store.tracks.length, equals(1));
      expect(store.getTrackById(1), isNotNull);

      // Re-hydrate with snapshot2
      store.hydrateFromSnapshot(snapshot2);
      expect(store.tracks.length, equals(1));
      expect(store.getTrackById(1), isNull);
      expect(store.getTrackByPath('/music/t1.mp3'), isNull);
      expect(store.getTrackById(2), isNotNull);
      expect(store.getTrackByPath('/music/t2.mp3'), isNotNull);
    });
  });
}
