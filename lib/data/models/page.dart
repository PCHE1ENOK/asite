/// Сведения о странице результатов из AniList `PageInfo`.
class PageInfo {
  const PageInfo({
    required this.currentPage,
    required this.hasNextPage,
    required this.perPage,
    this.total,
    this.lastPage,
  });

  final int currentPage;
  final bool hasNextPage;
  final int perPage;

  /// AniList не гарантирует точность `total` и `lastPage`.
  final int? total;
  final int? lastPage;

  factory PageInfo.fromJson(Map<String, dynamic> json) => PageInfo(
    currentPage: json['currentPage'] as int? ?? 1,
    hasNextPage: json['hasNextPage'] as bool? ?? false,
    perPage: json['perPage'] as int? ?? 0,
    total: json['total'] as int?,
    lastPage: json['lastPage'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'currentPage': currentPage,
    'hasNextPage': hasNextPage,
    'perPage': perPage,
    'total': total,
    'lastPage': lastPage,
  };
}

/// Страница результатов.
class Paged<T> {
  const Paged({required this.items, required this.pageInfo});

  final List<T> items;
  final PageInfo pageInfo;
}
