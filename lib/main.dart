import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'ui/app_scope.dart';
import 'ui/library_index.dart';
import 'ui/login_flow.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices.create();
  final settings = AppSettings(services.preferences);
  await settings.load();
  final showOnboarding = await services.preferences.shouldShowOnboarding();
  // Синхронизация при запуске; ошибки отражаются в services.sync.state.
  unawaited(services.sync.start());
  unawaited(services.anime.prune());
  runApp(
    AnimeViewerApp(
      services: services,
      settings: settings,
      showOnboarding: showOnboarding,
    ),
  );
}

class AnimeViewerApp extends StatefulWidget {
  const AnimeViewerApp({
    super.key,
    required this.services,
    required this.settings,
    required this.showOnboarding,
    this.imageResolver = networkImage,
    this.now,
  });

  final AppServices services;
  final AppSettings settings;
  final bool showOnboarding;
  final ImageResolver imageResolver;
  final DateTime? now;

  @override
  State<AnimeViewerApp> createState() => _AnimeViewerAppState();
}

class _AnimeViewerAppState extends State<AnimeViewerApp> {
  late bool _onboarding = widget.showOnboarding;
  late final _library = LibraryIndex(widget.services.library);

  @override
  void dispose() {
    _library.dispose();
    super.dispose();
  }

  void _finishOnboarding() {
    widget.services.preferences.markOnboardingSeen();
    setState(() => _onboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      settings: widget.settings,
      library: _library,
      imageResolver: widget.imageResolver,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          title: 'Anime Viewer',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: widget.settings.themeMode,
          home: _onboarding
              ? LoginFlow(sync: widget.services.sync, onDone: _finishOnboarding)
              : AppShell(now: widget.now),
        ),
      ),
    );
  }
}
