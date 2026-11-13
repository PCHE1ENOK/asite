import 'package:anime_viewer/ui/profiles/profile_widgets.dart';
import 'package:anime_viewer/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// Картинка, которая не загружается (404, нет сети).
class _BrokenImage extends ImageProvider<_BrokenImage> {
  @override
  Future<_BrokenImage> obtainKey(ImageConfiguration configuration) async =>
      this;

  @override
  ImageStreamCompleter loadImage(_BrokenImage key, ImageDecoderCallback d) =>
      OneFrameImageStreamCompleter(
        Future.error(NetworkImageLoadException(statusCode: 404, uri: Uri())),
      );
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('no avatar (not signed in): letter', (tester) async {
    await pump(
      tester,
      const GitHubAvatar(url: null, letter: 'октокот', size: 56),
    );
    expect(find.text('О'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('avatar loaded: picture, ?s= twice the size', (tester) async {
    final urls = <String>[];
    await pump(
      tester,
      GitHubAvatar(
        url: 'https://avatars.githubusercontent.com/u/1?v=4',
        letter: 'octocat',
        size: 32,
        resolver: (u) {
          urls.add(u);
          return MemoryImage(transparentPng);
        },
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(urls.single, 'https://avatars.githubusercontent.com/u/1?v=4&s=64');
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('load error (404, offline): letter, no crash', (tester) async {
    await pump(
      tester,
      GitHubAvatar(
        url: 'https://avatars.githubusercontent.com/u/404',
        letter: 'octocat',
        size: 56,
        resolver: (_) => _BrokenImage(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('O'), findsOneWidget);
    expect(find.byTooltip(GitHubAvatar.loadError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail and settings show the GitHub avatar of the profile', (
    tester,
  ) async {
    final h = UiHarness();
    await tester.runAsync(
      () => h.services.profiles.setGitHubAvatar(
        h.services.profile.id,
        'https://avatars.githubusercontent.com/u/1?v=4',
      ),
    );
    await h.pump(tester);
    expect(
      find.descendant(
        of: find.byType(ProfileMenuButton),
        matching: find.byType(GitHubAvatar),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ProfileMenuButton),
        matching: find.text('О'),
      ),
      findsNothing,
      reason: 'вместо буквы — картинка',
    );
    await h.dispose(tester);
  });
}
