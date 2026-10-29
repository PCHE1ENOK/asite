import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/anime_repository.dart';
import 'data/models/anime.dart';
import 'data/models/catalog_query.dart';
import 'ui/login_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices.create();
  final showOnboarding = await services.preferences.shouldShowOnboarding();
  // Синхронизация при запуске; ошибки отражаются в services.sync.state.
  unawaited(services.sync.start());
  runApp(AnimeViewerApp(services: services, showOnboarding: showOnboarding));
}

class AnimeViewerApp extends StatefulWidget {
  const AnimeViewerApp({
    super.key,
    required this.services,
    required this.showOnboarding,
  });

  final AppServices services;
  final bool showOnboarding;

  @override
  State<AnimeViewerApp> createState() => _AnimeViewerAppState();
}

class _AnimeViewerAppState extends State<AnimeViewerApp> {
  late bool _onboarding = widget.showOnboarding;

  void _finishOnboarding() {
    widget.services.preferences.markOnboardingSeen();
    setState(() => _onboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Viewer',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: _onboarding
          ? LoginFlow(sync: widget.services.sync, onDone: _finishOnboarding)
          : _CatalogPreview(repository: widget.services.anime),
    );
  }
}

/// Временный экран для проверки клиента и кэша; заменяется на этапе 2.
class _CatalogPreview extends StatefulWidget {
  const _CatalogPreview({required this.repository});

  final AnimeRepository repository;

  @override
  State<_CatalogPreview> createState() => _CatalogPreviewState();
}

class _CatalogPreviewState extends State<_CatalogPreview> {
  late Future<Cached<List<Anime>>> _future = _load();

  Future<Cached<List<Anime>>> _load() async {
    final page = await widget.repository.getCatalog(
      const CatalogQuery(sort: AnimeSort.trending),
    );
    return Cached(page.data.items, source: page.source, isStale: page.isStale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сейчас в тренде'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          final result = snapshot.data;
          if (result == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: result.data.length,
            itemBuilder: (context, i) {
              final anime = result.data[i];
              final score = anime.score10;
              return ListTile(
                leading: anime.coverImage.medium == null
                    ? null
                    : Image.network(anime.coverImage.medium!, width: 40),
                title: Text(anime.title.preferred),
                subtitle: Text(
                  [
                    if (anime.isAdult) '18+',
                    anime.format,
                    anime.seasonYear?.toString(),
                  ].whereType<String>().join(' · '),
                ),
                trailing: score == null ? null : Text(score.toStringAsFixed(1)),
              );
            },
          );
        },
      ),
    );
  }
}
