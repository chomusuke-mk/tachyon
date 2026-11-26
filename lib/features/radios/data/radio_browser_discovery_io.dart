import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:tachyon/core/logging/app_logger.dart';

const ScopedLogger _log = ScopedLogger('RadioBrowser');

/// Discovers active Radio Browser API servers using the official DNS method:
/// looking up A/AAAA records for [discoveryHost], resolving PTR hostnames via
/// reverse DNS, and returning a randomized list of `https://` mirror URLs.
Future<List<String>> discoverRadioBrowserServers({
  String discoveryHost = 'all.api.radio-browser.info',
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final addresses = await InternetAddress.lookup(
      discoveryHost,
    ).timeout(timeout);
    if (addresses.isEmpty) return const [];

    final uniqueAddresses = <String, InternetAddress>{};
    for (final addr in addresses) {
      uniqueAddresses.putIfAbsent(addr.address, () => addr);
    }

    final reversedHosts = await Future.wait(
      uniqueAddresses.values.map((addr) async {
        try {
          final reversed = await addr.reverse().timeout(timeout);
          final host = reversed.host
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'\.+$'), '');
          if (host.isEmpty ||
              host == addr.address.toLowerCase() ||
              !host.contains('.') ||
              InternetAddress.tryParse(host) != null) {
            return null;
          }
          return 'https://$host';
        } catch (e) {
          _log.w('Reverse DNS lookup failed for ${addr.address}: $e');
          return null;
        }
      }),
    );

    final discovered = LinkedHashSet<String>.from(
      reversedHosts.whereType<String>(),
    ).toList();
    discovered.shuffle(math.Random());
    return List<String>.unmodifiable(discovered);
  } catch (e) {
    _log.w('DNS discovery for $discoveryHost failed: $e');
    return const [];
  }
}
