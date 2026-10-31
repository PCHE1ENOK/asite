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
}
