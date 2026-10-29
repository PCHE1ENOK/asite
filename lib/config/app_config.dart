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
}
