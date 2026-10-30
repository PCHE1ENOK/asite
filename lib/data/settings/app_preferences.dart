import 'dart:convert';

import '../cache/app_database.dart';
import '../profiles/profile_repository.dart';

/// Тема оформления.
enum ThemePreference { system, dark, light }

/// Настройки пользователя, хранятся в локальной базе.
class AppPreferences {
  AppPreferences(this._db);

  final AppDatabase _db;

  static const _onboardingSeen = 'onboarding_seen';
  static const _showAdult = 'show_adult';
  static const _theme = 'theme';
  static const _musicRecognition = 'music_recognition';
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

  /// «Распознавать музыку»: по умолчанию выключено, потому что фрагмент
  /// звука уходит на сервер AcoustID.
  Future<bool> musicRecognition() async =>
      await _db.setting(_musicRecognition) == '1';

  Future<void> setMusicRecognition(bool value) =>
      _db.putSetting(_musicRecognition, value ? '1' : '0');

  /// Тема, по умолчанию системная.
  Future<ThemePreference> theme() async {
    final v = await _db.setting(_theme);
    return ThemePreference.values.where((t) => t.name == v).firstOrNull ??
        ThemePreference.system;
  }

  Future<void> setTheme(ThemePreference value) =>
      _db.putSetting(_theme, value.name);

  String _recentKey(int profileId) =>
      ProfileRepository.settingKey(profileId, _recentSearches);

  /// Недавние поисковые запросы профиля, новые первыми.
  Future<List<String>> recentSearches(int profileId) async {
    final v = await _db.setting(_recentKey(profileId));
    if (v == null) return const [];
    try {
      return (jsonDecode(v) as List).whereType<String>().toList();
    } on FormatException {
      return const [];
    }
  }

  /// Добавляет запрос в начало; повтор без учёта регистра поднимается
  /// наверх, список обрезается до [maxRecentSearches].
  Future<List<String>> addRecentSearch(int profileId, String query) async {
    final q = query.trim();
    if (q.isEmpty) return recentSearches(profileId);
    final list = [
      q,
      for (final s in await recentSearches(profileId))
        if (s.toLowerCase() != q.toLowerCase()) s,
    ].take(maxRecentSearches).toList();
    await _db.putSetting(_recentKey(profileId), jsonEncode(list));
    return list;
  }

  Future<void> clearRecentSearches(int profileId) =>
      _db.putSetting(_recentKey(profileId), null);
}
