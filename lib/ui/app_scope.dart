import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/settings/app_preferences.dart';
import 'library_index.dart';
import 'widgets/cached_image.dart';

/// Источник картинок по URL; в тестах подменяется.
typedef ImageResolver = ImageProvider Function(String url);

/// Картинки приложения — через дисковый кэш. В браузере диска нет, а
/// загрузка через fetch требует CORS от CDN картинок: если его нет,
/// картинка показывается обычным `<img>` (кэширует браузер).
ImageProvider networkImage(String url) => kIsWeb
    ? NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback)
    : DiskCachedImage(url);

/// Настройки, которые влияют на несколько экранов сразу.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, {this._profileId = 1});

  final AppPreferences _prefs;

  /// Профиль, чьи недавние запросы показываются.
  int _profileId;

  bool _showAdult = true;
  ThemePreference _theme = ThemePreference.system;
  List<String> _recentSearches = const [];
  bool _musicRecognition = false;
  bool _autoScroll = true;

  /// «Показывать 18+»: одно значение для фильтра каталога, поиска и
  /// настроек.
  bool get showAdult => _showAdult;
  ThemePreference get theme => _theme;
  List<String> get recentSearches => _recentSearches;

  /// «Распознавать музыку», по умолчанию выключено.
  bool get musicRecognition => _musicRecognition;

  /// «Автопрокрутка каруселей», по умолчанию включена.
  bool get autoScroll => _autoScroll;

  ThemeMode get themeMode => switch (_theme) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.light => ThemeMode.light,
  };

  Future<void> load() async {
    _showAdult = await _prefs.showAdult();
    _theme = await _prefs.theme();
    _recentSearches = await _prefs.recentSearches(_profileId);
    _musicRecognition = await _prefs.musicRecognition();
    _autoScroll = await _prefs.autoScroll();
    notifyListeners();
  }

  Future<void> setShowAdult(bool value) async {
    if (value == _showAdult) return;
    _showAdult = value;
    notifyListeners();
    await _prefs.setShowAdult(value);
  }

  Future<void> setMusicRecognition(bool value) async {
    if (value == _musicRecognition) return;
    _musicRecognition = value;
    notifyListeners();
    await _prefs.setMusicRecognition(value);
  }

  Future<void> setAutoScroll(bool value) async {
    if (value == _autoScroll) return;
    _autoScroll = value;
    notifyListeners();
    await _prefs.setAutoScroll(value);
  }

  Future<void> setTheme(ThemePreference value) async {
    if (value == _theme) return;
    _theme = value;
    notifyListeners();
    await _prefs.setTheme(value);
  }

  /// Переключение профиля: недавние запросы у каждого свои.
  Future<void> setProfile(int profileId) async {
    _profileId = profileId;
    _recentSearches = await _prefs.recentSearches(profileId);
    notifyListeners();
  }

  Future<void> addRecentSearch(String query) async {
    _recentSearches = await _prefs.addRecentSearch(_profileId, query);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = const [];
    notifyListeners();
    await _prefs.clearRecentSearches(_profileId);
  }
}

/// Даёт виджетам доступ к сервисам и настройкам.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.services,
    required this.settings,
    required this.library,
    this.imageResolver = networkImage,
    required super.child,
  });

  final AppServices services;
  final AppSettings settings;

  /// Списки пользователя в памяти.
  final LibraryIndex library;
  final ImageResolver imageResolver;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  /// [AppScope] или `null` (экраны поверх приложения в тестах).
  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  @override
  bool updateShouldNotify(AppScope old) =>
      services != old.services ||
      settings != old.settings ||
      library != old.library ||
      imageResolver != old.imageResolver;
}
