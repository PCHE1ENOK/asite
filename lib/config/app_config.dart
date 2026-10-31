/// Настройки сборки, передаются через `--dart-define`.
abstract final class AppConfig {
  /// Client ID OAuth-приложения GitHub для входа через Device Flow
  /// (хранение списков пользователя в приватном Gist).
  ///
  /// `flutter run --dart-define=GITHUB_CLIENT_ID=<id>`. Client secret
  /// для Device Flow не нужен и в приложение не попадает.
  static const githubClientId = String.fromEnvironment('GITHUB_CLIENT_ID');

  static bool get hasGitHubClientId => githubClientId.isNotEmpty;

  /// Ключ приложения AcoustID (бесплатный, регистрируется один раз на
  /// acoustid.org и переиспользуется). Используется распознаванием музыки
  /// (этап 4.5); без ключа распознавание недоступно.
  static const acoustIdApiKey = String.fromEnvironment('ACOUSTID_API_KEY');

  static bool get hasAcoustIdApiKey => acoustIdApiKey.isNotEmpty;

  /// Ключ YouTube Data API v3 для поиска официальных видео правообладателей
  /// (этап 6). Без ключа источник YouTube пустой и в сеть не ходит.
  static const youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  /// Страница просмотра каталога для друзей (GitHub Pages из `docs/`).
  /// Данных в ней нет: она читает `share.json` из Gist по `?g=<id>`.
  static const sharePageUrl = String.fromEnvironment(
    'SHARE_PAGE_URL',
    defaultValue: 'https://pche1enok.github.io/asite/friends/',
  );

  /// Ссылка для друзей на каталог в Gist [gistId].
  static Uri shareLink(String gistId) =>
      Uri.parse(sharePageUrl).replace(queryParameters: {'g': gistId});
}
