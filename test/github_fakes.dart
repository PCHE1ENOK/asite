import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Поддельный GitHub: Device Flow, /user и /gists в памяти.
class FakeGitHub {
  FakeGitHub({this.login = 'octocat', String? avatarUrl})
    : avatarUrl = avatarUrl ?? 'https://avatars.githubusercontent.com/u/1?v=4';

  String login;

  /// `avatar_url` в ответе `/user`.
  String? avatarUrl;
  int userRequests = 0;

  /// Публичные Gist созданные приложением (`public: true`).
  final publicIds = <String>{};

  /// Другие пользователи GitHub: логин → аватар.
  final users = <String, String?>{};

  /// Публичные Gist других пользователей: логин → файлы.
  final userGists = <String, Map<String, String>>{};

  /// GitHub отвечает «лимит запросов исчерпан».
  bool rateLimited = false;
  int apiRequests = 0;
  final gists = <String, Map<String, String>>{};
  var pendingPolls = 1;
  String? tokenError;
  bool offline = false;
  bool revoked = false;

  /// Токен, который принимает API (Device Flow выдаёт `tok`).
  String token = 'tok';

  /// Права classic-токена в заголовке `X-OAuth-Scopes` ответа `/user`;
  /// `null` — заголовка нет.
  String? scopes = 'gist';
  int writes = 0;
  final deleted = <String>[];
  int _nextId = 1;

  late final client = MockClient(_handle);

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline', r.url);
    final path = r.url.path;

    if (path == '/login/device/code') {
      return _json({
        'device_code': 'dev-123',
        'user_code': 'ABCD-1234',
        'verification_uri': 'https://github.com/login/device',
        'expires_in': 900,
        'interval': 5,
      });
    }
    if (path == '/login/oauth/access_token') {
      if (tokenError != null) return _json({'error': tokenError});
      if (pendingPolls > 0) {
        pendingPolls--;
        return _json({'error': 'authorization_pending'});
      }
      return _json({
        'access_token': 'tok',
        'token_type': 'bearer',
        'scope': 'gist',
      });
    }

    if (rateLimited) {
      return _json(
        {'message': 'API rate limit exceeded for user.'},
        403,
        {
          'x-ratelimit-remaining': '0',
          // 2026-11-13 10:30 UTC.
          'x-ratelimit-reset':
              '${DateTime.utc(2026, 11, 13, 10, 30).millisecondsSinceEpoch ~/ 1000}',
        },
      );
    }
    apiRequests++;
    if (revoked || r.headers['Authorization'] != 'Bearer $token') {
      return _json({'message': 'Bad credentials'}, 401);
    }
    if (path == '/user') {
      userRequests++;
      return _json(
        {'login': login, 'avatar_url': ?avatarUrl},
        200,
        {'x-oauth-scopes': ?scopes},
      );
    }
    if (path == '/gists' && r.method == 'GET') {
      final page = int.parse(r.url.queryParameters['page'] ?? '1');
      if (page > 1) return _json([]);
      return _json([
        for (final MapEntry(:key, :value) in gists.entries)
          {
            'id': key,
            'files': {
              for (final f in value.keys) f: {'filename': f},
            },
          },
      ]);
    }
    final userPath = RegExp(r'^/users/([\w-]+)(/gists)?$').firstMatch(path);
    if (userPath != null) {
      final login = userPath[1]!;
      final known = users.keys
          .where((u) => u.toLowerCase() == login.toLowerCase())
          .firstOrNull;
      if (known == null) return _json({'message': 'Not Found'}, 404);
      if (userPath[2] == null) {
        return _json({'login': known, 'avatar_url': ?users[known]});
      }
      final files = userGists[known];
      return _json([
        if (files != null)
          {
            'id': 'pub$known',
            'public': true,
            'files': {
              for (final f in files.keys) f: {'filename': f},
            },
          },
      ]);
    }
    final userGist = RegExp(r'^/gists/pub([\w-]+)$').firstMatch(path);
    final files = userGist == null ? null : userGists[userGist[1]];
    if (userGist != null && files != null) {
      return _json({
        'id': 'pub${userGist[1]}',
        'files': {
          for (final MapEntry(:key, :value) in files.entries)
            key: {'filename': key, 'content': value, 'truncated': false},
        },
      });
    }
    if (path == '/gists' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final id = 'g${_nextId++}';
      if (body['public'] == true) publicIds.add(id);
      gists[id] = _files(body);
      writes++;
      return _json({'id': id}, 201);
    }
    final match = RegExp(r'^/gists/(\w+)$').firstMatch(path);
    if (match != null) {
      final gist = gists[match[1]];
      if (gist == null) return _json({'message': 'Not Found'}, 404);
      if (r.method == 'DELETE') {
        gists.remove(match[1]);
        deleted.add(match[1]!);
        return http.Response('', 204);
      }
      if (r.method == 'PATCH') {
        gist.addAll(_files(jsonDecode(r.body) as Map<String, dynamic>));
        writes++;
      }
      return _json({
        'id': match[1],
        'files': {
          for (final MapEntry(:key, :value) in gist.entries)
            key: {'filename': key, 'content': value, 'truncated': false},
        },
      });
    }
    return _json({'message': 'Not Found'}, 404);
  }

  static Map<String, String> _files(Map<String, dynamic> body) => {
    for (final MapEntry(:key, :value)
        in (body['files'] as Map<String, dynamic>).entries)
      key: (value as Map)['content'] as String,
  };

  static http.Response _json(
    Object body, [
    int status = 200,
    Map<String, String> headers = const {},
  ]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );
}
