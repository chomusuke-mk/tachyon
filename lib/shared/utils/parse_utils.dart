/// Robust string and number parsing utilities.
class ParseUtils {
  /// Parses [val] into a `double`, returning `null` if parsing fails.
  static double? parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      final cleaned = val.replaceAll(RegExp(r'[^\d.-]'), '').trim();
      return double.tryParse(cleaned);
    }
    return null;
  }

  /// Parses [val] into an `int`, returning `null` if parsing fails.
  static int? parseInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) {
      final cleaned = val.replaceAll(RegExp(r'[^\d-]'), '').trim();
      return int.tryParse(cleaned);
    }
    return null;
  }

  /// Converts [val] into a trimmed `String`, returning `null` when [val] is `null`.
  static String? parseString(dynamic val) {
    if (val == null) return null;
    if (val is String) return val.trim();
    return val.toString();
  }
}
