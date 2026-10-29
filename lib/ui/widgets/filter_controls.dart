import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Чип-кнопка высотой 32 со скруглением pill; выбранный — `accentSoft`.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.trailingIcon,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.accent : t.fg;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? t.accentSoft : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? Colors.transparent : t.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: AppText.label.copyWith(color: fg)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailingIcon, size: 18, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Выпадающее меню на основе [PillButton] с галочкой у выбранного пункта.
class PillMenu<T> extends StatelessWidget {
  const PillMenu({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.itemLabel,
    required this.onSelected,
    this.selected = false,
  });

  final String label;
  final List<T> items;
  final T value;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MenuAnchor(
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: () => onSelected(item),
            leadingIcon: SizedBox(
              width: 20,
              child: item == value
                  ? Icon(Symbols.check_rounded, size: 18, color: t.accent)
                  : null,
            ),
            child: Text(itemLabel(item), style: AppText.label),
          ),
      ],
      builder: (context, controller, _) => PillButton(
        label: label,
        selected: selected,
        trailingIcon: Symbols.expand_more_rounded,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
