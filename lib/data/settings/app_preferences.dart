import '../cache/app_database.dart';

/// Настройки пользователя, хранятся в локальной базе.
class AppPreferences {
  AppPreferences(this._db);

  final AppDatabase _db;

  static const _onboardingSeen = 'onboarding_seen';
  static const _showAdult = 'show_adult';

  /// Экран входа показывается один раз при первом запуске.
  Future<bool> shouldShowOnboarding() async =>
      await _db.setting(_onboardingSeen) != '1';

  Future<void> markOnboardingSeen() => _db.putSetting(_onboardingSeen, '1');

  /// Фильтр «Показывать 18+», по умолчанию включён.
  Future<bool> showAdult() async => await _db.setting(_showAdult) != '0';

  Future<void> setShowAdult(bool value) =>
      _db.putSetting(_showAdult, value ? '1' : '0');
}
