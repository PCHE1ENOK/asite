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
}
