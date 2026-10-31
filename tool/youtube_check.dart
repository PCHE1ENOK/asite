// Диагностика источника YouTube: почему у тайтла нет официальных видео.
//
//   dart run tool/youtube_check.dart "DAN DA DAN"
//   dart run tool/youtube_check.dart "DAN DA DAN" --region=RU
//
// Ключ берётся из config/local.json (YOUTUBE_API_KEY) и не печатается.
// Скрипт только читает: ничего не записывает и кэш приложения не трогает.
// Квота YouTube: около 7 × 100 + 6 единиц из 10 000 в сутки.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/sources/youtube_match.dart';
import 'package:http/http.dart' as http;

late String _key;

Future<void> main(List<String> args) async {
  final query = args.where((a) => !a.startsWith('--')).join(' ').trim();
  if (query.isEmpty) {
    print(
      'Использование: dart run tool/youtube_check.dart "<название>" '
      '[--region=RU]',
    );
    exit(64);
  }
  final key = _readKey();
  if (key == null) exit(2);
  _key = key;
  print('Ключ: ${key.substring(0, 4)}… (длина ${key.length})');

  final regionArg = args
      .where((a) => a.startsWith('--region='))
      .map((a) => a.substring(9).toUpperCase())
      .firstOrNull;
  final region = regionArg ?? _regionFromLocale();
  print(
    'Регион поиска: ${region ?? 'не задан'}'
    '${regionArg == null ? ' (как в приложении — из языка системы ${Platform.localeName})' : ''}',
  );

  // 1. Тайтл из AniList — те же названия, что видит приложение.
  print('\n== AniList: «$query» ==');
  AnimeDetails? title;
  try {
    final client = AniListClient();
    final found = await client.search(query, perPage: 1);
    if (found.items.isEmpty) {
      print('AniList ничего не нашёл по запросу.');
    } else {
      title = await client.fetchDetails(found.items.first.id);
    }
  } on Object catch (e) {
    print('Не удалось получить тайтл из AniList: $e');
  }
  final String q;
  if (title == null) {
    q = query;
    print(
      'Дальше ищем по введённой строке; сопоставление с тайтлом '
      'не проверяется.',
    );
  } else {
    final t = title.anime.title;
    print('Тайтл: id ${title.id}, формат ${title.anime.format}');
    print('  romaji:  ${t.romaji}');
    print('  english: ${t.english}');
    print('  native:  ${t.native}');
    print('  синонимы: ${title.synonyms.join(' | ')}');
    final tr = title.trailer;
    print(
      '  трейлер в AniList: '
      '${tr == null ? 'нет' : '${tr.site} ${tr.id} (https://www.youtube.com/watch?v=${tr.id})'}',
    );
    q = t.romaji ?? t.preferred;
    print('Приложение ищет на YouTube по строке: «$q»');
    print(
      'Ролик привязывается, если его название (без регистра и знаков) '
      'содержит одно из:',
    );
    for (final n in YouTubeMatch.titleNames(title)) {
      print('  «$n»');
    }
    print('и в названии есть номер серии («Episode 5», «EP05», «#3»).');
  }

  // 2. Каналы.
  final channelIds = <String, String>{};
  for (final c in YouTubeMatch.officialChannels) {
    print('\n== channels.list forHandle=${c.handle} ==');
    final r = await _get('channels', {'part': 'id', 'forHandle': c.handle});
    if (r == null) continue;
    final items = r['items'] as List? ?? const [];
    if (items.isEmpty) {
      print('Канал не найден по @-имени.');
    } else {
      final id = (items.first as Map)['id'] as String;
      channelIds[c.handle] = id;
      print('id канала: $id');
    }
  }

  // 3. Поиск, как в приложении, и без региона — для сравнения.
  final allIds = <String>{};
  for (final c in YouTubeMatch.officialChannels) {
    final id = channelIds[c.handle];
    if (id == null) continue;
    for (final reg in {region, null}) {
      final label = reg == null ? 'без региона' : 'регион $reg';
      print('\n== search.list ${c.name}, $label ==');
      final items = await _search(q, channelId: id, region: reg);
      if (items == null) continue;
      _report(items, title);
      allIds.addAll(items.map(_videoId).whereType<String>());
    }
  }
  print(
    '\n== search.list по всему YouTube (не только официальные каналы), '
    '${region == null ? 'без региона' : 'регион $region'} ==',
  );
  final global = await _search(q, region: region);
  if (global != null) {
    for (final i in global.take(10)) {
      final s = i['snippet'] as Map? ?? const {};
      print(
        '  ${YouTubeMatch.unescape(s['title'] as String? ?? '')} '
        '— канал «${s['channelTitle']}»',
      );
    }
    if (global.isEmpty) print('  ничего');
  }

  // 4. Трейлеры: каналы и отбор, как в приложении.
  for (final c in YouTubeMatch.trailerChannels) {
    print('\n== Трейлеры: channels.list forHandle=${c.handle} ==');
    final r = await _get('channels', {
      'part': 'snippet',
      'forHandle': c.handle,
    });
    final items = (r?['items'] as List? ?? const []).cast<Map>();
    if (r != null && items.isEmpty) print('Канал не найден по @-имени.');
    if (items.isEmpty) continue;
    final ch = items.first;
    print(
      'id канала: ${ch['id']}, название: «${(ch['snippet'] as Map?)?['title']}»',
    );
    print('\n== search.list трейлера на ${c.name} ==');
    final found = await _search(
      '$q trailer|PV|teaser',
      channelId: ch['id'] as String,
      region: region,
    );
    if (found == null) continue;
    print('Найдено роликов: ${found.length}');
    for (final i in found) {
      final name = YouTubeMatch.unescape(
        (i['snippet'] as Map?)?['title'] as String? ?? '',
      );
      final ok = title != null && YouTubeMatch.isTrailerFor(name, title);
      print(
        '  $name\n    → ${title == null
            ? '?'
            : ok
            ? 'ТРЕЙЛЕР (подходит)'
            : 'не трейлер этого тайтла'}',
      );
    }
  }

  // 5. Региональные ограничения найденных роликов.
  if (allIds.isNotEmpty && region != null) {
    print('\n== videos.list: доступность в регионе $region ==');
    final r = await _get('videos', {
      'part': 'contentDetails,status',
      'id': allIds.take(50).join(','),
    });
    var blocked = 0;
    for (final v in (r?['items'] as List? ?? const []).cast<Map>()) {
      final rr = (v['contentDetails'] as Map?)?['regionRestriction'] as Map?;
      final allowed = (rr?['allowed'] as List?)?.cast<String>();
      final denied = (rr?['blocked'] as List?)?.cast<String>();
      final ok =
          (allowed == null || allowed.contains(region)) &&
          !(denied?.contains(region) ?? false);
      if (!ok) blocked++;
    }
    print(
      blocked == 0
          ? 'Все найденные ролики доступны в $region.'
          : 'Недоступны в $region: $blocked из ${allIds.length.clamp(0, 50)}.',
    );
  }

  print(
    '\nПримечание: приложение хранит результат поиска 3 дня (и пустой '
    'тоже). Ошибки API не кэшируются.',
  );
}

