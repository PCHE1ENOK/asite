import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/settings/app_preferences.dart';

/// Источник картинок по URL; в тестах подменяется.
typedef ImageResolver = ImageProvider Function(String url);

ImageProvider networkImage(String url) => NetworkImage(url);

/// Настройки, которые влияют на несколько экранов сразу.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final AppPreferences _prefs;

  bool _showAdult = true;
  ThemePreference _theme = ThemePreference.system;
  List<String> _recentSearches = const [];

  /// «Показывать 18+»: одно значение для фильтра каталога, поиска и
  /// настроек.
  bool get showAdult => _showAdult;
  ThemePreference get theme => _theme;
  List<String> get recentSearches => _recentSearches;

  ThemeMode get themeMode => switch (_theme) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.light => ThemeMode.light,
  };

  Future<void> load() async {
    _showAdult = await _prefs.showAdult();
    _theme = await _prefs.theme();
    _recentSearches = await _prefs.recentSearches();
    notifyListeners();
  }

  Future<void> setShowAdult(bool value) async {
    if (value == _showAdult) return;
    _showAdult = value;
    notifyListeners();
    await _prefs.setShowAdult(value);
  }

  Future<void> setTheme(ThemePreference value) async {
    if (value == _theme) return;
    _theme = value;
    notifyListeners();
    await _prefs.setTheme(value);
  }

  Future<void> addRecentSearch(String query) async {
    _recentSearches = await _prefs.addRecentSearch(query);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = const [];
    notifyListeners();
    await _prefs.clearRecentSearches();
  }
}

/// Даёт виджетам доступ к сервисам и настройкам.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.services,
    required this.settings,
    this.imageResolver = networkImage,
    required super.child,
  });

  final AppServices services;
  final AppSettings settings;
  final ImageResolver imageResolver;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      services != old.services ||
      settings != old.settings ||
      imageResolver != old.imageResolver;
}
