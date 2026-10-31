import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/anime.dart';
import '../data/shikimori/russian_text.dart';
import 'app_scope.dart';

/// Название тайтла: русское, если Shikimori его знает, иначе AniList.
class AnimeTitleText extends StatelessWidget {
  const AnimeTitleText(
    this.anime, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final Anime anime;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ShikiInfo?>(
    valueListenable: AppScope.of(context).services.shiki.of(anime.id),
    builder: (context, info, _) => Text(
      info?.title ?? anime.title.preferred,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    ),
  );
}

/// Подгружает русские названия для [items] после кадра (каталог, списки,
/// поиск); ошибки не мешают показу английских.
void prefetchShikimoriData(BuildContext context, Iterable<Anime> items) {
  final russian = AppScope.of(context).services.shiki;
  final list = items.toList();
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(russian.prefetch(list).catchError((Object _) {})),
  );
}
