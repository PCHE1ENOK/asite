import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/github/github_auth.dart';
import '../data/github/github_exception.dart';
import '../data/sync/library_merge.dart';
import '../data/sync/sync_service.dart';

/// Вход через GitHub Device Flow (design/screens.md §5).
///
/// Функциональная заготовка: оформление по дизайну — на этапе 2.
class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key, required this.sync, required this.onDone});

  final SyncService sync;

  /// Вызывается при входе, пропуске или отмене.
  final VoidCallback onDone;

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  DeviceCode? _code;
  SignInResult? _result;
  GitHubException? _error;
  bool _busy = false;
  bool _cancelled = false;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
      _cancelled = false;
    });
    try {
      final code = await widget.sync.requestDeviceCode();
      if (!mounted) return;
      setState(() => _code = code);
      final result = await widget.sync.completeSignIn(
        code,
        isCancelled: () => _cancelled || !mounted,
        resolveConflict: _askConflict,
      );
      if (mounted) setState(() => _result = result);
    } on GitHubException catch (e) {
      if (mounted && e.kind != GitHubErrorKind.cancelled) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<MergeStrategy> _askConflict() async {
    final choice = await showDialog<MergeStrategy>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Списки есть и здесь, и в Gist'),
        content: const Text(
          'Объединить: по каждому тайтлу останется более свежая запись.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, MergeStrategy.preferLocal),
            child: const Text('Оставить с устройства'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, MergeStrategy.preferRemote),
            child: const Text('Взять из Gist'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, MergeStrategy.merge),
            child: const Text('Объединить'),
          ),
        ],
      ),
    );
    return choice ?? MergeStrategy.merge;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (_result case final result?) {
      children.addAll([
        Text(
          'Вы вошли как ${result.login}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          result.gistCreated
              ? 'Создан приватный Gist, перенесено тайтлов: ${result.entryCount}'
              : 'Списки загружены из Gist',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.onDone,
          child: const Text('Открыть мои списки'),
        ),
      ]);
    } else if (_code case final code?) {
      children.addAll([
        Text(
          'Откройте ${code.verificationUri.host}${code.verificationUri.path} '
          'и введите код',
        ),
        const SizedBox(height: 16),
        SelectableText(code.userCode, style: theme.textTheme.displaySmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: code.userCode)),
              child: const Text('Копировать'),
            ),
            OutlinedButton(
              onPressed: () => launchUrl(
                code.verificationUri,
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Открыть в браузере'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        TextButton(
          onPressed: () => setState(() {
            _cancelled = true;
            _code = null;
          }),
          child: const Text('Отмена'),
        ),
      ]);
    } else {
      children.addAll([
        Text('Вход через GitHub', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'Списки хранятся в вашем приватном Gist — видите их только вы.\n'
          'Одинаково на Windows, iPhone и Android.\n'
          'Без входа всё работает, но только на этом устройстве.',
          textAlign: TextAlign.center,
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            _errorText(error),
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.sync.canSignIn && !_busy ? _start : null,
          child: Text(
            _error == null ? 'Войти через GitHub' : 'Попробовать снова',
          ),
        ),
        if (!widget.sync.canSignIn)
          const Text('Вход недоступен: не задан GITHUB_CLIENT_ID'),
        TextButton(
          onPressed: widget.onDone,
          child: const Text('Продолжить без входа'),
        ),
        Text(
          'Приложение просит только доступ к Gist',
          style: theme.textTheme.bodySmall,
        ),
      ]);
    }

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }

  static String _errorText(GitHubException e) => switch (e.kind) {
    GitHubErrorKind.network =>
      'Не удалось связаться с GitHub. Проверьте подключение. '
          'Списки на устройстве не пострадали',
    GitHubErrorKind.expired => 'Код устарел',
    GitHubErrorKind.denied => 'Вход отменён на GitHub',
    _ => e.message,
  };
}
