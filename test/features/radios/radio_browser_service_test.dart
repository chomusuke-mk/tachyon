import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/radios/data/radio_browser_service.dart';
import 'package:tachyon/features/radios/presentation/controllers/radio_controller.dart';

void main() {
  group('RadioBrowserService Unit Tests', () {
    test('getTopStations parses JSON response correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/json/stations/topclick/40');
        expect(request.headers['User-Agent'], contains('Tachyon'));

        final responseData = [
          {
            'stationuuid': 'uuid-1',
            'name': 'Radio Rock',
            'url': 'http://stream.rock.org/live',
            'url_resolved': 'https://stream.rock.org/live.m3u8',
            'homepage': 'https://rock.org',
            'favicon': 'https://rock.org/logo.png',
            'tags': 'classic rock,rock',
            'country': 'United Kingdom',
            'codec': 'AAC',
            'bitrate': 128,
          },
        ];
        return http.Response(jsonEncode(responseData), 200, headers: {
          'content-type': 'application/json; charset=utf-8',
        });
      });

      final service = RadioBrowserService(client: mockClient);
      final stations = await service.getTopStations();

      expect(stations.length, 1);
      final station = stations.first;
      expect(station.stationUuid, 'uuid-1');
      expect(station.name, 'Radio Rock');
      expect(station.streamUrl, 'https://stream.rock.org/live.m3u8');
      expect(station.homepageUrl, 'https://rock.org');
      expect(station.faviconUrl, 'https://rock.org/logo.png');
      expect(station.genre, 'classic rock,rock');
      expect(station.country, 'United Kingdom');
      expect(station.codec, 'AAC');
      expect(station.bitrateKbps, 128);
    });

    test('searchStations formats query parameters properly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/json/stations/search');
        expect(request.url.queryParameters['name'], 'Jazz');
        expect(request.url.queryParameters['country'], 'France');
        expect(request.url.queryParameters['tag'], 'smooth jazz');
        expect(request.url.queryParameters['hidebroken'], 'true');

        final responseData = [
          {
            'stationuuid': 'uuid-jazz-fr',
            'name': 'Jazz Paris',
            'url_resolved': 'https://jazz.fr/stream',
            'country': 'France',
            'tags': 'smooth jazz',
          },
        ];
        return http.Response(jsonEncode(responseData), 200);
      });

      final service = RadioBrowserService(client: mockClient);
      final stations = await service.searchStations(
        name: 'Jazz',
        country: 'France',
        tag: 'smooth jazz',
      );

      expect(stations.length, 1);
      expect(stations.first.name, 'Jazz Paris');
      expect(stations.first.country, 'France');
    });

    test('Mirror failover switches to secondary mirror when first fails', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        if (request.url.host == 'mirror1.test') {
          return http.Response('Internal Server Error', 500);
        }
        if (request.url.host == 'mirror2.test') {
          return http.Response(
            jsonEncode([
              {
                'stationuuid': 'mirror-ok-uuid',
                'name': 'Failover Station',
                'url_resolved': 'https://failover.radio/stream',
              }
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RadioBrowserService(
        client: mockClient,
        mirrors: ['https://mirror1.test', 'https://mirror2.test'],
      );

      final stations = await service.getTopStations();
      expect(stations.length, 1);
      expect(stations.first.name, 'Failover Station');
      expect(requestCount, 2);
    });

    test('getStationsByUuids and getStationByUrl query exact endpoints', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/json/stations/byuuid') {
          expect(request.url.queryParameters['uuids'], 'uuid-a,uuid-b');
          return http.Response(
            jsonEncode([
              {
                'stationuuid': 'uuid-a',
                'name': 'Station A',
                'url_resolved': 'https://a.stream/live',
              },
              {
                'stationuuid': 'uuid-b',
                'name': 'Station B',
                'url_resolved': 'https://b.stream/live',
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/json/stations/byurl') {
          expect(request.url.queryParameters['url'], 'https://a.stream/live');
          return http.Response(
            jsonEncode([
              {
                'stationuuid': 'uuid-a',
                'name': 'Station A',
                'url_resolved': 'https://a.stream/live',
              },
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RadioBrowserService(client: mockClient);
      final stations = await service.getStationsByUuids(['uuid-a', 'uuid-b']);
      expect(stations.length, 2);

      final single = await service.getStationByUrl('https://a.stream/live');
      expect(single, isNotNull);
      expect(single!.stationUuid, 'uuid-a');
    });

    test('validateAndRefreshStations detects stream URL and metadata changes', () async {
      final now = DateTime.now();
      final localStation = RadioStation(
        id: 42,
        stationUuid: 'uuid-orig',
        name: 'Classical FM',
        streamUrl: 'https://old.stream.url/audio.mp3',
        faviconUrl: 'https://old.fav/icon.png',
        genre: 'Classical',
        country: 'Germany',
        isFavorite: true,
        createdAt: now,
      );

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/json/stations/byuuid');
        return http.Response(
          jsonEncode([
            {
              'stationuuid': 'uuid-orig',
              'name': 'Classical FM',
              // New updated stream URL and updated favicon on platform:
              'url_resolved': 'https://new-cdn.stream.url/audio.m3u8',
              'favicon': 'https://new.fav/hd_logo.png',
              'codec': 'AAC',
              'bitrate': 320,
              'tags': 'Classical,Orchestra',
              'country': 'Germany',
            },
          ]),
          200,
        );
      });

      final service = RadioBrowserService(client: mockClient);
      final updatedList = await service.validateAndRefreshStations([localStation]);

      expect(updatedList.length, 1);
      final updated = updatedList.first;
      expect(updated.id, 42); // Local ID preserved
      expect(updated.isFavorite, isTrue); // Local favorite preserved
      expect(updated.createdAt, now); // Local creation time preserved
      expect(updated.streamUrl, 'https://new-cdn.stream.url/audio.m3u8'); // Stream URL updated!
      expect(updated.faviconUrl, 'https://new.fav/hd_logo.png'); // Favicon updated!
      expect(updated.codec, 'AAC');
      expect(updated.bitrateKbps, 320);
    });
  });

  group('RadioController Tab & Debounce Tests', () {
    late AppDatabase db;
    late LibraryStore store;

    setUp(() {
      db = AppDatabase.inMemory();
      store = LibraryStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('currentTabIndex persists and updates correctly', () {
      final service = RadioBrowserService();
      final controller = RadioController(service: service, store: store);

      expect(controller.currentTabIndex, 0);
      controller.setTabIndex(1);
      expect(controller.currentTabIndex, 1);
      controller.dispose();
    });

    test('search debounces and executes latest query only', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('[]', 200);
      });

      final service = RadioBrowserService(client: mockClient);
      final controller = RadioController(service: service, store: store);

      // Rapidly type letters 'r', 'ro', 'roc', 'rock'
      controller.search('r');
      controller.search('ro');
      controller.search('roc');
      controller.search('rock');

      // Before 320ms timer fires, 0 requests should have been made
      expect(requestCount, 0);

      // Wait for debounce timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 380));

      // Exactly 1 network request made for the full word 'rock'!
      expect(requestCount, 1);
      expect(controller.searchQuery, 'rock');

      controller.dispose();
    });
  });
}
