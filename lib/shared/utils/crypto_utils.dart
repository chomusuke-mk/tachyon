import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic and data hashing utilities (SHA256).
class CryptoUtils {
  /// Computes a standard hex SHA-256 hash of raw byte buffers.
  static String computeBytesHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Computes a standard hex SHA-256 hash of UTF-8 strings.
  static String computeStringHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}
