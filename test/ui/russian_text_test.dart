import 'dart:convert';

import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ui_harness.dart';

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openAot(WidgetTester tester) async {
    await tester.tap(find.byType(PosterCard).at(1));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('russian titles in the catalog and on the card', (tester) async {
    h.shikiHandler = (u) {
      if (u.path == '/api/animes') {
        return json([
          {'id': 1001, 'russian': 'Атака титанов'},
          {'id': 1000, 'russian': 'Провожающая в последний путь Фрирен'},
        ]);
      }
      return json({
        'id': 16498,
        'russian': 'Атака титанов',
        'description': '[character=1]Эрен[/character] живёт за стенами.',
      });
    };
    await h.pump(tester);
    await UiHarness.settle(tester);
    expect(find.text('Атака титанов'), findsOneWidget);
    expect(find.text('Провожающая в последний путь Фрирен'), findsOneWidget);
    expect(
      h.shikiRequests.where((u) => u.path == '/api/animes'),
      hasLength(1),
      reason: 'one request for the page',
    );

    await openAot(tester);
    // Русское основное, английское ниже.
    expect(find.text('Атака титанов'), findsWidgets);
    expect(find.text('Attack on Titan'), findsWidgets);
    await tester.tap(find.text('Описание'));
    await UiHarness.settle(tester);
    expect(find.text('Эрен живёт за стенами.'), findsOneWidget);
    expect(find.text('на английском'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('no russian: English with «на английском»', (tester) async {
    await h.pump(tester);
    await openAot(tester);
    expect(find.text('Attack on Titan'), findsWidgets);
    expect(
      find.text('Shingeki no Kyojin'),
      findsWidgets,
      reason: 'romaji below',
    );
    await tester.tap(find.text('Описание'));
    await UiHarness.settle(tester);
    expect(find.text('на английском'), findsOneWidget);
    expect(find.text('Русского описания нет'), findsOneWidget);
    expect(find.textContaining('Several hundred years ago'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('Shikimori unavailable: English, nothing breaks', (tester) async {
    h.shikiHandler = (_) => http.Response('', 503);
    await h.pump(tester);
    expect(find.text('Attack on Titan'), findsWidgets);
    await openAot(tester);
    await tester.tap(find.text('Описание'));
    await UiHarness.settle(tester);
    expect(find.text('на английском'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets('score: Shikimori with «Shiki», fallback AniList with «AL»', (
    tester,
  ) async {
    h.shikiHandler = (u) => u.path == '/api/animes'
        ? json([
            {'id': 1001, 'russian': 'Атака титанов', 'score': '8.84'},
            {'id': 1000, 'score': '0.0'},
          ])
        : json({'id': 16498, 'score': '8.84'});
    await h.pump(tester);
    await UiHarness.settle(tester);
    // Attack on Titan: Shikimori 8,84 → «8,8 Shiki».
    expect(find.text('8,8'), findsWidgets);
    expect(find.text('Shiki'), findsWidgets);
    // Frieren: на Shikimori 0 → AniList 90 / 10 → «9,0 AL».
    expect(find.text('9,0'), findsWidgets);
    expect(find.text('AL'), findsWidgets);
    expect(find.byTooltip('Оценка 8,8 из 10 · Shikimori'), findsWidgets);

    // Сортировка «по рейтингу» — по-прежнему AniList.
    await tester.tap(find.text('Популярность'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рейтинг AniList').last);
    await UiHarness.settle(tester);
    expect(h.catalogRequests.last['sort'], ['SCORE_DESC']);

    await tester.tap(find.text('Атака титанов').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('8,8/10', findRichText: true), findsOneWidget);
    expect(find.text('Оценка · Shikimori'), findsOneWidget);
    await h.dispose(tester);
  });
}
