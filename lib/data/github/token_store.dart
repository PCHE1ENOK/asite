import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранилище токена GitHub.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Токен в защищённом хранилище платформы (Keychain, Keystore,
/// Windows Credential Manager).
/// У каждого профиля свой токен.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({required this.profileId, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final int profileId;
  final FlutterSecureStorage _storage;

  /// Ключ до появления профилей; его токен принадлежит профилю 1.
  static const _legacyKey = 'github_token';

  String get _key => 'github_token_p$profileId';

  @override
  Future<String?> read() async {
    final token = await _storage.read(key: _key);
    if (token != null || profileId != 1) return token;
    final legacy = await _storage.read(key: _legacyKey);
    if (legacy != null) {
      await _storage.write(key: _key, value: legacy);
      await _storage.delete(key: _legacyKey);
    }
    return legacy;
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Токен в памяти, для тестов.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}
