import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/token_store.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/sync/sync_service.dart';
import 'package:anime_viewer/ui/login_flow.dart';
import 'package:anime_viewer/ui/theme/app_theme.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../github_fakes.dart';
import 'ui_harness.dart';

void main() {
  testWidgets('web: paste a classic gist token, errors, then sign in', (
    tester,
  ) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final github = FakeGitHub()
      ..token = 'ghp_ok'
      // Без картинки: в тесте нет сети, аватар — буква.
      ..avatarUrl = null;
    final tokens = MemoryTokenStore();
    final sync = SyncService(
      library: LibraryRepository(db),
      db: db,
      tokens: tokens,
      profiles: ProfileRepository(db),
      // Device Flow в браузере нет.
      auth: () => null,
      gistClient: (token) => GistClient(token, httpClient: github.client),
      tokenSignIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: LoginFlow(sync: sync, onDone: () {}, pasteToken: true),
      ),
    );

    expect(find.text('Токен GitHub (только право gist)'), findsOneWidget);
    expect(find.text('Открыть GitHub'), findsOneWidget);
    expect(
      find.textContaining(
        'Токен хранится только в этом браузере',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // Кнопка-глаз показывает и скрывает токен.
    expect(find.byTooltip('Показать токен'), findsOneWidget);
    await tester.tap(find.byTooltip('Показать токен'));
    await tester.pump();
    expect(find.byTooltip('Скрыть токен'), findsOneWidget);

    await tester.ensureVisible(find.text('Войти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Вставьте токен'), findsOneWidget);
    expect(
      find.text('Вход недоступен: не задан GITHUB_CLIENT_ID'),
      findsNothing,
    );
    expect(
      LoginFlow.newTokenUrl.queryParameters['scopes'],
      'gist',
      reason: 'страница GitHub открывается с отмеченным gist',
    );

    await tester.enterText(find.byType(TextField), 'github_pat_x');
    await tester.ensureVisible(find.text('Войти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('fine-grained'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ghp_ok');
    await tester.ensureVisible(find.text('Войти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Вы вошли как octocat'), findsOneWidget);
    expect(
      find.text('O'),
      findsOneWidget,
      reason: 'аватар без картинки — буква',
    );
    expect(tokens.token, 'ghp_ok');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await sync.dispose();
      await db.close();
    });
  });
}
