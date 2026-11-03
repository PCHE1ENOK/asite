// Генерирует цвета темы из design/tokens.json:
//
//   dart run tool/gen_tokens.dart
//
// Пишет lib/ui/theme/app_tokens.g.dart (part файла app_tokens.dart):
// палитры светлой и тёмной темы, статусы списка, тени e1/e2, бейдж 18+,
// цвета аватаров профилей. Руками этот файл не правится — меняется
// design/tokens.json и скрипт запускается заново. Тест
// test/tokens_test.dart проверяет, что файл совпадает с json.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const source = 'design/tokens.json';
const target = 'lib/ui/theme/app_tokens.g.dart';

/// Поля палитры темы в порядке конструктора AppTokens.
const paletteFields = [
  'bg',
  'surface1',
  'surface2',
  'surface3',
  'border',
  'borderStrong',
  'fg',
  'fg2',
  'fg3',
  'accent',
  'accentHover',
  'accentPressed',
  'onAccent',
  'accentSoft',
  'highlight',
  'good',
  'warn',
  'bad',
  'scrim',
  'skeleton',
  'skeletonShine',
];

/// Цвета аватаров профилей, пока их нет в tokens.json (`color.<тема>.avatars`):
/// прежние значения из profile_widgets.dart, одинаковые в обеих темах.
const fallbackAvatars = ['#6F86F2', '#199E70', '#C98500', '#D55181', '#3987E5'];

const statuses = {
  'CURRENT': 'current',
  'REPEATING': 'repeating',
  'PLANNING': 'planning',
  'COMPLETED': 'completed',
  'PAUSED': 'paused',
  'DROPPED': 'dropped',
};

/// `#RRGGBB` или `#RRGGBBAA` → `Color(0xAARRGGBB)`.
String color(String hex) {
  final h = hex.replaceFirst('#', '').toUpperCase();
  final argb = switch (h.length) {
    6 => 'FF$h',
    8 => '${h.substring(6)}${h.substring(0, 6)}',
    _ => throw FormatException('Цвет $hex'),
  };
  return 'Color(0x$argb)';
}

/// «0 1 2 #00000066» → BoxShadow.
String shadow(String spec) {
  final p = spec.trim().split(RegExp(r'\s+'));
  if (p.length != 4) throw FormatException('Тень $spec');
  return 'BoxShadow(color: ${color(p[3])}, '
      'offset: Offset(${p[0]}, ${p[1]}), blurRadius: ${p[2]})';
}

String generate(Map<String, dynamic> json) {
  final c = json['color'] as Map<String, dynamic>;
  final elevation = json['elevation'] as Map<String, dynamic>;
  final listStatus = c['listStatus'] as Map<String, dynamic>;
  final adult = c['adult'] as Map<String, dynamic>;
  final out = StringBuffer()
    ..writeln('// СГЕНЕРИРОВАНО tool/gen_tokens.dart из design/tokens.json.')
    ..writeln('// Не править руками: dart run tool/gen_tokens.dart')
    ..writeln()
    ..writeln("part of 'app_tokens.dart';")
    ..writeln()
    ..writeln('const _adultBg = ${color(adult['bg'] as String)};')
    ..writeln('const _adultFg = ${color(adult['fg'] as String)};');
  for (final mode in ['dark', 'light']) {
    final pal = c[mode] as Map<String, dynamic>;
    final el = elevation[mode] as Map<String, dynamic>;
    final avatars =
        (pal['avatars'] as List?)?.cast<String>() ?? fallbackAvatars;
    out
      ..writeln()
      ..writeln('const _$mode = AppTokens(');
    for (final f in paletteFields) {
      final v = pal[f];
      if (v is! String) throw FormatException('Нет color.$mode.$f');
      out.writeln('  $f: ${color(v)},');
    }
    out.writeln('  status: {');
    for (final MapEntry(:key, :value) in statuses.entries) {
      var s = listStatus[key] as Map<String, dynamic>;
      if (s['aliasOf'] case final String alias) {
        s = listStatus[alias] as Map<String, dynamic>;
      }
      out.writeln('    ListStatus.$value: ${color(s[mode] as String)},');
    }
    out
      ..writeln('  },')
      ..writeln('  shadowE1: [${shadow(el['e1'] as String)}],')
      ..writeln('  shadowE2: [${shadow(el['e2'] as String)}],')
      ..writeln('  avatars: [')
      ..writeAll([for (final a in avatars) '    ${color(a)},\n'])
      ..writeln('  ],')
      ..writeln(');');
  }
  return out.toString();
}

void main() {
  final json =
      jsonDecode(File(source).readAsStringSync()) as Map<String, dynamic>;
  File(target).writeAsStringSync(generate(json));
  // Формат как у остального кода (тест сравнивает без учёта пробелов).
  final r = Process.runSync('dart', ['format', target], runInShell: true);
  print(r.exitCode == 0 ? 'Записано: $target' : r.stderr);
}
