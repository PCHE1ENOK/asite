import 'dart:io';

import 'package:anime_viewer/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScaffoldMessengerState messenger;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  testWidgets('a toast with «Отменить» hides itself after 10 s', (
    tester,
  ) async {
    await pumpApp(tester);
    var undone = 0;
    messenger.showToast(
      'Серия 7 отмечена просмотренной',
      actionLabel: 'Отменить',
      onAction: () => undone++,
    );
    await tester.pumpAndSettle();
    expect(find.text('Серия 7 отмечена просмотренной'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Серия 7 отмечена просмотренной'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Серия 7 отмечена просмотренной'), findsNothing);
    expect(undone, 0);
  });

  testWidgets('«Отменить» works until the toast hides', (tester) async {
    await pumpApp(tester);
    var undone = 0;
    messenger.showToast(
      'Готово',
      actionLabel: 'Отменить',
      onAction: () => undone++,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(
      find.text('Готово'),
      findsNothing,
      reason: 'closes after the action',
    );
  });

  testWidgets('a new toast replaces the old one, no queue', (tester) async {
    await pumpApp(tester);
    messenger.showToast('Первый', actionLabel: 'Отменить', onAction: () {});
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    messenger.showToast('Второй');
    await tester.pumpAndSettle();
    expect(find.text('Первый'), findsNothing);
    expect(find.text('Второй'), findsOneWidget);
    // Срок второго считается с его показа.
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Второй'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Второй'), findsNothing);
    expect(find.text('Первый'), findsNothing, reason: 'not queued behind');
  });

  test('all toasts go through showToast (one timer, one place)', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('toast.dart') &&
            f.readAsStringSync().contains('showSnackBar('))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
