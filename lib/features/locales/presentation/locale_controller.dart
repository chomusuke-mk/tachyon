import 'dart:async';

import 'package:flutter/material.dart';
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
  Future<void> get whenReady => _initCompleter.future;

  Map<String, String> _fallbackCache = {};
  static const String _fallbackCode = 'en';

  AppStringKey get localeStrings => _localeStrings;
  String get currentLocaleCode => _currentLocaleCode;

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

    // El secreto perezoso: Clonamos el caché en inglés y le inyectamos el nuevo idioma.
    // Lo que falte en targetStrings se quedará automáticamente en inglés.
    final merged = Map<String, String>.from(_fallbackCache)
      ..addAll(targetStrings);

    // Al pasar el mapa fusionado completo, sobrescribimos todo rastro del idioma anterior.
    await _localeStrings.updateFromJson(merged, assertAllKeysPresent: true);
    notifyListeners();
  }

  /// Switches active language to [localeCode] in real time.
  ///
  /// Rebuilds all listening widgets instantly via [notifyListeners].
  void setLocale(String localeCode) async {
    if (localeCode == _currentLocaleCode) return;

    _currentLocaleCode = localeCode;

    if (localeCode == _fallbackCode) {
      // Si vuelve a inglés, usamos el caché instantáneamente (Cero demoras)
      await _localeStrings.updateFromJson(_fallbackCache);
      notifyListeners();
    } else {
      // Si cambia a otro idioma, descargamos y fusionamos
      await _loadAndMerge(localeCode);
    }
  }
}
