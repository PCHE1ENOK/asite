import 'dart:convert';
import 'dart:typed_data';

import 'package:anime_viewer/app_services.dart';
import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/anime_repository.dart';
import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/token_store.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/music/music_recognition.dart';
import 'package:anime_viewer/data/notes/notes_repository.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:anime_viewer/data/sources/youtube_comments.dart';
import 'package:anime_viewer/data/translation/translation.dart';
import 'package:anime_viewer/data/sync/sync_service.dart';
import 'package:anime_viewer/main.dart';
import 'package:anime_viewer/ui/app_scope.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    final preferences = AppPreferences(db);
    final profiles = ProfileRepository(db);
    services = AppServices(
      db: db,
      anime: AnimeRepository(
        client: AniListClient(httpClient: fake.client),
        db: db,
      ),
      preferences: preferences,
      profiles: profiles,
      tokensFor: tokenStore,
      sources: VideoSources([videoSource]),
      comments: YouTubeCommentsClient(
        apiKey: 'test-key',
        httpClient: MockClient((r) async {
          commentRequests.add(r.url);
          return commentsHandler(r.url);
        }),
      ),
      translator: CommentTranslator(
        detector: const ScriptLanguageDetector(),
        engine: _DelegatingEngine(() => translationEngine),
      ),
      music: MusicRecognitionGate(
        isEnabled: preferences.musicRecognition,
        hasApiKey: false,
        recognizer: const StubMusicRecognizer(),
      ),
      sessionFactory: (profile) {
        final library = LibraryRepository(db, profileId: profile.id);
        final notes = NotesRepository(db, profileId: profile.id);
        return ProfileSession(
          profile: profile,
          library: library,
          notes: notes,
          sync: SyncService(
            library: library,
            notes: notes,
            db: db,
            tokens: tokenStore(profile.id),
            profiles: profiles,
            auth: () => null,
            gistClient: (token) => GistClient(token),
          ),
        );
      },
      initialProfile: const Profile(
        id: AppDatabase.defaultProfileId,
        name: 'Основной',
        color: 0,
      ),
    );
    settings = AppSettings(services.preferences);
    translationEngine = MyMemoryEngine(
      usage: preferences.myMemoryUsage,
      saveUsage: preferences.setMyMemoryUsage,
      httpClient: MockClient((r) async {
        translateRequests.add(r.url);
        return translateHandler(r.url);
      }),
    );
  }

  /// Переводчик комментариев: по умолчанию MyMemory (как на ПК)
  /// с ответами [translateHandler].
  late TranslationEngine translationEngine;
  http.Response Function(Uri) translateHandler = (uri) => http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'responseStatus': 200,
        'responseData': {
          'translatedText': 'Перевод: ${uri.queryParameters['q']}',
        },
      }),
    ),
    200,
  );
  final translateRequests = <Uri>[];

  late final AppDatabase db;
  late final FakeAniList fake;
  final tokens = <int, MemoryTokenStore>{};

  /// Ответы `commentThreads.list` для тестов.
  http.Response Function(Uri) commentsHandler = (_) =>
      http.Response('{"items":[]}', 200);
  final commentRequests = <Uri>[];

  /// Источник видео для тестов: по умолчанию не настроен.
  final videoSource = FakeVideoSource();

  MemoryTokenStore tokenStore(int profileId) =>
      tokens.putIfAbsent(profileId, MemoryTokenStore.new);
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
    if (query.contains('query ByIds')) {
      final ids = (vars['ids'] as List).cast<int>().toSet();
      final page = jsonDecode(fixture('catalog_page_30.json')) as Map;
      final media = [
        for (final m in page['data']['Page']['media'] as List)
          if (ids.contains(m['id'])) m,
      ];
      return jsonResponse(
        jsonEncode({
          'data': {
            'Page': {
              'pageInfo': {'hasNextPage': false},
              'media': media,
            },
          },
        }),
      );
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

  /// Выполняет операцию с базой в тестовом времени: после запуска
  /// приложения обращения к базе из `runAsync` могут ждать блокировку,
  /// которую держит операция в тестовом времени.
  static Future<T> run<T>(WidgetTester tester, Future<T> Function() op) async {
    var done = false;
    late T value;
    Object? error;
    op().then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    for (var i = 0; i < 100 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (!done) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
    }
    if (!done) throw StateError('database operation did not complete');
    if (error != null) throw error!;
    return value;
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
    // Подписки drift закрываются по таймеру; ждём их в тестовом времени.
    await tester.pump(const Duration(seconds: 1));
    await run(tester, db.close);
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Источник видео с заранее заданными роликами.
class FakeVideoSource implements VideoSource {
  List<EmbeddedVideo> videos = const [];

  @override
  bool isConfigured = false;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake';

  @override
  Future<List<EmbeddedVideo>> find(AnimeDetails title) async => videos;
}

class _DelegatingEngine implements TranslationEngine {
  _DelegatingEngine(this._engine);

  final TranslationEngine Function() _engine;

  @override
  String? get server => _engine().server;

  @override
  Future<TranslationResult> translate(
    String text, {
    String? source,
    void Function(TranslationStage stage)? onStage,
  }) => _engine().translate(text, source: source, onStage: onStage);

  @override
  Future<void> close() async {}
}
