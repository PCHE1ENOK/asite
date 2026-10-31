import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Как показывать официальный плеер YouTube на текущей платформе.
enum EmbedKind {
  /// `webview_flutter` (Android, iOS, macOS).
  webview,

  /// WebView2 через `webview_windows` (Windows).
  webview2,

  /// Встроить нельзя — ролик открывается на youtube.com.
  browser,
}

EmbedKind embedKindFor(TargetPlatform platform, {bool isWeb = kIsWeb}) {
  if (isWeb) return EmbedKind.browser;
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => EmbedKind.webview,
    TargetPlatform.windows => EmbedKind.webview2,
    _ => EmbedKind.browser,
  };
}

/// Адрес страницы плеера внутри приложения. YouTube требует, чтобы
/// встроенный плеер передавал Referer/origin приложения (иначе ошибка
/// 153); страница с iframe открывается с этого адреса (WebView2 — через
/// виртуальный хост, мобильный WebView — через baseUrl), и тот же адрес
/// передаётся в параметре `origin`.
const playerHost = 'player.anime-viewer.pche1enok';
const playerOrigin = 'https://$playerHost';

/// Имя JS-канала (мобильный WebView); в WebView2 — `chrome.webview`.
const playerBridge = 'AppBridge';

/// Сколько ждём `onReady` от плеера, прежде чем считать, что он не
/// открылся (чёрный экран без событий).
const playerReadyTimeout = Duration(seconds: 20);

/// Событие плеера из IFrame API.
sealed class PlayerEvent {
  const PlayerEvent();

  /// Сообщение страницы: объект (WebView2 разбирает JSON сам) или строка.
  static PlayerEvent? parse(Object? message) {
    Object? m = message;
    if (m is String) {
      try {
        m = jsonDecode(m);
      } on FormatException {
        return null;
      }
    }
    if (m is! Map) return null;
    return switch (m['event']) {
      'ready' => const PlayerReady(),
      'error' => PlayerError('${m['code']}'),
      _ => null,
    };
  }
}

class PlayerReady extends PlayerEvent {
  const PlayerReady();
}

/// Ошибка: код IFrame API (`2`, `5`, `100`, `101`, `150`, `152`, `153`)
/// или наш: `script` — не загрузился плеер, `timeout` — нет ответа.
class PlayerError extends PlayerEvent {
  const PlayerError(this.code);

  final String code;

  /// Причина для пользователя.
  String get reason => switch (code) {
    '2' => 'Неверный адрес ролика',
    '5' => 'Плеер YouTube не смог воспроизвести ролик',
    '100' => 'Ролик удалён или скрыт',
    '101' || '150' => 'Владелец запретил показ ролика в приложениях',
    '152' || '153' =>
      'Плеер YouTube не принял приложение (ошибка настройки встраивания)',
    'script' => 'Не удалось загрузить плеер YouTube. Проверьте подключение',
    'timeout' => 'Плеер YouTube не ответил',
    _ when code.startsWith('load:') =>
      'Страница плеера не загрузилась. Проверьте подключение',
    _ => 'Плеер YouTube сообщил об ошибке',
  };
}

/// HTML-страница с официальным iframe-плеером YouTube. Видео
/// воспроизводит только плеер YouTube: ссылок на видеофайлы или потоки
/// здесь нет. IFrame API подключается к iframe только ради событий
/// `onReady` / `onError`, которые уходят в приложение.
String youtubePlayerHtml(String videoId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(videoId)) {
    throw ArgumentError.value(videoId, 'videoId');
  }
  final src = Uri.https('www.youtube.com', '/embed/$videoId', {
    'playsinline': '1',
    'rel': '0',
    // Полный экран — только наш (кнопка fullscreen iframe в WebView не
    // работает без поддержки приложения), design/screens.md §11.
    'fs': '0',
    'enablejsapi': '1',
    'origin': playerOrigin,
  });
  return '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>
  html, body { margin: 0; height: 100%; background: #000; }
  iframe { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; }
</style>
<script>
  function post(m) {
    try {
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(m);
      } else if (window.$playerBridge) {
        window.$playerBridge.postMessage(JSON.stringify(m));
      }
    } catch (e) {}
  }
  function onYouTubeIframeAPIReady() {
    new YT.Player('player', {
      events: {
        onReady: function () { post({event: 'ready'}); },
        onError: function (e) { post({event: 'error', code: e.data}); }
      }
    });
  }
</script>
</head>
<body>
<iframe id="player" src="$src" title="YouTube video player"
  allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
  referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
<script src="https://www.youtube.com/iframe_api"
  onerror="post({event: 'error', code: 'script'})"></script>
</body>
</html>
''';
}
