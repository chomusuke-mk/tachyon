import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> bundles;
  final Duration? delay;

  MockLocaleRepository(this.bundles, {this.delay});

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    return bundles[localeCode] ?? <String, String>{};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('i18n Catalogs (en.jsonc and es.jsonc)', () {
    test('en.jsonc and es.jsonc exist, decode valid JSONC, and have 100% key parity', () {
      final enFile = File('i18n/en.jsonc');
      final esFile = File('i18n/es.jsonc');

      expect(enFile.existsSync(), isTrue, reason: 'i18n/en.jsonc must exist');
      expect(esFile.existsSync(), isTrue, reason: 'i18n/es.jsonc must exist');

      final enDecoded = jsoncDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
      final esDecoded = jsoncDecode(esFile.readAsStringSync()) as Map<String, dynamic>;

      final enKeys = enDecoded.keys.toSet();
      final esKeys = esDecoded.keys.toSet();

      final missingInEs = enKeys.difference(esKeys);
      final missingInEn = esKeys.difference(enKeys);

      expect(missingInEs, isEmpty, reason: 'Keys in en.jsonc missing from es.jsonc: $missingInEs');
      expect(missingInEn, isEmpty, reason: 'Keys in es.jsonc missing from en.jsonc: $missingInEn');
      expect(enKeys.length, greaterThanOrEqualTo(100));
    });

    test('all keys in en.jsonc match AppStringKey.allKeys registry exactly', () {
      final enFile = File('i18n/en.jsonc');
      final enDecoded = jsoncDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
      final enKeys = enDecoded.keys.toSet();

      final appKey = AppStringKey();
      final registryKeys = appKey.allKeys.toSet();

      final missingInRegistry = enKeys.difference(registryKeys);
      final extraInRegistry = registryKeys.difference(enKeys);

      expect(missingInRegistry, isEmpty, reason: 'Keys in en.jsonc missing from AppStringKey: $missingInRegistry');
      expect(extraInRegistry, isEmpty, reason: 'Keys in AppStringKey not in en.jsonc: $extraInRegistry');
    });
  });

  group('AppStringKey Domain Class', () {
    test('getters return non-empty strings when populated', () async {
      final enFile = File('i18n/en.jsonc');
      final enDecoded = jsoncDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
      final enMap = enDecoded.map((k, v) => MapEntry(k, v.toString()));

      final appKey = AppStringKey();
      await appKey.updateFromJson(enMap, assertAllKeysPresent: true);

      expect(appKey.npTitle, equals('Now Playing'));
      expect(appKey.npPlay, equals('Play'));
      expect(appKey.npPause, equals('Pause'));
      expect(appKey.trTitle, equals('Tracks'));
      expect(appKey.alTitle, equals('Albums'));
      expect(appKey.arTitle, equals('Artists'));
      expect(appKey.plTitle, equals('Playlists'));
      expect(appKey.gTitle, equals('Genres'));
      expect(appKey.fTitle, equals('Folders'));
      expect(appKey.srTitle, equals('Search'));
      expect(appKey.sTitle, equals('Settings'));
      expect(appKey.upTitle, equals('Software Update'));
      expect(appKey.clTitle, equals('Changelog'));
    });

    test('getters return empty string on unpopulated keys without throwing', () {
      final appKey = AppStringKey();
      expect(appKey.npTitle, equals(''));
      expect(appKey.trPlay, equals(''));
      expect(appKey.sCrossfadeDuration, equals(''));
    });

    test('parametric formatters interpolate placeholders correctly', () async {
      final appKey = AppStringKey();
      await appKey.updateFromJson({
        'tr_count': '{count} tracks',
        'pl_delete_confirm': 'Delete {name}?',
        's_scanning_progress': '{progress}% done',
        'up_current_version': 'v{version}',
      });

      expect(appKey.trCountFormatted(42), equals('42 tracks'));
      expect(appKey.plDeleteConfirmFormatted('My Playlist'), equals('Delete My Playlist?'));
      expect(appKey.sScanningProgressFormatted(75), equals('75% done'));
      expect(appKey.upCurrentVersionFormatted('1.2.0'), equals('v1.2.0'));
    });
  });

  group('LocaleController Presentation', () {
    test('initializes with fallback cache and switches locales dynamically', () async {
      final mockRepo = MockLocaleRepository({
        'en': {
          'np_title': 'Now Playing',
          'np_play': 'Play',
          's_title': 'Settings',
        },
        'es': {
          'np_title': 'Reproduciendo Ahora',
          'np_play': 'Reproducir',
          // 's_title' omitted to test fallback
        },
      });

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.flutterLocale, equals(const Locale('en')));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(controller.localeStrings.npPlay, equals('Play'));
      expect(controller.localeStrings.sTitle, equals('Settings'));

      int notifications = 0;
      controller.addListener(() => notifications++);

      // Switch to Spanish
      await controller.setLocale('es');
      expect(controller.currentLocaleCode, equals('es'));
      expect(controller.flutterLocale, equals(const Locale('es')));
      expect(controller.localeStrings.npTitle, equals('Reproduciendo Ahora'));
      expect(controller.localeStrings.npPlay, equals('Reproducir'));
      // Fallback to English for omitted key
      expect(controller.localeStrings.sTitle, equals('Settings'));
      expect(notifications, equals(1));

      // Switch back to English
      await controller.setLocale('en');
      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(notifications, equals(2));
    });

    test('rapid concurrent setLocale switching drops stale async completions via generation counter', () async {
      final mockRepo = MockLocaleRepository({
        'en': {
          'np_title': 'Now Playing',
          'np_play': 'Play',
        },
        'es': {
          'np_title': 'Reproduciendo Ahora',
          'np_play': 'Reproducir',
        },
        'fr': {
          'np_title': 'Lecture En Cours',
          'np_play': 'Lire',
        },
      }, delay: const Duration(milliseconds: 15));

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      // Concurrently fire switch to 'es', then immediately switch to 'en'
      final futEs = controller.setLocale('es');
      final futEn = controller.setLocale('en');

      await Future.wait([futEs, futEn]);

      // Generation counter drops stale 'es' completion so English remains active
      expect(controller.currentLocaleCode, equals('en'));
      expect(controller.localeStrings.npTitle, equals('Now Playing'));
      expect(controller.localeStrings.npPlay, equals('Play'));

      // Concurrently switch to 'es' then 'fr'
      final futEs2 = controller.setLocale('es');
      final futFr = controller.setLocale('fr');

      await Future.wait([futEs2, futFr]);

      expect(controller.currentLocaleCode, equals('fr'));
      expect(controller.localeStrings.npTitle, equals('Lecture En Cours'));
      expect(controller.localeStrings.npPlay, equals('Lire'));
    });
  });
}
