import 'dart:async';

import 'package:http/http.dart' as http;

/// Итог проверки ключа YouTube Data API.
enum YouTubeKeyCheck {
  ok,
  empty,

  /// 400 `keyInvalid` / `API key not valid`.
  invalid,

  /// 403 `accessNotConfigured`: в проекте не включён YouTube Data API v3.
  notEnabled,

  /// Сеть или другой ответ.
  failed,
}

/// Проверяет ключ одним запросом `i18nLanguages.list` (1 единица квоты)
/// перед сохранением (веб-версия, «Свой ключ YouTube»).
Future<YouTubeKeyCheck> checkYouTubeKey(
  String raw, {
  http.Client? client,
}) async {
  final key = raw.trim();
  if (key.isEmpty) return YouTubeKeyCheck.empty;
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.https('www.googleapis.com', '/youtube/v3/i18nLanguages', {
            'part': 'snippet',
            'hl': 'ru',
            'key': key,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) return YouTubeKeyCheck.ok;
    if (res.body.contains('accessNotConfigured') ||
        res.body.contains('SERVICE_DISABLED')) {
      return YouTubeKeyCheck.notEnabled;
    }
    if (res.statusCode == 400 &&
        (res.body.contains('keyInvalid') ||
            res.body.contains('API_KEY_INVALID') ||
            res.body.contains('API key not valid'))) {
      return YouTubeKeyCheck.invalid;
    }
    return YouTubeKeyCheck.failed;
  } on Object {
    return YouTubeKeyCheck.failed;
  } finally {
    if (client == null) c.close();
  }
}

/// «AIza…rsXY»: видны только первые и последние 4 символа.
String maskKey(String key) => key.length <= 8
    ? '…'
    : '${key.substring(0, 4)}…${key.substring(key.length - 4)}';
