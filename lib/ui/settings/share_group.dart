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

/// Что увидят все — в диалоге перед публикацией и рядом со ссылкой
/// (design/screens.md §19.3).
String shareWarning(String nick) =>
    'Ваш каталог станет виден всем, кто найдёт вас по нику GitHub $nick: '
    'списки, «Понравилось», оценки и все заметки, включая тайтлы 18+. '
    'Каталог лежит в публичном Gist и обновляется вместе с синхронизацией.';

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

  /// «@ник» вошедшего аккаунта для текстов.
  String get _nick {
    final login = sync.state.value.login;
    return login == null ? 'GitHub' : '@$login';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: sync.share,
    builder: (context, share, _) {
      final t = context.tokens;
      if (!share.isSharing) {
        return row(
          title: 'Публичный каталог',
          subtitle:
              'Откройте каталог, чтобы друзья нашли вас по нику $_nick во '
              'вкладке «Друзья». Сейчас его видите только вы.',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _start(context),
            icon: const Icon(Symbols.public_rounded, size: 18),
            label: const Text('Открыть каталог'),
          ),
        );
      }
      final at = share.updatedAt;
      final updated = at == null
          ? ''
          : ' Обновлено ${Fmt.relative(at.toLocal())}, вместе с '
                'синхронизацией.';
      return row(
        title: share.isPublic
            ? 'Публичный каталог ✓ включён'
            : 'Каталог открыт только по ссылке',
        subtitle: [
          if (share.isPublic)
            'Друзья находят вас по нику $_nick во вкладке «Друзья». Видны '
                'списки, «Понравилось», оценки и заметки.$updated'
          else
            // Прежняя секретная публикация: по нику её не найти.
            'По нику вас не найти — нажмите «Открыть каталог».$updated',
          if (share.error case final e?) 'Не удалось обновить: $e',
        ].join(' '),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!share.isPublic)
              FilledButton.tonalIcon(
                onPressed: () => _start(context),
                icon: const Icon(Symbols.public_rounded, size: 18),
                label: const Text('Открыть каталог'),
              ),
            OutlinedButton(
              onPressed: () => showShareLink(context, share.gistId!),
              child: const Text('Ссылка'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.bad,
                side: BorderSide(color: t.bad),
              ),
              onPressed: () => _stop(context),
              child: Text(
                share.isPublic
                    ? 'Отключить публичный каталог'
                    : 'Прекратить показ',
              ),
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
        title: Text('Открыть публичный каталог?', style: AppText.title),
        content: Text(
          '${shareWarning(_nick)}\n\nОтключить можно в любой момент в '
          'настройках — каталог перестанет находиться и открываться.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Открыть каталог'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sync.startSharing();
      messenger.showToast('Каталог открыт: друзья найдут вас по нику $_nick');
    } on GitHubException catch (e) {
      messenger.showToast('Не удалось открыть каталог: ${e.message}');
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.tokens;
        return AlertDialog(
          backgroundColor: t.surface2,
          title: Text('Отключить публичный каталог?', style: AppText.title),
          content: const Text(
            'Публичный Gist с каталогом будет удалён. Вас перестанут находить '
            'по нику, а у друзей ваш каталог перестанет открываться. Ваши '
            'списки и заметки останутся у вас.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.bad),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Отключить публичный каталог'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sync.stopSharing();
      messenger.showToast('Публичный каталог отключён, Gist удалён');
    } on GitHubException catch (e) {
      messenger.showToast('Не удалось отключить: ${e.message}');
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
            'По ссылке каталог откроется в браузере, без приложения: '
            'списки, «Понравилось», оценки и все заметки, включая 18+.',
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
