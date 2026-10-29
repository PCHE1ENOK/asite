import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/settings/app_preferences.dart';
import '../../data/sync/sync_service.dart';
import '../app_scope.dart';
import '../login_flow.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import 'sync_visuals.dart';

/// Настройки (design/screens.md §7).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                      _AccountGroup(sync: scope.services.sync),
                      _Group(
                        title: 'Каталог',
                        rows: [
                          _Row(
                            title: 'Показывать 18+',
                            leading: const AdultBadge(),
                            subtitle: 'Тайтлы для взрослых видны в каталоге и поиске с пометкой 18+',
                            trailing: Switch.adaptive(
                              value: settings.showAdult,
                              onChanged: settings.setShowAdult,
                            ),
                            onTap: () =>
                                settings.setShowAdult(!settings.showAdult),
                          ),
                        ],
                      ),
                      _Group(
                        title: 'Плеер',
                        rows: [
                          _Row(
                            title: 'Распознавать музыку',
                            subtitle: 'Короткий фрагмент звука из серии отправляется на сервер AcoustID для распознавания. Кнопка «Что играет» в плеере',
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
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: AppText.bodyStrong)),
                        if (leading != null) ...[
                          const SizedBox(width: 8),
                          leading!,
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: AppText.label.copyWith(color: t.fg2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              trailing,
            ],
          ),
        ),
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
  const _AccountGroup({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder(
      valueListenable: sync.state,
      builder: (context, state, _) {
        if (state.status == SyncStatus.signedOut) {
          return _Group(
            title: 'Аккаунт и синхронизация',
            rows: [
              _Row(
                title: 'Вход не выполнен',
                subtitle: 'Списки хранятся только на этом устройстве',
                trailing: FilledButton(
                  onPressed: sync.canSignIn
                      ? () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (context) => LoginFlow(
                              sync: sync,
                              onDone: () => Navigator.of(context).pop(),
                            ),
                          ),
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
          title: 'Аккаунт и синхронизация',
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
              trailing: OutlinedButton(
                onPressed: () async {
                  await sync.signOut();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Вы вышли из GitHub. Списки остались на устройстве',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Выйти из GitHub'),
              ),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                  },
            icon: const Icon(Symbols.content_copy_rounded, size: 18),
            label: const Text('Скопировать'),
          ),
        );
      },
    );
  }
}