/// Ключ из config/local.json; при проблеме печатает причину.
String? _readKey() {
  final f = File('config/local.json');
  if (!f.existsSync()) {
    print(
      'НЕТ КЛЮЧА: файл config/local.json не найден '
      '(запускайте из корня проекта; образец — config/local.json.example).',
    );
    return null;
  }
  try {
    final j = jsonDecode(f.readAsStringSync());
    final key = j is Map ? j['YOUTUBE_API_KEY'] : null;
    if (key is! String || key.trim().isEmpty) {
      print('НЕТ КЛЮЧА: в config/local.json нет непустого YOUTUBE_API_KEY.');
      return null;
    }
    if (key.trim() != key) {
      print(
        'ВНИМАНИЕ: в ключе есть пробелы по краям — приложение отправит '
        'их как есть.',
      );
    }
    return key;
  } on FormatException catch (e) {
    print('НЕТ КЛЮЧА: config/local.json — не JSON: ${e.message}');
    return null;
  }
}

/// Страна из языка системы, как `PlatformDispatcher.locale.countryCode`.
String? _regionFromLocale() {
  final parts = Platform.localeName.split(RegExp('[_.-]'));
  return parts.length > 1 && parts[1].length == 2
      ? parts[1].toUpperCase()
      : null;
}

String? _videoId(Map<String, dynamic> item) =>
    (item['id'] as Map?)?['videoId'] as String?;

Future<List<Map<String, dynamic>>?> _search(
  String q, {
  String? channelId,
  String? region,
}) async {
  final r = await _get('search', {
    'part': 'snippet',
    'type': 'video',
    'videoEmbeddable': 'true',
    'q': q,
    'maxResults': '50',
    'channelId': ?channelId,
    'regionCode': ?region,
  });
  return (r?['items'] as List?)?.whereType<Map<String, dynamic>>().toList();
}

/// Как приложение разбирает выдачу: что привяжется и почему нет.
void _report(List<Map<String, dynamic>> items, AnimeDetails? title) {
  print('Найдено роликов: ${items.length}');
  var bound = 0;
  for (final i in items) {
    final s = i['snippet'] as Map? ?? const {};
    final name = YouTubeMatch.unescape(s['title'] as String? ?? '');
    if (title == null) {
      print('  $name');
      continue;
    }
    final matched = YouTubeMatch.matchedName(name, title);
    final ep = YouTubeMatch.episodeNumber(name);
    final String verdict;
    if (matched == null) {
      verdict = 'НЕ привязан: нет названия тайтла в заголовке';
    } else if (ep == null) {
      verdict = title.anime.format == 'MOVIE'
          ? 'привязан как фильм (совпало «$matched»)'
          : 'НЕ привязан: нет номера серии (совпало «$matched»)';
    } else {
      verdict = 'серия $ep (совпало «$matched»)';
      bound++;
    }
    print('  $name\n    → $verdict');
  }
  if (title != null) print('Итого привязано к сериям: $bound');
}

/// GET к YouTube Data API; ошибку печатает без ключа и возвращает `null`.
Future<Map<String, dynamic>?> _get(
  String method,
  Map<String, String> params,
) async {
  final uri = Uri.parse('https://www.googleapis.com/youtube/v3/$method')
      .replace(queryParameters: {...params, 'key': _key});
  final http.Response res;
  try {
    res = await http.get(uri).timeout(const Duration(seconds: 20));
  } on Object catch (e) {
    print('Сеть: ${_hide(e.toString())}');
    return null;
  }
  print('HTTP ${res.statusCode}');
  final body = utf8.decode(res.bodyBytes, allowMalformed: true);
  if (res.statusCode != 200) {
    try {
      final err = (jsonDecode(body) as Map)['error'] as Map;
      final reasons = (err['errors'] as List? ?? const [])
          .map((e) => (e as Map)['reason'])
          .join(', ');
      print('Ошибка Google: ${_hide('${err['message']}')} [причина: $reasons]');
    } on Object {
      print('Ошибка Google: ${_hide(body)}');
    }
    return null;
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

String _hide(String s) => s.replaceAll(_key, '<ключ>');
