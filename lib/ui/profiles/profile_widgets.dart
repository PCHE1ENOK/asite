import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/profiles/profile_repository.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/skeleton.dart';
import '../widgets/toast.dart';

/// Круглый аватар профиля: аватар GitHub, если профиль вошёл в GitHub,
/// иначе первая буква имени на цвете профиля (design/screens.md §9.1).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 36});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) => GitHubAvatar(
    url: profile.githubAvatarUrl,
    letter: profile.name,
    color: profile.color,
    size: size,
  );
}

/// Аватар GitHub по [url] с подложкой и обводкой 1 px внутрь; пока
/// грузится — круг-скелетон; нет [url] или картинка не загрузилась —
/// первая буква [letter] на цвете профиля [color]. Картинка кэшируется
/// на устройстве, как обложки.
class GitHubAvatar extends StatelessWidget {
  const GitHubAvatar({
    super.key,
    required this.url,
    required this.letter,
    this.color = 0,
    required this.size,
    this.resolver,
  });

  final String? url;

  /// Загрузчик картинки (тесты); по умолчанию — из [AppScope] или сеть
  /// с дисковым кэшем.
  final ImageResolver? resolver;
  final String letter;
  final int color;
  final double size;

  /// Подсказка, если картинка не загрузилась.
  static const loadError = 'Не удалось загрузить аватар GitHub';

  /// Адрес картинки вдвое больше размера на экране — для чёткости.
  static String sized(String url, double size) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            's': '${(size * 2).round()}',
          },
        )
        .toString();
  }

  /// Токены темы; без темы приложения (экраны поверх неё) — тёмные.
  static AppTokens _tokens(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? AppTokens.dark;

  Widget _letter(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      // Цвет аватара — из токенов темы (design/tokens.json).
      color: _tokens(context).avatar(color),
      shape: BoxShape.circle,
    ),
    child: Text(
      letter.isEmpty ? '?' : letter.characters.first.toUpperCase(),
      style: AppText.labelStrong.copyWith(
        color: AppTokens.onAvatar,
        fontSize: size * 0.42,
        height: 1,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final src = url;
    if (src == null || src.isEmpty) return _letter(context);
    final t = _tokens(context);
    final resolve =
        resolver ?? AppScope.maybeOf(context)?.imageResolver ?? networkImage;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.avatarGround, shape: BoxShape.circle),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: t.avatarRing,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: ClipOval(
        child: Image(
          image: resolve(sized(src, size)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Alt пустой: рядом всегда имя профиля или логин.
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, sync) => sync || frame != null
              ? child
              : Skeleton(width: size, height: size, radius: size / 2),
          errorBuilder: (context, _, _) =>
              Tooltip(message: loadError, child: _letter(context)),
        ),
      ),
    );
  }
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
                for (var i = 0; i < t.avatars.length; i++)
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
                            color: t.avatars[i],
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
                                  color: AppTokens.onAvatar,
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
    messenger.showToast(
      p.githubLogin != null
          ? 'Профиль удалён с устройства. Gist на GitHub не тронут'
          : 'Профиль удалён с устройства',
    );
  } on ProfileException catch (e) {
    messenger.showToast(e.message);
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
                leadingIcon: ProfileAvatar(profile: p, size: 32),
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

/// Быстрый выбор профиля на телефоне (долгое нажатие на вкладку «Профиль»).
Future<void> showProfileSheet(
  BuildContext context, {
  required VoidCallback onManage,
}) {
  final services = AppScope.of(context).services;
  final t = context.tokens;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: t.surface1,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: FutureBuilder<List<Profile>>(
        future: services.profiles.all(),
        builder: (sheet, snapshot) {
          final profiles = snapshot.data ?? [services.profile];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Профили', style: AppText.title),
                ),
              ),
              for (final p in profiles)
                ListTile(
                  minTileHeight: 56,
                  leading: ProfileAvatar(profile: p),
                  title: Text(p.name, style: AppText.bodyStrong),
                  subtitle: Text(
                    p.githubLogin ?? 'Без входа в GitHub',
                    style: AppText.caption.copyWith(color: t.fg2),
                  ),
                  trailing: p.id == services.profile.id
                      ? Icon(Symbols.check_rounded, color: t.accent)
                      : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    services.switchProfile(p.id);
                  },
                ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Symbols.person_add_rounded),
                title: const Text('Добавить профиль'),
                onTap: () {
                  Navigator.pop(sheet);
                  showAddProfileDialog(context);
                },
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Symbols.manage_accounts_rounded),
                title: const Text('Управление профилями'),
                onTap: () {
                  Navigator.pop(sheet);
                  onManage();
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}
