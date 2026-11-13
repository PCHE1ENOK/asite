import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Плашка-предупреждение со значком (по умолчанию замок в цвете `warn`):
/// [title] жирным, затем [text] (design/screens.md §18).
class NoticePlate extends StatelessWidget {
  const NoticePlate({
    super.key,
    required this.title,
    required this.text,
    this.icon = Symbols.lock_rounded,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: t.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' $text'),
                ],
              ),
              style: AppText.label.copyWith(color: t.fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле для секрета (токен, ключ): скрытый ввод моноширинным шрифтом,
/// кнопка-глаз, без автозаполнения и проверки орфографии.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.showLabel,
    required this.hideLabel,
    this.error,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String showLabel;
  final String hideLabel;
  final String? error;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: widget.focusNode,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: null,
    keyboardType: TextInputType.visiblePassword,
    style: const TextStyle(fontFamily: 'monospace'),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      errorText: widget.error,
      errorMaxLines: 4,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: _visible ? widget.hideLabel : widget.showLabel,
        onPressed: () => setState(() => _visible = !_visible),
        icon: Icon(
          _visible
              ? Symbols.visibility_off_rounded
              : Symbols.visibility_rounded,
        ),
      ),
    ),
    onSubmitted: widget.onSubmitted,
  );
}
