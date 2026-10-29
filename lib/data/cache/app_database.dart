import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Кэш тайтлов: краткая карточка и, если загружалась, полная.
@DataClassName('CachedAnimeRow')
class CachedAnime extends Table {
  IntColumn get id => integer()();

  /// JSON `Anime.toJson()`.
  TextColumn get summaryJson => text()();
  DateTimeColumn get summaryUpdatedAt => dateTime()();

  /// Исходный JSON объекта `Media` из запроса деталей.
  TextColumn get detailsJson => text().nullable()();
  DateTimeColumn get detailsUpdatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Произвольные закэшированные ответы по ключу: страницы каталога, жанры.
@DataClassName('CacheEntryRow')
class CacheEntries extends Table {
  TextColumn get key => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Списки пользователя. Источник правды на устройстве; синхронизируются
/// с приватным GitHub Gist.
@DataClassName('LibraryEntryRow')
class LibraryEntries extends Table {
  IntColumn get mediaId => integer()();

  /// Значение `ListStatus.apiValue`.
  TextColumn get status => text()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  IntColumn get score => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Изменение ещё не отправлено в Gist.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {mediaId};
}

/// Настройки приложения; в отличие от [CacheEntries], не очищаются.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [CachedAnime, CacheEntries, LibraryEntries, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Файл базы в каталоге данных приложения
  /// (на Windows — `%APPDATA%\<company>\<app>`).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: 'anime_cache',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(libraryEntries);
        await m.createTable(settings);
      }
    },
  );

  Future<CachedAnimeRow?> animeById(int id) =>
      (select(cachedAnime)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Возвращает строки в порядке [ids]; отсутствующие пропускаются.
  Future<List<CachedAnimeRow>> animeByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (select(
      cachedAnime,
    )..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    return [for (final id in ids) ?byId[id]];
  }

  /// Сохраняет краткие карточки, не затирая уже загруженные детали.
  Future<void> upsertSummaries(Map<int, String> jsonById, DateTime now) =>
      batch((b) {
        for (final MapEntry(key: id, value: json) in jsonById.entries) {
          b.insert(
            cachedAnime,
            CachedAnimeCompanion.insert(
              id: Value(id),
              summaryJson: json,
              summaryUpdatedAt: now,
            ),
            onConflict: DoUpdate(
              (_) => CachedAnimeCompanion(
                summaryJson: Value(json),
                summaryUpdatedAt: Value(now),
              ),
            ),
          );
        }
      });

  Future<void> upsertDetails(
    int id, {
    required String summaryJson,
    required String detailsJson,
    required DateTime now,
  }) => into(cachedAnime).insertOnConflictUpdate(
    CachedAnimeCompanion.insert(
      id: Value(id),
      summaryJson: summaryJson,
      summaryUpdatedAt: now,
      detailsJson: Value(detailsJson),
      detailsUpdatedAt: Value(now),
    ),
  );

  Future<CacheEntryRow?> entry(String key) =>
      (select(cacheEntries)..where((t) => t.key.equals(key))).getSingleOrNull();

  Future<void> putEntry(String key, String payload, DateTime now) =>
      into(cacheEntries).insertOnConflictUpdate(
        CacheEntriesCompanion.insert(
          key: key,
          payload: payload,
          updatedAt: now,
        ),
      );

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> putSetting(String key, String? value) => value == null
      ? (delete(settings)..where((t) => t.key.equals(key))).go()
      : into(settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );

  /// Удаляет записи кэша, не обновлявшиеся с [threshold].
  Future<void> pruneOlderThan(DateTime threshold) => transaction(() async {
    await (delete(
      cacheEntries,
    )..where((t) => t.updatedAt.isSmallerThanValue(threshold))).go();
    await (delete(
      cachedAnime,
    )..where((t) => t.summaryUpdatedAt.isSmallerThanValue(threshold))).go();
  });
}
