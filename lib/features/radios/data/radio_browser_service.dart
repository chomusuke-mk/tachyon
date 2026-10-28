import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tachyon/core/playback/domain/radio_station.dart';

/// Direct HTTP client service for querying the open-source community
/// [Radio Browser](https://www.radio-browser.info/) API with automatic mirror failover.
class RadioBrowserService {
  final http.Client _client;
  final List<String> _mirrors;

  static const List<String> defaultMirrors = [
    'https://de1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];

  static const Map<String, String> _headers = {
    'User-Agent': 'Tachyon/0.1.0 (music player)',
    'Accept': 'application/json',
  };

  RadioBrowserService({
    http.Client? client,
    List<String>? mirrors,
  })  : _client = client ?? http.Client(),
        _mirrors = mirrors ?? defaultMirrors;

  /// Fetches top voted / top clicked radio stations globally.
  Future<List<RadioStation>> getTopStations({int limit = 40}) async {
    final jsonList = await _getJsonList('/json/stations/topclick/$limit');
    return _parseStations(jsonList);
  }

  /// Searches radio stations by keyword, country, or musical genre/tag.
  Future<List<RadioStation>> searchStations({
    String? name,
    String? country,
    String? tag,
    int limit = 40,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
    };

    if (name != null && name.trim().isNotEmpty) {
      queryParams['name'] = name.trim();
    }
    if (country != null && country.trim().isNotEmpty && country != 'All') {
      queryParams['country'] = country.trim();
    }
    if (tag != null && tag.trim().isNotEmpty && tag != 'All') {
      queryParams['tag'] = tag.trim().toLowerCase();
    }

    final jsonList = await _getJsonList(
      '/json/stations/search',
      queryParams: queryParams,
    );
    return _parseStations(jsonList);
  }

  /// Fetches the most represented countries by station count.
  Future<List<String>> getPopularCountries({int limit = 30}) async {
    try {
      final jsonList = await _getJsonList(
        '/json/countries',
        queryParams: {
          'order': 'stationcount',
          'reverse': 'true',
          'limit': limit.toString(),
        },
      );
      return jsonList
          .map((item) => (item['name'] as String?)?.trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[RadioBrowserService] getPopularCountries error: $e');
      return const [];
    }
  }

  /// Fetches the most popular genres and tags.
  Future<List<String>> getPopularTags({int limit = 30}) async {
    try {
      final jsonList = await _getJsonList(
        '/json/tags',
        queryParams: {
          'order': 'stationcount',
          'reverse': 'true',
          'limit': limit.toString(),
        },
      );
      return jsonList
          .map((item) => (item['name'] as String?)?.trim() ?? '')
          .where((tag) => tag.isNotEmpty && tag.length > 2)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[RadioBrowserService] getPopularTags error: $e');
      return const [];
    }
  }

  /// Fetches radio stations by their Radio Browser station UUIDs.
  Future<List<RadioStation>> getStationsByUuids(List<String> uuids) async {
    if (uuids.isEmpty) return const [];
    final jsonList = await _getJsonList(
      '/json/stations/byuuid',
      queryParams: {'uuids': uuids.join(',')},
    );
    return _parseStations(jsonList);
  }

  /// Looks up a radio station by its exact stream URL on Radio Browser.
  Future<RadioStation?> getStationByUrl(String url) async {
    final jsonList = await _getJsonList(
      '/json/stations/byurl',
      queryParams: {'url': url},
    );
    final stations = _parseStations(jsonList);
    return stations.isNotEmpty ? stations.first : null;
  }

  /// Validates a list of saved radio stations against Radio Browser platform data.
  /// If stream URLs, favicons, or metadata have changed on the platform, returns
  /// the updated [RadioStation] instances preserving local [id], [isFavorite],
  /// and [createdAt].
  Future<List<RadioStation>> validateAndRefreshStations(
    List<RadioStation> savedStations,
  ) async {
    if (savedStations.isEmpty) return const [];

    final updated = <RadioStation>[];
    final uuidMap = <String, RadioStation>{};
    final nonUuidStations = <RadioStation>[];

    for (final s in savedStations) {
      if (s.stationUuid != null && s.stationUuid!.isNotEmpty) {
        uuidMap[s.stationUuid!] = s;
      } else {
        nonUuidStations.add(s);
      }
    }

    // 1. Process stations with stationUuid in chunks of up to 40
    if (uuidMap.isNotEmpty) {
      final uuids = uuidMap.keys.toList();
      const chunkSize = 40;
      for (int i = 0; i < uuids.length; i += chunkSize) {
        final chunk = uuids.sublist(i, math.min(i + chunkSize, uuids.length));
        try {
          final remoteStations = await getStationsByUuids(chunk);
          for (final remote in remoteStations) {
            final local = uuidMap[remote.stationUuid];
            if (local == null) continue;
            if (_hasStationChanged(local, remote)) {
              updated.add(
                local.copyWith(
                  streamUrl: remote.streamUrl,
                  faviconUrl: remote.faviconUrl ?? local.faviconUrl,
                  homepageUrl: remote.homepageUrl ?? local.homepageUrl,
                  genre: remote.genre ?? local.genre,
                  country: remote.country ?? local.country,
                  codec: remote.codec ?? local.codec,
                  bitrateKbps: remote.bitrateKbps ?? local.bitrateKbps,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('[RadioBrowserService] validateAndRefresh chunk error: $e');
        }
      }
    }

    // 2. For stations without stationUuid, look up by streamUrl to see if we can resolve them
    for (final local in nonUuidStations) {
      try {
        final remote = await getStationByUrl(local.streamUrl);
        if (remote != null) {
          if (local.stationUuid != remote.stationUuid ||
              _hasStationChanged(local, remote)) {
            updated.add(
              local.copyWith(
                stationUuid: remote.stationUuid,
                streamUrl: remote.streamUrl,
                faviconUrl: remote.faviconUrl ?? local.faviconUrl,
                homepageUrl: remote.homepageUrl ?? local.homepageUrl,
                genre: remote.genre ?? local.genre,
                country: remote.country ?? local.country,
                codec: remote.codec ?? local.codec,
                bitrateKbps: remote.bitrateKbps ?? local.bitrateKbps,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[RadioBrowserService] validateAndRefresh URL error: $e');
      }
    }

    return updated;
  }

  bool _hasStationChanged(RadioStation local, RadioStation remote) {
    return local.streamUrl != remote.streamUrl ||
        (remote.faviconUrl != null && local.faviconUrl != remote.faviconUrl) ||
        (remote.codec != null && local.codec != remote.codec) ||
        (remote.bitrateKbps != null && local.bitrateKbps != remote.bitrateKbps);
  }

  Future<List<dynamic>> _getJsonList(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    Object? lastError;

    for (final mirror in _mirrors) {
      try {
        final uri = Uri.parse('$mirror$path').replace(
          queryParameters: queryParams?.isNotEmpty == true ? queryParams : null,
        );

        final response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is List) {
            return decoded;
          }
          return const [];
        }
      } catch (e) {
        lastError = e;
        debugPrint('[RadioBrowserService] Mirror $mirror failed: $e. Trying next mirror...');
      }
    }

    debugPrint('[RadioBrowserService] All mirrors exhausted. Last error: $lastError');
    return const [];
  }

  List<RadioStation> _parseStations(List<dynamic> jsonList) {
    final stations = <RadioStation>[];

    for (final raw in jsonList) {
      if (raw is! Map<String, dynamic>) continue;

      final stationUuid = (raw['stationuuid'] as String?)?.trim();
      final name = (raw['name'] as String?)?.trim();
      final streamUrl = ((raw['url_resolved'] as String?)?.trim().isNotEmpty == true
              ? raw['url_resolved']
              : raw['url']) as String?;

      if (name == null || name.isEmpty || streamUrl == null || streamUrl.isEmpty) {
        continue;
      }

      final favicon = (raw['favicon'] as String?)?.trim();
      final homepage = (raw['homepage'] as String?)?.trim();
      final genre = (raw['tags'] as String?)?.trim();
      final country = (raw['country'] as String?)?.trim();
      final codec = (raw['codec'] as String?)?.trim();
      final bitrate = raw['bitrate'] is num ? (raw['bitrate'] as num).toInt() : null;

      stations.add(
        RadioStation(
          stationUuid: stationUuid != null && stationUuid.isNotEmpty ? stationUuid : null,
          name: name,
          streamUrl: streamUrl,
          homepageUrl: homepage != null && homepage.isNotEmpty ? homepage : null,
          faviconUrl: favicon != null && favicon.isNotEmpty ? favicon : null,
          genre: genre != null && genre.isNotEmpty ? genre : null,
          country: country != null && country.isNotEmpty ? country : null,
          codec: codec != null && codec.isNotEmpty ? codec : null,
          bitrateKbps: bitrate != null && bitrate > 0 ? bitrate : null,
          createdAt: DateTime.now(),
        ),
      );
    }

    return List<RadioStation>.unmodifiable(stations);
  }
}
