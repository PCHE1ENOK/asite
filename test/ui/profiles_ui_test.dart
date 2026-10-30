import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/ui/profiles/profile_widgets.dart';
import 'package:anime_viewer/ui/widgets/status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Настройки').first);
    await UiHarness.settle(tester);
  }

  Future<void> addProfile(WidgetTester tester, String name) async {
    await tester.tap(find.text('Добавить профиль'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Создать и переключиться'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('settings: profiles group, add with validation, switch', (
    tester,
  ) async {
    await h.pump(tester);
    await openSettings(tester);

    expect(find.text('Профили'.toUpperCase()), findsOneWidget);
    expect(find.text('Основной'), findsWidgets);
    expect(find.text('текущий'), findsOneWidget);
    expect(find.text('АККАУНТ ПРОФИЛЯ «ОСНОВНОЙ»'), findsOneWidget);

    await tester.tap(find.text('Добавить профиль'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и переключиться'));
    await UiHarness.settle(tester);
    expect(find.text('Введите имя профиля'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'основной');
    await tester.tap(find.text('Создать и переключиться'));
    await UiHarness.settle(tester);
    expect(find.text('Профиль с таким именем уже есть'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    await addProfile(tester, 'Каито');

    expect(h.services.profile.name, 'Каито');
    expect(find.text('Профиль «Каито»'), findsOneWidget);
    expect(find.text('АККАУНТ ПРОФИЛЯ «КАИТО»'), findsOneWidget);
    // Остаёмся в настройках после переключения.
    expect(find.text('Добавить профиль'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('lists of another profile are not shown after switching', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.services.library.setStatus(1001, ListStatus.completed),
    );
    await h.pump(tester);
    expect(find.byType(ListStatusDot), findsOneWidget);

    await openSettings(tester);
    await addProfile(tester, 'Каито');
    await tester.tap(find.text('Каталог').first);
    await UiHarness.settle(tester);
    expect(find.byType(ListStatusDot), findsNothing);

    // Обратно на «Основной» — статус снова виден.
    await tester.tap(find.text('Настройки').first);
    await UiHarness.settle(tester);
    await tester.tap(find.text('Переключить'));
    await UiHarness.settle(tester);
    await tester.tap(find.text('Каталог').first);
    await UiHarness.settle(tester);
    expect(find.byType(ListStatusDot), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('delete another profile with confirmation', (tester) async {
    await h.pump(tester);
    await openSettings(tester);
    await addProfile(tester, 'Каито');

    // Текущий удалить нельзя.
    await tester.tap(find.byTooltip('Удалить профиль «Каито»'));
    await tester.pumpAndSettle();
    expect(
      find.text('Это текущий профиль — сначала переключитесь на другой.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Переключить'));
    await UiHarness.settle(tester);
    await tester.tap(find.byTooltip('Удалить профиль «Каито»'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Удалить профиль «Каито»?'), findsOneWidget);
    expect(
      find.textContaining('восстановить списки будет нельзя'),
      findsOneWidget,
    );
    await tester.tap(find.text('Удалить профиль'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Профиль удалён с устройства'), findsOneWidget);
    final all = await UiHarness.run(tester, h.services.profiles.all);
    expect(all.map((p) => p.name), ['Основной']);
    // Последний профиль: кнопки удаления нет.
    expect(find.byTooltip('Удалить профиль «Основной»'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('rail avatar opens the profile menu', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Без входа в GitHub'), findsOneWidget);
    expect(find.text('Управление профилями'), findsOneWidget);
    await tester.tap(find.text('Управление профилями'));
    await UiHarness.settle(tester);
    expect(find.text('Добавить профиль'), findsOneWidget);
    await h.dispose(tester);
  });
}
