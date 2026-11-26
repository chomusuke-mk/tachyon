import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/features/radios/data/radio_browser_discovery.dart';

/// Callback that dynamically discovers candidate Radio Browser base URLs.
typedef RadioBrowserServerDiscoverer = Future<List<String>> Function();

/// Direct HTTP client service for querying the open-source community
/// [Radio Browser](https://www.radio-browser.info/) API with official DNS
/// server discovery and automatic mirror failover.
class RadioBrowserService {
  static const _log = ScopedLogger('RadioBrowser');

  /// Official round-robin DNS hostname used to discover active Radio Browser servers.
  static const String discoveryHost = 'all.api.radio-browser.info';

  final http.Client _client;
  final List<String> _fallbackMirrors;
  final RadioBrowserServerDiscoverer _discoverServers;
  final bool _usingDefaultDiscoverer;
  final bool _enableDynamicDiscovery;

  /// Duration for which dynamically discovered mirror lists are cached.
  final Duration discoveryCacheTtl;

  List<String>? _resolvedMirrors;
  DateTime? _lastDiscoveryAt;
  Future<List<String>>? _inFlightDiscovery;

  /// Fallback Radio Browser API mirror base URLs used if dynamic DNS discovery
  /// fails or returns no results.
  static const List<String> defaultMirrors = [
    'https://all.api.radio-browser.info',
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
  ];

  static const Map<String, String> _headers = {
    'User-Agent': 'Tachyon/0.1.0 (music player)',
    'Accept': 'application/json',
  };

  /// Creates a [RadioBrowserService] using optional [client], fallback [mirrors],
  /// dynamic [discoverServers] callback, [enableDynamicDiscovery] toggle, and
  /// [discoveryCacheTtl].
  RadioBrowserService({
    http.Client? client,
    List<String>? mirrors,
    RadioBrowserServerDiscoverer? discoverServers,
    bool? enableDynamicDiscovery,
    this.discoveryCacheTtl = const Duration(minutes: 30),
  })  : _client = client ?? http.Client(),
        _fallbackMirrors = List<String>.unmodifiable(
          (mirrors ?? defaultMirrors)
              .map(_normalizeBaseUrl)
              .where((m) => m.isNotEmpty),
        ),
        _usingDefaultDiscoverer = discoverServers == null,
        _discoverServers = discoverServers ?? discoverRadioBrowserServers,
        _enableDynamicDiscovery =
            enableDynamicDiscovery ?? (discoverServers != null || mirrors == null);

  static String _normalizeBaseUrl(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  /// Resolves the ordered list of Radio Browser mirror URLs to query.
  ///
  /// When dynamic discovery is enabled, discovers active servers via DNS
  /// (`all.api.radio-browser.info`), caches results for [discoveryCacheTtl],
  /// coalesces concurrent lookups, and appends deduplicated fallback mirrors.
  Future<List<String>> resolveMirrors({bool forceRefresh = false}) async {
    if (!_enableDynamicDiscovery) {
      return List<String>.unmodifiable(_resolvedMirrors ?? _fallbackMirrors);
    }

    if (!forceRefresh &&
        _resolvedMirrors != null &&
        _lastDiscoveryAt != null &&
        DateTime.now().difference(_lastDiscoveryAt!) < discoveryCacheTtl) {
      return List<String>.unmodifiable(_resolvedMirrors!);
    }

    if (!forceRefresh && _inFlightDiscovery != null) {
      return _inFlightDiscovery!;
    }

    final future = _performDiscovery();
    _inFlightDiscovery = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightDiscovery, future)) {
        _inFlightDiscovery = null;
      }
    }
  }

  Future<List<String>> _performDiscovery() async {
    List<String> discovered = const [];
    try {
      discovered = await _discoverServers();
    } catch (e) {
      _log.w('Dynamic server discovery failed: $e');
    }

    if (kIsWeb && discovered.isEmpty && _usingDefaultDiscoverer) {
      discovered = await _discoverViaServersEndpoint();
    }

    final merged = <String>{};
    for (final raw in discovered) {
      final normalized = _normalizeBaseUrl(raw);
      if (normalized.isNotEmpty) {
        merged.add(normalized);
      }
    }
    for (final fallback in _fallbackMirrors) {
      if (fallback.isNotEmpty) {
        merged.add(fallback);
      }
    }

    final result = merged.toList();
    _resolvedMirrors = result;
    _lastDiscoveryAt = DateTime.now();
    return List<String>.unmodifiable(result);
  }

  Future<List<String>> _discoverViaServersEndpoint() async {
    try {
      final uri = Uri.parse('https://$discoveryHost/json/servers');
      final response = await _client
          .get(uri, headers: kIsWeb ? null : _headers)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const [];
      final servers = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['name'] as String?)
            ?.trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\.+$'), '');
        if (name == null || name.isEmpty || !name.contains('.')) continue;
        servers.add(
          name.startsWith('http://') || name.startsWith('https://')
              ? _normalizeBaseUrl(name)
              : 'https://$name',
        );
      }
      final list = servers.toList();
      list.shuffle(math.Random());
      return list;
    } catch (e) {
      _log.w('Web /json/servers discovery failed: $e');
      return const [];
    }
  }

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
      _log.e('getPopularCountries error', error: e);
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
      _log.e('getPopularTags error', error: e);
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
  ///
  /// If stream URLs, favicons, or metadata have changed on the platform, returns
  /// the updated [RadioStation] instances preserving local `id`, `isFavorite`,
  /// and `createdAt`.
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
          _log.w('validateAndRefresh chunk error: $e');
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
        _log.w('validateAndRefresh URL error: $e');
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
    final mirrors = await resolveMirrors();

    for (var i = 0; i < mirrors.length; i++) {
      final mirror = mirrors[i];
      try {
        final uri = Uri.parse('$mirror$path').replace(
          queryParameters: queryParams?.isNotEmpty == true ? queryParams : null,
        );

        final response = await _client
            .get(uri, headers: kIsWeb ? null : _headers)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (i > 0) {
            final updated = List<String>.of(_resolvedMirrors ?? mirrors);
            if (updated.remove(mirror)) {
              updated.insert(0, mirror);
              _resolvedMirrors = updated;
            }
          }
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is List) {
            return decoded;
          }
          return const [];
        }
        lastError = 'HTTP ${response.statusCode}';
        _log.w(
          'Mirror $mirror returned HTTP ${response.statusCode}. Trying next mirror...',
        );
      } catch (e) {
        lastError = e;
        _log.w('Mirror $mirror failed: $e. Trying next mirror...');
      }
    }

    _resolvedMirrors = null;
    _lastDiscoveryAt = null;
    _log.e('All mirrors exhausted', error: lastError);
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
