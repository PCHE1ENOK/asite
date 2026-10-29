import 'dart:convert';

import '../cache/app_database.dart';

/// Тема оформления.
enum ThemePreference { system, dark, light }

/// Настройки пользователя, хранятся в локальной базе.
class AppPreferences {
  AppPreferences(this._db);

  final AppDatabase _db;

  static const _onboardingSeen = 'onboarding_seen';
  static const _showAdult = 'show_adult';
  static const _theme = 'theme';
  static const _recentSearches = 'recent_searches';

  /// Сколько недавних запросов хранится.
  static const maxRecentSearches = 8;

  /// Экран входа показывается один раз при первом запуске.
  Future<bool> shouldShowOnboarding() async =>
      await _db.setting(_onboardingSeen) != '1';

  Future<void> markOnboardingSeen() => _db.putSetting(_onboardingSeen, '1');

  /// Фильтр «Показывать 18+», по умолчанию включён.
  Future<bool> showAdult() async => await _db.setting(_showAdult) != '0';

  Future<void> setShowAdult(bool value) =>
      _db.putSetting(_showAdult, value ? '1' : '0');

  /// Тема, по умолчанию системная.
  Future<ThemePreference> theme() async {
    final v = await _db.setting(_theme);
    return ThemePreference.values.where((t) => t.name == v).firstOrNull ??
        ThemePreference.system;
  }

  Future<void> setTheme(ThemePreference value) =>
      _db.putSetting(_theme, value.name);

  /// Недавние поисковые запросы, новые первыми.
  Future<List<String>> recentSearches() async {
    final v = await _db.setting(_recentSearches);
    if (v == null) return const [];
    try {
      return (jsonDecode(v) as List).whereType<String>().toList();
    } on FormatException {
      return const [];
    }
  }

  /// Добавляет запрос в начало; повтор без учёта регистра поднимается
  /// наверх, список обрезается до [maxRecentSearches].
  Future<List<String>> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return recentSearches();
    final list = [
      q,
      for (final s in await recentSearches())
        if (s.toLowerCase() != q.toLowerCase()) s,
    ].take(maxRecentSearches).toList();
    await _db.putSetting(_recentSearches, jsonEncode(list));
    return list;
  }

  Future<void> clearRecentSearches() => _db.putSetting(_recentSearches, null);
}
