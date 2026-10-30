import 'package:drift/drift.dart';

import '../cache/app_database.dart';

/// Профиль: имя, цвет аватара и привязка к GitHub.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.color,
    this.githubLogin,
  });

  final int id;
  final String name;

  /// Номер цвета аватара (0–4).
  final int color;
  final String? githubLogin;

  static Profile fromRow(ProfileRow r) => Profile(
    id: r.id,
    name: r.name,
    color: r.color,
    githubLogin: r.githubLogin,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.githubLogin == githubLogin;

  @override
  int get hashCode => Object.hash(id, name, color, githubLogin);
}

/// Ошибка при создании профиля или привязке GitHub.
class ProfileException implements Exception {
  const ProfileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Профили на устройстве.
class ProfileRepository {
  ProfileRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  static const maxNameLength = 20;
  static const colorCount = 5;
  static const _activeKey = 'active_profile';

  /// Префикс ключей настроек, которые принадлежат профилю.
  static String settingKey(int profileId, String key) => 'p$profileId:$key';

  Future<List<Profile>> all() async => [
    for (final r in await (_db.select(
      _db.profiles,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get())
      Profile.fromRow(r),
  ];

  Stream<List<Profile>> watchAll() =>
      (_db.select(_db.profiles)..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch()
          .map((rows) => [for (final r in rows) Profile.fromRow(r)]);

  Future<Profile?> byId(int id) async {
    final r = await (_db.select(
      _db.profiles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : Profile.fromRow(r);
  }

  /// Активный профиль; если сохранённого нет — первый по порядку.
  Future<Profile> active() async {
    final id = int.tryParse(await _db.setting(_activeKey) ?? '');
    final p = id == null ? null : await byId(id);
    return p ?? (await all()).first;
  }

  Future<void> setActive(int id) => _db.putSetting(_activeKey, '$id');

  /// Проверяет имя: не пустое, до 20 символов, уникальное.
  Future<String> validateName(String name, {int? exceptId}) async {
    final n = name.trim();
    if (n.isEmpty) throw const ProfileException('Введите имя профиля');
    if (n.length > maxNameLength) {
      throw const ProfileException('Имя профиля — не длиннее 20 символов');
    }
    // Сравнение в Dart: lower() в SQLite не знает кириллицу.
    final same = (await all())
        .where((p) => p.name.toLowerCase() == n.toLowerCase())
        .firstOrNull;
    if (same != null && same.id != exceptId) {
      throw const ProfileException('Профиль с таким именем уже есть');
    }
    return n;
  }

  Future<Profile> create(String name, {int color = 0}) async {
    final n = await validateName(name);
    final id = await _db
        .into(_db.profiles)
        .insert(
          ProfilesCompanion.insert(
            name: n,
            color: Value(color % colorCount),
            createdAt: _now(),
          ),
        );
    return (await byId(id))!;
  }

  /// Сколько тайтлов в списках профиля (без удалённых).
  Future<int> entryCount(int profileId) async {
    final count = _db.libraryEntries.mediaId.count();
    final row =
        await (_db.selectOnly(_db.libraryEntries)
              ..addColumns([count])
              ..where(
                _db.libraryEntries.profileId.equals(profileId) &
                    _db.libraryEntries.deleted.equals(false),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Привязывает логин GitHub. Один аккаунт — один профиль: если логин уже
  /// у другого профиля, бросает [GitHubAccountInUse].
  Future<void> bindGitHub(int profileId, String login) async {
    final other =
        await (_db.select(_db.profiles)..where(
              (t) =>
                  t.githubLogin.lower().equals(login.toLowerCase()) &
                  t.id.equals(profileId).not(),
            ))
            .getSingleOrNull();
    if (other != null) throw GitHubAccountInUse(Profile.fromRow(other));
    await (_db.update(_db.profiles)..where((t) => t.id.equals(profileId)))
        .write(ProfilesCompanion(githubLogin: Value(login)));
  }

  Future<void> unbindGitHub(int profileId) =>
      (_db.update(_db.profiles)..where((t) => t.id.equals(profileId))).write(
        const ProfilesCompanion(githubLogin: Value(null)),
      );

  /// Удаляет профиль и его локальные данные (списки и настройки профиля).
  /// Gist на GitHub не трогается. Токен удаляет вызывающий.
  /// Текущий и последний профиль удалить нельзя.
  Future<void> delete(int profileId) async {
    final active = await this.active();
    if (active.id == profileId) {
      throw const ProfileException(
        'Это текущий профиль — сначала переключитесь на другой',
      );
    }
    if ((await all()).length <= 1) {
      throw const ProfileException('Нельзя удалить последний профиль');
    }
    await _db.transaction(() async {
      await (_db.delete(
        _db.libraryEntries,
      )..where((t) => t.profileId.equals(profileId))).go();
      await (_db.delete(
        _db.notes,
      )..where((t) => t.profileId.equals(profileId))).go();
      await (_db.delete(
        _db.settings,
      )..where((t) => t.key.like('p$profileId:%'))).go();
      await (_db.delete(
        _db.profiles,
      )..where((t) => t.id.equals(profileId))).go();
    });
  }
}

/// Аккаунт GitHub уже привязан к другому профилю.
class GitHubAccountInUse implements Exception {
  const GitHubAccountInUse(this.profile);

  final Profile profile;

  String get message =>
      'Этот аккаунт уже привязан к профилю «${profile.name}». '
      'Один аккаунт GitHub — один профиль, иначе списки разных людей смешаются.';

  @override
  String toString() => message;
}
