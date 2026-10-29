import 'package:flutter/material.dart';

import 'data/anilist/anilist_client.dart';
import 'data/anime_repository.dart';
import 'data/cache/app_database.dart';
import 'data/models/anime.dart';
import 'data/models/catalog_query.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = AnimeRepository(
    client: AniListClient(),
    db: AppDatabase.open(),
  );
  runApp(AnimeViewerApp(repository: repository));
}

class AnimeViewerApp extends StatelessWidget {
  const AnimeViewerApp({super.key, required this.repository});

  final AnimeRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Viewer',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: _CatalogPreview(repository: repository),
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
