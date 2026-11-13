import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/profiles/profile_repository.dart';
import '../../data/settings/app_preferences.dart';
import '../../data/sources/youtube_key_check.dart';
import '../../data/sync/sync_service.dart';
import '../../platform/platform.dart' as platform;
import '../app_scope.dart';
import '../login_flow.dart';
import '../profiles/profile_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import '../widgets/notice_plate.dart';
import 'sync_visuals.dart';
import 'share_group.dart';
import '../widgets/toast.dart';

/// Настройки (design/screens.md §7).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Веб-версия (в тестах подменяется).
  @visibleForTesting
  static bool isWeb = platform.isWeb;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        final compact = width < AppLayout.medium;
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(gutter, compact ? 16 : 28, gutter, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Настройки',
                        style: compact
                            ? AppText.headline
                            : AppText.displayStyle,
                      ),
                      const SizedBox(height: 24),
                      const _ProfilesGroup(),
                      _AccountGroup(
                        sync: scope.services.sync,
                        profileName: scope.services.profile.name,
                      ),
                      // Веб-версия: свой ключ YouTube (§18.2), общий для
                      // всех профилей браузера.
                      if (SettingsScreen.isWeb)
                        const _Group(title: 'YouTube', rows: [YouTubeKeyRow()]),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Настройки ниже общие для всех профилей на этом устройстве',
                          style: AppText.label.copyWith(
                            color: context.tokens.fg2,
                          ),
                        ),
                      ),
                      _Group(
                        title: 'Каталог',
                        rows: [
                          _Row(
                            title: 'Показывать 18+',
                            leading: const AdultBadge(),
                            subtitle: 'Тайтлы для взрослых видны в каталоге и поиске с пометкой 18+',
                            inlineOnNarrow: true,
                            trailing: Switch.adaptive(
                              value: settings.showAdult,
                              onChanged: settings.setShowAdult,
                            ),
                            onTap: () =>
                                settings.setShowAdult(!settings.showAdult),
                          ),
                          _Row(
                            title: 'Автопрокрутка каруселей',
                            subtitle:
                                'Онгоинги, «Связанные» и «Рекомендации» '
                                'листаются сами каждые 5 секунд. При '
                                '«уменьшить движение» в системе — выключена',
                            inlineOnNarrow: true,
                            trailing: Switch.adaptive(
                              value: settings.autoScroll,
                              onChanged: settings.setAutoScroll,
                            ),
                            onTap: () =>
                                settings.setAutoScroll(!settings.autoScroll),
                          ),
                        ],
                      ),
                      if (!SettingsScreen.isWeb)
                        _Group(
                          title: 'Плеер',
                          rows: [
                            _Row(
                              title: 'Распознавать музыку',
                              subtitle: 'Короткий фрагмент звука из серии отправляется на сервер AcoustID для распознавания. Кнопка «Что играет» в плеере',
                              inlineOnNarrow: true,
                              trailing: Switch.adaptive(
                                value: settings.musicRecognition,
                                onChanged: settings.setMusicRecognition,
                              ),
                              onTap: () => settings.setMusicRecognition(
                                !settings.musicRecognition,
                              ),
                            ),
                          ],
                        ),
                      _Group(
                        title: 'Оформление',
                        rows: [
                          _Row(
                            title: 'Тема',
                            trailing: _ThemePicker(
                              value: settings.theme,
                              onChanged: settings.setTheme,
                            ),
                          ),
                        ],
                      ),
                      const _Group(
                        title: 'О приложении',
                        rows: [_VersionRow()],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Веб-версия: «Свой ключ YouTube» (design/screens.md §18.2). Ключ
/// хранится только в этом браузере; ключей в публичной сборке нет.
class YouTubeKeyRow extends StatefulWidget {
  const YouTubeKeyRow({
    super.key,
    this.currentKey = platform.youtubeApiKey,
    this.save = platform.saveYoutubeApiKey,
    this.check = checkYouTubeKey,
  });

  final String Function() currentKey;
  final Future<void> Function(String? key) save;
  final Future<YouTubeKeyCheck> Function(String key) check;

  /// «Указать ключ» во вкладке «Сообщество»: прокрутка к полю и фокус.
  static final focusRequest = ValueNotifier<int>(0);

  static const helpUrl =
      'https://console.cloud.google.com/apis/library/youtube.googleapis.com';

  @override
  State<YouTubeKeyRow> createState() => _YouTubeKeyRowState();
}

class _YouTubeKeyRowState extends State<YouTubeKeyRow> {
  final _key = TextEditingController();
  final _focus = FocusNode();
  late final String _current = widget.currentKey();
  String? _error;
  bool _busy = false;

  bool get _hasKey => _current.isNotEmpty;

  @override
  void initState() {
    super.initState();
    YouTubeKeyRow.focusRequest.addListener(_onFocusRequest);
    // Запрос пришёл до того, как вкладка настроек была построена.
    if (YouTubeKeyRow.focusRequest.value != _handled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFocusRequest());
    }
  }

  @override
  void dispose() {
    YouTubeKeyRow.focusRequest.removeListener(_onFocusRequest);
    _key.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Последний выполненный запрос фокуса.
  static int _handled = 0;

  void _onFocusRequest() {
    if (!mounted) return;
    _handled = YouTubeKeyRow.focusRequest.value;
    Scrollable.ensureVisible(context, duration: AppMotion.base);
    _focus.requestFocus();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.check(_key.text);
    if (!mounted) return;
    final error = switch (result) {
      YouTubeKeyCheck.ok => null,
      YouTubeKeyCheck.empty => 'Вставьте ключ',
      YouTubeKeyCheck.invalid =>
        'Ключ не подошёл: YouTube отвечает «ключ неверный». Ключ начинается '
            'с AIza и длиной 39 символов.',
      YouTubeKeyCheck.notEnabled =>
        'В проекте Google Cloud не включён YouTube Data API v3. Включите его '
            'и попробуйте снова.',
      YouTubeKeyCheck.failed =>
        'Не удалось проверить ключ: нет связи с YouTube. Попробуйте ещё раз.',
    };
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      await widget.save(_key.text);
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Свой ключ YouTube',
                style: AppText.bodyStrong.copyWith(color: t.fg),
              ),
              if (_hasKey)
                Text(
                  '✓ Задан · ${maskKey(_current)}',
                  style: AppText.label.copyWith(color: t.good),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.key_rounded, size: 16, color: t.fg2),
                    const SizedBox(width: 4),
                    Text(
                      'Не задан',
                      style: AppText.label.copyWith(color: t.fg2),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hasKey
                ? 'С ключом ищутся трейлеры, официальные серии, комментарии и '
                      '«Сообщество».'
                : 'Без ключа не работают поиск трейлеров, официальные серии на '
                      'YouTube, комментарии и «Сообщество». Ключ YouTube Data '
                      'API v3 бесплатный, создаётся в Google Cloud Console.',
            style: AppText.label.copyWith(color: t.fg2),
          ),
          const SizedBox(height: 12),
          SecretField(
            controller: _key,
            focusNode: _focus,
            label: _hasKey ? 'Новый ключ' : 'Ключ',
            hint: 'AIza…',
            showLabel: 'Показать ключ',
            hideLabel: 'Скрыть ключ',
            error: _error,
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 12),
          const NoticePlate(
            title: 'Ключ хранится только в этом браузере',
            text:
                '(localStorage). В веб-версии видео не встраивается — серии и '
                'трейлеры открываются на YouTube; встроенный плеер есть в '
                'приложении.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Проверить и сохранить'),
              ),
              if (_hasKey)
                OutlinedButton(
                  onPressed: _busy ? null : () => widget.save(null),
                  child: const Text('Удалить ключ'),
                ),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(YouTubeKeyRow.helpUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                label: const Text('Как получить ключ'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppText.overline.copyWith(color: t.fg2),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: t.border),
              // Карточка: тень e1 в светлой теме (в тёмной её нет).
              boxShadow: t.shadowE1,
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.leading,
    this.avatar,
    required this.trailing,
    this.onTap,
    this.inlineOnNarrow = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Слева от подписи (аватар профиля).
  final Widget? avatar;
  final Widget trailing;
  final VoidCallback? onTap;

  /// Компактный контрол (переключатель) остаётся справа и на узком экране.
  final bool inlineOnNarrow;

  /// Уже этой ширины кнопки переносятся под подпись.
  static const narrow = 480.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(child: Text(title, style: AppText.bodyStrong)),
            if (leading != null) ...[const SizedBox(width: 8), leading!],
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: AppText.label.copyWith(color: t.fg2)),
          ),
      ],
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < narrow && !inlineOnNarrow;
              final head = Row(
                children: [
                  if (avatar != null) ...[avatar!, const SizedBox(width: 12)],
                  Expanded(child: texts),
                  if (!stacked) ...[const SizedBox(width: 16), trailing],
                ],
              );
              if (!stacked || trailing is SizedBox) return head;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  head,
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Аватар текущего профиля; обновляется, когда синхронизация получает
/// новый аватар GitHub.
class _CurrentProfileAvatar extends StatelessWidget {
  const _CurrentProfileAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context).services;
    final current = services.profile;
    return StreamBuilder<List<Profile>>(
      stream: services.profiles.watchAll(),
      builder: (context, snapshot) => ProfileAvatar(
        profile:
            snapshot.data?.where((p) => p.id == current.id).firstOrNull ??
            current,
        size: size,
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});

  final ThemePreference value;
  final ValueChanged<ThemePreference> onChanged;

  static const labels = {
    ThemePreference.system: 'Системная',
    ThemePreference.dark: 'Тёмная',
    ThemePreference.light: 'Светлая',
  };

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoSlidingSegmentedControl<ThemePreference>(
        groupValue: value,
        children: {for (final e in labels.entries) e.key: Text(e.value)},
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }
    return SegmentedButton<ThemePreference>(
      showSelectedIcon: false,
      segments: [
        for (final e in labels.entries)
          ButtonSegment(value: e.key, label: Text(e.value)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.sync, required this.profileName});

  final SyncService sync;
  final String profileName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder(
      valueListenable: sync.state,
      builder: (context, state, _) {
        if (state.status == SyncStatus.signedOut) {
          return _Group(
            title: 'Аккаунт профиля «$profileName»',
            rows: [
              _Row(
                title: 'Вход не выполнен',
                subtitle: SettingsScreen.isWeb
                    ? 'Списки хранятся только в этом браузере'
                    : 'Списки хранятся только на этом устройстве',
                trailing: FilledButton(
                  onPressed: sync.canSignIn
                      ? () => pushLoginFlow(
                          context,
                          sync: sync,
                          switchProfile: AppScope.of(context)
                              .services
                              .switchProfile,
                        )
                      : null,
                  child: const Text('Войти через GitHub'),
                ),
              ),
            ],
          );
        }
        final v = syncVisual(state, t);
        final action = switch (state.status) {
          SyncStatus.pending => 'Синхронизировать',
          SyncStatus.error => 'Повторить',
          _ => null,
        };
        return _Group(
          title: 'Аккаунт профиля «$profileName»',
          rows: [
            _Row(
              title: v.label,
              leading: Icon(v.icon, size: 18, color: v.color),
              subtitle: v.detail,
              trailing: action == null
                  ? const SizedBox.shrink()
                  : OutlinedButton(
                      onPressed: sync.syncNow,
                      child: Text(action),
                    ),
            ),
            _Row(
              title: 'GitHub · ${state.login ?? ''}',
              subtitle: 'Списки в приватном Gist',
              avatar: const _CurrentProfileAvatar(size: 56),
              trailing: OutlinedButton(
                onPressed: () async {
                  await sync.signOut();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showToast(
                      SettingsScreen.isWeb
                          ? 'Вы вышли из GitHub, токен стёрт из браузера. '
                                'Списки остались в браузере'
                          : 'Вы вышли из GitHub. Списки остались на устройстве',
                    );
                  }
                },
                child: const Text('Выйти из GitHub'),
              ),
            ),
            ShareGroup(
              sync: sync,
              row: ({required title, subtitle, required trailing}) =>
                  _Row(title: title, subtitle: subtitle, trailing: trailing),
            ),
          ],
        );
      },
    );
  }
}

