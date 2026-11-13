import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_exception.dart';

/// Минимальный клиент GitHub REST API для работы с Gist.
class GistClient {
  GistClient(this._token, {http.Client? httpClient, Uri? baseUri})
    : _http = httpClient ?? http.Client(),
      _base = baseUri ?? Uri.parse('https://api.github.com');

  final String _token;
  final http.Client _http;
  final Uri _base;

  /// Логин владельца токена.
  Future<String> currentLogin() async => (await currentUser()).login;

  /// Владелец токена и права classic-токена (заголовок `X-OAuth-Scopes`;
  /// `null` — GitHub его не прислал или браузер не дал прочитать).
  Future<({String login, String? avatarUrl, Set<String>? scopes})>
  currentUser() async {
    final response = await _request('GET', _base.resolve('/user'));
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final header = response.headers['x-oauth-scopes'];
    return (
      login: json['login'] as String,
      avatarUrl: json['avatar_url'] as String?,
      scopes: header == null
          ? null
          : {
              for (final s in header.split(','))
                if (s.trim().isNotEmpty) s.trim(),
            },
    );
  }

  /// Ищет среди Gist пользователя тот, где есть файл [fileName].
  Future<String?> findGistWithFile(String fileName) async {
    for (var page = 1; page <= 30; page++) {
      final list = await _send('GET', '/gists?per_page=100&page=$page');
      final gists = list['items'] as List;
      for (final g in gists) {
        final files = (g as Map)['files'] as Map? ?? const {};
        if (files.containsKey(fileName)) return g['id'] as String;
      }
      if (gists.length < 100) break;
    }
    return null;
  }

  /// Содержимое файла или `null`, если файла в Gist нет.
  /// Бросает [GitHubException] со статусом 404, если нет самого Gist.
  Future<String?> readFile(String gistId, String fileName) async {
    final json = await _send('GET', '/gists/$gistId');
    final file = (json['files'] as Map?)?[fileName] as Map?;
    if (file == null) return null;
    if (file['truncated'] != true) return file['content'] as String?;
    // Файлы больше 1 МБ API отдаёт обрезанными; полный текст — по raw_url.
    final raw = await _request('GET', Uri.parse(file['raw_url'] as String));
    return utf8.decode(raw.bodyBytes);
  }

  /// Публичный профиль пользователя [login]: логин и аватар; `null` —
  /// такого пользователя нет.
  Future<({String login, String? avatarUrl})?> user(String login) async {
    try {
      final json = await _send('GET', '/users/${Uri.encodeComponent(login)}');
      return (
        login: json['login'] as String,
        avatarUrl: json['avatar_url'] as String?,
      );
    } on GitHubException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Ищет среди **публичных** Gist пользователя [login] тот, где есть файл
  /// [fileName]; `null` — нет (или нет пользователя).
  Future<String?> findPublicGist(String login, String fileName) async {
    for (var page = 1; page <= 10; page++) {
      final Map<String, dynamic> list;
      try {
        list = await _send(
          'GET',
          '/users/${Uri.encodeComponent(login)}/gists?per_page=100&page=$page',
        );
      } on GitHubException catch (e) {
        if (e.statusCode == 404) return null;
        rethrow;
      }
      final gists = list['items'] as List;
      for (final g in gists) {
        final files = (g as Map)['files'] as Map? ?? const {};
        if (g['public'] != false && files.containsKey(fileName)) {
          return g['id'] as String;
        }
      }
      if (gists.length < 100) break;
    }
    return null;
  }

  /// Создаёт Gist и возвращает его id. Секретный (`public: false`) не
  /// виден в списках и поиске, открывается по ссылке; публичный виден в
  /// профиле GitHub — по нему друзья находят каталог по нику.
  Future<String> createGist({
    required String fileName,
    required String content,
    required String description,
    bool public = false,
  }) async {
    final json = await _send(
      'POST',
      '/gists',
      body: {
        'description': description,
        'public': public,
        'files': {
          fileName: {'content': content},
        },
      },
    );
    return json['id'] as String;
  }

  /// Удаляет Gist; уже удалённый (404) — не ошибка.
  Future<void> deleteGist(String gistId) async {
    try {
      await _request('DELETE', _base.resolve('/gists/$gistId'));
    } on GitHubException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  Future<void> writeFile(String gistId, String fileName, String content) =>
      _send(
        'PATCH',
        '/gists/$gistId',
        body: {
          'files': {
            fileName: {'content': content},
          },
        },
      );

  /// Возвращает JSON ответа; списки оборачиваются в `{'items': [...]}`.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final response = await _request(
      method,
      _base.resolve(path),
      body: body == null ? null : jsonEncode(body),
    );
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    return json is List ? {'items': json} : json as Map<String, dynamic>;
  }

  Future<http.Response> _request(String method, Uri uri, {String? body}) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = body;

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 30)),
      );
    } on TimeoutException {
      throw const GitHubException(GitHubErrorKind.network, 'Нет ответа');
    } on http.ClientException catch (e) {
      throw GitHubException(GitHubErrorKind.network, e.message);
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    String message = 'HTTP $status';
    try {
      final json = jsonDecode(response.body);
      if (json is Map && json['message'] is String) message = json['message'];
    } on FormatException {
      // Оставляем HTTP-статус.
    }
    final rateLimited =
        status == 429 ||
        (status == 403 &&
            (response.headers['x-ratelimit-remaining'] == '0' ||
                message.toLowerCase().contains('rate limit')));
    if (rateLimited) {
      final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
      throw GitHubException(
        GitHubErrorKind.rateLimited,
        'GitHub временно ограничил число запросов. Попробуйте через час',
        statusCode: status,
        retryAt: reset == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true),
      );
    }
    throw GitHubException(
      switch (status) {
        401 => GitHubErrorKind.unauthorized,
        >= 500 => GitHubErrorKind.network,
        _ => GitHubErrorKind.other,
      },
      message,
      statusCode: status,
    );
  }

  void close() => _http.close();
}
