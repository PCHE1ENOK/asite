import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/friends/friends_repository.dart';
import '../../data/sync/sync_service.dart';
import '../app_scope.dart';
import '../format.dart';
import '../login_flow.dart';
import '../profiles/profile_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/state_views.dart';
import '../widgets/toast.dart';
import 'friend_catalog_screen.dart';

/// «Друзья»: поиск публичного каталога по нику GitHub, список друзей
/// (локально в профиле) и просмотр их каталогов.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _query = TextEditingController();
  FriendLookup? _result;
  bool _busy = false;
  bool _loaded = false;

  FriendsRepository get _friends => AppScope.of(context).services.friends;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _friends.load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_query.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await _friends.find(_query.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r;
      });
    }
  }

  Future<void> _add(FriendFound found) async {
    await _friends.add(found);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showToast('${found.login} — в друзьях');
  }

  Future<void> _remove(Friend friend) async {
    final friends = _friends;
    await friends.remove(friend.login);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showToast(
      '${friend.login} удалён из друзей',
      actionLabel: 'Отменить',
      onAction: () => friends.restore(friend),
    );
  }

  void _open(Friend f) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => FriendCatalogScreen(friend: f)),
  );

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sync = scope.services.sync;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        final compact = width < AppLayout.medium;
        return ValueListenableBuilder<SyncState>(
          valueListenable: sync.state,
          builder: (context, state, _) {
            final signedIn = state.status != SyncStatus.signedOut;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? 16 : 28,
                gutter,
                32,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Друзья',
                          style: compact
                              ? AppText.headline
                              : AppText.displayStyle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Каталоги друзей: их списки, «Понравилось» и '
                          'заметки. У друга должен быть включён «Поделиться '
                          'каталогом».',
                          style: AppText.label.copyWith(
                            color: context.tokens.fg2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (signedIn)
                          _search(context)
                        else
                          _signInFirst(context, sync),
                        const SizedBox(height: 28),
                        _list(context),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _signInFirst(BuildContext context, SyncService sync) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Поиск друзей — после входа',
            style: AppText.bodyStrong.copyWith(color: t.fg),
          ),
          const SizedBox(height: 4),
          Text(
            'Поиск по нику идёт через GitHub API; без входа GitHub даёт '
            'слишком мало запросов.',
            style: AppText.label.copyWith(color: t.fg2),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: sync.canSignIn
                ? () => pushLoginFlow(
                    context,
                    sync: sync,
                    switchProfile: AppScope.of(context).services.switchProfile,
                  )
                : null,
            child: const Text('Войти через GitHub'),
          ),
        ],
      ),
    );
  }

  Widget _search(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Найти друга по нику GitHub',
                  hintText: 'octocat',
                  prefixIcon: Icon(Symbols.alternate_email_rounded),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _find,
              child: const Text('Найти'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_result case final r?) ...[
          const SizedBox(height: 16),
          switch (r) {
            FriendFound() => _found(context, r),
            FriendNotFound() => _message(
              t,
              Symbols.person_search_rounded,
              'У этого пользователя нет публичного каталога',
            ),
            FriendRateLimited() => _message(
              t,
              Symbols.hourglass_empty_rounded,
              'GitHub временно ограничил число запросов. Попробуйте через час',
            ),
            FriendSignInRequired() => _message(
              t,
              Symbols.login_rounded,
              'Войдите через GitHub, чтобы искать друзей',
            ),
            FriendLookupFailed() => _message(
              t,
              Symbols.cloud_off_rounded,
              'Не удалось связаться с GitHub. Проверьте подключение',
            ),
          },
        ],
      ],
    );
  }

  Widget _message(AppTokens t, IconData icon, String text) => Row(
    children: [
      Icon(icon, color: t.fg2, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: AppText.body.copyWith(color: t.fg)),
      ),
    ],
  );

  Widget _found(BuildContext context, FriendFound f) {
    final t = context.tokens;
    final already = _friends.contains(f.login);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          GitHubAvatar(url: f.avatarUrl, letter: f.login, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.login, style: AppText.bodyStrong.copyWith(color: t.fg)),
                Text(
                  '${f.titleCount} '
                  '${Fmt.plural(f.titleCount, 'тайтл', 'тайтла', 'тайтлов')}',
                  style: AppText.label.copyWith(color: t.fg2),
                ),
              ],
            ),
          ),
          if (already)
            const OutlinedButton(onPressed: null, child: Text('Уже в друзьях'))
          else
            FilledButton.icon(
              onPressed: () => _add(f),
              icon: const Icon(Symbols.person_add_rounded),
              label: const Text('Добавить в друзья'),
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<List<Friend>>(
      valueListenable: _friends.friends,
      builder: (context, friends, _) {
        if (friends.isEmpty) {
          return const EmptyState(
            icon: Symbols.group_rounded,
            text: 'Пока нет друзей',
            hint:
                'Найдите друга по нику GitHub. Чтобы вас нашли — '
                '«Настройки → Аккаунт профиля → Поделиться каталогом».',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('МОИ ДРУЗЬЯ', style: AppText.overline.copyWith(color: t.fg2)),
            const SizedBox(height: 8),
            for (final f in friends)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: GitHubAvatar(
                  url: f.avatarUrl,
                  letter: f.login,
                  size: 40,
                ),
                title: Text(f.login, style: AppText.bodyStrong),
                subtitle: Text(
                  'в друзьях с ${Fmt.dayMonth(f.addedAt)} '
                  '${f.addedAt.toLocal().year}',
                  style: AppText.caption.copyWith(color: t.fg2),
                ),
                onTap: () => _open(f),
                trailing: IconButton(
                  tooltip: 'Удалить ${f.login} из друзей',
                  onPressed: () => _remove(f),
                  icon: const Icon(Symbols.person_remove_rounded),
                ),
              ),
          ],
        );
      },
    );
  }
}
