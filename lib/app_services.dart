import 'config/app_config.dart';
import 'data/anilist/anilist_client.dart';
import 'data/anime_repository.dart';
import 'data/cache/app_database.dart';
import 'data/github/gist_client.dart';
import 'data/github/github_auth.dart';
import 'data/github/token_store.dart';
import 'data/library/library_repository.dart';
import 'data/music/music_recognition.dart';
import 'data/settings/app_preferences.dart';
import 'data/sync/sync_service.dart';

/// Сервисы приложения, общие для всех платформ.
class AppServices {
  AppServices({
    required this.db,
    required this.anime,
    required this.library,
    required this.preferences,
    required this.sync,
    required this.music,
  });

  factory AppServices.create() {
    final db = AppDatabase.open();
    final library = LibraryRepository(db);
    final preferences = AppPreferences(db);
    return AppServices(
      db: db,
      anime: AnimeRepository(client: AniListClient(), db: db),
      library: library,
      preferences: preferences,
      sync: SyncService(
        library: library,
        db: db,
        tokens: SecureTokenStore(),
        auth: () => AppConfig.hasGitHubClientId
            ? GitHubAuth(clientId: AppConfig.githubClientId)
            : null,
        gistClient: GistClient.new,
      ),
      // Этап 4.5: заглушка заменится распознавателем на Chromaprint +
      // AcoustID, звук — из AudioSnippetSource слоя источников.
      music: MusicRecognitionGate(
        isEnabled: preferences.musicRecognition,
        hasApiKey: AppConfig.hasAcoustIdApiKey,
        recognizer: const StubMusicRecognizer(),
      ),
    );
  }

  final AppDatabase db;
  final AnimeRepository anime;
  final LibraryRepository library;
  final AppPreferences preferences;
  final SyncService sync;

  /// Распознавание музыки в плеере.
  final MusicRecognizer music;
}
