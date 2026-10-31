import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../config/app_config.dart';
import '../../data/github/github_exception.dart';
import '../../data/sync/sync_service.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Что видит друг по ссылке — в каждом диалоге, до и после публикации.
const shareWarning =
    'Кто знает ссылку, видит ваши списки, «Понравилось», оценки и все '
    'заметки, включая тайтлы 18+. Ссылку можно отозвать — Gist удаляется.';

/// «Поделиться каталогом»: секретный Gist с `share.json` и ссылка на
/// страницу просмотра; «Прекратить показ» удаляет Gist.
class ShareGroup extends StatelessWidget {
  const ShareGroup({super.key, required this.sync, required this.row});

  final SyncService sync;

  /// Строка настроек (заголовок, подпись, действие) — как у остальных.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget trailing,
  })
  row;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: sync.share,
    builder: (context, share, _) {
      if (!share.isSharing) {
        return row(
          title: 'Поделиться каталогом',
          subtitle:
              'Друзья откроют ваш каталог по ссылке в браузере, без '
              'регистрации — только просмотр',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _start(context),
            icon: const Icon(Symbols.share_rounded, size: 18),
            label: const Text('Поделиться'),
          ),
        );
      }
      final at = share.updatedAt;
      return row(
        title: 'Каталог открыт по ссылке',
        subtitle: [
          if (at != null) 'Обновлено ${Fmt.relative(at.toLocal())}',
          if (share.error case final e?) 'Не удалось обновить: $e',
          'Обновляется вместе с синхронизацией, не чаще раза в 5 минут',
        ].join(' · '),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => showShareLink(context, share.gistId!),
              child: const Text('Ссылка'),
            ),
            TextButton(
              onPressed: () => _stop(context),
              child: const Text('Прекратить показ'),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _start(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.tokens.surface2,
        title: Text('Поделиться каталогом?', style: AppText.title),
        content: const Text(shareWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Создать ссылку'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await sync.startSharing();
      if (context.mounted) await showShareLink(context, id);
    } on GitHubException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось поделиться: ${e.message}')),
      );
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.tokens.surface2,
        title: Text('Прекратить показ?', style: AppText.title),
        content: const Text(
          'Gist с каталогом будет удалён, ссылка перестанет работать у всех, '
          'кому вы её отправили',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Прекратить показ'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sync.stopSharing();
      messenger.showSnackBar(
        const SnackBar(content: Text('Показ прекращён, ссылка удалена')),
      );
    } on GitHubException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось удалить ссылку: ${e.message}')),
      );
    }
  }
}

/// Ссылка на каталог с «Скопировать» и напоминанием, что она открывает.
Future<void> showShareLink(BuildContext context, String gistId) {
  final link = AppConfig.shareLink(gistId).toString();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.tokens.surface2,
      title: Text('Ссылка на каталог', style: AppText.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(link, style: AppText.bodyStrong),
          const SizedBox(height: 12),
          Text(
            shareWarning,
            style: AppText.label.copyWith(color: context.tokens.fg2),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
          },
          icon: const Icon(Symbols.content_copy_rounded, size: 18),
          label: const Text('Скопировать'),
        ),
      ],
    ),
  );
}
