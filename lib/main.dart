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
  final services = await AppServices.open();
  final settings = AppSettings(
    services.preferences,
    profileId: services.profile.id,
  );
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
  late LibraryIndex _library = LibraryIndex(widget.services.library);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  AppTab _tab = AppTab.catalog;

  @override
  void initState() {
    super.initState();
    widget.services.session.addListener(_onProfile);
  }

  @override
  void dispose() {
    widget.services.session.removeListener(_onProfile);
    _library.dispose();
    super.dispose();
  }

  /// Другой профиль: свои списки, недавние запросы и синхронизация;
  /// текущий раздел открывается заново с данными нового профиля.
  void _onProfile() {
    final old = _library;
    setState(() => _library = LibraryIndex(widget.services.library));
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    widget.settings.setProfile(widget.services.profile.id);
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Профиль «${widget.services.profile.name}»')),
      );
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
          scaffoldMessengerKey: _messenger,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: widget.settings.themeMode,
          home: _onboarding
              ? LoginFlow(sync: widget.services.sync, onDone: _finishOnboarding)
              : AppShell(
                  key: ValueKey(widget.services.profile.id),
                  now: widget.now,
                  initialTab: _tab,
                  onTabChanged: (t) => _tab = t,
                ),
        ),
      ),
    );
  }
}