class _ProfilesGroup extends StatelessWidget {
  const _ProfilesGroup();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = AppScope.of(context).services;
    return StreamBuilder<List<Profile>>(
      stream: services.profiles.watchAll(),
      builder: (context, snapshot) {
        final profiles = snapshot.data ?? [services.profile];
        return _Group(
          title: 'Профили',
          rows: [
            for (final p in profiles)
              FutureBuilder<int>(
                // Ключ по профилю и логину: подпись обновляется после входа.
                key: ValueKey('${p.id}:${p.githubLogin}'),
                future: services.profiles.entryCount(p.id),
                builder: (context, count) {
                  final current = p.id == services.profile.id;
                  return _Row(
                    title: p.name,
                    leading: current
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: t.accentSoft,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              'текущий',
                              style: AppText.caption.copyWith(color: t.accent),
                            ),
                          )
                        : null,
                    avatar: ProfileAvatar(profile: p),
                    subtitle: profileSubtitle(p, count.data ?? 0),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!current)
                          OutlinedButton(
                            onPressed: () => services.switchProfile(p.id),
                            child: const Text('Переключить'),
                          ),
                        if (profiles.length > 1)
                          IconButton(
                            tooltip: 'Удалить профиль «${p.name}»',
                            onPressed: () => confirmDeleteProfile(context, p),
                            icon: const Icon(Symbols.delete_rounded),
                          ),
                      ],
                    ),
                  );
                },
              ),
            _Row(
              title: 'Добавить профиль',
              avatar: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.borderStrong),
                ),
                child: Icon(Symbols.add_rounded, color: t.fg2, size: 20),
              ),
              trailing: const SizedBox.shrink(),
              onTap: () => showAddProfileDialog(context),
            ),
          ],
        );
      },
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  static String _platform() => switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Windows',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null
            ? 'Версия…'
            : 'Версия ${info.version} (сборка ${info.buildNumber}) · ${_platform()}';
        return _Row(
          title: text,
          trailing: TextButton.icon(
            onPressed: info == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showToast('Скопировано');
                  },
            icon: const Icon(Symbols.content_copy_rounded, size: 18),
            label: const Text('Скопировать'),
          ),
        );
      },
    );
  }
}
