import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../github/gist_client.dart';
import '../github/github_auth.dart';
import '../github/github_exception.dart';
import '../github/token_store.dart';
import '../favorites/favorites_repository.dart';
import '../library/library_repository.dart';
import '../models/favorite.dart';
import '../models/title_note.dart';
import '../notes/notes_repository.dart';
import '../profiles/profile_repository.dart';
import '../share/share_codec.dart';
import 'library_codec.dart';
import 'library_merge.dart';

enum SyncStatus { signedOut, synced, pending, syncing, error }

/// Глобальное состояние синхронизации для точки на профиле и `SyncBar`.
@immutable
/// Показ каталога друзьям: секретный Gist с `share.json`.
class ShareState {
  const ShareState({this.gistId, this.updatedAt, this.error});

  /// `null` — каталог не показывается.
  final String? gistId;
  final DateTime? updatedAt;

  /// Последняя ошибка обновления (показ при этом продолжается).
  final String? error;

  bool get isSharing => gistId != null;
}

class SyncState {
  const SyncState({
    required this.status,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.login,
    this.error,
  });

  const SyncState.signedOut({this.pendingCount = 0, this.error})
    : status = SyncStatus.signedOut,
      lastSyncedAt = null,
      login = null;

  final SyncStatus status;

  /// Сколько изменений ждут отправки.
  final int pendingCount;
  final DateTime? lastSyncedAt;

  /// Логин GitHub.
  final String? login;
  final GitHubException? error;

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.status == status &&
      other.pendingCount == pendingCount &&
      other.lastSyncedAt == lastSyncedAt &&
      other.login == login &&
      other.error?.kind == error?.kind;

  @override
  int get hashCode =>
      Object.hash(status, pendingCount, lastSyncedAt, login, error?.kind);

  @override
  String toString() => 'SyncState(${status.name}, pending: $pendingCount)';
}

/// Итог первого входа, для шага «Готово».
class SignInResult {
  const SignInResult({
    required this.login,
    required this.gistCreated,
    required this.entryCount,
    required this.conflicts,
  });

  final String login;

  /// `true` — создан новый Gist, `false` — найден существующий.
  final bool gistCreated;

  /// Сколько тайтлов в списках после объединения.
  final int entryCount;

  /// По скольким тайтлам взята более свежая запись.
  final int conflicts;
}

