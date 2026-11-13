import 'package:web/web.dart' as web;

import '../data/github/token_store.dart';

/// Веб-сборка.
const isWeb = true;

/// В браузере диска нет: обложки кэширует сам браузер.
Future<void> setUpPlatform() async {}

/// Токен GitHub профиля — в localStorage браузера (защищённого хранилища
/// в браузере нет; экран входа об этом предупреждает). Стирается при
/// выходе.
TokenStore tokenStoreFor(int profileId) =>
    LocalStorageTokenStore(profileId: profileId);

const _youtubeKey = 'youtube_api_key';

/// Свой ключ YouTube пользователя из localStorage. Ключей из сборки в
/// веб-версии нет: страница публичная, их увидел бы любой.
String youtubeApiKey() => _read(_youtubeKey) ?? '';

/// Распознавание музыки в браузере выключено.
bool get hasAcoustIdApiKey => false;

/// Сохраняет (или стирает, если пусто) свой ключ YouTube и перезагружает
/// страницу: сервисы YouTube создаются при запуске. Тост о сохранении
/// показывается после перезагрузки ([takePendingToast]).
Future<void> saveYoutubeApiKey(String? key) async {
  final k = key?.trim() ?? '';
  try {
    if (k.isEmpty) {
      web.window.localStorage.removeItem(_youtubeKey);
    } else {
      web.window.localStorage.setItem(_youtubeKey, k);
    }
    web.window.sessionStorage.setItem(
      _toastKey,
      k.isEmpty
          ? 'Ключ удалён из браузера'
          : 'Ключ YouTube сохранён в этом браузере',
    );
  } on Object {
    // Хранилище сайта запрещено (приватный режим) — ключ не сохранится.
  }
  web.window.location.reload();
}

const _toastKey = 'pending_toast';

/// Тост, отложенный до перезагрузки страницы (один раз).
String? takePendingToast() {
  try {
    final text = web.window.sessionStorage.getItem(_toastKey);
    web.window.sessionStorage.removeItem(_toastKey);
    return text;
  } on Object {
    return null;
  }
}

String? _read(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } on Object {
    return null;
  }
}

/// Токен в localStorage, у каждого профиля свой.
class LocalStorageTokenStore implements TokenStore {
  LocalStorageTokenStore({required this.profileId});

  final int profileId;

  String get _key => 'github_token_p$profileId';

  @override
  Future<String?> read() async => _read(_key);

  @override
  Future<void> write(String token) async =>
      web.window.localStorage.setItem(_key, token);

  @override
  Future<void> delete() async {
    try {
      web.window.localStorage.removeItem(_key);
    } on Object {
      // Нечего стирать.
    }
  }
}
