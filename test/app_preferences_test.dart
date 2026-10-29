import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding is shown once; 18+ is on by default', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final prefs = AppPreferences(db);

    expect(await prefs.shouldShowOnboarding(), isTrue);
    await prefs.markOnboardingSeen();
    expect(await prefs.shouldShowOnboarding(), isFalse);

    expect(await prefs.showAdult(), isTrue);
    await prefs.setShowAdult(false);
    expect(await prefs.showAdult(), isFalse);
    await db.close();
  });

  test('theme defaults to system and persists', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final prefs = AppPreferences(db);
    expect(await prefs.theme(), ThemePreference.system);
    await prefs.setTheme(ThemePreference.light);
    expect(await prefs.theme(), ThemePreference.light);
    await db.close();
  });

  test('recent searches: newest first, deduplicated, at most 8', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final prefs = AppPreferences(db);
    for (var i = 0; i < 10; i++) {
      await prefs.addRecentSearch('q$i');
    }
    await prefs.addRecentSearch('  Q5 ');
    final list = await prefs.recentSearches();
    expect(list, hasLength(8));
    expect(list.first, 'Q5');
    expect(list.where((s) => s.toLowerCase() == 'q5'), hasLength(1));
    await prefs.clearRecentSearches();
    expect(await prefs.recentSearches(), isEmpty);
    await db.close();
  });
}
