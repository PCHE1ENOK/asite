import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../theme/app_tokens.dart';

/// Переключает «Понравилось» с тостом и «Отменить» (design/screens.md §15).
Future<void> toggleFavorite(BuildContext context, Anime anime) async {
  final scope = AppScope.of(context);
  final favorites = scope.services.favorites;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final title =
      scope.services.shiki.of(anime.id).value?.title ?? anime.title.preferred;
  final now = await favorites.toggle(anime.id);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          now ? '«$title» в «Понравилось»' : '«$title» убран из «Понравилось»',
        ),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => favorites.set(anime.id, !now),
        ),
      ),
    );
}

/// Сердце «Понравилось». [onPoster] — круглая кнопка 28 на тёмной подложке;
/// иначе — иконка-кнопка в ряду действий карточки тайтла.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.anime,
    this.onPoster = false,
    this.visibleWhenOff = true,
  });

  final Anime anime;
  final bool onPoster;

  /// Неотмеченное сердце видно (телефон, наведение, фокус).
  final bool visibleWhenOff;

  @override
  Widget build(BuildContext context) {
    final favorites = AppScope.of(context).services.favorites;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: favorites.ids,
      builder: (context, ids, _) {
        final on = ids.contains(anime.id);
        if (!on && !visibleWhenOff) return const SizedBox.shrink();
        final t = context.tokens;
        final red = (onPoster ? AppTokens.dark : t).bad;
        final icon = Icon(
          Symbols.favorite_rounded,
          fill: on ? 1 : 0,
          size: onPoster ? 16 : 22,
          color: on ? red : (onPoster ? Colors.white : t.fg),
        );
        final label = on ? 'Убрать из «Понравилось»' : 'В «Понравилось»';
        if (!onPoster) {
          return IconButton(
            tooltip: label,
            isSelected: on,
            onPressed: () => toggleFavorite(context, anime),
            icon: icon,
          );
        }
        return Semantics(
          button: true,
          toggled: on,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: Material(
              color: AppTokens.posterBadgeBg,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => toggleFavorite(context, anime),
                child: SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Opacity(opacity: on ? 1 : 0.85, child: icon),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
