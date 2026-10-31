import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_services.dart';
import 'data/cache/image_disk_cache.dart';
import 'data/profiles/profile_repository.dart';
import 'ui/app_scope.dart';
import 'ui/library_index.dart';
import 'ui/login_flow.dart';
import 'ui/profiles/profile_widgets.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Дисковый кэш обложек: до 200 МБ, старые файлы вытесняются.
  final cacheDir = await getApplicationCacheDirectory();
  ImageDiskCache.instance = ImageDiskCache(
    Directory(p.join(cacheDir.path, 'images')),
  );
  unawaited(ImageDiskCache.instance!.trim());
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
    _splashTimer?.cancel();
    _library.dispose();
    super.dispose();
  }

  /// Другой профиль: свои списки, недавние запросы и синхронизация;
  /// текущий раздел открывается заново с данными нового профиля.
  void _onProfile() {
    final old = _library;
    final profile = widget.services.profile;
    setState(() {
      _library = LibraryIndex(widget.services.library);
      _switchingTo = profile;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    widget.settings.setProfile(profile.id);
    _splashTimer?.cancel();
    _splashTimer = Timer(switchSplash, () {
      if (!mounted) return;
      setState(() => _switchingTo = null);
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Профиль «${profile.name}»')));
    });
  }

  /// Заставка при переключении профиля (design/screens.md §9).
  static const switchSplash = Duration(milliseconds: 600);
  Profile? _switchingTo;
  Timer? _splashTimer;

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
          builder: (context, child) => Stack(
            children: [
              ?child,
              if (_switchingTo case final p?) _SwitchSplash(profile: p),
            ],
          ),
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

class _SwitchSplash extends StatelessWidget {
  const _SwitchSplash({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        // Над навигатором нет Material: без него текст без стиля темы.
        child: Material(
          color: theme.scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfileAvatar(profile: profile, size: 88),
                const SizedBox(height: 20),
                Text(
                  'Переключаем на профиль «${profile.name}»…',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
