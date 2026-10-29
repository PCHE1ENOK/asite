import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_tokens.dart';

/// Пустое состояние: иконка, одна фраза, одно действие.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: t.fg3),
              const SizedBox(height: AppSpace.s4),
              Text(
                text,
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpace.s2),
                Text(
                  hint!,
                  style: context.text.bodyMedium?.copyWith(color: t.fg2),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: AppSpace.s5),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ошибка: что случилось, как исправить, кнопка «Повторить».
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.hint,
    required this.onRetry,
  });

  final String message;
  final String? hint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Symbols.cloud_off_rounded,
    text: message,
    hint: hint,
    actionLabel: 'Повторить',
    onAction: onRetry,
  );
}
