import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jsonc/jsonc.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/services/lyrics_service.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

class _FakePlaybackControllerForGating extends ChangeNotifier implements PlaybackController {
  QueueItem? _track;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);

  @override
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;

  @override
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  @override
  QueueItem? get currentTrack => _track;

  void setTrack(QueueItem? t) {
    _track = t;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTranslationClientForGating extends Fake implements LyricsTranslationClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AST & i18n Static Verification Suite', () {
    test('100% key parity and non-empty values between en.jsonc and es.jsonc', () async {
      final enFile = File('i18n/en.jsonc');
      final esFile = File('i18n/es.jsonc');

      expect(enFile.existsSync(), isTrue, reason: 'i18n/en.jsonc must exist');
      expect(esFile.existsSync(), isTrue, reason: 'i18n/es.jsonc must exist');

      final enRaw = await enFile.readAsString();
      final esRaw = await esFile.readAsString();

      final enJson = jsoncDecode(enRaw) as Map<String, dynamic>;
      final esJson = jsoncDecode(esRaw) as Map<String, dynamic>;

      final enKeys = enJson.keys.toSet();
      final esKeys = esJson.keys.toSet();

      // Bidirectional symmetry check
      final missingInEs = enKeys.difference(esKeys);
      final missingInEn = esKeys.difference(enKeys);

      expect(
        missingInEs,
        isEmpty,
        reason: 'Keys present in en.jsonc but missing in es.jsonc: $missingInEs',
      );
      expect(
        missingInEn,
        isEmpty,
        reason: 'Keys present in es.jsonc but missing in en.jsonc: $missingInEn',
      );

      // Verify no empty string values
      for (final entry in enJson.entries) {
        expect(
          entry.value.toString().trim(),
          isNotEmpty,
          reason: 'Key "${entry.key}" in en.jsonc has an empty value',
        );
      }

      for (final entry in esJson.entries) {
        expect(
          entry.value.toString().trim(),
          isNotEmpty,
          reason: 'Key "${entry.key}" in es.jsonc has an empty value',
        );
      }
    });

    test('All i18n keys are declared and mapped in AppStringKey.allKeys', () async {
      final enFile = File('i18n/en.jsonc');
      final enRaw = await enFile.readAsString();
      final enJson = jsoncDecode(enRaw) as Map<String, dynamic>;

      final appStringKeys = AppStringKey().allKeys.toSet();
      final enKeys = enJson.keys.toSet();

      final unmappedKeys = enKeys.difference(appStringKeys);
      expect(
        unmappedKeys,
        isEmpty,
        reason: 'Keys present in en.jsonc without getters in AppStringKey: $unmappedKeys',
      );
    });

    test('Zero hardcoded user-facing string literals in playback UI widgets', () {
      final playbackDir = Directory('lib/features/playback/presentation');
      expect(playbackDir.existsSync(), isTrue);

      final hardcodedTextRegex = RegExp(
        r'''(?:Text|SelectableText)\(\s*['"]([A-Za-zÀ-ÿ]{3,}[^'"]*)['"]''',
      );

      final violations = <String>[];

      for (final entity in playbackDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final lines = entity.readAsLinesSync();
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            final trimmed = line.trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

            final match = hardcodedTextRegex.firstMatch(line);
            if (match != null) {
              final literal = match.group(1)?.trim() ?? '';
              if (!literal.startsWith('\$') &&
                  !literal.startsWith('{') &&
                  !literal.contains('package:')) {
                violations.add('${entity.path}:${i + 1} -> "$literal" in line: $trimmed');
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded user-facing strings found in playback UI widgets:\n${violations.join('\n')}',
      );
    });

    test('Audit of legacy hardcoded strings in outer modules enforces baseline ratchet', () {
      final outerDirs = [
        Directory('lib/features/library'),
        Directory('lib/features/playlists'),
        Directory('lib/features/settings'),
        Directory('lib/shared/widgets'),
      ];

      final hardcodedTextRegex = RegExp(
        r'''(?:Text|SelectableText)\(\s*['"]([A-Za-zÀ-ÿ]{3,}[^'"]*)['"]''',
      );

      // Known baseline of legacy unmigrated strings slated for subsequent localization refactor
      final knownLegacyBaseline = <String>{
        'Close',
        'Add to Playlist',
        'Added to \${pl.name}',
        'Cancel',
        'Delete Track',
        'Delete',
        'Add Music Folder',
        'Add',
        'Cover cache cleared successfully',
        'Clear',
        'English',
        'Español',
        'Rename Playlist',
        'Rename',
        'Play',
        'Play Next',
        'Add to Queue',
        'View Album',
        'View Artist',
        'File Info',
      };

      final newViolations = <String>[];

      for (final dir in outerDirs) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final lines = entity.readAsLinesSync();
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              final trimmed = line.trim();
              if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

              final match = hardcodedTextRegex.firstMatch(line);
              if (match != null) {
                final literal = match.group(1)?.trim() ?? '';
                if (!knownLegacyBaseline.contains(literal) &&
                    !literal.startsWith('\$') &&
                    !literal.startsWith('{') &&
                    !literal.contains('package:')) {
                  newViolations.add('${entity.path}:${i + 1} -> "$literal" in line: $trimmed');
                }
              }
            }
          }
        }
      }

      // Ratchet: No NEW hardcoded strings outside the documented legacy baseline
      expect(
        newViolations,
        isEmpty,
        reason: 'New uncatalogued hardcoded strings introduced outside legacy baseline:\n${newViolations.join('\n')}',
      );
    });
  });

  group('Lyrics Visibility Gating Invariant Regression Tests', () {
    test('Zero network calls dispatched when _showLyrics == false', () async {
      int lrclibCallCount = 0;
      int ovhCallCount = 0;

      final mockLrclib = LrclibClient(
        httpClient: MockClient((req) async {
          lrclibCallCount++;
          return http.Response('{}', 404);
        }),
        minPacing: Duration.zero,
      );

      final mockOvh = LyricsOvhClient(
        httpClient: MockClient((req) async {
          ovhCallCount++;
          return http.Response('{}', 404);
        }),
      );

      final db = AppDatabase.inMemory();
      final cooldownManager = LyricsCooldownManager();
      final lyricsService = LyricsService(
        database: db,
        cooldownManager: cooldownManager,
        lrclibClient: mockLrclib,
        lyricsOvhClient: mockOvh,
      );

      final playback = _FakePlaybackControllerForGating();
      final translationClient = _FakeTranslationClientForGating();
      final controller = LyricsController(
        lyricsService: lyricsService,
        playbackController: playback,
        cooldownManager: cooldownManager,
        translationClient: translationClient,
      );

      final track = const QueueItem(
        id: 'track_1',
        uri: '/storage/music/gate_test.mp3',
        title: 'Hidden Gem',
        artist: 'Secret Band',
        album: 'Private Archive',
        duration: Duration(seconds: 180),
      );

      // 1. Play track while LyricsView is NOT visible (_showLyrics == false)
      expect(controller.isLyricsViewVisible, isFalse);
      playback.setTrack(track);

      // Wait a moment to ensure no background listener triggers
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert ZERO network calls dispatched
      expect(
        lrclibCallCount,
        equals(0),
        reason: 'lrclib.net must not be called when LyricsView is hidden',
      );
      expect(
        ovhCallCount,
        equals(0),
        reason: 'lyrics.ovh must not be called when LyricsView is hidden',
      );

      // 2. Open LyricsView (_showLyrics == true)
      controller.setLyricsViewVisible(true);
      expect(controller.isLyricsViewVisible, isTrue);

      // Force load for active track upon mounting
      await controller.ensureLyricsLoaded();

      // Now network calls should have fired
      expect(
        lrclibCallCount,
        greaterThanOrEqualTo(1),
        reason: 'lrclib.net must be queried once LyricsView mounts',
      );

      // 3. Close LyricsView (_showLyrics == false) and switch track
      controller.setLyricsViewVisible(false);
      expect(controller.isLyricsViewVisible, isFalse);

      final previousLrclibCount = lrclibCallCount;
      final previousOvhCount = ovhCallCount;

      final track2 = const QueueItem(
        id: 'track_2',
        uri: '/storage/music/gate_test_2.mp3',
        title: 'Another Track',
        artist: 'Secret Band',
        album: 'Private Archive',
        duration: Duration(seconds: 210),
      );
      playback.setTrack(track2);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Network count must remain unchanged
      expect(lrclibCallCount, equals(previousLrclibCount));
      expect(ovhCallCount, equals(previousOvhCount));

      await db.close();
    });
  });
}
