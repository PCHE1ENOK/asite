import 'dart:convert';
import 'dart:typed_data';

import 'package:anime_viewer/app_services.dart';
import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/anime_repository.dart';
import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/token_store.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:anime_viewer/data/sync/sync_service.dart';
import 'package:anime_viewer/main.dart';
import 'package:anime_viewer/ui/app_scope.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../fixtures.dart';

/// Прозрачный PNG 1×1 вместо сетевых картинок.
final transparentPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

ImageProvider fakeImage(String url) => MemoryImage(transparentPng);

/// Фиксированное «сейчас» для списка сезонов.
final testNow = DateTime(2026, 10, 29);

/// Приложение на поддельном AniList и базе в памяти.
class UiHarness {
  UiHarness({ImageResolver? images}) : imageResolver = images ?? fakeImage {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    fake = FakeAniList(_route);
    final library = LibraryRepository(db);
    services = AppServices(
      db: db,
      anime: AnimeRepository(
        client: AniListClient(httpClient: fake.client),
        db: db,
      ),
      library: library,
      preferences: AppPreferences(db),
      sync: SyncService(
        library: library,
        db: db,
        tokens: MemoryTokenStore(),
        auth: () => null,
        gistClient: (token) => GistClient(token),
      ),
    );
    settings = AppSettings(services.preferences);
  }

  late final AppDatabase db;
  late final FakeAniList fake;
  late final AppServices services;
  late final AppSettings settings;
  final ImageResolver imageResolver;

  bool offline = false;

  /// Поиск по этой строке ничего не находит.
  static const nothing = 'zzzz';

  List<Map<String, dynamic>> get catalogRequests => [
    for (final r in fake.requests)
      if ((r['query'] as String).contains('query Catalog'))
        r['variables'] as Map<String, dynamic>,
  ];

  http.Response _route(Map<String, dynamic> body) {
    if (offline) return http.Response('', 503);
    final query = body['query'] as String;
    final vars = body['variables'] as Map<String, dynamic>;
    if (query.contains('query Catalog')) {
      if (vars['search'] == nothing || (vars['page'] as int? ?? 1) > 1) {
        return jsonResponse(
          '{"data":{"Page":{"pageInfo":{"total":0,"perPage":30,"currentPage":2,"hasNextPage":false},"media":[]}}}',
        );
      }
      return jsonResponse(fixture('catalog_page_30.json'));
    }
    if (query.contains('query Details')) {
      return jsonResponse(fixture('details_response.json'));
    }
    return jsonResponse(
      '{"data":{"GenreCollection":["Action","Comedy","Drama","Hentai"]}}',
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(settings.load);
    await tester.pumpWidget(
      AnimeViewerApp(
        services: services,
        settings: settings,
        showOnboarding: false,
        imageResolver: imageResolver,
        now: testNow,
      ),
    );
    await settle(tester);
  }

  /// Даёт отработать запросам к поддельному API и базе.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  }
}
