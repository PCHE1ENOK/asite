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
  Future<String> currentLogin() async {
    final json = await _send('GET', '/user');
    return json['login'] as String;
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

  /// Создаёт секретный Gist (`public: false`: не виден в списках и поиске,
  /// открывается по ссылке) и возвращает его id.
  Future<String> createGist({
    required String fileName,
    required String content,
    required String description,
  }) async {
    final json = await _send(
      'POST',
      '/gists',
      body: {
        'description': description,
        'public': false,
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
