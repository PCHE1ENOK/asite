// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedAnimeTable extends CachedAnime
    with TableInfo<$CachedAnimeTable, CachedAnimeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAnimeTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  @override
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryUpdatedAtMeta = const VerificationMeta(
    'summaryUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> summaryUpdatedAt =
      GeneratedColumn<DateTime>(
        'summary_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailsUpdatedAtMeta = const VerificationMeta(
    'detailsUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> detailsUpdatedAt =
      GeneratedColumn<DateTime>(
        'details_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    summaryJson,
    summaryUpdatedAt,
    detailsJson,
    detailsUpdatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_anime';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAnimeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryJsonMeta);
    }
    if (data.containsKey('summary_updated_at')) {
      context.handle(
        _summaryUpdatedAtMeta,
        summaryUpdatedAt.isAcceptableOrUnknown(
          data['summary_updated_at']!,
          _summaryUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryUpdatedAtMeta);
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    if (data.containsKey('details_updated_at')) {
      context.handle(
        _detailsUpdatedAtMeta,
        detailsUpdatedAt.isAcceptableOrUnknown(
          data['details_updated_at']!,
          _detailsUpdatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedAnimeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAnimeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      summaryUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}summary_updated_at'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      ),
      detailsUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}details_updated_at'],
      ),
    );
  }

  @override
  $CachedAnimeTable createAlias(String alias) {
    return $CachedAnimeTable(attachedDatabase, alias);
  }
}

class CachedAnimeRow extends DataClass implements Insertable<CachedAnimeRow> {
  final int id;

  /// JSON `Anime.toJson()`.
  final String summaryJson;
  final DateTime summaryUpdatedAt;

  /// Исходный JSON объекта `Media` из запроса деталей.
  final String? detailsJson;
  final DateTime? detailsUpdatedAt;
  const CachedAnimeRow({
    required this.id,
    required this.summaryJson,
    required this.summaryUpdatedAt,
    this.detailsJson,
    this.detailsUpdatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['summary_json'] = Variable<String>(summaryJson);
    map['summary_updated_at'] = Variable<DateTime>(summaryUpdatedAt);
    if (!nullToAbsent || detailsJson != null) {
      map['details_json'] = Variable<String>(detailsJson);
    }
    if (!nullToAbsent || detailsUpdatedAt != null) {
      map['details_updated_at'] = Variable<DateTime>(detailsUpdatedAt);
    }
    return map;
  }

  CachedAnimeCompanion toCompanion(bool nullToAbsent) {
    return CachedAnimeCompanion(
      id: Value(id),
      summaryJson: Value(summaryJson),
      summaryUpdatedAt: Value(summaryUpdatedAt),
      detailsJson: detailsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(detailsJson),
      detailsUpdatedAt: detailsUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(detailsUpdatedAt),
    );
  }

  factory CachedAnimeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAnimeRow(
      id: serializer.fromJson<int>(json['id']),
      summaryJson: serializer.fromJson<String>(json['summaryJson']),
      summaryUpdatedAt: serializer.fromJson<DateTime>(json['summaryUpdatedAt']),
      detailsJson: serializer.fromJson<String?>(json['detailsJson']),
      detailsUpdatedAt: serializer.fromJson<DateTime?>(
        json['detailsUpdatedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'summaryJson': serializer.toJson<String>(summaryJson),
      'summaryUpdatedAt': serializer.toJson<DateTime>(summaryUpdatedAt),
      'detailsJson': serializer.toJson<String?>(detailsJson),
      'detailsUpdatedAt': serializer.toJson<DateTime?>(detailsUpdatedAt),
    };
  }

  CachedAnimeRow copyWith({
    int? id,
    String? summaryJson,
    DateTime? summaryUpdatedAt,
    Value<String?> detailsJson = const Value.absent(),
    Value<DateTime?> detailsUpdatedAt = const Value.absent(),
  }) => CachedAnimeRow(
    id: id ?? this.id,
    summaryJson: summaryJson ?? this.summaryJson,
    summaryUpdatedAt: summaryUpdatedAt ?? this.summaryUpdatedAt,
    detailsJson: detailsJson.present ? detailsJson.value : this.detailsJson,
    detailsUpdatedAt: detailsUpdatedAt.present
        ? detailsUpdatedAt.value
        : this.detailsUpdatedAt,
  );
  CachedAnimeRow copyWithCompanion(CachedAnimeCompanion data) {
    return CachedAnimeRow(
      id: data.id.present ? data.id.value : this.id,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      summaryUpdatedAt: data.summaryUpdatedAt.present
          ? data.summaryUpdatedAt.value
          : this.summaryUpdatedAt,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
      detailsUpdatedAt: data.detailsUpdatedAt.present
          ? data.detailsUpdatedAt.value
          : this.detailsUpdatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAnimeRow(')
          ..write('id: $id, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('summaryUpdatedAt: $summaryUpdatedAt, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('detailsUpdatedAt: $detailsUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    summaryJson,
    summaryUpdatedAt,
    detailsJson,
    detailsUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAnimeRow &&
          other.id == this.id &&
          other.summaryJson == this.summaryJson &&
          other.summaryUpdatedAt == this.summaryUpdatedAt &&
          other.detailsJson == this.detailsJson &&
          other.detailsUpdatedAt == this.detailsUpdatedAt);
}

class CachedAnimeCompanion extends UpdateCompanion<CachedAnimeRow> {
  final Value<int> id;
  final Value<String> summaryJson;
  final Value<DateTime> summaryUpdatedAt;
  final Value<String?> detailsJson;
  final Value<DateTime?> detailsUpdatedAt;
  const CachedAnimeCompanion({
    this.id = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.summaryUpdatedAt = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.detailsUpdatedAt = const Value.absent(),
  });
  CachedAnimeCompanion.insert({
    this.id = const Value.absent(),
    required String summaryJson,
    required DateTime summaryUpdatedAt,
    this.detailsJson = const Value.absent(),
    this.detailsUpdatedAt = const Value.absent(),
  }) : summaryJson = Value(summaryJson),
       summaryUpdatedAt = Value(summaryUpdatedAt);
  static Insertable<CachedAnimeRow> custom({
    Expression<int>? id,
    Expression<String>? summaryJson,
    Expression<DateTime>? summaryUpdatedAt,
    Expression<String>? detailsJson,
    Expression<DateTime>? detailsUpdatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (summaryUpdatedAt != null) 'summary_updated_at': summaryUpdatedAt,
      if (detailsJson != null) 'details_json': detailsJson,
      if (detailsUpdatedAt != null) 'details_updated_at': detailsUpdatedAt,
    });
  }

  CachedAnimeCompanion copyWith({
    Value<int>? id,
    Value<String>? summaryJson,
    Value<DateTime>? summaryUpdatedAt,
    Value<String?>? detailsJson,
    Value<DateTime?>? detailsUpdatedAt,
  }) {
    return CachedAnimeCompanion(
      id: id ?? this.id,
      summaryJson: summaryJson ?? this.summaryJson,
      summaryUpdatedAt: summaryUpdatedAt ?? this.summaryUpdatedAt,
      detailsJson: detailsJson ?? this.detailsJson,
      detailsUpdatedAt: detailsUpdatedAt ?? this.detailsUpdatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (summaryUpdatedAt.present) {
      map['summary_updated_at'] = Variable<DateTime>(summaryUpdatedAt.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (detailsUpdatedAt.present) {
      map['details_updated_at'] = Variable<DateTime>(detailsUpdatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAnimeCompanion(')
          ..write('id: $id, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('summaryUpdatedAt: $summaryUpdatedAt, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('detailsUpdatedAt: $detailsUpdatedAt')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, payload, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntryRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntryRow extends DataClass implements Insertable<CacheEntryRow> {
  final String key;
  final String payload;
  final DateTime updatedAt;
  const CacheEntryRow({
    required this.key,
    required this.payload,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['payload'] = Variable<String>(payload);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      key: Value(key),
      payload: Value(payload),
      updatedAt: Value(updatedAt),
    );
  }

  factory CacheEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntryRow(
      key: serializer.fromJson<String>(json['key']),
      payload: serializer.fromJson<String>(json['payload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'payload': serializer.toJson<String>(payload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CacheEntryRow copyWith({String? key, String? payload, DateTime? updatedAt}) =>
      CacheEntryRow(
        key: key ?? this.key,
        payload: payload ?? this.payload,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CacheEntryRow copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntryRow(
      key: data.key.present ? data.key.value : this.key,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntryRow(')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, payload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntryRow &&
          other.key == this.key &&
          other.payload == this.payload &&
          other.updatedAt == this.updatedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntryRow> {
  final Value<String> key;
  final Value<String> payload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required String payload,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       payload = Value(payload),
       updatedAt = Value(updatedAt);
  static Insertable<CacheEntryRow> custom({
    Expression<String>? key,
    Expression<String>? payload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? payload,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      payload: payload ?? this.payload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedAnimeTable cachedAnime = $CachedAnimeTable(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedAnime,
    cacheEntries,
  ];
}

typedef $$CachedAnimeTableCreateCompanionBuilder =
    CachedAnimeCompanion Function({
      Value<int> id,
      required String summaryJson,
      required DateTime summaryUpdatedAt,
      Value<String?> detailsJson,
      Value<DateTime?> detailsUpdatedAt,
    });
typedef $$CachedAnimeTableUpdateCompanionBuilder =
    CachedAnimeCompanion Function({
      Value<int> id,
      Value<String> summaryJson,
      Value<DateTime> summaryUpdatedAt,
      Value<String?> detailsJson,
      Value<DateTime?> detailsUpdatedAt,
    });

class $$CachedAnimeTableFilterComposer
    extends Composer<_$AppDatabase, $CachedAnimeTable> {
  $$CachedAnimeTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get summaryUpdatedAt => $composableBuilder(
    column: $table.summaryUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get detailsUpdatedAt => $composableBuilder(
    column: $table.detailsUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAnimeTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedAnimeTable> {
  $$CachedAnimeTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get summaryUpdatedAt => $composableBuilder(
    column: $table.summaryUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get detailsUpdatedAt => $composableBuilder(
    column: $table.detailsUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAnimeTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedAnimeTable> {
  $$CachedAnimeTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get summaryUpdatedAt => $composableBuilder(
    column: $table.summaryUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get detailsUpdatedAt => $composableBuilder(
    column: $table.detailsUpdatedAt,
    builder: (column) => column,
  );
}

class $$CachedAnimeTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedAnimeTable,
          CachedAnimeRow,
          $$CachedAnimeTableFilterComposer,
          $$CachedAnimeTableOrderingComposer,
          $$CachedAnimeTableAnnotationComposer,
          $$CachedAnimeTableCreateCompanionBuilder,
          $$CachedAnimeTableUpdateCompanionBuilder,
          (
            CachedAnimeRow,
            BaseReferences<_$AppDatabase, $CachedAnimeTable, CachedAnimeRow>,
          ),
          CachedAnimeRow,
          PrefetchHooks Function()
        > {
  $$CachedAnimeTableTableManager(_$AppDatabase db, $CachedAnimeTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAnimeTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAnimeTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAnimeTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<DateTime> summaryUpdatedAt = const Value.absent(),
                Value<String?> detailsJson = const Value.absent(),
                Value<DateTime?> detailsUpdatedAt = const Value.absent(),
              }) => CachedAnimeCompanion(
                id: id,
                summaryJson: summaryJson,
                summaryUpdatedAt: summaryUpdatedAt,
                detailsJson: detailsJson,
                detailsUpdatedAt: detailsUpdatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String summaryJson,
                required DateTime summaryUpdatedAt,
                Value<String?> detailsJson = const Value.absent(),
                Value<DateTime?> detailsUpdatedAt = const Value.absent(),
              }) => CachedAnimeCompanion.insert(
                id: id,
                summaryJson: summaryJson,
                summaryUpdatedAt: summaryUpdatedAt,
                detailsJson: detailsJson,
                detailsUpdatedAt: detailsUpdatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedAnimeTable, CachedAnimeRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedAnimeTable,
                    CachedAnimeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedAnimeTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedAnimeTable,
      CachedAnimeRow,
      $$CachedAnimeTableFilterComposer,
      $$CachedAnimeTableOrderingComposer,
      $$CachedAnimeTableAnnotationComposer,
      $$CachedAnimeTableCreateCompanionBuilder,
      $$CachedAnimeTableUpdateCompanionBuilder,
      (
        CachedAnimeRow,
        BaseReferences<_$AppDatabase, $CachedAnimeTable, CachedAnimeRow>,
      ),
      CachedAnimeRow,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String key,
      required String payload,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> key,
      Value<String> payload,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheEntriesTable,
          CacheEntryRow,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntryRow,
            BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
          ),
          CacheEntryRow,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                key: key,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String payload,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                key: key,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTable, CacheEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CacheEntriesTable,
                    CacheEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheEntriesTable,
      CacheEntryRow,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntryRow,
        BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
      ),
      CacheEntryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedAnimeTableTableManager get cachedAnime =>
      $$CachedAnimeTableTableManager(_db, _db.cachedAnime);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
}
