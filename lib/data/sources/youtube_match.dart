import '../models/anime.dart';

/// Официальный канал правообладателя на YouTube.
class OfficialChannel {
  const OfficialChannel(this.handle, this.name);

  /// @-имя канала; id канала узнаётся через API и кэшируется.
  final String handle;
  final String name;
}

/// Сопоставление роликов YouTube с тайтлом AniList. Без зависимостей от
/// Flutter — используется и приложением, и `tool/youtube_check.dart`.
abstract final class YouTubeMatch {
  /// Каналы, которые выкладывают аниме бесплатно и официально.
  static const officialChannels = [
    OfficialChannel('@MuseAsia', 'Muse Asia'),
    OfficialChannel('@AniOneAsia', 'Ani-One Asia'),
  ];

  /// Официальные каналы, откуда берутся только трейлеры (серии — нет).
  static const trailerChannels = [
    OfficialChannel('@Crunchyroll', 'Crunchyroll'),
    OfficialChannel('@NetflixAnime', 'Netflix Anime'),
  ];

  /// Слова трейлера в названии ролика.
  static final _trailerWord = RegExp(
    r'(?<![\p{L}\p{N}])(?:trailer|teaser|pv\d*|трейлер|тизер|予告|ティザー)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  /// Опенинги, эндинги, клипы и музыка — не трейлеры, даже если в
  /// названии есть «PV» («Music PV», «Opening PV»).
  static final _notTrailer = RegExp(
    r'(?<![\p{L}\p{N}])(?:opening|ending|op\d*|ed\d*|ncop|nced|creditless|'
    r'music video|mv|clip|lyric|lyrics|song|ost|soundtrack|full episode|'
    r'episode|ep\d+|опенинг|эндинг|клип)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  /// Ролик — трейлер этого тайтла: есть название тайтла и слово
  /// трейлера, нет признаков опенинга, клипа или серии.
  static bool isTrailerFor(String videoTitle, AnimeDetails title) =>
      matchesTitle(videoTitle, title) &&
      _trailerWord.hasMatch(videoTitle) &&
      !_notTrailer.hasMatch(videoTitle);

  /// Названия тайтла, которые ищутся в названии ролика: romaji, english,
  /// native и синонимы AniList после [norm], не короче 4 символов.
  static List<String> titleNames(AnimeDetails title) => [
    title.anime.title.romaji,
    title.anime.title.english,
    title.anime.title.native,
    ...title.synonyms,
  ].whereType<String>().map(norm).where((n) => n.length >= 4).toSet().toList();

  /// Первое название тайтла, которое содержится в названии ролика.
  static String? matchedName(String videoTitle, AnimeDetails title) {
    final v = norm(videoTitle);
    return titleNames(title).where(v.contains).firstOrNull;
  }

  /// Название ролика содержит одно из названий тайтла (от 4 символов).
  static bool matchesTitle(String videoTitle, AnimeDetails title) =>
      matchedName(videoTitle, title) != null;

  /// Номер серии из названия: «Episode 5», «EP05», «Ep. 12», «#3».
  static int? episodeNumber(String videoTitle) {
    final m = RegExp(
      r'(?:episode|ep\.?|эпизод|серия|#)\s*0*(\d{1,4})\b',
      caseSensitive: false,
    ).firstMatch(videoTitle);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Нижний регистр, всё кроме букв и цифр — пробелы.
  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static String unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
