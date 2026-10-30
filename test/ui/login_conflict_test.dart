import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/github_auth.dart';
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
  testWidgets('account bound to another profile: switch or use another', (
    tester,
  ) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    final github = FakeGitHub(login: 'yuki-dev')..pendingPolls = 0;
    final profiles = ProfileRepository(db);
    late int kaitoId;
    await tester.runAsync(() async {
      await profiles.bindGitHub(AppDatabase.defaultProfileId, 'yuki-dev');
      kaitoId = (await profiles.create('Каито')).id;
    });
    final tokens = MemoryTokenStore();
    final sync = SyncService(
      library: LibraryRepository(db, profileId: kaitoId),
      db: db,
      tokens: tokens,
      profiles: profiles,
      auth: () => GitHubAuth(
        clientId: 'client',
        httpClient: github.client,
        delay: (_) async {},
      ),
      gistClient: (token) => GistClient(token, httpClient: github.client),
    );
    int? switchedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginFlow(
          sync: sync,
          onDone: () {},
          onSwitchProfile: (id) => switchedTo = id,
        ),
      ),
    );
    await tester.tap(find.text('Войти через GitHub'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Этот аккаунт уже привязан к профилю «Основной»'),
      findsOneWidget,
    );
    expect(find.text('Войти другим аккаунтом'), findsOneWidget);
    expect(tokens.token, isNull);

    await tester.tap(find.text('Переключиться на «Основной»'));
    expect(switchedTo, AppDatabase.defaultProfileId);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await UiHarness.run(tester, db.close);
  });
}
