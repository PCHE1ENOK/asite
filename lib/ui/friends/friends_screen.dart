import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/friends/friends_repository.dart';
import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
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

/// «Друзья» (design/screens.md §19.1): поиск публичного каталога по нику
/// GitHub, список друзей (локально в профиле) и их каталоги.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.onOpenTitle});

  /// Карточка тайтла из каталога друга.
  final ValueChanged<Anime> onOpenTitle;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _query = TextEditingController();
  FriendLookup? _result;
  String? _searching;
  bool _loaded = false;

  /// Каталоги друзей из кэша — для карточек (счётчики, дата, имя).
  final _cached = <String, FriendCatalog?>{};

  FriendsRepository get _friends => AppScope.of(context).services.friends;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _friends.load().then((_) => _loadCached());
  }

  Future<void> _loadCached() async {
    final friends = _friends;
    for (final f in friends.friends.value) {
      if (_cached.containsKey(f.login)) continue;
      final c = await friends.cached(f.login);
      if (!mounted) return;
      setState(() => _cached[f.login] = c);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final nick = _query.text.trim().replaceFirst(RegExp('^@'), '');
    if (nick.isEmpty || _searching != null) return;
    setState(() {
      _searching = nick;
      _result = null;
    });
    final r = await _friends.find(nick);
    if (!mounted) return;
    setState(() {
      _searching = null;
      _result = r;
      if (r is FriendFound) _cached[r.login] = r.catalog;
    });
  }

  Future<void> _add(FriendFound found) async {
    await _friends.add(found);
    if (!mounted) return;
    setState(() {});
    final name = found.catalog?.owner;
    ScaffoldMessenger.of(context).showToast(
      '${name == null || name.isEmpty ? found.login : name} в друзьях',
    );
  }

  Future<void> _open(Friend f) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FriendCatalogScreen(friend: f, onOpenTitle: widget.onOpenTitle),
      ),
    );
    // Каталог мог обновиться — свежие счётчики.
    if (!mounted) return;
    final c = await _friends.cached(f.login);
    if (mounted) setState(() => _cached[f.login] = c);
  }

  Friend? _friendOf(String login) => _friends.friends.value
      .where((f) => f.login.toLowerCase() == login.toLowerCase())
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).services.sync;
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
                Text(
                  'Друзья',
                  style: compact ? AppText.headline : AppText.displayStyle,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: signedIn
                        ? _search(context, compact)
                        : _signInFirst(context, sync),
                  ),
                ),
                const SizedBox(height: 28),
                _list(context, width, compact),
              ],
            );
          },
        );
      },
    );
  }

  Widget _card(AppTokens t, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface1,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: t.border),
      boxShadow: t.shadowE1,
    ),
    child: child,
  );

  Widget _signInFirst(BuildContext context, SyncService sync) {
    final t = context.tokens;
    return _card(
      t,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Войдите через GitHub, чтобы искать друзей',
            style: AppText.bodyStrong.copyWith(color: t.fg),
          ),
          const SizedBox(height: 4),
          Text(
            'Друзья находятся по нику GitHub, а их каталоги лежат в '
            'публичных Gist. Поиск идёт через GitHub API с вашим входом.',
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

  Widget _search(BuildContext context, bool compact) {
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
                  prefixIcon: Icon(Symbols.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _searching == null ? _find : null,
              child: const Text('Найти'),
            ),
          ],
        ),
        if (_searching case final nick?) ...[
          const SizedBox(height: 16),
          _card(
            t,
            Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _texts(
                    t,
                    'Ищем @$nick…',
                    'Проверяем ник на GitHub и публичный каталог.',
                  ),
                ),
              ],
            ),
          ),
        ] else if (_result case final r?) ...[
          const SizedBox(height: 16),
          switch (r) {
            FriendFound() => _found(context, r, compact),
            FriendNoCatalog(:final login, :final avatarUrl) => _card(
              t,
              Row(
                children: [
                  GitHubAvatar(url: avatarUrl, letter: login, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _texts(
                      t,
                      'У @$login нет публичного каталога',
                      'Пользователь есть на GitHub, но не открыл каталог. '
                          'Попросите включить «Публичный каталог» в '
                          'настройках приложения.',
                    ),
                  ),
                ],
              ),
            ),
            FriendNotFound() => _card(
              t,
              _texts(
                t,
                'На GitHub нет пользователя @${_query.text.trim().replaceFirst(RegExp('^@'), '')}',
                'Проверьте ник — он такой же, как в адресе github.com/ник.',
              ),
            ),
            FriendRateLimited(:final retryAt) => _card(
              t,
              _texts(
                t,
                'Лимит поиска GitHub исчерпан',
                'GitHub ограничивает число запросов в час. Попробуйте '
                    '${_inMinutes(retryAt)} — список друзей и их каталоги '
                    'открываются как обычно.',
              ),
            ),
            FriendSignInRequired() => _card(
              t,
              _texts(t, 'Войдите через GitHub, чтобы искать друзей', null),
            ),
            FriendLookupFailed() => _card(
              t,
              _texts(
                t,
                'Не удалось связаться с GitHub',
                'Проверьте подключение и попробуйте ещё раз.',
              ),
            ),
          },
        ],
      ],
    );
  }

  /// «через 12 минут» по `X-RateLimit-Reset`; нет — «через час».
  static String _inMinutes(DateTime? at) {
    if (at == null) return 'через час';
    final m = at.difference(DateTime.now()).inMinutes.clamp(1, 60);
    return 'через $m ${Fmt.plural(m, 'минуту', 'минуты', 'минут')}';
  }

  Widget _texts(AppTokens t, String title, String? hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppText.bodyStrong.copyWith(color: t.fg)),
      if (hint != null) ...[
        const SizedBox(height: 2),
        Text(hint, style: AppText.label.copyWith(color: t.fg2)),
      ],
    ],
  );

  /// «@ник · 10 тайтлов · обновлено вчера».
  static String _subtitle(String login, FriendCatalog? c, int? count) {
    final n = count ?? c?.titles.length;
    return [
      '@$login',
      if (n != null) '$n ${Fmt.plural(n, 'тайтл', 'тайтла', 'тайтлов')}',
      if (c?.updatedAt case final at?) 'обновлено ${Fmt.relative(at)}',
    ].join(' · ');
  }

  Widget _found(BuildContext context, FriendFound f, bool compact) {
    final t = context.tokens;
    final friend = _friendOf(f.login);
    final name = f.catalog?.owner;
    final action = friend != null
        ? OutlinedButton.icon(
            onPressed: () => _open(friend),
            icon: const Icon(Symbols.check_rounded, size: 18),
            label: const Text('В друзьях'),
          )
        : FilledButton.icon(
            onPressed: () => _add(f),
            icon: const Icon(Symbols.person_add_rounded),
            label: const Text('Добавить в друзья'),
          );
    final info = Row(
      children: [
        GitHubAvatar(url: f.avatarUrl, letter: name ?? f.login, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name == null || name.isEmpty ? f.login : name,
                style: AppText.bodyStrong.copyWith(color: t.fg),
              ),
              Text(
                _subtitle(f.login, f.catalog, f.titleCount),
                style: AppText.label.copyWith(color: t.fg2),
              ),
              if (f.catalog case final c?) ...[
                const SizedBox(height: 4),
                _Counters(catalog: c),
              ],
            ],
          ),
        ),
        if (!compact) ...[const SizedBox(width: 12), action],
      ],
    );
    return _card(
      t,
      compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), action],
            )
          : info,
    );
  }

  Widget _list(BuildContext context, double width, bool compact) {
    final t = context.tokens;
    return ValueListenableBuilder<List<Friend>>(
      valueListenable: _friends.friends,
      builder: (context, friends, _) {
        if (friends.isEmpty) {
          return const EmptyState(
            icon: Symbols.group_rounded,
            text: 'Пока нет друзей',
            hint:
                'Найдите друга по нику GitHub. У него в настройках должен '
                'быть включён «Публичный каталог».',
          );
        }
        // Новые друзья без кэша — подгрузить счётчики.
        if (friends.any((f) => !_cached.containsKey(f.login))) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadCached());
        }
        // По дате обновления каталога, свежие первыми.
        final sorted = [...friends]
          ..sort((a, b) {
            final x = _cached[a.login]?.updatedAt ?? a.addedAt;
            final y = _cached[b.login]?.updatedAt ?? b.addedAt;
            return y.compareTo(x);
          });
        const gap = 16.0;
        final cols = compact
            ? 1
            : ((width + gap) / (320 + gap)).floor().clamp(1, 4);
        final itemWidth =
            (width - AppLayout.gutter(width) * 2 - gap * (cols - 1)) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Мои друзья · ${friends.length}',
              style: AppText.title.copyWith(color: t.fg),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final f in sorted)
                  SizedBox(
                    width: compact ? double.infinity : itemWidth,
                    child: _FriendCard(
                      friend: f,
                      catalog: _cached[f.login],
                      onTap: () => _open(f),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Карточка друга: аватар 48, имя, «@ник · N тайтлов · обновлено …»,
/// счётчики, шеврон.
class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.catalog,
    required this.onTap,
  });

  final Friend friend;
  final FriendCatalog? catalog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = catalog;
    final name = c?.owner.isNotEmpty ?? false ? c!.owner : friend.displayName;
    return Material(
      color: t.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              GitHubAvatar(url: friend.avatarUrl, letter: name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong.copyWith(color: t.fg),
                    ),
                    Text(
                      _FriendsScreenState._subtitle(friend.login, c, null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                    if (c != null) ...[
                      const SizedBox(height: 4),
                      _Counters(catalog: c),
                    ],
                  ],
                ),
              ),
              Icon(Symbols.chevron_right_rounded, color: t.fg3),
            ],
          ),
        ),
      ),
    );
  }
}

/// «● смотрю 3 · ● просмотрено 7 · ● понравилось 3».
class _Counters extends StatelessWidget {
  const _Counters({required this.catalog});

  final FriendCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget item(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: AppText.caption.copyWith(color: t.fg2)),
      ],
    );
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        item(t.status[ListStatus.current]!, 'смотрю ${catalog.watching}'),
        item(
          t.status[ListStatus.completed]!,
          'просмотрено ${catalog.completed}',
        ),
        item(t.bad, 'понравилось ${catalog.favorites}'),
      ],
    );
  }
}
