import 'package:flutter/material.dart';

/// Сколько тост виден. Один срок для всех тостов приложения.
const toastDuration = Duration(seconds: 10);

/// Тосты приложения — только через [showToast].
///
/// Flutter не скрывает SnackBar с кнопкой действия сам (`persist` по
/// умолчанию `true`, если есть `action`), поэтому «Серия 7 отмечена
/// просмотренной · Отменить» висел, пока его не закроют. Здесь каждый тост
/// скрывается через [toastDuration], а «Отменить» доступна до скрытия.
/// Новый тост заменяет предыдущий, очередь не копится.
extension Toasts on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    clearSnackBars();
    return showSnackBar(
      SnackBar(
        content: Text(text),
        duration: toastDuration,
        persist: false,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }
}
