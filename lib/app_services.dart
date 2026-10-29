import 'config/app_config.dart';
import 'data/anilist/anilist_client.dart';
import 'data/anime_repository.dart';
import 'data/cache/app_database.dart';
import 'data/github/gist_client.dart';
import 'data/github/github_auth.dart';
import 'data/github/token_store.dart';
import 'data/library/library_repository.dart';
import 'data/settings/app_preferences.dart';
import 'data/sync/sync_service.dart';

/// Сервисы приложения, общие для всех платформ.
class AppServices {
  AppServices._({
    required this.db,
    required this.anime,
    required this.library,
    required this.preferences,
    required this.sync,
  });

  factory AppServices.create() {
    final db = AppDatabase.open();
    final library = LibraryRepository(db);
    return AppServices._(
      db: db,
      anime: AnimeRepository(client: AniListClient(), db: db),
      library: library,
      preferences: AppPreferences(db),
      sync: SyncService(
        library: library,
        db: db,
        tokens: SecureTokenStore(),
        auth: () => AppConfig.hasGitHubClientId
            ? GitHubAuth(clientId: AppConfig.githubClientId)
            : null,
        gistClient: GistClient.new,
      ),
    );
  }

  final AppDatabase db;
  final AnimeRepository anime;
  final LibraryRepository library;
  final AppPreferences preferences;
  final SyncService sync;
}
