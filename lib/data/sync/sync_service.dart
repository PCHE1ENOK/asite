import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../github/gist_client.dart';
import '../github/github_auth.dart';
import '../github/github_exception.dart';
import '../github/token_store.dart';
import '../library/library_repository.dart';
import '../models/library_entry.dart';
import 'library_codec.dart';
import 'library_merge.dart';

enum SyncStatus { signedOut, synced, pending, syncing, error }

/// Глобальное состояние синхронизации для точки на профиле и `SyncBar`.
@immutable
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
  });

  final String login;

  /// `true` — создан новый Gist, `false` — найден существующий.
  final bool gistCreated;

  /// Сколько тайтлов в списках после слияния.
  final int entryCount;
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

  static const _gistIdKey = 'sync_gist_id';
  static const _loginKey = 'sync_login';
  static const _lastSyncedKey = 'sync_last_synced_at';

  final state = ValueNotifier<SyncState>(const SyncState.signedOut());

  String? _token;
  Timer? _debounceTimer;
  Future<void>? _running;
  bool _rerun = false;
  StreamSubscription<int>? _pendingSub;

  /// Можно ли войти: задан ли Client ID OAuth-приложения.
  bool get canSignIn => _auth() != null;

  /// Загружает токен, подписывается на изменения и синхронизирует.
  Future<void> start() async {
    _token = await _tokens.read();
    _library.onChanged = _scheduleSync;
    _pendingSub ??= _library.watchPendingCount().listen(_onPendingChanged);
    await _publishIdle();
    if (_token != null) await syncNow();
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _pendingSub?.cancel();
    _library.onChanged = null;
    state.dispose();
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

  /// Ждёт подтверждения на GitHub, сохраняет токен и синхронизирует.
  ///
  /// Если списки есть и на устройстве, и в Gist, вызывается
  /// [resolveConflict]; по умолчанию — «Объединить».
  Future<SignInResult> completeSignIn(
    DeviceCode code, {
    bool Function()? isCancelled,
    Future<MergeStrategy> Function()? resolveConflict,
  }) async {
    final token = await _auth()!.waitForToken(code, isCancelled: isCancelled);
    final client = _gistClient(token);
    final login = await client.currentLogin();

    // Новый аккаунт: старая привязка к Gist не годится.
    await _db.putSetting(_gistIdKey, null);
    final gistId = await client.findGistWithFile(LibraryCodec.fileName);
    var strategy = MergeStrategy.merge;
    if (gistId != null && await _library.hasEntries()) {
      final remote = LibraryCodec.decode(
        await client.readFile(gistId, LibraryCodec.fileName),
      );
      if (remote.any((e) => !e.deleted) && resolveConflict != null) {
        strategy = await resolveConflict();
      }
    }

    await _tokens.write(token);
    _token = token;
    await _db.putSetting(_loginKey, login);
    if (gistId != null) await _db.putSetting(_gistIdKey, gistId);

    await syncNow(strategy: strategy);
    final error = state.value.error;
    if (state.value.status == SyncStatus.error && error != null) throw error;

    final entries = await _library.allForSync();
    return SignInResult(
      login: login,
      gistCreated: gistId == null,
      entryCount: entries.where((e) => !e.deleted).length,
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
    await _publishIdle();
  }

  /// Синхронизирует сейчас. Параллельные вызовы объединяются.
  Future<void> syncNow({MergeStrategy strategy = MergeStrategy.merge}) {
    _debounceTimer?.cancel();
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    return _running = _runLoop(strategy).whenComplete(() => _running = null);
  }

  Future<void> _runLoop(MergeStrategy strategy) async {
    do {
      _rerun = false;
      await _syncOnce(strategy);
      strategy = MergeStrategy.merge;
    } while (_rerun && _token != null);
  }

  Future<void> _syncOnce(MergeStrategy strategy) async {
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
      final (gistId, remote) = await _loadRemote(client);
      final local = await _library.allForSync();
      final merge = mergeLibraries(
        local,
        remote,
        strategy: strategy,
        now: _now(),
      );

      final remoteById = {for (final e in remote) e.mediaId: e};
      final localSnapshot = {for (final e in local) e.mediaId: e};
      await _library.applyMerged(
        merge.localChanged,
        snapshot: localSnapshot,
        isClean: (e) => remoteById[e.mediaId] == e,
      );

      final content = LibraryCodec.encode(merge.entries);
      if (gistId == null) {
        final id = await client.createGist(
          fileName: LibraryCodec.fileName,
          content: content,
          description: LibraryCodec.description,
        );
        await _db.putSetting(_gistIdKey, id);
      } else if (merge.remoteChanged) {
        await client.writeFile(gistId, LibraryCodec.fileName, content);
      }
      await _library.markSynced(merge.entries);
      await _db.putSetting(_lastSyncedKey, _now().toUtc().toIso8601String());
      await _publishIdle();
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
          pendingCount: await _library.pendingCount(),
          lastSyncedAt: await _lastSyncedAt(),
          login: await _db.setting(_loginKey),
          error: e,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Id Gist (`null`, если его ещё нет) и записи из него.
  Future<(String?, List<LibraryEntry>)> _loadRemote(GistClient client) async {
    var gistId = await _db.setting(_gistIdKey);
    if (gistId != null) {
      try {
        final content = await client.readFile(gistId, LibraryCodec.fileName);
        return (gistId, LibraryCodec.decode(content));
      } on GitHubException catch (e) {
        // Gist удалили на GitHub — ищем другой или создаём новый.
        if (e.statusCode != 404) rethrow;
        await _db.putSetting(_gistIdKey, null);
      }
    }
    gistId = await client.findGistWithFile(LibraryCodec.fileName);
    if (gistId == null) return (null, const <LibraryEntry>[]);
    await _db.putSetting(_gistIdKey, gistId);
    final content = await client.readFile(gistId, LibraryCodec.fileName);
    return (gistId, LibraryCodec.decode(content));
  }

  void _scheduleSync() {
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
    final pending = await _library.pendingCount();
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
