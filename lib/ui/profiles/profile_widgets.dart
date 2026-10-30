import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/profiles/profile_repository.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Цвета аватаров профилей (5 вариантов).
const profileColors = [
  Color(0xFF6F86F2),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF3987E5),
];

/// Круглый аватар: первая буква имени на цвете профиля.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 36});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: profileColors[profile.color % profileColors.length],
      shape: BoxShape.circle,
    ),
    child: Text(
      profile.name.characters.first.toUpperCase(),
      style: AppText.labelStrong.copyWith(
        color: Colors.white,
        fontSize: size * 0.42,
        height: 1,
      ),
    ),
  );
}

/// Подпись профиля: «3 тайтла · GitHub login» или «· без входа в GitHub».
String profileSubtitle(Profile p, int count) => [
  '$count ${Fmt.plural(count, 'тайтл', 'тайтла', 'тайтлов')}',
  p.githubLogin == null ? 'без входа в GitHub' : 'GitHub ${p.githubLogin}',
].join(' · ');

/// Диалог «Новый профиль»; создаёт профиль и переключается на него.
Future<void> showAddProfileDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _AddProfileDialog(),
);

class _AddProfileDialog extends StatefulWidget {
  const _AddProfileDialog();

  @override
  State<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<_AddProfileDialog> {
  final _name = TextEditingController();
  int _color = 1;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = AppScope.of(context).services;
    try {
      await services.profiles.validateName(_name.text);
      if (mounted) Navigator.pop(context);
      await services.addProfile(_name.text, color: _color);
    } on ProfileException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface2,
      title: Text('Новый профиль', style: AppText.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: ProfileRepository.maxNameLength,
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(labelText: 'Имя', errorText: _error),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < profileColors.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      label: 'Цвет ${i + 1}',
                      selected: i == _color,
                      button: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = i),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: profileColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == _color ? t.fg : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: i == _color
                              ? const Icon(
                                  Symbols.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'У профиля свои списки, вход в GitHub и недавние запросы. '
              'Тема, 18+ и другие настройки устройства общие.',
              style: AppText.label.copyWith(color: t.fg2),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text('Создать и переключиться'),
        ),
      ],
    );
  }
}

/// Удаление профиля с подтверждением (или объяснение, почему нельзя).
Future<void> confirmDeleteProfile(BuildContext context, Profile p) async {
  final services = AppScope.of(context).services;
  final t = context.tokens;
  final messenger = ScaffoldMessenger.of(context);
  if (p.id == services.profile.id) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface2,
        title: Text('Профиль «${p.name}» сейчас открыт', style: AppText.title),
        content: const Text(
          'Это текущий профиль — сначала переключитесь на другой.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
    return;
  }
  final count = await services.profiles.entryCount(p.id);
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: t.surface2,
      title: Text('Удалить профиль «${p.name}»?', style: AppText.title),
      content: Text(
        'Локальные списки этого профиля ($count '
        '${Fmt.plural(count, 'тайтл', 'тайтла', 'тайтлов')}) будут удалены '
        'с устройства. '
        '${p.githubLogin != null ? 'Gist на GitHub (${p.githubLogin}) не трогается — списки можно вернуть, войдя этим аккаунтом в другой профиль.' : 'Профиль не привязан к GitHub, восстановить списки будет нельзя.'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: t.bad,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить профиль'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await services.deleteProfile(p.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            p.githubLogin != null
                ? 'Профиль удалён с устройства. Gist на GitHub не тронут'
                : 'Профиль удалён с устройства',
          ),
        ),
      );
  } on ProfileException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Меню профилей над аватаром внизу NavRail (Windows и широкие экраны).
class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({
    super.key,
    required this.extended,
    required this.onManage,
  });

  final bool extended;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = AppScope.of(context).services;
    final current = services.profile;
    return StreamBuilder<List<Profile>>(
      stream: services.profiles.watchAll(),
      builder: (context, snapshot) {
        final profiles = snapshot.data ?? [current];
        final me =
            profiles.where((p) => p.id == current.id).firstOrNull ?? current;
        return MenuAnchor(
          alignmentOffset: const Offset(0, -8),
          menuChildren: [
            for (final p in profiles)
              MenuItemButton(
                leadingIcon: ProfileAvatar(profile: p, size: 28),
                trailingIcon: p.id == current.id
                    ? Icon(Symbols.check_rounded, size: 18, color: t.accent)
                    : null,
                onPressed: () => services.switchProfile(p.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.name, style: AppText.labelStrong),
                    Text(
                      p.githubLogin ?? 'Без входа в GitHub',
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                  ],
                ),
              ),
            const Divider(height: 8),
            MenuItemButton(
              leadingIcon: const Icon(Symbols.person_add_rounded, size: 20),
              onPressed: () => showAddProfileDialog(context),
              child: const Text('Добавить профиль'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(
                Symbols.manage_accounts_rounded,
                size: 20,
              ),
              onPressed: onManage,
              child: const Text('Управление профилями'),
            ),
          ],
          builder: (context, controller, _) => Semantics(
            button: true,
            label: 'Профиль ${me.name}. Сменить профиль',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: extended
                    ? Row(
                        children: [
                          const SizedBox(width: 8),
                          ProfileAvatar(profile: me, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              me.name,
                              style: AppText.labelStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Symbols.unfold_more_rounded,
                            color: t.fg3,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                        ],
                      )
                    : Column(
                        children: [
                          ProfileAvatar(profile: me, size: 32),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              me.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                fontSize: 11,
                                color: t.fg2,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
