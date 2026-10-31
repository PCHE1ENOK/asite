import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../models/favorite.dart';

/// «Понравилось» одного профиля. Как и списки: каждое изменение получает
/// `updatedAt` и флаг `dirty` до отправки в Gist, снятие хранится отметкой.
class FavoritesRepository {
  FavoritesRepository(
    this._db, {
    this.profileId = AppDatabase.defaultProfileId,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final int profileId;
  final DateTime Function() _now;
  StreamSubscription<Set<int>>? _sub;
  final _ids = ValueNotifier<Set<int>>(const {});

  /// Отмеченные тайтлы (без снятых) — для сердец и вкладки. Подписка на
  /// базу начинается при первом обращении, а не при создании профиля.
  ValueNotifier<Set<int>> get ids {
    _sub ??= _watchIds().listen((v) => _ids.value = v);
    return _ids;
  }

  /// Вызывается после каждого изменения (для автоотправки).
  void Function()? onChanged;

  bool isFavorite(int mediaId) => ids.value.contains(mediaId);

  Stream<Set<int>> _watchIds() =>
      (_db.select(_db.favorites)..where(
            (t) => t.profileId.equals(profileId) & t.deleted.equals(false),
          ))
          .watch()
          .map((rows) => {for (final r in rows) r.mediaId});

  /// Ставит или снимает отметку.
  Future<void> set(int mediaId, bool favorite) async {
    final cur = await _row(mediaId);
    if (favorite == (cur != null && !cur.deleted)) return;
    if (!favorite && cur == null) return;
    await _write(
      Favorite(mediaId: mediaId, updatedAt: _stamp(), deleted: !favorite),
      dirty: true,
    );
    // Сразу в памяти — сердце меняется без ожидания базы.
    ids.value = favorite
        ? {...ids.value, mediaId}
        : ({...ids.value}..remove(mediaId));
    onChanged?.call();
  }

  /// Переключает по записи в базе, а не по [ids]: те обновляются
  /// подпиской и на мгновение могут отставать.
  Future<bool> toggle(int mediaId) async {
    final cur = await _row(mediaId);
    final next = cur == null || cur.deleted;
    await set(mediaId, next);
    return next;
  }

  Future<FavoriteRow?> _row(int mediaId) =>
      (_db.select(_db.favorites)..where(
            (t) => t.profileId.equals(profileId) & t.mediaId.equals(mediaId),
          ))
          .getSingleOrNull();

  Future<List<Favorite>> allForSync() async => [
    for (final r in await (_db.select(
      _db.favorites,
    )..where((t) => t.profileId.equals(profileId))).get())
      Favorite(mediaId: r.mediaId, updatedAt: r.updatedAt, deleted: r.deleted),
  ];

  Stream<int> watchPendingCount() {
    final count = _db.favorites.mediaId.count();
    final q = _db.selectOnly(_db.favorites)
      ..addColumns([count])
      ..where(
        _db.favorites.profileId.equals(profileId) &
            _db.favorites.dirty.equals(true),
      );
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  Future<int> pendingCount() => watchPendingCount().first;

  /// Записывает результат слияния; отметку, изменённую после чтения
  /// [snapshot], не трогает.
  Future<void> applyMerged(
    List<Favorite> changed, {
    required Map<int, Favorite> snapshot,
    required bool Function(Favorite) isClean,
  }) => _db.transaction(() async {
    for (final f in changed) {
      final r = await _row(f.mediaId);
      final current = r == null
          ? null
          : Favorite(
              mediaId: r.mediaId,
              updatedAt: r.updatedAt,
              deleted: r.deleted,
            );
      if (current != snapshot[f.mediaId]) continue;
      await _write(f, dirty: !isClean(f));
    }
  });

  Future<void> markSynced(List<Favorite> pushed) => _db.transaction(() async {
    for (final f in pushed) {
      await (_db.update(_db.favorites)..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.mediaId.equals(f.mediaId) &
                t.updatedAt.equals(f.updatedAt),
          ))
          .write(const FavoritesCompanion(dirty: Value(false)));
    }
  });

  DateTime _stamp() => DateTime.fromMillisecondsSinceEpoch(
    _now().millisecondsSinceEpoch,
    isUtc: true,
  );

  Future<void> _write(Favorite f, {required bool dirty}) => _db
      .into(_db.favorites)
      .insertOnConflictUpdate(
        FavoritesCompanion.insert(
          profileId: profileId,
          mediaId: f.mediaId,
          updatedAt: f.updatedAt,
          deleted: Value(f.deleted),
          dirty: Value(dirty),
        ),
      );

  Future<void> dispose() async {
    await _sub?.cancel();
    _ids.dispose();
  }
}
