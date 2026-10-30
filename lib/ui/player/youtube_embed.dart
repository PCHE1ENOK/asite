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
/// встроенный плеер передавал Referer/origin приложения; страница
/// с iframe открывается с этого адреса (WebView2 — через виртуальный
/// хост, мобильный WebView — через baseUrl).
const playerHost = 'player.anime-viewer.pche1enok';
const playerOrigin = 'https://$playerHost';

/// HTML-страница с официальным iframe-плеером YouTube. Видео
/// воспроизводит только плеер YouTube: ссылок на видеофайлы или потоки
/// здесь нет.
String youtubePlayerHtml(String videoId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(videoId)) {
    throw ArgumentError.value(videoId, 'videoId');
  }
  final src = Uri.https('www.youtube.com', '/embed/$videoId', {
    'playsinline': '1',
    'rel': '0',
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
</head>
<body>
<iframe src="$src" title="YouTube video player"
  allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
  referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
</body>
</html>
''';
}
