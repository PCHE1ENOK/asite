// Замер каталога и карточки тайтла (виджет-тест, поддельный AniList).
//
//   flutter test test/perf --dart-define=BENCH=true
//
// Время — в тестовой среде (debug, без отрисовки на GPU): годится для
// сравнения «до/после», не для абсолютных цифр на устройстве. Пересборки
// считаются через debugOnRebuildDirtyWidget.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import '../ui/ui_harness.dart';

const bench = bool.fromEnvironment('BENCH');
const runs = 5;
const pages = 10;

/// Страница каталога [page] с уникальными id (30 тайтлов).
String catalogPage(int page) {
  final j = jsonDecode(fixture('catalog_page_30.json')) as Map;
  final p = j['data']['Page'] as Map;
  final media = (p['media'] as List).cast<Map<String, dynamic>>();
  p['media'] = [
    for (final m in media)
      {...m, 'id': page == 1 ? m['id'] : (m['id'] as int) + page * 100000},
  ];
  p['pageInfo'] = {
    'total': 30 * pages,
    'perPage': 30,
    'currentPage': page,
    'hasNextPage': page < pages,
  };
  return jsonEncode(j);
}

class Counter {
  int all = 0;
  int posters = 0;

  void attach() {
    debugOnRebuildDirtyWidget = (e, _) {
      all++;
      if (e.widget is PosterCard ||
          e.findAncestorWidgetOfExactType<PosterCard>() != null) {
        posters++;
      }
    };
  }

  void reset() => all = posters = 0;

  static void detach() => debugOnRebuildDirtyWidget = null;
}

int median(List<int> xs) => (xs.toList()..sort())[xs.length ~/ 2];

void main() {
  final results = <String, List<int>>{};
  void record(String k, int v) => results.putIfAbsent(k, () => []).add(v);

  tearDownAll(() {
    if (!bench) return;
    print('\n=== perf (медиана из $runs) ===');
    for (final e in results.entries) {
      print('${e.key.padRight(44)} ${median(e.value)}');
    }
  });

  for (var run = 0; run < runs; run++) {
    testWidgets('bench run $run', skip: !bench, (tester) async {
      final h = UiHarness();
      h.route = (body) {
        if (!(body['query'] as String).contains('query Catalog')) return null;
        final page =
            (body['variables'] as Map<String, dynamic>)['page'] as int? ?? 1;
        return jsonResponse(catalogPage(page));
      };
      final c = Counter()..attach();
      addTearDown(Counter.detach);

      // 1. Открытие каталога: до первой страницы постеров.
      final sw = Stopwatch()..start();
      await h.pump(tester);
      while (find.byType(PosterCard).evaluate().isEmpty) {
        await UiHarness.settle(tester);
      }
      record('catalog open, ms', sw.elapsedMilliseconds);
      record('catalog open, builds', c.all);

      // 2. Прокрутка через все страницы с подгрузкой.
      c.reset();
      sw.reset();
      final scroll = find.byType(Scrollable).first;
      for (var i = 0; i < pages * 4; i++) {
        await tester.drag(scroll, const Offset(0, -900));
        await UiHarness.settle(tester);
      }
      record('scroll $pages pages, ms', sw.elapsedMilliseconds);
      record('scroll $pages pages, builds', c.all);
      record('scroll $pages pages, poster subtree builds', c.posters);
      expect(h.catalogRequests.length, greaterThanOrEqualTo(pages));

      // 3. Изменение списка (один тайтл): сколько постеров пересобралось.
      await tester.drag(scroll, const Offset(0, 100000));
      await UiHarness.settle(tester);
      final visible = find.byType(PosterCard).evaluate().length;
      final id = (find.byType(PosterCard).evaluate().first.widget as PosterCard)
          .anime
          .id;
      c.reset();
      sw.reset();
      await UiHarness.run(
        tester,
        () => h.services.library.setStatus(id, ListStatus.planning),
      );
      await UiHarness.settle(tester);
      record('library change: visible posters', visible);
      record('library change: poster subtree builds', c.posters);
      record('library change: builds', c.all);

      // 4. Открытие карточки тайтла.
      await tester.drag(scroll, const Offset(0, -100000));
      await UiHarness.settle(tester);
      c.reset();
      sw.reset();
      await tester.tap(find.byType(PosterCard).first);
      await UiHarness.settle(tester);
      await tester.pumpAndSettle();
      record('title open, ms', sw.elapsedMilliseconds);
      record('title open, builds', c.all);

      Counter.detach();
      await h.dispose(tester);
    });
  }
}
