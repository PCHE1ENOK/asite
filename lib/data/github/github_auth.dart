import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_exception.dart';

/// Код устройства для входа через GitHub Device Flow.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;

  /// Код, который пользователь вводит на [verificationUri].
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration interval;
}

/// Вход через GitHub OAuth Device Flow.
///
/// https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
/// Client secret не нужен. Запрашивается только scope `gist`.
class GitHubAuth {
  GitHubAuth({
    required this.clientId,
    http.Client? httpClient,
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _delay = delay ?? Future<void>.delayed,
       _now = clock ?? DateTime.now;

  final String clientId;
  final http.Client _http;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  static const scope = 'gist';
  static final _codeUri = Uri.parse('https://github.com/login/device/code');
  static final _tokenUri = Uri.parse(
    'https://github.com/login/oauth/access_token',
  );

  Future<DeviceCode> requestCode() async {
    final json = await _post(_codeUri, {'client_id': clientId, 'scope': scope});
    final error = json['error'] as String?;
    if (error != null) throw _error(error, json);
    return DeviceCode(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: Uri.parse(json['verification_uri'] as String),
      expiresAt: _now().add(Duration(seconds: json['expires_in'] as int)),
      interval: Duration(seconds: json['interval'] as int? ?? 5),
    );
  }

  /// Опрашивает GitHub, пока пользователь не подтвердит вход.
  /// Возвращает токен доступа. [isCancelled] проверяется перед каждым
  /// запросом.
  Future<String> waitForToken(
    DeviceCode code, {
    bool Function()? isCancelled,
  }) async {
    var interval = code.interval;
    while (true) {
      await _delay(interval);
      if (isCancelled?.call() ?? false) {
        throw const GitHubException(GitHubErrorKind.cancelled, 'Вход отменён');
      }
      if (_now().isAfter(code.expiresAt)) {
        throw const GitHubException(GitHubErrorKind.expired, 'Код устарел');
      }
      final json = await _post(_tokenUri, {
        'client_id': clientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final token = json['access_token'] as String?;
      if (token != null) return token;

      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          final next = json['interval'] as int?;
          interval = next != null
              ? Duration(seconds: next)
              : interval + const Duration(seconds: 5);
        case final String error:
          throw _error(error, json);
        default:
          throw const GitHubException(
            GitHubErrorKind.other,
            'Некорректный ответ GitHub',
          );
      }
    }
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, String> body) async {
    final http.Response response;
    try {
      response = await _http
          .post(uri, headers: const {'Accept': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const GitHubException(GitHubErrorKind.network, 'Нет ответа');
    } on http.ClientException catch (e) {
      throw GitHubException(GitHubErrorKind.network, e.message);
    }
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Ниже.
    }
    throw GitHubException(
      response.statusCode >= 500
          ? GitHubErrorKind.network
          : GitHubErrorKind.other,
      'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  static GitHubException _error(String error, Map<String, dynamic> json) {
    final message = json['error_description'] as String? ?? error;
    return GitHubException(switch (error) {
      'expired_token' => GitHubErrorKind.expired,
      'access_denied' => GitHubErrorKind.denied,
      _ => GitHubErrorKind.other,
    }, message);
  }
}
