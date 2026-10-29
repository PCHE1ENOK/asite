import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/state_views.dart';

/// «Мои списки» — пока заготовка: экран со статусами появится вместе
/// с этапом статусов.
class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key, required this.onOpenCatalog});

  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = AppLayout.gutter(constraints.maxWidth);
        final compact = constraints.maxWidth < AppLayout.medium;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? 16 : 28,
                gutter,
                0,
              ),
              child: Text(
                'Мои списки',
                style: compact ? AppText.headline : AppText.displayStyle,
              ),
            ),
            Expanded(
              child: EmptyState(
                icon: Symbols.bookmarks_rounded,
                text: 'Здесь появятся тайтлы из ваших списков',
                hint: 'Отметки «Смотрю», «В планах» и «Просмотрено» скоро будут доступны',
                actionLabel: 'Открыть каталог',
                onAction: onOpenCatalog,
              ),
            ),
          ],
        );
      },
    );
  }
}
