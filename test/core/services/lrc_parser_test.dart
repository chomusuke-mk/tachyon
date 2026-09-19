import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/lrc_parser.dart';

void main() {
  group('LrcParser - Standard Timestamp Formats', () {
    test('parses centisecond timestamps [mm:ss.xx]', () {
      const lrc = '[01:23.45]Centisecond line';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.length, equals(1));
      expect(parsed.lines.first.timestampMs, equals(83450)); // (1 * 60 + 23) * 1000 + 450
      expect(parsed.lines.first.text, equals('Centisecond line'));
      expect(parsed.lines.first.isSynced, isTrue);
    });

    test('parses millisecond timestamps [mm:ss.xxx]', () {
      const lrc = '[02:10.456]Millisecond line';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.length, equals(1));
      expect(parsed.lines.first.timestampMs, equals(130456)); // (2 * 60 + 10) * 1000 + 456
      expect(parsed.lines.first.text, equals('Millisecond line'));
    });

    test('parses single digit minutes [m:ss.xx]', () {
      const lrc = '[1:05.20]Single digit minute';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.first.timestampMs, equals(65200));
      expect(parsed.lines.first.text, equals('Single digit minute'));
    });

    test('parses extended minutes >= 100 [mmm:ss.xx]', () {
      const lrc = '''
[105:20.50]Over 100 minutes
[120:00.00]Two hours long
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.length, equals(2));
      expect(parsed.lines[0].timestampMs, equals(6320500)); // 105 * 60 * 1000 + 20500
      expect(parsed.lines[1].timestampMs, equals(7200000)); // 120 * 60 * 1000
    });
  });

  group('LrcParser - Multi-Timestamp Lines', () {
    test('expands single line with multiple timestamp tags into sorted distinct LyricLine instances', () {
      const lrc = '[00:10.00][00:25.50][01:00.00]Chorus line';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.length, equals(3));

      expect(parsed.lines[0].timestampMs, equals(10000));
      expect(parsed.lines[0].text, equals('Chorus line'));

      expect(parsed.lines[1].timestampMs, equals(25500));
      expect(parsed.lines[1].text, equals('Chorus line'));

      expect(parsed.lines[2].timestampMs, equals(60000));
      expect(parsed.lines[2].text, equals('Chorus line'));
    });

    test('correctly re-sorts non-chronological multi-timestamp rows', () {
      const lrc = '[00:40.00][00:15.00]Repeated refrain';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.length, equals(2));
      expect(parsed.lines[0].timestampMs, equals(15000));
      expect(parsed.lines[1].timestampMs, equals(40000));
    });
  });

  group('LrcParser - Offset Tag Handling', () {
    test('applies positive offset [offset:500] to all lines', () {
      const lrc = '''
[offset:500]
[00:01.00]First
[00:05.00]Second
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.offsetMs, equals(500));
      expect(parsed.lines[0].timestampMs, equals(1500)); // 1000 + 500
      expect(parsed.lines[1].timestampMs, equals(5500)); // 5000 + 500
    });

    test('applies negative offset and clamps negative timestamps to 0', () {
      const lrc = '''
[offset:-800]
[00:00.50]Very early start
[00:02.00]Later line
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.offsetMs, equals(-800));
      // 500 - 800 = -300 -> clamped to 0
      expect(parsed.lines[0].timestampMs, equals(0));
      // 2000 - 800 = 1200
      expect(parsed.lines[1].timestampMs, equals(1200));
    });

    test('combines header offset with user offset calibration', () {
      const lrc = '''
[offset:200]
[00:01.00]Line with dual offset
''';
      final parsed = LrcParser.parse(lrc, userOffsetMs: 300);
      expect(parsed.lines[0].timestampMs, equals(1500)); // 1000 + 200 + 300
    });
  });

  group('LrcParser - Metadata Headers', () {
    test('extracts title, artist, album, and creator tags accurately', () {
      const lrc = '''
[ti:Bohemian Rhapsody]
[ar:Queen]
[al:A Night at the Opera]
[by:Tachyon Dev]
[length:05:55]
[00:02.00]Is this the real life?
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.title, equals('Bohemian Rhapsody'));
      expect(parsed.artist, equals('Queen'));
      expect(parsed.album, equals('A Night at the Opera'));
      expect(parsed.author, equals('Tachyon Dev'));
      expect(parsed.length, equals('05:55'));
      expect(parsed.lines.length, equals(1));
    });
  });

  group('LrcParser - Edge Cases, Malformed Lines & Unicode', () {
    test('handles unicode, accents, CJK, and emoji without corruption', () {
      const lrc = '''
[00:01.00]日本語の歌詞 🌸
[00:03.50]Canción con acentos: ¡Olé, corazón! 🎵
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines[0].text, equals('日本語の歌詞 🌸'));
      expect(parsed.lines[1].text, equals('Canción con acentos: ¡Olé, corazón! 🎵'));
    });

    test('ignores malformed brackets and non-timestamp tags', () {
      const lrc = '''
[ti:Test]
[Chorus]
[00:05.00]Valid line
[invalid:tag:extra]
''';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.any((l) => l.text == 'Valid line'), isTrue);
    });

    test('handles UTF-8 BOM prefix cleanly', () {
      const lrc = '\uFEFF[00:02.00]BOM test';
      final parsed = LrcParser.parse(lrc);
      expect(parsed.lines.first.text, equals('BOM test'));
    });

    test('handles plain text unsynchronized lyrics gracefully', () {
      const plain = '''
Verse 1 line 1
Verse 1 line 2
Chorus line
''';
      final parsed = LrcParser.parse(plain);
      expect(parsed.isSynced, isFalse);
      expect(parsed.lines.length, equals(3));
      expect(parsed.lines.first.isSynced, isFalse);
      expect(parsed.activeIndexAt(const Duration(seconds: 10)), equals(0));
    });

    test('handles empty input gracefully', () {
      final parsed = LrcParser.parse('');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.lines, isEmpty);
      expect(parsed.activeIndexAt(const Duration(seconds: 5)), equals(-1));
      expect(parsed.lineAt(const Duration(seconds: 5)), isNull);
    });
  });

  group('LrcParser - SplayTreeMap O(log n) Active Lookup', () {
    test('accurately resolves active line and index in O(log n)', () {
      const lrc = '''
[00:02.00]Intro
[00:05.00]Verse 1
[00:10.00]Chorus
[00:20.00]Outro
''';
      final parsed = LrcParser.parse(lrc);

      // Before first line (1000ms) -> line 0
      expect(parsed.activeIndexAt(const Duration(milliseconds: 1000)), equals(0));
      expect(parsed.lineAt(const Duration(milliseconds: 1000))?.text, equals('Intro'));

      // Exactly on Verse 1 (5000ms)
      expect(parsed.activeIndexAt(const Duration(milliseconds: 5000)), equals(1));
      expect(parsed.lineAt(const Duration(milliseconds: 5000))?.text, equals('Verse 1'));

      // Between Verse 1 and Chorus (7500ms) -> still Verse 1
      expect(parsed.activeIndexAt(const Duration(milliseconds: 7500)), equals(1));
      expect(parsed.lineAt(const Duration(milliseconds: 7500))?.text, equals('Verse 1'));

      // Past Outro (30000ms) -> Outro
      expect(parsed.activeIndexAt(const Duration(milliseconds: 30000)), equals(3));
      expect(parsed.lineAt(const Duration(milliseconds: 30000))?.text, equals('Outro'));
    });

    test('isValidLrc correctly detects LRC format', () {
      expect(LrcParser.isValidLrc('[00:10.00]Hello'), isTrue);
      expect(LrcParser.isValidLrc('Plain text without brackets'), isFalse);
      expect(LrcParser.isValidLrc(null), isFalse);
      expect(LrcParser.isValidLrc(''), isFalse);
    });
  });
}
