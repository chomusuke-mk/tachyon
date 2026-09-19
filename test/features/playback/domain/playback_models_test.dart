import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  group('Loop Mode Enum', () {
    test('cycles correctly: off -> all -> one -> off', () {
      expect(Loop.off.next(), equals(Loop.all));
      expect(Loop.all.next(), equals(Loop.one));
      expect(Loop.one.next(), equals(Loop.off));
    });

    test('fromIndex returns corresponding enum or off on out-of-bounds', () {
      expect(Loop.fromString(0), equals(Loop.off));
      expect(Loop.fromString(1), equals(Loop.one));
      expect(Loop.fromString(2), equals(Loop.all));
      expect(Loop.fromString(-1), equals(Loop.off));
      expect(Loop.fromString(5), equals(Loop.off));
    });
  });

  group('QueueItem & Playable', () {
    test(
      'QueueItem.fromTrack extracts all track properties and metadata extras',
      () {
        const track = Track(
          id: 10,
          uri: 'file:///music/queen/bohemian_rhapsody.flac',
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          artists: ['Freddie Mercury', 'Brian May'],
          album: 'A Night at the Opera',
          trackNumber: 11,
          discNumber: 1,
          year: 1975,
          durationMs: 354000,
          bitrate: 1411000,
          fileSize: 40000000,
          modifiedAt: 1600000000,
        );

        final queueItem = QueueItem.fromTrack(track);

        expect(queueItem.trackId, equals(10));
        expect(queueItem.uri, equals(track.uri));
        expect(queueItem.title, equals('Bohemian Rhapsody'));
        expect(queueItem.artist, equals('Queen'));
        expect(queueItem.artists, equals(['Freddie Mercury', 'Brian May']));
        expect(queueItem.album, equals('A Night at the Opera'));
        expect(
          queueItem.duration,
          equals(const Duration(milliseconds: 354000)),
        );
        expect(queueItem.extras['year'], equals(1975));
        expect(queueItem.extras['trackNumber'], equals(11));
        expect(queueItem.extras['bitrate'], equals(1411000));
      },
    );

    test('toJson and fromJson serialize accurately', () {
      const item = QueueItem(
        id: 'q-123',
        trackId: 5,
        uri: 'file:///music/song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 180),
        coverPath: '/cache/covers/123.jpg',
      );

      final json = item.toJson();
      final fromJson = QueueItem.fromJson(json);

      expect(fromJson.id, equals(item.id));
      expect(fromJson.uri, equals(item.uri));
      expect(fromJson.duration, equals(item.duration));
      expect(fromJson.coverPath, equals(item.coverPath));
      expect(fromJson, equals(item));
      expect(fromJson.hashCode, equals(item.hashCode));
    });
  });

  group('PlaybackState & MediaPlayerState', () {
    test('initial state conforms to required audio defaults', () {
      const state = PlaybackState.initial();

      expect(state.index, equals(0));
      expect(state.playables, isEmpty);
      expect(state.playing, isFalse);
      expect(state.buffering, isFalse);
      expect(state.completed, isFalse);
      expect(state.position, equals(Duration.zero));
      expect(state.duration, equals(Duration.zero));
      expect(state.volume, equals(100.0));
      expect(state.rate, equals(1.0));
      expect(state.pitch, equals(1.0));
      expect(state.shuffle, isFalse);
      expect(state.loop, equals(Loop.off));
      expect(state.crossfadeDuration, equals(const Duration(seconds: 5)));
      expect(state.exclusiveAudio, isFalse);
      expect(state.replayGain, equals(ReplayGainMode.off));
      expect(state.replayGainPreamp, equals(0.0));
      expect(state.status, equals(PlaybackStatus.idle));
    });

    test('computed properties (currentTrack, hasNext, hasPrevious, progress, remaining)', () {
      const item1 = QueueItem(
        id: '1',
        uri: 'uri1',
        title: 'Track 1',
        artist: 'Artist 1',
        album: 'Album 1',
        duration: Duration(seconds: 200),
      );
      const item2 = QueueItem(
        id: '2',
        uri: 'uri2',
        title: 'Track 2',
        artist: 'Artist 2',
        album: 'Album 2',
        duration: Duration(seconds: 300),
      );

      final state = const PlaybackState().copyWith(
        playables: [item1, item2],
        index: 0,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 200),
        playing: true,
      );

      expect(state.currentTrack, equals(item1));
      expect(state.hasNext, isTrue);
      expect(state.hasPrevious, isTrue); // position > 3s
      expect(state.progress, closeTo(0.25, 0.001));
      expect(state.remaining, equals(const Duration(seconds: 150)));
      expect(state.status, equals(PlaybackStatus.playing));
    });

    test(
      'status transitions through loading, playing, paused, completed, idle',
      () {
        const state1 = PlaybackState(buffering: true);
        expect(state1.status, equals(PlaybackStatus.loading));

        const state2 = PlaybackState(completed: true);
        expect(state2.status, equals(PlaybackStatus.completed));

        const state3 = PlaybackState(playing: true);
        expect(state3.status, equals(PlaybackStatus.playing));

        const state4 = PlaybackState(
          playing: false,
          position: Duration(seconds: 10),
        );
        expect(state4.status, equals(PlaybackStatus.paused));

        const state5 = PlaybackState();
        expect(state5.status, equals(PlaybackStatus.idle));
      },
    );

    test('toJson and fromJson roundtrip correctly', () {
      const state = PlaybackState(
        index: 2,
        playing: true,
        volume: 85.0,
        rate: 1.2,
        pitch: 0.9,
        loop: Loop.all,
        shuffle: true,
        replayGain: ReplayGainMode.album,
        replayGainPreamp: 3.5,
      );

      final json = state.toJson();
      final restored = PlaybackState.fromJson(json);

      expect(restored.index, equals(2));
      expect(restored.playing, isTrue);
      expect(restored.volume, equals(85.0));
      expect(restored.rate, equals(1.2));
      expect(restored.pitch, equals(0.9));
      expect(restored.loop, equals(Loop.all));
      expect(restored.shuffle, isTrue);
      expect(restored.replayGain, equals(ReplayGainMode.album));
      expect(restored.replayGainPreamp, equals(3.5));
    });
  });

  group('CrossfadeConfig & Formulas', () {
    test('clampedDuration enforces [1s, 12s] bounds', () {
      const tooShort = CrossfadeConfig(duration: Duration(milliseconds: 200));
      expect(tooShort.clampedDuration, equals(const Duration(seconds: 1)));

      const tooLong = CrossfadeConfig(duration: Duration(seconds: 20));
      expect(tooLong.clampedDuration, equals(const Duration(seconds: 12)));

      const valid = CrossfadeConfig(duration: Duration(seconds: 7));
      expect(valid.clampedDuration, equals(const Duration(seconds: 7)));
    });

    test(
      'effectiveDuration clamps to half of track duration for short songs',
      () {
        const config = CrossfadeConfig(duration: Duration(seconds: 6));
        // Track is only 4 seconds long -> effective duration must be 2 seconds
        expect(
          config.effectiveDuration(const Duration(seconds: 4)),
          equals(const Duration(seconds: 2)),
        );

        // Track is 300 seconds long -> effective duration remains 6 seconds
        expect(
          config.effectiveDuration(const Duration(seconds: 300)),
          equals(const Duration(seconds: 6)),
        );

        // Disabled crossfade returns Duration.zero
        const disabled = CrossfadeConfig(enabled: false);
        expect(
          disabled.effectiveDuration(const Duration(seconds: 300)),
          equals(Duration.zero),
        );
      },
    );

    test('equalPower curve satisfies constant acoustic energy cos^2(p) + sin^2(p) = 1', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.equalPower);
      const masterVolume = 100.0;

      // Start: p = 0.0 -> out = 100.0, in = 0.0
      expect(
        config.calculateFadeOutVolume(0.0, masterVolume),
        closeTo(100.0, 0.001),
      );
      expect(
        config.calculateFadeInVolume(0.0, masterVolume),
        closeTo(0.0, 0.001),
      );

      // Midpoint: p = 0.5 -> out ~ 70.71, in ~ 70.71
      final midOut = config.calculateFadeOutVolume(0.5, masterVolume);
      final midIn = config.calculateFadeInVolume(0.5, masterVolume);
      expect(midOut, closeTo(100.0 * math.sqrt(0.5), 0.001));
      expect(midIn, closeTo(100.0 * math.sqrt(0.5), 0.001));

      // Constant acoustic energy property
      final energy = (midOut * midOut) + (midIn * midIn);
      expect(energy, closeTo(masterVolume * masterVolume, 0.01));

      // End: p = 1.0 -> out = 0.0, in = 100.0
      expect(
        config.calculateFadeOutVolume(1.0, masterVolume),
        closeTo(0.0, 0.001),
      );
      expect(
        config.calculateFadeInVolume(1.0, masterVolume),
        closeTo(100.0, 0.001),
      );
    });

    test('linear curve produces linear scaling', () {
      const config = CrossfadeConfig(curve: CrossfadeCurve.linear);
      const masterVolume = 100.0;

      expect(
        config.calculateFadeOutVolume(0.5, masterVolume),
        closeTo(50.0, 0.001),
      );
      expect(
        config.calculateFadeInVolume(0.5, masterVolume),
        closeTo(50.0, 0.001),
      );
    });
  });

  group('LyricLine & LRC Parser', () {
    test('parses timestamped LRC strings into LyricLines chronologically', () {
      const lrc = '''
[offset:500]
[00:01.00]First line
[00:05.50]Second line
[00:10.00]Third line
''';

      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(3));
      // First line: 1000ms + 500ms offset = 1500ms
      expect(lines[0].timestampMs, equals(1500));
      expect(lines[0].text, equals('First line'));
      expect(lines[0].isSynced, isTrue);
      // Second line: 5500ms + 500ms offset = 6000ms
      expect(lines[1].timestampMs, equals(6000));
      expect(lines[1].text, equals('Second line'));
    });

    test('parses timestamps with single-digit minutes and >= 100 minutes', () {
      const lrc = '''
[1:05.00]Single digit minute
[02:10.50]Two digit minute
[105:20.50]Over 100 minutes
[120:00.00]Two hours in
''';

      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(4));

      // 1:05.00 -> 65 seconds -> 65,000 ms
      expect(lines[0].text, equals('Single digit minute'));
      expect(lines[0].isSynced, isTrue);
      expect(lines[0].timestampMs, equals(65000));

      // 02:10.50 -> 130.5 seconds -> 130,500 ms
      expect(lines[1].text, equals('Two digit minute'));
      expect(lines[1].isSynced, isTrue);
      expect(lines[1].timestampMs, equals(130500));

      // 105:20.50 -> 105 * 60 + 20.5 = 6320.5s -> 6,320,500 ms
      expect(lines[2].text, equals('Over 100 minutes'));
      expect(lines[2].isSynced, isTrue);
      expect(lines[2].timestampMs, equals(6320500));

      // 120:00.00 -> 120 * 60 = 7200s -> 7,200,000 ms
      expect(lines[3].text, equals('Two hours in'));
      expect(lines[3].isSynced, isTrue);
      expect(lines[3].timestampMs, equals(7200000));
    });

    test('handles multi-timestamp lines (e.g. repeated refrains)', () {
      const lrc = '''
[00:02.00][00:12.00]Chorus line
''';

      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(2));
      expect(lines[0].timestampMs, equals(2000));
      expect(lines[0].text, equals('Chorus line'));
      expect(lines[1].timestampMs, equals(12000));
      expect(lines[1].text, equals('Chorus line'));
    });

    test('handles plain unsynced lyric text', () {
      const text = '''
Line one without timestamps
Line two without timestamps
''';

      final lines = LyricLine.parseLrc(text);
      expect(lines.length, equals(2));
      expect(lines[0].isSynced, isFalse);
      expect(lines[0].text, equals('Line one without timestamps'));
      expect(lines[1].isSynced, isFalse);
    });

    test(
      'SplayTreeMap index provides O(log n) real-time active lyric lookup',
      () {
        const lrc = '''
[00:02.00]Line 0
[00:05.00]Line 1
[00:10.00]Line 2
[00:15.00]Line 3
''';

        final lines = LyricLine.parseLrc(lrc);
        final indexMap = LyricLine.buildIndex(lines);

        // Before first line (1000ms) -> line 0
        expect(LyricLine.findActiveIndex(indexMap, 1000), equals(0));
        // Exactly on line 1 (5000ms) -> line 1
        expect(LyricLine.findActiveIndex(indexMap, 5000), equals(1));
        // Between line 1 and line 2 (7500ms) -> line 1
        expect(LyricLine.findActiveIndex(indexMap, 7500), equals(1));
        // Past last line (20000ms) -> line 3
        expect(LyricLine.findActiveIndex(indexMap, 20000), equals(3));
      },
    );
  });
}
