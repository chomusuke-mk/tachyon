import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/ffprobe_metadata_parser.dart';

void main() {
  const parser = FfprobeMetadataParser();

  group('FfprobeMetadataParser - Audio Stream Properties', () {
    test('extracts audio properties correctly from standard streams JSON', () {
      final jsonMap = {
        'streams': [
          {
            'index': 0,
            'codec_name': 'flac',
            'codec_type': 'audio',
            'sample_rate': '44100',
            'channels': 2,
            'bits_per_sample': 16,
            'bit_rate': '892000',
            'duration': '243.512000',
          },
          {
            'index': 1,
            'codec_name': 'mjpeg',
            'codec_type': 'video',
            'disposition': {'attached_pic': 1},
          }
        ],
        'format': {
          'filename': '/music/album/track01.flac',
          'duration': '243.512000',
          'size': '27164920',
          'bit_rate': '892400',
        }
      };

      final audioProps = parser.parseAudioStream(
        jsonMap['streams'] as List<dynamic>,
        jsonMap['format'] as Map<String, dynamic>,
      );

      expect(audioProps.codec, equals('flac'));
      expect(audioProps.sampleRate, equals(44100));
      expect(audioProps.channels, equals(2));
      expect(audioProps.bitsPerSample, equals(16));
      expect(audioProps.bitrate, equals(892000));
      expect(audioProps.durationMs, equals(243512));
    });

    test('falls back to format duration and format bitrate if stream lacks them', () {
      final jsonMap = {
        'streams': [
          {
            'codec_name': 'mp3',
            'codec_type': 'audio',
            'sample_rate': '48000',
            'channels': '2',
          }
        ],
        'format': {
          'duration': '180.200',
          'bit_rate': '320000',
        }
      };

      final audioProps = parser.parseAudioStream(
        jsonMap['streams'] as List<dynamic>,
        jsonMap['format'] as Map<String, dynamic>,
      );

      expect(audioProps.codec, equals('mp3'));
      expect(audioProps.sampleRate, equals(48000));
      expect(audioProps.channels, equals(2));
      expect(audioProps.bitrate, equals(320000));
      expect(audioProps.durationMs, equals(180200));
    });
  });

  group('FfprobeMetadataParser - Attached Picture Detection', () {
    test('detects attached picture in video stream disposition', () {
      final jsonMap = {
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'disposition': {'attached_pic': 1},
          }
        ]
      };
      expect(parser.hasAttachedPicture(jsonMap), isTrue);
    });

    test('returns false when no attached picture exists', () {
      final jsonMap = {
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'disposition': {'attached_pic': 0},
          },
          {
            'codec_type': 'audio',
            'codec_name': 'aac',
          }
        ]
      };
      expect(parser.hasAttachedPicture(jsonMap), isFalse);
    });
  });

  group('FfprobeMetadataParser - Tag Extraction & Normalization', () {
    test('parses full tags and normalizes case-insensitively', () {
      final format = {
        'tags': {
          'TITLE': 'Starboy',
          'ARTIST': 'The Weeknd feat. Daft Punk',
          'ALBUM': 'Starboy',
          'ALBUM_ARTIST': 'The Weeknd',
          'DATE': '2016-11-25',
          'TRACK': '1/18',
          'DISC': '1/1',
          'GENRE': 'R&B / Pop',
          'LYRICS': '[00:01.00]I am tryna put you in the worst mood...',
        }
      };

      final tags = parser.parseTags(format, const [], '/music/starboy.mp3');

      expect(tags.title, equals('Starboy'));
      expect(tags.artist, equals('The Weeknd'));
      expect(tags.artists, equals(['The Weeknd', 'Daft Punk']));
      expect(tags.album, equals('Starboy'));
      expect(tags.albumArtist, equals('The Weeknd'));
      expect(tags.trackNumber, equals(1));
      expect(tags.trackTotal, equals(18));
      expect(tags.discNumber, equals(1));
      expect(tags.discTotal, equals(1));
      expect(tags.year, equals(2016));
      expect(tags.genres, equals(['R&B', 'Pop']));
      expect(tags.lyrics, startsWith('[00:01.00]'));
    });

    test('falls back to filename when title is missing', () {
      final tags = parser.parseTags(const {}, const [], '/music/UnknownTrack.flac');
      expect(tags.title, equals('UnknownTrack'));
      expect(tags.album, equals('Unknown Album'));
      expect(tags.artist, equals('Unknown Artist'));
    });
  });

  group('FfprobeMetadataParser - Artist Splitting Edge Cases', () {
    test('splits multiple artists across various delimiters', () {
      expect(parser.splitArtists('Radiohead'), equals(['Radiohead']));
      expect(
        parser.splitArtists('Daft Punk / Pharrell Williams'),
        equals(['Daft Punk', 'Pharrell Williams']),
      );
      expect(
        parser.splitArtists('Queen/David Bowie'),
        equals(['Queen', 'David Bowie']),
      );
      expect(
        parser.splitArtists('Artist A; Artist B; Artist C'),
        equals(['Artist A', 'Artist B', 'Artist C']),
      );
      expect(
        parser.splitArtists('Eminem feat. Rihanna'),
        equals(['Eminem', 'Rihanna']),
      );
      expect(
        parser.splitArtists('Post Malone ft. 21 Savage'),
        equals(['Post Malone', '21 Savage']),
      );
      expect(
        parser.splitArtists('Kendrick Lamar (feat. SZA)'),
        equals(['Kendrick Lamar', 'SZA']),
      );
      expect(
        parser.splitArtists('Artist [feat. Collaborator]'),
        equals(['Artist', 'Collaborator']),
      );
    });

    test('preserves AC/DC without splitting on slash', () {
      expect(parser.splitArtists('AC/DC'), equals(['AC/DC']));
      expect(
        parser.splitArtists('AC/DC, Guns N\' Roses'),
        equals(['AC/DC', 'Guns N\' Roses']),
      );
      expect(
        parser.splitArtists('AC/DC / Aerosmith'),
        equals(['AC/DC', 'Aerosmith']),
      );
    });
  });

  group('FfprobeMetadataParser - Genre Splitting Edge Cases', () {
    test('cleans ID3v1 genre indices and splits multi-genres', () {
      expect(parser.splitGenres('(17) Rock / Metal'), equals(['Rock', 'Metal']));
      expect(parser.splitGenres('Electronic; Ambient'), equals(['Electronic', 'Ambient']));
      expect(parser.splitGenres('Pop, Dance'), equals(['Pop', 'Dance']));
    });
  });

  group('FfprobeMetadataParser - Track & Disc Number Parsing', () {
    test('handles single numbers and slash totals', () {
      expect(parser.parseTrackNumber('3'), equals((3, null)));
      expect(parser.parseTrackNumber('03/12'), equals((3, 12)));
      expect(parser.parseTrackNumber('3 of 12'), equals((3, 12)));
      expect(parser.parseTrackNumber(null), equals((null, null)));

      expect(parser.parseDiscNumber('1'), equals((1, null)));
      expect(parser.parseDiscNumber('2/2'), equals((2, 2)));
      expect(parser.parseDiscNumber(null), equals((1, null)));
    });
  });

  group('FfprobeMetadataParser - Year Extraction', () {
    test('extracts 4-digit years from dates or strings', () {
      expect(parser.parseYear('2023'), equals(2023));
      expect(parser.parseYear('2023-05-12'), equals(2023));
      expect(parser.parseYear('1997/10/24'), equals(1997));
      expect(parser.parseYear('Recorded 1984 in London'), equals(1984));
      expect(parser.parseYear('invalid date'), isNull);
      expect(parser.parseYear(null), isNull);
    });
  });

  group('FfprobeMetadataParser - Full Track Integration & Edge Cases', () {
    test('assembles complete Track entity', () {
      final sampleJson = json.encode({
        'streams': [
          {
            'codec_type': 'audio',
            'codec_name': 'flac',
            'sample_rate': '96000',
            'channels': 2,
            'bits_per_sample': 24,
            'bit_rate': '2800000',
            'duration': '300.5',
          },
          {
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'disposition': {'attached_pic': 1},
          }
        ],
        'format': {
          'duration': '300.5',
          'size': '105000000',
          'tags': {
            'TITLE': 'Comfortably Numb',
            'ARTIST': 'Pink Floyd',
            'ALBUM': 'The Wall',
            'DATE': '1979',
            'TRACK': '6/13',
            'DISC': '2/2',
            'GENRE': 'Progressive Rock',
          }
        }
      });

      final track = parser.parse(
        jsonString: sampleJson,
        filePath: '/music/pink_floyd/comfortably_numb.flac',
        hasCover: true,
      );

      expect(track.uri, equals('/music/pink_floyd/comfortably_numb.flac'));
      expect(track.title, equals('Comfortably Numb'));
      expect(track.artist, equals('Pink Floyd'));
      expect(track.album, equals('The Wall'));
      expect(track.year, equals(1979));
      expect(track.trackNumber, equals(6));
      expect(track.discNumber, equals(2));
      expect(track.durationMs, equals(300500));
      expect(track.codec, equals('flac'));
      expect(track.sampleRate, equals(96000));
      expect(track.channels, equals(2));
      expect(track.hasCover, isTrue);
      expect(track.genres, equals(['Progressive Rock']));
    });

    test('handles corrupted JSON and empty strings without crashing', () {
      final trackCorrupt = parser.parse(
        jsonString: 'INVALID_CORRUPTED_JSON}{[',
        filePath: '/music/Damaged.mp3',
      );

      expect(trackCorrupt.uri, equals('/music/Damaged.mp3'));
      expect(trackCorrupt.title, equals('Damaged'));
      expect(trackCorrupt.artist, equals('Unknown Artist'));
      expect(trackCorrupt.album, equals('Unknown Album'));
      expect(trackCorrupt.durationMs, equals(0));

      final trackEmpty = parser.parse(
        jsonString: '{}',
        filePath: '/music/Empty.mp3',
      );
      expect(trackEmpty.title, equals('Empty'));
      expect(trackEmpty.durationMs, equals(0));
    });
  });
}
