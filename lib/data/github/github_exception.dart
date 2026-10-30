/// Причина ошибки при работе с GitHub.
enum GitHubErrorKind {
  /// Нет сети или GitHub недоступен.
  network,

  /// Токен отозван или недействителен.
  unauthorized,

  /// Код устройства истёк.
  expired,

  /// Пользователь отклонил вход на GitHub.
  denied,

  /// Вход отменён в приложении.
  cancelled,

  /// Этот аккаунт GitHub уже привязан к другому профилю.
  accountInUse,

  /// Прочие ответы GitHub.
  other,
}

class GitHubException implements Exception {
  const GitHubException(this.kind, this.message, {this.statusCode});

  final GitHubErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GitHubException(${kind.name}): $message';
}
