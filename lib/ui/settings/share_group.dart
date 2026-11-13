import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../config/app_config.dart';
import '../../data/github/github_exception.dart';
import '../../data/sync/sync_service.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/toast.dart';

/// Что видит друг по ссылке — в каждом диалоге, до и после публикации.
const shareWarning =
    'Ваш каталог станет виден всем, кто найдёт вас по нику GitHub: списки, '
    '«Понравилось», оценки и все заметки, включая 18+. Ссылку и поиск можно '
    'отключить в любой момент — Gist удаляется';

/// «Поделиться каталогом»: публичный Gist с `anime-viewer-share.json` —
/// друзья находят его по нику GitHub («Друзья») или открывают по ссылке;
/// «Прекратить показ» удаляет Gist.
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
              'Друзья найдут ваш каталог по нику GitHub или откроют по '
              'ссылке в браузере — только просмотр',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _start(context),
            icon: const Icon(Symbols.share_rounded, size: 18),
            label: const Text('Поделиться'),
          ),
        );
      }
      final at = share.updatedAt;
      return row(
        title: share.isPublic
            ? 'Каталог открыт: по нику и по ссылке'
            : 'Каталог открыт по ссылке',
        subtitle: [
          // Прежняя секретная публикация: по нику её не найти.
          if (!share.isPublic)
            'Чтобы друзья нашли вас по нику, нажмите «Открыть по нику»',
          if (at != null) 'Обновлено ${Fmt.relative(at.toLocal())}',
          if (share.error case final e?) 'Не удалось обновить: $e',
          'Обновляется вместе с синхронизацией, не чаще раза в 5 минут',
        ].join(' · '),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!share.isPublic)
              FilledButton.tonal(
                onPressed: () => _start(context),
                child: const Text('Открыть по нику'),
              ),
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
            child: const Text('Сделать каталог публичным'),
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
      messenger.showToast('Не удалось поделиться: ${e.message}');
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.tokens.surface2,
        title: Text('Прекратить показ?', style: AppText.title),
        content: const Text(
          'Gist с каталогом будет удалён: ссылка перестанет работать, а '
          'друзья не найдут вас по нику',
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
      messenger.showToast('Показ прекращён, ссылка удалена');
    } on GitHubException catch (e) {
      messenger.showToast('Не удалось удалить ссылку: ${e.message}');
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
            ScaffoldMessenger.of(context).showToast('Ссылка скопирована');
          },
          icon: const Icon(Symbols.content_copy_rounded, size: 18),
          label: const Text('Скопировать'),
        ),
      ],
    ),
  );
}
