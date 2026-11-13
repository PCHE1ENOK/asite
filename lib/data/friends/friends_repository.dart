import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../github/gist_client.dart';
import '../github/github_exception.dart';
import '../models/library_entry.dart';
import '../profiles/profile_repository.dart';
import '../share/share_codec.dart';

/// Друг: пользователь GitHub с публичным каталогом. Хранится локально в
/// профиле.
@immutable
class Friend {
  const Friend({required this.login, this.avatarUrl, required this.addedAt});

  final String login;
  final String? avatarUrl;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'login': login,
    'avatarUrl': ?avatarUrl,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  static Friend? fromJson(Object? json) {
    if (json is! Map || json['login'] is! String) return null;
    return Friend(
      login: json['login'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.utc(1970),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Friend &&
      other.login == login &&
      other.avatarUrl == avatarUrl &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(login, avatarUrl, addedAt);
}

/// Заметка друга о тайтле (как в его файле).
class FriendNote {
  const FriendNote({
    required this.verdict,
    this.summary = '',
    this.liked = const [],
    this.dropReasons = const [],
    this.dropText = '',
    this.moments = const [],
  });

  /// `rewatch`, `recommend`, `not`, `none`.
  final String verdict;
  final String summary;
  final List<String> liked;
  final List<String> dropReasons;
  final String dropText;

  /// `(серия, время «12:34» или null, текст)`.
  final List<(int, String?, String)> moments;

  bool get isEmpty =>
      summary.isEmpty &&
      liked.isEmpty &&
      dropReasons.isEmpty &&
      dropText.isEmpty &&
      moments.isEmpty &&
      verdict == 'none';

  static FriendNote? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> strings(Object? v) => [
      if (v is List)
        for (final s in v)
          if (s is String) s,
    ];
    return FriendNote(
      verdict: json['verdict'] as String? ?? 'none',
      summary: json['summary'] as String? ?? '',
      liked: strings(json['liked']),
      dropReasons: strings(json['dropReasons']),
      dropText: json['dropText'] as String? ?? '',
      moments: [
        if (json['moments'] case final List list)
          for (final m in list)
            if (m is Map && m['episode'] is int && m['text'] is String)
              (m['episode'] as int, m['time'] as String?, m['text'] as String),
      ],
    );
  }
}

/// Тайтл из каталога друга.
class FriendTitle {
  const FriendTitle({
    required this.id,
    required this.title,
    this.cover,
    this.format,
    this.year,
    this.episodes,
    this.score,
    this.scoreSource,
    this.status,
    this.progress = 0,
    this.favorite = false,
    this.adult = false,
    this.note,
  });

  final int id;
  final String title;
  final String? cover;
  final String? format;
  final int? year;
  final int? episodes;
  final double? score;

  /// `shikimori` или `anilist`.
  final String? scoreSource;
  final ListStatus? status;
  final int progress;
  final bool favorite;
  final bool adult;
  final FriendNote? note;

  static FriendTitle? fromJson(Object? json) {
    if (json is! Map || json['id'] is! int) return null;
    final t = json['title'] as Map? ?? const {};
    final name =
        (t['ru'] ?? t['en'] ?? t['romaji']) as String? ?? '#${json['id']}';
    final score = json['score'] as Map?;
    return FriendTitle(
      id: json['id'] as int,
      title: name,
      cover: json['cover'] as String?,
      format: json['format'] as String?,
      year: json['year'] as int?,
      episodes: json['episodes'] as int?,
      score: (score?['value'] as num?)?.toDouble(),
      scoreSource: score?['source'] as String?,
      status: ListStatus.fromApi(json['status'] as String?),
      progress: json['progress'] as int? ?? 0,
      favorite: json['favorite'] == true,
      adult: json['adult'] == true,
      note: FriendNote.fromJson(json['note']),
    );
  }
}

/// Каталог друга из его `anime-viewer-share.json`.
class FriendCatalog {
  const FriendCatalog({
    required this.owner,
    required this.titles,
    this.updatedAt,
  });

  /// Имя профиля, как у друга в приложении.
  final String owner;
  final DateTime? updatedAt;
  final List<FriendTitle> titles;

  /// Разбор `share.json` v1: неизвестные поля игнорируются, битые записи
  /// пропускаются (как на странице docs/friends).
  static FriendCatalog parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map || json['titles'] is! List) {
      throw const FormatException('Не каталог Anime Viewer');
    }
    return FriendCatalog(
      owner: json['owner'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      titles: [
        for (final t in json['titles'] as List) ?FriendTitle.fromJson(t),
      ],
    );
  }
}

/// Итог поиска друга по нику.
sealed class FriendLookup {
  const FriendLookup();
}

class FriendFound extends FriendLookup {
  const FriendFound({
    required this.login,
    required this.avatarUrl,
    required this.titleCount,
  });

