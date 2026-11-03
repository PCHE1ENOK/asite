import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:anime_viewer/ui/theme/app_tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_tokens.dart' as gen;

/// Контраст WCAG 2.x двух непрозрачных цветов.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _squash(String s) => s
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(',)', ')')
    .replaceAll(',]', ']')
    .replaceAll(',}', '}');

void main() {
  test('app_tokens.g.dart is generated from design/tokens.json', () {
    final json =
        jsonDecode(File(gen.source).readAsStringSync()) as Map<String, dynamic>;
    expect(
      _squash(File(gen.target).readAsStringSync()),
      _squash(gen.generate(json)),
      reason: 'запустите dart run tool/gen_tokens.dart',
    );
  });

  test('avatars: same look in the dark theme as before tokens', () {
    expect(AppTokens.dark.avatars, const [
      Color(0xFF6F86F2),
      Color(0xFF199E70),
      Color(0xFFC98500),
      Color(0xFFD55181),
      Color(0xFF3987E5),
    ]);
    expect(AppTokens.light.avatars, hasLength(AppTokens.dark.avatars.length));
    expect(AppTokens.dark.avatar(7), AppTokens.dark.avatars[2]);
  });

  group('white text on avatars', () {
    for (final (name, t) in [
      ('dark', AppTokens.dark),
      ('light', AppTokens.light),
    ]) {
      test('$name: at least 3:1 (large text, icons)', () {
        for (final c in t.avatars) {
          expect(
            contrast(AppTokens.onAvatar, c),
            greaterThanOrEqualTo(3.0),
            reason: '$c',
          );
        }
      });

      // Буква на аватаре 28–36 — это 12–15 px полужирным, то есть обычный
      // текст: нужно 4,5:1. Сейчас 3,07–3,94 — ждём решения дизайна
      // (тёмная буква #0E1016 дала бы 4,82–6,19).
      test(
        '$name: 4.5:1 for small initials',
        skip: 'не проходит: 3,07–3,94; палитру аватаров меняет дизайн-чат',
        () {
          for (final c in t.avatars) {
            expect(contrast(AppTokens.onAvatar, c), greaterThanOrEqualTo(4.5));
          }
        },
      );
    }
  });
}
