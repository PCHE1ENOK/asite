import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// JSON-ответ с корректной кодировкой UTF-8.
http.Response jsonResponse(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

/// Мок AniList: записывает тела запросов и отвечает через [handler].
class FakeAniList {
  FakeAniList(this.handler);

  http.Response Function(Map<String, dynamic> body) handler;
  final requests = <Map<String, dynamic>>[];

  late final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    return handler(body);
  });
}
