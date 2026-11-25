import 'package:flutter/foundation.dart' show kIsWeb;

/// Utilities for adapting remote image requests on Flutter Web when running
/// under strict `Cross-Origin-Opener-Policy: same-origin` and
/// `Cross-Origin-Embedder-Policy: require-corp` headers (required by
/// `SharedArrayBuffer` / WebAssembly audio workers).
abstract final class CorsImageUtils {
  /// Rewrites third-party image URLs on Web to pass through a CORS- and
  /// CORP-compliant endpoint (`Access-Control-Allow-Origin: *` and
  /// `Cross-Origin-Resource-Policy: cross-origin`), while also upgrading
  /// insecure `http://` image URLs to `https://`.
  ///
  /// On native platforms (`!kIsWeb`), returns [rawUrl] unchanged unless the
  /// caller explicitly sets [forceProxyForTests].
  static String resolveWebCorsImageUrl(
    String rawUrl, {
    int? width,
    int? height,
    bool forceProxyForTests = false,
  }) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!kIsWeb && !forceProxyForTests) return trimmed;

    if (trimmed.startsWith('data:') || trimmed.startsWith('blob:')) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return trimmed;
    }

    final host = uri.host.toLowerCase();
    // Hosts that natively serve Access-Control-Allow-Origin: * and
    // Cross-Origin-Resource-Policy: cross-origin over HTTPS.
    if (scheme == 'https' &&
        (host == 'localhost' ||
            host == '127.0.0.1' ||
            host == 'raw.githubusercontent.com' ||
            host == 'wsrv.nl' ||
            host.endsWith('.wsrv.nl'))) {
      return trimmed;
    }
    if (host == 'localhost' || host == '127.0.0.1') {
      return trimmed;
    }

    final buffer = StringBuffer('https://wsrv.nl/?url=')
      ..write(Uri.encodeComponent(trimmed));
    if (width != null && width > 0) {
      buffer.write('&w=$width');
    }
    if (height != null && height > 0) {
      buffer.write('&h=$height');
    }
    if ((width != null && width > 0) && (height != null && height > 0)) {
      buffer.write('&fit=cover');
    }
    return buffer.toString();
  }
}
