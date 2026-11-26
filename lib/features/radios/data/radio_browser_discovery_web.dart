/// Web stub for DNS-based Radio Browser server discovery.
///
/// Browsers cannot perform raw DNS/PTR lookups; [RadioBrowserService] handles
/// web discovery fallback via `/json/servers` and [defaultMirrors].
Future<List<String>> discoverRadioBrowserServers({
  String discoveryHost = 'all.api.radio-browser.info',
  Duration timeout = const Duration(seconds: 4),
}) {
  return Future<List<String>>.value(const []);
}
