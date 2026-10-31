import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config/app_config.dart';
import 'data/anilist/anilist_client.dart';
import 'data/anime_repository.dart';
import 'data/cache/app_database.dart';
import 'data/github/gist_client.dart';
import 'data/github/github_auth.dart';
import 'data/github/token_store.dart';
import 'data/library/library_repository.dart';
import 'data/music/music_recognition.dart';
import 'data/notes/notes_repository.dart';
import 'data/profiles/profile_repository.dart';
import 'data/settings/app_preferences.dart';
import 'data/sources/video_source.dart';
import 'data/sources/youtube_comments.dart';
import 'data/sources/youtube_source.dart';
import 'data/sync/sync_service.dart';
import 'data/translation/mlkit_translation.dart';
import 'data/translation/translation.dart';
import 'data/shikimori/russian_text.dart';
import 'data/shikimori/shikimori_client.dart';

/// Списки и синхронизация одного профиля.
class ProfileSession {
  ProfileSession({
    required this.profile,
    required this.library,
    required this.notes,
    required this.sync,
  });

  final Profile profile;
  final LibraryRepository library;

  /// Личные заметки о тайтлах.
  final NotesRepository notes;
  final SyncService sync;
}

/// Сервисы приложения, общие для всех платформ. Списки и синхронизация
/// принадлежат активному профилю ([session]) и пересоздаются при
/// переключении.
class AppServices {
  AppServices({
    required this.db,
    required this.anime,
    required this.preferences,
    required this.profiles,
    required this.music,
    required this.sources,
    required this.comments,
    required this.translator,
    required this.shiki,
    required this.tokensFor,
    required ProfileSession Function(Profile) sessionFactory,
    required Profile initialProfile,
  }) : _sessionFactory = sessionFactory,
       session = ValueNotifier(sessionFactory(initialProfile));

  /// Сервисы для приложения: база в каталоге данных, сеть, токены в
  /// защищённом хранилище.
  static Future<AppServices> open() async {
    final db = AppDatabase.open();
    final profiles = ProfileRepository(db);
    final preferences = AppPreferences(db);
    TokenStore tokensFor(int id) => SecureTokenStore(profileId: id);
    return AppServices(
      db: db,
      anime: AnimeRepository(client: AniListClient(), db: db),
      preferences: preferences,
      profiles: profiles,
      tokensFor: tokensFor,
      // Этап 6: официальные бесплатные видео правообладателей на YouTube,
      // только через встроенный плеер YouTube.
      sources: VideoSources([
        YouTubeSource(
          apiKey: AppConfig.youtubeApiKey,
          db: db,
          regionCode: PlatformDispatcher.instance.locale.countryCode,
        ),
      ]),
      comments: YouTubeCommentsClient(apiKey: AppConfig.youtubeApiKey),
      translator: _translator(preferences),
      shiki: ShikimoriData(
        RussianTextRepository(db: db, client: ShikimoriClient()),
      ),
      // Этап 4.5: заглушка заменится распознавателем на Chromaprint +
      // AcoustID, звук — из AudioSnippetSource слоя источников.
      music: MusicRecognitionGate(
        isEnabled: preferences.musicRecognition,
        hasApiKey: AppConfig.hasAcoustIdApiKey,
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
            tokens: tokensFor(profile.id),
            profiles: profiles,
            auth: () => AppConfig.hasGitHubClientId
                ? GitHubAuth(clientId: AppConfig.githubClientId)
                : null,
            gistClient: GistClient.new,
          ),
        );
      },
      initialProfile: await profiles.active(),
    );
  }

  final AppDatabase db;
  final AnimeRepository anime;
  final AppPreferences preferences;
  final ProfileRepository profiles;

  /// Распознавание музыки в плеере.
  final MusicRecognizer music;

  /// Легальные источники видео.
  final VideoSources sources;

  /// Комментарии к официальным роликам YouTube.
  final YouTubeCommentsClient comments;

  /// Перевод комментариев на русский.
  final CommentTranslator translator;

  /// Русские названия и описания (Shikimori).
  final ShikimoriData shiki;

  /// Телефон — ML Kit на устройстве; ПК — бесплатный MyMemory
  /// (ML Kit на ПК не работает).
  static CommentTranslator _translator(AppPreferences preferences) {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (mobile) {
      final detector = MlKitLanguageDetector();
      return CommentTranslator(
        detector: detector,
        engine: MlKitEngine(detector: detector),
      );
    }
    return CommentTranslator(
      detector: const ScriptLanguageDetector(),
      engine: MyMemoryEngine(
        usage: preferences.myMemoryUsage,
        saveUsage: preferences.setMyMemoryUsage,
      ),
    );
  }

  /// Хранилище токена GitHub профиля.
  final TokenStore Function(int profileId) tokensFor;
  final ProfileSession Function(Profile) _sessionFactory;

  /// Активный профиль со своими списками и синхронизацией.
  final ValueNotifier<ProfileSession> session;

  Profile get profile => session.value.profile;
  LibraryRepository get library => session.value.library;
  NotesRepository get notes => session.value.notes;
  SyncService get sync => session.value.sync;

  /// Переключает профиль: синхронизация старого останавливается, новый
  /// синхронизируется сразу.
  Future<void> switchProfile(int profileId) async {
    if (profileId == profile.id) return;
    final next = await profiles.byId(profileId);
    if (next == null) return;
    final old = session.value;
    await profiles.setActive(profileId);
    session.value = _sessionFactory(next);
    await old.sync.dispose();
    unawaited(session.value.sync.start());
  }

  /// Создаёт профиль и сразу переключается на него.
  Future<Profile> addProfile(String name, {int color = 0}) async {
    final p = await profiles.create(name, color: color);
    await switchProfile(p.id);
    return p;
  }

  /// Удаляет профиль с устройства: списки, настройки и токен. Gist на
  /// GitHub не трогается.
  Future<void> deleteProfile(int profileId) async {
    await profiles.delete(profileId);
    await tokensFor(profileId).delete();
  }
}
