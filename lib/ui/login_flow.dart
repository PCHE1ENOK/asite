import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/github/github_auth.dart';
import '../data/github/github_exception.dart';
import '../data/sync/sync_service.dart';
import '../platform/platform.dart' as platform;
import 'profiles/profile_widgets.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'widgets/notice_plate.dart';

/// Вход через GitHub Device Flow (design/screens.md §5).
///
/// Функциональная заготовка: оформление по дизайну — на этапе 2.
class LoginFlow extends StatefulWidget {
  const LoginFlow({
    super.key,
    required this.sync,
    required this.onDone,
    this.onSwitchProfile,
    this.pasteToken = platform.isWeb,
  });

  final SyncService sync;

  /// Вход вставленным токеном вместо Device Flow (веб-версия: в браузере
  /// Device Flow закрыт CORS).
  final bool pasteToken;

  /// Страница создания classic-токена с отмеченным правом gist.
  static final newTokenUrl = Uri.parse(
    'https://github.com/settings/tokens/new'
    '?scopes=gist&description=Anime%20Viewer%20(%D0%B1%D1%80%D0%B0%D1%83%D0%B7%D0%B5%D1%80)',
  );

  /// Вызывается при входе, пропуске или отмене.
  final VoidCallback onDone;

  /// «Переключиться на «…»», если аккаунт уже привязан к другому профилю.
  final ValueChanged<int>? onSwitchProfile;

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  DeviceCode? _code;
  SignInResult? _result;
  GitHubException? _error;
  bool _busy = false;
  bool _cancelled = false;
  final _token = TextEditingController();
  final _tokenFocus = FocusNode();

  @override
  void dispose() {
    _token.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  Future<void> _signInWithToken() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.sync.signInWithToken(_token.text);
      if (mounted) setState(() => _result = result);
    } on GitHubException catch (e) {
      if (mounted) {
        setState(() => _error = e);
        // Фокус — обратно в поле, к ошибке.
        _tokenFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _tokenForm(ThemeData theme) {
    final t = context.tokens;
    final network = _error?.kind == GitHubErrorKind.network;
    return [
      Text('Вход через GitHub', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text(
        'Списки хранятся в вашем приватном Gist — видите их только вы. '
        'В браузере вход — по токену GitHub с одним правом: gist.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    '1. Откройте на GitHub страницу нового токена — кнопка '
                    'ниже, право gist уже отмечено.\n2. Тип — ',
              ),
              const TextSpan(
                text: 'classic',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                text:
                    '. Других прав не нужно. Срок — на ваш выбор.\n3. Нажмите ',
              ),
              const TextSpan(
                text: 'Generate token',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                text: ', скопируйте токен (ghp_…) и вставьте сюда.',
              ),
            ],
            style: AppText.body.copyWith(color: t.fg),
          ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => launchUrl(
          LoginFlow.newTokenUrl,
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Symbols.open_in_new_rounded, size: 18),
        label: const Text('Открыть GitHub'),
      ),
      const SizedBox(height: 16),
      SecretField(
        controller: _token,
        focusNode: _tokenFocus,
        label: 'Токен GitHub (только право gist)',
        hint: 'ghp_…',
        showLabel: 'Показать токен',
        hideLabel: 'Скрыть токен',
        error: _error == null ? null : _errorText(_error!),
        onSubmitted: (_) => _busy ? null : _signInWithToken(),
      ),
      const SizedBox(height: 16),
      const NoticePlate(
        title: 'Токен хранится только в этом браузере',
        text:
            '(localStorage) — не в Gist и не на сервере. Не входите так на '
            'чужом или общем компьютере. «Выйти» стирает токен из браузера; '
            'отозвать его совсем можно на GitHub.',
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _signInWithToken,
        child: Text(network ? 'Повторить' : 'Войти'),
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      TextButton(
        onPressed: widget.onDone,
        child: const Text('Продолжить без входа'),
      ),
    ];
  }

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
      );
      if (mounted) setState(() => _result = result);
    } on GitHubException catch (e) {
      if (mounted && e.kind != GitHubErrorKind.cancelled) {
        // Возврат к первому шагу, где показаны ошибка и действия.
        setState(() {
          _error = e;
          _code = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (_result case final result?) {
      children.addAll([
        GitHubAvatar(url: result.avatarUrl, letter: result.login, size: 56),
        const SizedBox(height: 12),
        Text(
          'Вы вошли как ${result.login}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          result.gistCreated
              ? 'Создан приватный Gist, перенесено тайтлов с устройства: '
                    '${result.entryCount}'
              : 'Списки объединены: тайтлов ${result.entryCount}, '
                    'более свежая запись взята по ${result.conflicts}',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.onDone,
          child: const Text('Открыть мои списки'),
        ),
      ]);
    } else if (widget.pasteToken) {
      children.addAll(_tokenForm(theme));
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
          child: Text(switch (_error?.kind) {
            null => 'Войти через GitHub',
            GitHubErrorKind.accountInUse => 'Войти другим аккаунтом',
            _ => 'Попробовать снова',
          }),
        ),
        if (_error
            case GitHubException(
              kind: GitHubErrorKind.accountInUse,
              conflictProfileId: final id?,
              conflictProfileName: final name?,
            )
            when widget.onSwitchProfile != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: () => widget.onSwitchProfile!(id),
              child: Text('Переключиться на «$name»'),
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
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }

  static String _errorText(GitHubException e) => switch (e.kind) {
    GitHubErrorKind.accountInUse =>
      '${e.message} Чтобы войти другим аккаунтом, сначала выйдите из этого '
          'на github.com.',
    GitHubErrorKind.network =>
      'Не удалось связаться с GitHub. Проверьте подключение. '
          'Списки на устройстве не пострадали',
    GitHubErrorKind.expired => 'Код устарел',
    GitHubErrorKind.denied => 'Вход отменён на GitHub',
    _ => e.message,
  };
}

/// Открывает вход через GitHub для текущего профиля поверх приложения.
Future<void> pushLoginFlow(
  BuildContext context, {
  required SyncService sync,
  required Future<void> Function(int profileId) switchProfile,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    builder: (context) => LoginFlow(
      sync: sync,
      onDone: () => Navigator.of(context).pop(),
      onSwitchProfile: (id) {
        Navigator.of(context).pop();
        switchProfile(id);
      },
    ),
  ),
);
