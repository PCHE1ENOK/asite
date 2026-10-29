import '../data/models/anime.dart';
import '../data/models/library_entry.dart';

/// Подписи и форматирование для интерфейса (русский).
abstract final class Fmt {
  static const formats = {
    'TV': 'TV',
    'TV_SHORT': 'TV-шорт',
    'MOVIE': 'Фильм',
    'SPECIAL': 'Спешл',
    'OVA': 'OVA',
    'ONA': 'ONA',
    'MUSIC': 'Клип',
  };

  static const seasons = {
    'WINTER': 'Зима',
    'SPRING': 'Весна',
    'SUMMER': 'Лето',
    'FALL': 'Осень',
  };

  static const releaseStatuses = {
    'RELEASING': 'Выходит',
    'FINISHED': 'Вышло',
    'NOT_YET_RELEASED': 'Анонс',
    'CANCELLED': 'Отменено',
    'HIATUS': 'Перерыв',
  };

  static const sources = {
    'ORIGINAL': 'Оригинал',
    'MANGA': 'Манга',
    'LIGHT_NOVEL': 'Ранобэ',
    'WEB_NOVEL': 'Веб-новелла',
    'NOVEL': 'Роман',
    'VISUAL_NOVEL': 'Визуальная новелла',
    'VIDEO_GAME': 'Игра',
    'GAME': 'Игра',
    'WEB_MANGA': 'Веб-манга',
    'COMIC': 'Комикс',
    'MULTIMEDIA_PROJECT': 'Медиапроект',
    'PICTURE_BOOK': 'Книга с картинками',
    'OTHER': 'Другое',
  };

  static const relations = {
    'SEQUEL': 'Сиквел',
    'PREQUEL': 'Приквел',
    'SIDE_STORY': 'Побочная история',
    'PARENT': 'Основная история',
    'SPIN_OFF': 'Спин-офф',
    'ALTERNATIVE': 'Альтернатива',
    'SUMMARY': 'Пересказ',
    'COMPILATION': 'Компиляция',
    'CHARACTER': 'Персонажи',
    'ADAPTATION': 'Адаптация',
    'SOURCE': 'Первоисточник',
    'CONTAINS': 'Содержит',
    'OTHER': 'Другое',
  };

  /// Жанры AniList на русском; неизвестные остаются как есть.
  static const genres = {
    'Action': 'Экшен',
    'Adventure': 'Приключения',
    'Comedy': 'Комедия',
    'Drama': 'Драма',
    'Ecchi': 'Этти',
    'Fantasy': 'Фэнтези',
    'Hentai': 'Хентай',
    'Horror': 'Ужасы',
    'Mahou Shoujo': 'Махо-сёдзё',
    'Mecha': 'Меха',
    'Music': 'Музыка',
    'Mystery': 'Мистика',
    'Psychological': 'Психологическое',
    'Romance': 'Романтика',
    'Sci-Fi': 'Фантастика',
    'Slice of Life': 'Повседневность',
    'Sports': 'Спорт',
    'Supernatural': 'Сверхъестественное',
    'Thriller': 'Триллер',
  };

  static String genre(String g) => genres[g] ?? g;

  static String status(ListStatus s) => switch (s) {
    ListStatus.current => 'Смотрю',
    ListStatus.planning => 'В планах',
    ListStatus.completed => 'Просмотрено',
    ListStatus.paused => 'Отложено',
    ListStatus.dropped => 'Брошено',
    ListStatus.repeating => 'Пересматриваю',
  };

  /// «TV · 2026 · 12 эп.»
  static String posterCaption(Anime a) => [
    if (a.format != null) formats[a.format] ?? a.format!,
    if (a.seasonYear != null) '${a.seasonYear}',
    if (a.episodes != null) '${a.episodes} эп.',
  ].join(' · ');

  /// «TV · Осень 2026 · 12 эп. · 24 мин · MAPPA»
  static String titleMeta(AnimeDetails d) {
    final a = d.anime;
    final main =
        d.studios.where((s) => s.isMain).firstOrNull ?? d.studios.firstOrNull;
    return [
      if (a.format != null) formats[a.format] ?? a.format!,
      ?season(a.season, a.seasonYear),
      if (a.episodes != null) '${a.episodes} эп.',
      if (a.duration != null) '${a.duration} мин',
      ?main?.name,
    ].join(' · ');
  }

  static String? season(String? season, int? year) {
    if (season == null && year == null) return null;
    return [?seasons[season], ?year?.toString()].join(' ');
  }

  /// 520 000 → «520 тыс.», 1 200 000 → «1,2 млн».
  static String compact(int n) {
    if (n >= 1000000) {
      final v = n / 1000000;
      return '${_trim(v)} млн';
    }
    if (n >= 1000) return '${(n / 1000).round()} тыс.';
    return '$n';
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(v >= 10 ? 0 : 1);
    return s.replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '');
  }

  /// 24310 → «24 310».
  static String thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  static const _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  /// «3 ноября» (локальное время).
  static String dayMonth(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]}';
  }

  static String fuzzyDate(FuzzyDate d) => [
    if (d.day != null && d.month != null)
      '${d.day} ${_months[d.month! - 1]}'
    else if (d.month != null)
      _monthNominative[d.month! - 1],
    ?d.year?.toString(),
  ].join(' ');

  static const _monthNominative = [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];

  /// Склонение: plural(5, 'тайтл', 'тайтла', 'тайтлов').
  static String plural(int n, String one, String few, String many) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }
}
