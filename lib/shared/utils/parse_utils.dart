import 'dart:typed_data';
import 'crypto_utils.dart';

export 'crypto_utils.dart';

/// Legacy alias for [ParseUtils].
typedef ParserUtils = ParseUtils;

/// Robust string and number parsing utilities.
class ParseUtils {
  static double? parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      final cleaned = val.replaceAll(RegExp(r'[^\d.-]'), '').trim();
      return double.tryParse(cleaned);
    }
    return null;
  }

  static int? parseInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) {
      final cleaned = val.replaceAll(RegExp(r'[^\d-]'), '').trim();
      return int.tryParse(cleaned);
    }
    return null;
  }

  static String? parseString(dynamic val) {
    if (val == null) return null;
    if (val is String) return val.trim();
    return val.toString();
  }

  /// @deprecated Use [CryptoUtils.computeBytesHash] directly.
  static String computeBytesHash(Uint8List bytes) =>
      CryptoUtils.computeBytesHash(bytes);

  /// @deprecated Use [CryptoUtils.computeStringHash] directly.
  static String computeStringHash(String input) =>
      CryptoUtils.computeStringHash(input);
}
