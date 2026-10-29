import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Поддельный GitHub: Device Flow, /user и /gists в памяти.
class FakeGitHub {
  FakeGitHub({this.login = 'octocat'});

  final String login;
  final gists = <String, Map<String, String>>{};
  var pendingPolls = 1;
  String? tokenError;
  bool offline = false;
  bool revoked = false;
  int writes = 0;
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

    if (revoked || r.headers['Authorization'] != 'Bearer tok') {
      return _json({'message': 'Bad credentials'}, 401);
    }
    if (path == '/user') return _json({'login': login});
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
    if (path == '/gists' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      assert(body['public'] == false);
      final id = 'g${_nextId++}';
      gists[id] = _files(body);
      writes++;
      return _json({'id': id}, 201);
    }
    final match = RegExp(r'^/gists/(\w+)$').firstMatch(path);
    if (match != null) {
      final gist = gists[match[1]];
      if (gist == null) return _json({'message': 'Not Found'}, 404);
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

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
