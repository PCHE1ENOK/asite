import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/token_store.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/sync/sync_service.dart';
import 'package:anime_viewer/ui/login_flow.dart';
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
    final github = FakeGitHub()..token = 'ghp_ok';
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
        home: LoginFlow(sync: sync, onDone: () {}, pasteToken: true),
      ),
    );

    expect(find.text('Токен GitHub (только права gist)'), findsOneWidget);
    expect(find.text('Открыть GitHub'), findsOneWidget);
    expect(find.textContaining('только в этом браузере'), findsOneWidget);
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
    await tester.tap(find.text('Войти'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('fine-grained'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ghp_ok');
    await tester.tap(find.text('Войти'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Вы вошли как octocat'), findsOneWidget);
    expect(tokens.token, 'ghp_ok');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await sync.dispose();
      await db.close();
    });
  });
}