  final String login;
  final String? avatarUrl;
  final int titleCount;
}

/// Нет пользователя или у него нет публичного каталога.
class FriendNotFound extends FriendLookup {
  const FriendNotFound();
}

/// Поиск без входа недоступен (лимит 60 запросов в час на адрес).
class FriendSignInRequired extends FriendLookup {
  const FriendSignInRequired();
}

class FriendRateLimited extends FriendLookup {
  const FriendRateLimited();
}

class FriendLookupFailed extends FriendLookup {
  const FriendLookupFailed();
}

/// Друзья профиля: список (локально, в настройках профиля), поиск по нику
/// GitHub и каталоги друзей из их публичных Gist (кэш — час).
class FriendsRepository {
  FriendsRepository(
    this._db, {
    required this.profileId,
    required this._token,
    GistClient Function(String token)? gistClient,
    this.ttl = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _gistClient = gistClient ?? GistClient.new,
       _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final int profileId;
  final String? Function() _token;
  final GistClient Function(String token) _gistClient;
  final Duration ttl;
  final DateTime Function() _now;

  String get _listKey => ProfileRepository.settingKey(profileId, 'friends');
  String _catalogKey(String login) =>
      'friend:$profileId:${login.toLowerCase()}';

  /// Список друзей; загружается при первом [load].
  final friends = ValueNotifier<List<Friend>>(const []);
  bool _loaded = false;

  Future<List<Friend>> load() async {
    if (_loaded) return friends.value;
    final raw = await _db.setting(_listKey);
    final list = <Friend>[];
    if (raw != null) {
      try {
        for (final f in jsonDecode(raw) as List) {
          if (Friend.fromJson(f) case final friend?) list.add(friend);
        }
      } on FormatException {
        // Битая запись — пустой список.
      }
    }
    _loaded = true;
    return friends.value = list;
  }

  Future<void> _save(List<Friend> list) async {
    friends.value = list;
    await _db.putSetting(
      _listKey,
      jsonEncode([for (final f in list) f.toJson()]),
    );
  }

  bool contains(String login) =>
      friends.value.any((f) => f.login.toLowerCase() == login.toLowerCase());

  Future<void> add(FriendFound found) async {
    await load();
    if (contains(found.login)) return;
    await _save([
      ...friends.value,
      Friend(
        login: found.login,
        avatarUrl: found.avatarUrl,
        addedAt: _now().toUtc(),
      ),
    ]);
  }

  /// Возвращает удалённого друга («Отменить»).
  Future<void> restore(Friend friend) async {
    await load();
    if (contains(friend.login)) return;
    await _save([...friends.value, friend]);
  }

  /// Удаление — только из своего списка; у друга ничего не меняется.
  Future<void> remove(String login) async {
    await load();
    await _save([
      for (final f in friends.value)
        if (f.login.toLowerCase() != login.toLowerCase()) f,
    ]);
    await _db.putSetting('${_catalogKey(login)}:gist', null);
  }

  /// Ищет публичный каталог пользователя GitHub [rawLogin].
  Future<FriendLookup> find(String rawLogin) async {
    final login = rawLogin.trim().replaceFirst(RegExp('^@'), '');
    if (login.isEmpty || !RegExp(r'^[A-Za-z0-9-]{1,39}$').hasMatch(login)) {
      return const FriendNotFound();
    }
    final token = _token();
    if (token == null) return const FriendSignInRequired();
    final client = _gistClient(token);
    try {
      final user = await client.user(login);
      if (user == null) return const FriendNotFound();
      final gist = await client.findPublicGist(user.login, ShareCodec.fileName);
      if (gist == null) return const FriendNotFound();
      final text = await client.readFile(gist, ShareCodec.fileName);
      if (text == null) return const FriendNotFound();
      final catalog = FriendCatalog.parse(text);
      await _cache(user.login, gist, text);
      return FriendFound(
        login: user.login,
        avatarUrl: user.avatarUrl,
        titleCount: catalog.titles.length,
      );
    } on GitHubException catch (e) {
      return e.kind == GitHubErrorKind.rateLimited
          ? const FriendRateLimited()
          : const FriendLookupFailed();
    } on FormatException {
      return const FriendNotFound();
    } finally {
      client.close();
    }
  }

  Future<void> _cache(String login, String gist, String text) async {
    await _db.putEntry(_catalogKey(login), text, _now());
    await _db.putSetting('${_catalogKey(login)}:gist', gist);
  }

  /// Каталог друга: из кэша, если ему меньше [ttl], иначе из его Gist.
  /// Без сети и при лимите — устаревший кэш, если есть.
  Future<FriendCatalog> catalog(String login, {bool force = false}) async {
    final key = _catalogKey(login);
    final cached = await _db.entry(key);
    if (!force && cached != null && _now().difference(cached.updatedAt) < ttl) {
      return FriendCatalog.parse(cached.payload);
    }
    final token = _token();
    try {
      if (token == null) {
        throw const GitHubException(
          GitHubErrorKind.unauthorized,
          'Войдите через GitHub, чтобы смотреть каталоги друзей',
        );
      }
      final client = _gistClient(token);
      try {
        var gist = await _db.setting('$key:gist');
        String? text;
        if (gist != null) {
          try {
            text = await client.readFile(gist, ShareCodec.fileName);
          } on GitHubException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
        }
        if (text == null) {
          // Друг пересоздал публикацию — ищем заново.
          gist = await client.findPublicGist(login, ShareCodec.fileName);
          if (gist != null) {
            text = await client.readFile(gist, ShareCodec.fileName);
          }
        }
        if (gist == null || text == null) {
          throw const GitHubException(
            GitHubErrorKind.other,
            'Друг больше не показывает каталог',
            statusCode: 404,
          );
        }
        final parsed = FriendCatalog.parse(text);
        await _cache(login, gist, text);
        return parsed;
      } finally {
        client.close();
      }
    } on GitHubException catch (e) {
      if (cached != null && e.statusCode != 404) {
        return FriendCatalog.parse(cached.payload);
      }
      rethrow;
    }
  }

  void dispose() => friends.dispose();
}