/// Синхронизация списков с приватным GitHub Gist.
///
/// Локальная база — источник правды на устройстве. Синхронизация
/// запускается при старте приложения ([start]) и через [debounce] после
/// локального изменения, пока приложение открыто; фонового расписания нет
/// (ограничение iOS).
class SyncService {
  SyncService({
    required this._library,
    required this._db,
    required this._tokens,
    required this._auth,
    required this._gistClient,
    required this.profiles,
    this.notes,
    this.favorites,
    this.buildShare,
    this.shareInterval = const Duration(minutes: 5),
    this.debounce = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final LibraryRepository _library;
  final AppDatabase _db;
  final TokenStore _tokens;
  final GitHubAuth? Function() _auth;
  final GistClient Function(String token) _gistClient;
  final Duration debounce;
  final DateTime Function() _now;

  /// Профили: привязка логина GitHub к профилю списков.
  final ProfileRepository profiles;

  /// Заметки о тайтлах; синхронизируются в том же файле Gist.
  final NotesRepository? notes;

  /// «Понравилось»; в том же файле Gist.
  final FavoritesRepository? favorites;

  /// Собирает `share.json` (каталог для друзей); `null` — показ недоступен.
  final Future<String> Function()? buildShare;

  /// `share.json` обновляется не чаще, чем раз в [shareInterval].
  final Duration shareInterval;

  int get profileId => _library.profileId;

  String get _gistIdKey =>
      ProfileRepository.settingKey(profileId, 'sync_gist_id');
  String get _loginKey => ProfileRepository.settingKey(profileId, 'sync_login');
  String get _lastSyncedKey =>
      ProfileRepository.settingKey(profileId, 'sync_last_synced_at');

  final state = ValueNotifier<SyncState>(const SyncState.signedOut());

  /// Показ каталога друзьям.
  final share = ValueNotifier<ShareState>(const ShareState());

  String get _shareIdKey =>
      ProfileRepository.settingKey(profileId, 'share_gist_id');
  String get _shareAtKey =>
      ProfileRepository.settingKey(profileId, 'share_updated_at');
  bool _shareDirty = false;
  Timer? _shareTimer;

  String? _token;
  Timer? _debounceTimer;
  Future<void>? _running;
  bool _rerun = false;
  StreamSubscription<int>? _pendingSub;
  StreamSubscription<int>? _notesPendingSub;
  StreamSubscription<int>? _favoritesPendingSub;
  int _libraryPending = 0;
  int _notesPending = 0;
  int _favoritesPending = 0;

  int get _allPending => _libraryPending + _notesPending + _favoritesPending;
  bool _lastHadGist = false;
  int _lastConflicts = 0;

  /// Можно ли войти: задан ли Client ID OAuth-приложения.
  bool get canSignIn => _auth() != null;

  /// Загружает токен, подписывается на изменения и синхронизирует.
  Future<void> start() async {
    _token = await _tokens.read();
    _library.onChanged = _scheduleSync;
    notes?.onChanged = _scheduleSync;
    favorites?.onChanged = _scheduleSync;
    _pendingSub ??= _library.watchPendingCount().listen((c) {
      _libraryPending = c;
      _onPendingChanged(_allPending);
    });
    _notesPendingSub ??= notes?.watchPendingCount().listen((c) {
      _notesPending = c;
      _onPendingChanged(_allPending);
    });
    _favoritesPendingSub ??= favorites?.watchPendingCount().listen((c) {
      _favoritesPending = c;
      _onPendingChanged(_allPending);
    });
    final shareId = await _db.setting(_shareIdKey);
    if (shareId != null) {
      share.value = ShareState(
        gistId: shareId,
        updatedAt: DateTime.tryParse(await _db.setting(_shareAtKey) ?? ''),
      );
    }
    await _publishIdle();
    if (_token != null) await syncNow();
  }

  /// Создаёт секретный Gist с `share.json` и возвращает его id. Ссылку на
  /// страницу просмотра собирает интерфейс.
  Future<String> startSharing() async {
    final token = _token;
    final build = buildShare;
    if (token == null || build == null) {
      throw const GitHubException(
        GitHubErrorKind.unauthorized,
        'Войдите через GitHub, чтобы поделиться каталогом',
      );
    }
    if (share.value.gistId case final id?) return id;
    final client = _gistClient(token);
    try {
      final id = await client.createGist(
        fileName: ShareCodec.fileName,
        content: await build(),
        description: ShareCodec.description,
      );
      final now = _now().toUtc();
      await _db.putSetting(_shareIdKey, id);
      await _db.putSetting(_shareAtKey, now.toIso8601String());
      _shareDirty = false;
      share.value = ShareState(gistId: id, updatedAt: now);
      return id;
    } finally {
      client.close();
    }
  }

  /// «Прекратить показ»: Gist удаляется, ссылка перестаёт работать.
  Future<void> stopSharing() async {
    final id = share.value.gistId;
    if (id == null) return;
    _shareTimer?.cancel();
    final token = _token;
    if (token != null) {
      final client = _gistClient(token);
      try {
        await client.deleteGist(id);
      } finally {
        client.close();
      }
    }
    await _db.putSetting(_shareIdKey, null);
    await _db.putSetting(_shareAtKey, null);
    share.value = const ShareState();
  }

  /// Переписывает `share.json` после изменений, не чаще [shareInterval];
  /// раньше срока — откладывает до его конца.
  Future<void> _updateShare() async {
    final id = share.value.gistId;
    final token = _token;
    final build = buildShare;
    if (id == null || token == null || build == null || !_shareDirty) return;
    final last = share.value.updatedAt;
    final wait = last == null
        ? Duration.zero
        : shareInterval - _now().toUtc().difference(last);
    if (wait > Duration.zero) {
      _shareTimer ??= Timer(wait, () {
        _shareTimer = null;
        unawaited(_updateShare());
      });
      return;
    }
    final client = _gistClient(token);
    try {
      await client.writeFile(id, ShareCodec.fileName, await build());
      final now = _now().toUtc();
      await _db.putSetting(_shareAtKey, now.toIso8601String());
      _shareDirty = false;
      share.value = ShareState(gistId: id, updatedAt: now);
    } on GitHubException catch (e) {
      share.value = ShareState(
        gistId: id,
        updatedAt: share.value.updatedAt,
        error: e.message,
      );
    } finally {
      client.close();
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _shareTimer?.cancel();
    await _pendingSub?.cancel();
    await _notesPendingSub?.cancel();
    await _favoritesPendingSub?.cancel();
    _library.onChanged = null;
    notes?.onChanged = null;
    favorites?.onChanged = null;
    state.dispose();
    share.dispose();
  }

  /// Шаг 2 входа: получить код устройства.
  Future<DeviceCode> requestDeviceCode() {
    final auth = _auth();
    if (auth == null) {
      throw const GitHubException(
        GitHubErrorKind.other,
        'Не задан GITHUB_CLIENT_ID',
      );
    }
    return auth.requestCode();
  }

  /// Ждёт подтверждения на GitHub, сохраняет токен и объединяет списки
  /// устройства и Gist (без диалога, решение пользователя).
  Future<SignInResult> completeSignIn(
    DeviceCode code, {
    bool Function()? isCancelled,
  }) async {
    final token = await _auth()!.waitForToken(code, isCancelled: isCancelled);
    final client = _gistClient(token);
    final String login;
    try {
      login = await client.currentLogin();
    } finally {
      client.close();
    }

    // Один аккаунт GitHub — один профиль: иначе списки разных людей
    // смешаются. Токен не сохраняем, списки профиля не трогаем.
    try {
      await profiles.bindGitHub(profileId, login);
    } on GitHubAccountInUse catch (e) {
      throw GitHubException(
        GitHubErrorKind.accountInUse,
        e.message,
        conflictProfileId: e.profile.id,
        conflictProfileName: e.profile.name,
      );
    }

    // Новый аккаунт: старая привязка к Gist не годится.
    await _db.putSetting(_gistIdKey, null);
    await _tokens.write(token);
    _token = token;
    await _db.putSetting(_loginKey, login);

    final hadGist = await syncNow().then((_) => _lastHadGist);
    final error = state.value.error;
    if (state.value.status == SyncStatus.error && error != null) throw error;

    final entries = await _library.allForSync();
    return SignInResult(
      login: login,
      gistCreated: !hadGist,
      entryCount: entries.where((e) => !e.deleted).length,
      conflicts: _lastConflicts,
    );
  }

  /// Выход: токен удаляется, списки остаются на устройстве, Gist — на GitHub.
  Future<void> signOut() async {
    _debounceTimer?.cancel();
    await _tokens.delete();
    _token = null;
    await _db.putSetting(_gistIdKey, null);
    await _db.putSetting(_loginKey, null);
    await _db.putSetting(_lastSyncedKey, null);
    await profiles.unbindGitHub(profileId);
    await _publishIdle();
  }

  /// Синхронизирует сейчас. Параллельные вызовы объединяются.
  Future<void> syncNow() {
    _debounceTimer?.cancel();
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    return _running = _runLoop().whenComplete(() => _running = null);
  }

  Future<void> _runLoop() async {
    do {
      _rerun = false;
      await _syncOnce();
    } while (_rerun && _token != null);
  }

  Future<void> _syncOnce() async {
    final token = _token;
    if (token == null) return _publishIdle();

    _set(
      SyncState(
        status: SyncStatus.syncing,
        pendingCount: state.value.pendingCount,
        lastSyncedAt: state.value.lastSyncedAt,
        login: await _db.setting(_loginKey),
      ),
    );

    final client = _gistClient(token);
    try {
      final (gistId, remoteFile) = await _loadRemote(client);
      final remote = remoteFile.entries;
      final local = await _library.allForSync();
      final merge = mergeLibraries(local, remote);
      final notesMerge = await _mergeNotes(remoteFile.notes);
      final favMerge = await _mergeFavorites(remoteFile.favorites);
      _lastHadGist = gistId != null;
      _lastConflicts = merge.conflicts;

      final remoteById = {for (final e in remote) e.mediaId: e};
      final localSnapshot = {for (final e in local) e.mediaId: e};
      await _library.applyMerged(
        merge.localChanged,
        snapshot: localSnapshot,
        isClean: (e) => remoteById[e.mediaId] == e,
      );

      final content = LibraryCodec.encode(
        merge.entries,
        notes: notesMerge?.entries ?? const [],
        favorites: favMerge?.entries ?? const [],
      );
      if (gistId == null) {
        final id = await client.createGist(
          fileName: LibraryCodec.fileName,
          content: content,
          description: LibraryCodec.description,
        );
        await _db.putSetting(_gistIdKey, id);
      } else if (merge.remoteChanged ||
          (notesMerge?.remoteChanged ?? false) ||
          (favMerge?.remoteChanged ?? false)) {
        await client.writeFile(gistId, LibraryCodec.fileName, content);
      }
      await _library.markSynced(merge.entries);
      if (notesMerge != null) await notes!.markSynced(notesMerge.entries);
      if (favMerge != null) await favorites!.markSynced(favMerge.entries);
      await _db.putSetting(_lastSyncedKey, _now().toUtc().toIso8601String());
      await _publishIdle();
      await _updateShare();
    } on GitHubException catch (e) {
      if (e.kind == GitHubErrorKind.unauthorized) {
        await signOut();
        _set(
          SyncState.signedOut(pendingCount: state.value.pendingCount, error: e),
        );
        return;
      }
      _set(
        SyncState(
          status: SyncStatus.error,
          pendingCount: await _pendingCount(),
          lastSyncedAt: await _lastSyncedAt(),
          login: await _db.setting(_loginKey),
          error: e,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Заметки: слияние по `updatedAt` на заметку, как у списков.
  Future<MergeResult<TitleNote>?> _mergeNotes(List<TitleNote> remote) async {
    final repo = notes;
    if (repo == null) return null;
    final local = await repo.allForSync();
    final merge = mergeNotes(local, remote);
    final remoteById = {for (final n in remote) n.mediaId: n};
    await repo.applyMerged(
      merge.localChanged,
      snapshot: {for (final n in local) n.mediaId: n},
      isClean: (n) => remoteById[n.mediaId] == n,
    );
    return merge;
  }

  /// «Понравилось»: слияние по `updatedAt` на тайтл.
  Future<MergeResult<Favorite>?> _mergeFavorites(List<Favorite> remote) async {
    final repo = favorites;
    if (repo == null) return null;
    final local = await repo.allForSync();
    final merge = mergeFavorites(local, remote);
    final remoteById = {for (final f in remote) f.mediaId: f};
    await repo.applyMerged(
      merge.localChanged,
      snapshot: {for (final f in local) f.mediaId: f},
      isClean: (f) => remoteById[f.mediaId] == f,
    );
    return merge;
  }

  Future<int> _pendingCount() async =>
      await _library.pendingCount() +
      (await notes?.pendingCount() ?? 0) +
      (await favorites?.pendingCount() ?? 0);

  /// Id Gist (`null`, если его ещё нет) и его содержимое.
  Future<(String?, LibraryFile)> _loadRemote(GistClient client) async {
    var gistId = await _db.setting(_gistIdKey);
    if (gistId != null) {
      try {
        final content = await client.readFile(gistId, LibraryCodec.fileName);
        return (gistId, LibraryCodec.decodeFile(content));
      } on GitHubException catch (e) {
        // Gist удалили на GitHub — ищем другой или создаём новый.
        if (e.statusCode != 404) rethrow;
        await _db.putSetting(_gistIdKey, null);
      }
    }
    gistId = await client.findGistWithFile(LibraryCodec.fileName);
    if (gistId == null) return (null, const LibraryFile());
    await _db.putSetting(_gistIdKey, gistId);
    final content = await client.readFile(gistId, LibraryCodec.fileName);
    return (gistId, LibraryCodec.decodeFile(content));
  }

  void _scheduleSync() {
    _shareDirty = true;
    if (_token == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, syncNow);
  }

  void _onPendingChanged(int count) {
    final s = state.value;
    if (s.status == SyncStatus.syncing) return;
    if (s.status == SyncStatus.signedOut || s.status == SyncStatus.error) {
      _set(
        SyncState(
          status: s.status,
          pendingCount: count,
          lastSyncedAt: s.lastSyncedAt,
          login: s.login,
          error: s.error,
        ),
      );
      return;
    }
    _set(
      SyncState(
        status: count > 0 ? SyncStatus.pending : SyncStatus.synced,
        pendingCount: count,
        lastSyncedAt: s.lastSyncedAt,
        login: s.login,
      ),
    );
  }

  Future<void> _publishIdle() async {
    final pending = await _pendingCount();
    if (_token == null) {
      _set(SyncState.signedOut(pendingCount: pending));
      return;
    }
    _set(
      SyncState(
        status: pending > 0 ? SyncStatus.pending : SyncStatus.synced,
        pendingCount: pending,
        lastSyncedAt: await _lastSyncedAt(),
        login: await _db.setting(_loginKey),
      ),
    );
  }

  Future<DateTime?> _lastSyncedAt() async {
    final v = await _db.setting(_lastSyncedKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  void _set(SyncState next) {
    if (state.value != next) state.value = next;
  }
}
