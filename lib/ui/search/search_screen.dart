import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/anilist/anilist_client.dart';
import '../../data/models/anime.dart';
import '../../data/models/catalog_query.dart';
import '../app_scope.dart';
import '../format.dart';
import '../paged_anime_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import '../widgets/cover_image.dart';
import '../widgets/filter_controls.dart';
import '../widgets/poster_grid.dart';

/// Поиск (design/screens.md §6): запрос через 300 мс от 2 символов.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.onOpenTitle,
    this.debounce = const Duration(milliseconds: 300),
  });

  final ValueChanged<Anime> onOpenTitle;
  final Duration debounce;

  static const minLength = 2;

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late PagedAnimeController _results;
  late AppSettings _settings;
  Timer? _debounce;
  String _query = '';
  int _highlighted = 0;
  List<Anime> _trending = const [];
  bool _initialized = false;
  bool _lastAdult = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final scope = AppScope.of(context);
    _settings = scope.settings..addListener(_onSettings);
    _lastAdult = _settings.showAdult;
    _results = PagedAnimeController(scope.services.anime);
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _settings.removeListener(_onSettings);
    _results.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Ставит фокус в поле (Ctrl+K, открытие вкладки).
  void focusField() {
    _focus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  void _onSettings() {
    if (_settings.showAdult != _lastAdult) {
      _lastAdult = _settings.showAdult;
      _loadTrending();
      if (_query.isNotEmpty) _search(_query);
    }
  }

  Future<void> _loadTrending() async {
    try {
      final r = await AppScope.of(context).services.anime.getCatalog(
        CatalogQuery(
          sort: AnimeSort.trending,
          includeAdult: _settings.showAdult,
        ),
        perPage: 6,
      );
      if (mounted) setState(() => _trending = r.data.items);
    } on AniListException {
      // Блок «Популярное сейчас» просто не показывается.
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < SearchScreen.minLength) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(widget.debounce, () => _search(q));
  }

  void _search(String q) {
    setState(() {
      _query = q;
      _highlighted = 0;
    });
    _results.setQuery(
      CatalogQuery(search: q, includeAdult: _settings.showAdult),
    );
  }

  void _useQuery(String q) {
    _text.text = q;
    _text.selection = TextSelection.collapsed(offset: q.length);
    _debounce?.cancel();
    _search(q);
    _settings.addRecentSearch(q);
  }

  void _open(Anime a) {
    if (_query.isNotEmpty) _settings.addRecentSearch(_query);
    widget.onOpenTitle(a);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _suggestions;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape when _text.text.isNotEmpty:
        _text.clear();
        _onChanged('');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown when suggestions.isNotEmpty:
        setState(() => _highlighted = (_highlighted + 1) % suggestions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when suggestions.isNotEmpty:
        setState(
          () => _highlighted =
              (_highlighted - 1 + suggestions.length) % suggestions.length,
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _onSubmitted(String value) {
    final suggestions = _suggestions;
    if (suggestions.isNotEmpty) {
      _open(suggestions[_highlighted.clamp(0, suggestions.length - 1)]);
    } else if (value.trim().length >= SearchScreen.minLength) {
      _debounce?.cancel();
      _search(value.trim());
      _settings.addRecentSearch(value.trim());
    }
  }

  List<Anime> get _suggestions =>
      _query.isEmpty ? const [] : _results.items.take(3).toList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        final compact = width < AppLayout.medium;
        return ListenableBuilder(
          listenable: Listenable.merge([_results, _settings]),
          builder: (context, _) {
            final header = Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? 16 : 28,
                gutter,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Поиск',
                    style: compact ? AppText.headline : AppText.displayStyle,
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _field(context),
                  ),
                ],
              ),
            );

            // Поле вне прокрутки: его место в дереве не меняется, и фокус
            // с клавиатурой не теряются при появлении результатов.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: _content(context, gutter)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _content(BuildContext context, double gutter) {
    if (_query.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: _idle(context, gutter),
      );
    }
    final suggestions = _suggestions;
    final total = _results.total;
    return PosterGrid(
      controller: _results,
      gutter: gutter,
      onOpenTitle: _open,
      skeletonCount: 6,
      header: [
        if (suggestions.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    for (var i = 0; i < suggestions.length; i++)
                      _SuggestionRow(
                        anime: suggestions[i],
                        query: _query,
                        highlighted: i == _highlighted,
                        onTap: () => _open(suggestions[i]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_results.items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 16),
              child: Text(
                'Результаты · ${Fmt.thousands(total ?? _results.items.length)}',
                style: AppText.title,
              ),
            ),
          ),
      ],
      emptyText: 'Ничего не нашлось по «$_query»',
      emptyHint: 'Проверьте написание или попробуйте английское название',
      errorText: 'Поиск недоступен без сети. Проверьте подключение',
      errorHint: 'Ваши списки открываются и без интернета',
    );
  }

  Widget _field(BuildContext context) {
    final t = context.tokens;
    return Focus(
      onKeyEvent: _onKey,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: _onSubmitted,
        style: AppText.body.copyWith(color: t.fg),
        decoration: InputDecoration(
          hintText: 'Название на русском, английском или ромадзи',
          prefixIcon: Icon(Symbols.search_rounded, color: t.fg3),
          suffixIcon: ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      _text.clear();
                      _onChanged('');
                      _focus.requestFocus();
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context, double gutter) {
    final t = context.tokens;
    final recent = _settings.recentSearches;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'НЕДАВНИЕ ЗАПРОСЫ',
                  style: AppText.overline.copyWith(color: t.fg2),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _settings.clearRecentSearches,
                  child: const Text('Очистить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in recent)
                  PillButton(
                    label: q,
                    icon: Symbols.history_rounded,
                    onPressed: () => _useQuery(q),
                  ),
              ],
            ),
            const SizedBox(height: 28),
          ],
          if (_trending.isNotEmpty) ...[
            Text(
              'ПОПУЛЯРНОЕ СЕЙЧАС',
              style: AppText.overline.copyWith(color: t.fg2),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _trending)
                  PillButton(
                    label: a.title.preferred,
                    icon: Symbols.trending_up_rounded,
                    onPressed: () => _open(a),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.anime,
    required this.query,
    required this.highlighted,
    required this.onTap,
  });

  final Anime anime;
  final String query;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = anime;
    final original = a.title.native ?? a.title.romaji;
    return Material(
      color: highlighted ? t.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 48,
                child: NetworkCover(
                  url: a.coverImage.medium ?? a.coverImage.best,
                  color: a.coverImage.color,
                  radius: AppRadius.xs,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      highlightMatch(
                        a.title.preferred,
                        query,
                        AppText.bodyStrong.copyWith(color: t.fg),
                        t.accent.withValues(alpha: 0.35),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (original != null && original != a.title.preferred)
                          original,
                        Fmt.posterCaption(a),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (a.isAdult) ...[const AdultBadge(), const SizedBox(width: 6)],
              ScoreBadge(score: a.averageScore),
            ],
          ),
        ),
      ),
    );
  }
}

/// Текст с подсветкой первого вхождения [query] без учёта регистра.
TextSpan highlightMatch(
  String text,
  String query,
  TextStyle style,
  Color highlight,
) {
  final i = query.isEmpty
      ? -1
      : text.toLowerCase().indexOf(query.toLowerCase());
  if (i < 0) return TextSpan(text: text, style: style);
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: text.substring(0, i)),
      TextSpan(
        text: text.substring(i, i + query.length),
        style: TextStyle(background: Paint()..color = highlight),
      ),
      TextSpan(text: text.substring(i + query.length)),
    ],
  );
}
