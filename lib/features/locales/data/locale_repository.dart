import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Repository responsible for loading and parsing JSONC localization files
/// from the Flutter application bundle assets (compatible with both Native and Web/JS).
class LocaleRepository {
  /// Parses a JSON-with-Comments (JSONC) document into a decoded value,
  /// stripping single-line (`//`) and multi-line (`/* ... */`) comments
  /// as well as trailing commas outside string literals.
  static dynamic decodeJsonc(String input) {
    final sb = StringBuffer();
    final len = input.length;
    bool inString = false;
    bool escaped = false;
    int i = 0;

    while (i < len) {
      final ch = input.codeUnitAt(i);
      if (inString) {
        sb.writeCharCode(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == 0x5C) {
          // '\'
          escaped = true;
        } else if (ch == 0x22) {
          // '"'
          inString = false;
        }
        i++;
      } else {
        if (ch == 0x22) {
          // '"'
          inString = true;
          sb.writeCharCode(ch);
          i++;
        } else if (ch == 0x2F && i + 1 < len) {
          final next = input.codeUnitAt(i + 1);
          if (next == 0x2F) {
            // '//' single-line comment
            i += 2;
            while (i < len &&
                input.codeUnitAt(i) != 0x0A &&
                input.codeUnitAt(i) != 0x0D) {
              i++;
            }
          } else if (next == 0x2A) {
            // '/*' multi-line comment
            i += 2;
            while (i + 1 < len &&
                !(input.codeUnitAt(i) == 0x2A &&
                    input.codeUnitAt(i + 1) == 0x2F)) {
              i++;
            }
            i += 2;
          } else {
            sb.writeCharCode(ch);
            i++;
          }
        } else {
          sb.writeCharCode(ch);
          i++;
        }
      }
    }

    // Strip optional trailing commas before '}' or ']'
    final cleaned = sb.toString().replaceAll(
      RegExp(r',\s*([}\]])'),
      r'$1',
    );
    return jsonDecode(cleaned);
  }

  /// Loads and parses the localized string catalog for [localeCode].
  ///
  /// Reads `i18n/<localeCode>.jsonc` from the asset bundle, strips JSONC
  /// comments and trailing commas, trims values, and omits empty entries.
  /// Returns an empty map if the asset cannot be loaded or parsed.
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final assetPath = 'i18n/$localeCode.jsonc';
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> jsonData =
          decodeJsonc(jsonString) as Map<String, dynamic>;
      final Map<String, String> stringMap = jsonData.map(
        (key, value) => MapEntry(key, value.toString().trim()),
      );
      stringMap.removeWhere((key, value) => value.trim().isEmpty);

      return stringMap;
    } catch (e) {
      debugPrint('Error loading localization for "$localeCode": $e');
      return {};
    }
  }
}
