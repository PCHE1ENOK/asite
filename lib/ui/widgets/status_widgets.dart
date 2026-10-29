import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/library_entry.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'status_visuals.dart';

/// Круг цвета статуса с белой иконкой (не только цвет).
class ListStatusDot extends StatelessWidget {
  const ListStatusDot({super.key, required this.status, this.size = 24});

  final ListStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'В списке: ${Fmt.status(status)}',
    excludeSemantics: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.tokens.status[status],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
      ),
      child: Icon(
        statusIcon(status),
        size: size * 0.66,
        color: Colors.white,
        fill: 1,
      ),
    ),
  );
}

/// Статусы, которые можно выбрать в меню.
const selectableStatuses = [
  ListStatus.current,
  ListStatus.planning,
  ListStatus.completed,
  ListStatus.paused,
  ListStatus.dropped,
];

/// Пункты меню статуса: 5 статусов и «Удалить из списка».
List<Widget> statusMenuItems(
  BuildContext context,
  int mediaId,
  ListStatus? current,
) {
  final t = context.tokens;
  final library = AppScope.of(context).services.library;
  return [
    for (final s in selectableStatuses)
      MenuItemButton(
        leadingIcon: Icon(statusIcon(s), color: t.status[s], fill: 1, size: 20),
        trailingIcon:
            s == current ||
                (s == ListStatus.current && current == ListStatus.repeating)
            ? Icon(Symbols.check_rounded, size: 18, color: t.accent)
            : null,
        onPressed: () => library.setStatus(mediaId, s),
        child: Text(Fmt.status(s), style: AppText.label),
      ),
    if (current != null) ...[
      const Divider(height: 8),
      MenuItemButton(
        leadingIcon: Icon(Symbols.delete_rounded, color: t.bad, size: 20),
        onPressed: () => library.remove(mediaId),
        child: Text(
          'Удалить из списка',
          style: AppText.label.copyWith(color: t.bad),
        ),
      ),
    ],
  ];
}

/// Кнопка статуса в карточке тайтла (design: StatusButton).
class StatusButton extends StatelessWidget {
  const StatusButton({super.key, required this.mediaId});

  final int mediaId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final index = AppScope.of(context).library;
    return ListenableBuilder(
      listenable: index,
      builder: (context, _) {
        final status = index[mediaId]?.status;
        return MenuAnchor(
          menuChildren: statusMenuItems(context, mediaId, status),
          builder: (context, controller, _) => OutlinedButton.icon(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: status == null
                ? const Icon(Symbols.add_rounded, size: 20)
                : Icon(
                    statusIcon(status),
                    color: t.status[status],
                    fill: 1,
                    size: 20,
                  ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status == null ? 'Добавить в список' : Fmt.status(status)),
                const SizedBox(width: 4),
                const Icon(Symbols.arrow_drop_down_rounded, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Контекстное меню статуса по правому клику или долгому нажатию.
Future<void> showStatusContextMenu(
  BuildContext context,
  Offset position,
  int mediaId,
) async {
  final t = context.tokens;
  final library = AppScope.of(context).services.library;
  final current = AppScope.of(context).library[mediaId]?.status;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<Object>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final s in selectableStatuses)
        PopupMenuItem(
          value: s,
          child: Row(
            children: [
              Icon(statusIcon(s), color: t.status[s], fill: 1, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(Fmt.status(s))),
              if (s == current)
                Icon(Symbols.check_rounded, size: 18, color: t.accent),
            ],
          ),
        ),
      if (current != null)
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Symbols.delete_rounded, color: t.bad, size: 20),
              const SizedBox(width: 12),
              Text('Удалить из списка', style: TextStyle(color: t.bad)),
            ],
          ),
        ),
    ],
  );
  if (choice is ListStatus) {
    await library.setStatus(mediaId, choice);
  } else if (choice == 'remove') {
    await library.remove(mediaId);
  }
}
