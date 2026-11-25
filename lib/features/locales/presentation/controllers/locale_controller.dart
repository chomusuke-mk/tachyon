import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/domain/locale.dart';

/// State management controller providing reactive localized strings to UI widgets.
///
/// Features:
/// - In-memory immutable fallback cache loaded once from English ('en').
/// - Dynamic hot-swapping between locales without app restart.
/// - Defensive merge ensuring missing translations transparently fallback to English.
/// - Asynchronous initialization synchronization via [whenReady].
class LocaleController extends ChangeNotifier {
  final LocaleRepository _repository;
  final AppStringKey _localeStrings = AppStringKey();

  late String _currentLocaleCode;

  final Completer<void> _initCompleter = Completer<void>();

  /// Future completing once the initial locale strings have finished loading.
  Future<void> get whenReady => _initCompleter.future;

  Map<String, String> _fallbackCache = {};
  static const String _fallbackCode = 'en';

  /// Live mutable string catalog exposed to widgets across the app.
  AppStringKey get localeStrings => _localeStrings;

  /// Two-letter ISO language code of the active locale.
  String get currentLocaleCode => _currentLocaleCode;

  /// Creates a [LocaleController] backed by [_repository] starting with [initialLocale].
  LocaleController(this._repository, String initialLocale) {
    _currentLocaleCode = initialLocale;
    _init();
  }

  Future<void> _init() async {
    // 1. Load English fallback into memory once during startup
    _fallbackCache = await _repository.getLocaleStrings(_fallbackCode);

    // 2. If initial locale is English, directly populate strings
    if (_currentLocaleCode == _fallbackCode) {
      await _localeStrings.updateFromJson(
        _fallbackCache,
        assertAllKeysPresent: false,
      );
      notifyListeners();
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      return;
    }
    await _loadAndMerge(_currentLocaleCode);
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  Future<void> _loadAndMerge(String targetLocale) async {
    final targetStrings = await _repository.getLocaleStrings(targetLocale);

    // Clone the English fallback map and overlay target-locale entries so missing keys remain in English.
    final merged = Map<String, String>.from(_fallbackCache)
      ..addAll(targetStrings);

    // Pass the complete merged map to overwrite any leftover entries from the previous locale.
    try {
      await _localeStrings.updateFromJson(merged, assertAllKeysPresent: true);
    } on FormatException catch (e) {
      debugPrint('[LocaleController] Incomplete locale translations: $e');
      await _localeStrings.updateFromJson(merged, assertAllKeysPresent: false);
    }
    notifyListeners();
  }

  /// Switches active language to [localeCode] in real time.
  ///
  /// Rebuilds all listening widgets instantly via [notifyListeners].
  Future<void> setLocale(String localeCode) async {
    if (localeCode == _currentLocaleCode) return;

    _currentLocaleCode = localeCode;

    try {
      if (localeCode == _fallbackCode) {
        await _localeStrings.updateFromJson(_fallbackCache);
        notifyListeners();
      } else {
        await _loadAndMerge(localeCode);
      }
    } catch (e, st) {
      debugPrint('[LocaleController] Error switching locale to $localeCode: $e\n$st');
    }
  }
}
