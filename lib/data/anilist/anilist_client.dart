import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime.dart';
import '../models/catalog_query.dart';
import '../models/page.dart';
import 'anilist_queries.dart';

/// Ошибка обращения к AniList.
class AniListException implements Exception {
  const AniListException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;

  /// Задержка из заголовка `Retry-After` при превышении лимита запросов.
  final Duration? retryAfter;

  bool get isRateLimited => statusCode == 429;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'AniListException(${statusCode ?? '-'}): $message';
}

/// Клиент GraphQL API AniList (https://docs.anilist.co).
///
/// Авторизация не требуется для чтения публичных данных. Лимит API —
/// порядка 90 запросов в минуту; на ответ 429 клиент один раз ждёт
/// `Retry-After` (не дольше [maxRetryDelay]) и повторяет запрос.
class AniListClient {
  AniListClient({
    http.Client? httpClient,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
    this.maxRetryDelay = const Duration(seconds: 65),
  }) : _http = httpClient ?? http.Client(),
       _endpoint = endpoint ?? Uri.parse('https://graphql.anilist.co');

  final http.Client _http;
  final Uri _endpoint;
  final Duration timeout;
  final Duration maxRetryDelay;

  /// Страница каталога с учётом фильтров, сортировки и поиска.
  Future<Paged<Anime>> fetchCatalog(
    CatalogQuery query, {
    int page = 1,
    int perPage = 30,
  }) async {
    final data = await rawQuery(AniListQueries.catalog, {
      ...query.toVariables(),
      'page': page,
      'perPage': perPage,
    });
    return parseCatalog(data);
  }

  /// Поиск по названию; сокращение для [fetchCatalog].
  Future<Paged<Anime>> search(String text, {int page = 1, int perPage = 30}) =>
      fetchCatalog(
        CatalogQuery(search: text),
        page: page,
        perPage: perPage,
      );

  /// Полная карточка тайтла.
  Future<AnimeDetails> fetchDetails(int id) async {
    final data = await rawQuery(AniListQueries.details, {'id': id});
    return parseDetails(data);
  }

  /// Список жанров AniList.
  Future<List<String>> fetchGenres() async {
    final data = await rawQuery(AniListQueries.genres, const {});
    return (data['GenreCollection'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
  }

  /// Выполняет запрос и возвращает поле `data` ответа.
  Future<Map<String, dynamic>> rawQuery(
    String query,
    Map<String, dynamic> variables,
  ) async {
    try {
      return await _send(query, variables);
    } on AniListException catch (e) {
      final delay = e.retryAfter;
      if (!e.isRateLimited || delay == null || delay > maxRetryDelay) rethrow;
      await Future<void>.delayed(delay);
      return _send(query, variables);
    }
  }

  Future<Map<String, dynamic>> _send(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AniListException('Превышено время ожидания ответа');
    } on http.ClientException catch (e) {
      throw AniListException('Сетевая ошибка: ${e.message}');
    }
    return parseResponse(response);
  }

  /// Разбирает HTTP-ответ GraphQL: проверяет статус и массив `errors`.
  static Map<String, dynamic> parseResponse(http.Response response) {
    final status = response.statusCode;
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }

    final errors = body?['errors'];
    if (status != 200 || (errors is List && errors.isNotEmpty)) {
      final message = errors is List && errors.isNotEmpty
          ? errors
                .map((e) => e is Map ? e['message'] : e)
                .whereType<Object>()
                .join('; ')
          : 'HTTP $status';
      final firstError = errors is List && errors.isNotEmpty
          ? errors.first
          : null;
      final errorStatus = firstError is Map
          ? firstError['status'] as int?
          : null;
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      throw AniListException(
        message,
        statusCode: status != 200 ? status : errorStatus,
        retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      );
    }

    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw AniListException(
        'Некорректный ответ: нет поля data',
        statusCode: status,
      );
    }
    return data;
  }

  /// Разбирает `data` ответа на [AniListQueries.catalog].
  static Paged<Anime> parseCatalog(Map<String, dynamic> data) {
    final page = data['Page'] as Map<String, dynamic>? ?? const {};
    return Paged(
      items: [
        for (final m in (page['media'] as List? ?? const []))
          if (m is Map<String, dynamic>) Anime.fromJson(m),
      ],
      pageInfo: PageInfo.fromJson(
        page['pageInfo'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  /// Разбирает `data` ответа на [AniListQueries.details].
  static AnimeDetails parseDetails(Map<String, dynamic> data) {
    final media = data['Media'];
    if (media is! Map<String, dynamic>) {
      throw const AniListException('Тайтл не найден', statusCode: 404);
    }
    return AnimeDetails.fromJson(media);
  }

  void close() => _http.close();
}
