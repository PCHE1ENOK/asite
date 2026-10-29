import 'package:anime_viewer/ui/title/title_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openTitle(WidgetTester tester, {Size? size}) async {
    await h.pump(tester, size: size ?? const Size(1440, 900));
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('header: titles, meta, rating, rank, popularity', (tester) async {
    await openTitle(tester);

    expect(find.byType(TitleScreen), findsOneWidget);
    expect(find.text('進撃の巨人'), findsOneWidget);
    expect(
      find.text('TV · Весна 2013 · 25 эп. · 24 мин · Wit Studio'),
      findsOneWidget,
    );
    expect(find.text('85'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('950 тыс.'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('episodes tab lists 25 episodes with titles', (tester) async {
    await openTitle(tester);

    expect(find.text('To You, in 2000 Years'), findsOneWidget);
    expect(find.text('That Day'), findsOneWidget);
    expect(find.text('Серия 3'), findsOneWidget);
    expect(find.text('24 мин'), findsWidgets);
    await h.dispose(tester);
  });

  testWidgets('description, stats and similar tabs', (tester) async {
    await openTitle(tester);

    await tester.tap(find.text('Описание'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Several hundred years ago'), findsOneWidget);
    expect(find.text('Экшен'), findsOneWidget);
    expect(find.text('Манга'), findsOneWidget);
    expect(find.text('Survival · 92%'), findsOneWidget);
    expect(find.text('Twist · 70%'), findsNothing, reason: 'spoiler hidden');
    await tester.ensureVisible(find.text('Показать теги-спойлеры'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать теги-спойлеры'));
    await tester.pumpAndSettle();
    expect(find.text('Twist · 70%'), findsOneWidget);

    await tester.ensureVisible(find.text('Статистика'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    expect(find.text('Оценки пользователей AniList'), findsOneWidget);
    expect(find.text('98 000'), findsWidgets);
    expect(find.text('Просмотрено'), findsOneWidget);
    expect(find.text('43%'), findsOneWidget);

    await tester.ensureVisible(find.text('Похожие'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Похожие'));
    await tester.pumpAndSettle();
    expect(find.text('Demon Slayer: Kimetsu no Yaiba'), findsOneWidget);
    expect(find.text('Сиквел'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('compact layout renders without overflow', (tester) async {
    await openTitle(tester, size: const Size(390, 844));
    expect(find.text('Рейтинг AniList'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('offline without cache shows error with retry', (tester) async {
    await h.pump(tester);
    h.offline = true;
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Не удалось загрузить подробности. Проверьте подключение'),
      findsOneWidget,
    );
    // Шапка из каталога видна и без сети.
    expect(find.text('Рейтинг AniList'), findsOneWidget);
    await h.dispose(tester);
  });
}
