import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/sync/sync_service.dart';
import '../app_scope.dart';
import '../catalog/catalog_screen.dart';
import '../lists/lists_screen.dart';
import '../profiles/profile_widgets.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/sync_visuals.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../title/title_screen.dart';

enum AppTab {
  catalog('Каталог', Symbols.grid_view_rounded),
  lists('Списки', Symbols.format_list_bulleted_rounded),
  search('Поиск', Symbols.search_rounded),
  settings('Настройки', Symbols.settings_rounded);

  const AppTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Каркас приложения: NavRail на широких экранах, нижняя навигация на
/// телефоне. У каждой вкладки свой навигатор, поэтому карточка тайтла
/// открывается внутри вкладки и панель навигации остаётся видна.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.now,
    this.initialTab = AppTab.catalog,
    this.onTabChanged,
  });

  /// Текущее время для фильтра сезонов (в тестах фиксируется).
  final DateTime? now;

  /// Раздел, открытый при создании (после смены профиля — прежний).
  final AppTab initialTab;
  final ValueChanged<AppTab>? onTabChanged;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late AppTab _tab = widget.initialTab;
  final _navigators = {
    for (final t in AppTab.values) t: GlobalKey<NavigatorState>(),
  };
  final _searchKey = GlobalKey<SearchScreenState>();

  /// Вкладки строятся при первом открытии, чтобы не грузить их заранее.
  late final _visited = {widget.initialTab};

  AppTab get tab => _tab;

  void select(AppTab tab) {
    if (tab == _tab) {
      _navigators[tab]!.currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _tab = tab;
        _visited.add(tab);
      });
      widget.onTabChanged?.call(tab);
    }
    if (tab == AppTab.search) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchKey.currentState?.focusField(),
      );
    }
  }

  void _openTitle(Anime anime) {
    _navigators[_tab]!.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TitleScreen(id: anime.id, preview: anime, onOpenTitle: _openTitle),
      ),
    );
  }

  Widget _root(AppTab tab) => switch (tab) {
    AppTab.catalog => CatalogScreen(
      onOpenTitle: _openTitle,
      onOpenSearch: () => select(AppTab.search),
      now: widget.now,
    ),
    AppTab.lists => ListsScreen(
      onOpenCatalog: () => select(AppTab.catalog),
      onOpenTitle: _openTitle,
    ),
    AppTab.search => SearchScreen(key: _searchKey, onOpenTitle: _openTitle),
    AppTab.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppLayout.medium;

    final pages = IndexedStack(
      index: _tab.index,
      children: [
        for (final tab in AppTab.values)
          if (!_visited.contains(tab))
            const SizedBox.shrink()
          else
            HeroControllerScope.none(
              child: Navigator(
                key: _navigators[tab],
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Material(color: t.bg, child: _root(tab)),
                ),
              ),
            ),
      ],
    );

    final body = NavigatorPopHandler(
      onPopWithResult: (_) => _navigators[_tab]!.currentState?.maybePop(),
      child: pages,
    );

    return Focus(
      // Ctrl+K по физической клавише: на русской раскладке логическая
      // клавиша приходит как «л».
      onKeyEvent: (node, event) {
        final keys = HardwareKeyboard.instance;
        if (event is KeyDownEvent &&
            event.physicalKey == PhysicalKeyboardKey.keyK &&
            (keys.isControlPressed || keys.isMetaPressed)) {
          select(AppTab.search);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: t.bg,
          body: compact
              ? SafeArea(bottom: false, child: body)
              : Row(
                  children: [
                    _Rail(
                      selected: _tab,
                      extended: width >= AppLayout.large,
                      onSelect: select,
                    ),
                    VerticalDivider(width: 1, color: t.border),
                    Expanded(child: body),
                  ],
                ),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) => select(AppTab.values[i]),
                  destinations: [
                    for (final tab in AppTab.values)
                      NavigationDestination(
                        icon: tab == AppTab.settings
                            ? _ProfileIcon(icon: Symbols.person_rounded)
                            : Icon(tab.icon),
                        selectedIcon: tab == AppTab.settings
                            ? _ProfileIcon(
                                icon: Symbols.person_rounded,
                                fill: 1,
                              )
                            : Icon(tab.icon, fill: 1),
                        label: tab == AppTab.settings ? 'Профиль' : tab.label,
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.extended,
    required this.onSelect,
  });

  final AppTab selected;
  final bool extended;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget item(AppTab tab, {Widget? icon}) => _RailItem(
      tab: tab,
      selected: tab == selected,
      extended: extended,
      icon: icon,
      onTap: () => onSelect(tab),
    );
    return Container(
      width: extended ? AppLayout.navRailExpanded : AppLayout.navRail,
      color: t.bg,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            item(AppTab.catalog),
            item(AppTab.lists),
            item(AppTab.search),
            const Spacer(),
            item(
              AppTab.settings,
              icon: _ProfileIcon(
                icon: AppTab.settings.icon,
                fill: selected == AppTab.settings ? 1 : 0,
              ),
            ),
            const SizedBox(height: 4),
            ProfileMenuButton(
              extended: extended,
              onManage: () => onSelect(AppTab.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.icon,
  });

  final AppTab tab;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.accent : t.fg2;
    final iconWidget = IconTheme(
      data: IconThemeData(color: color, size: 22),
      child: icon ?? Icon(tab.icon, fill: selected ? 1 : 0),
    );
    final label = Text(
      tab.label,
      style: AppText.caption.copyWith(
        color: selected ? t.fg : t.fg2,
        fontSize: extended ? 14 : 11,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        button: true,
        label: tab == AppTab.search ? 'Поиск, Ctrl+K' : tab.label,
        excludeSemantics: true,
        child: Material(
          color: selected ? t.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: SizedBox(
              height: extended ? 44 : 56,
              child: extended
                  ? Row(
                      children: [
                        const SizedBox(width: 14),
                        iconWidget,
                        const SizedBox(width: 12),
                        Expanded(child: label),
                        if (tab == AppTab.search)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              'Ctrl K',
                              style: AppText.caption.copyWith(
                                color: t.fg3,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        iconWidget,
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(fit: BoxFit.scaleDown, child: label),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Иконка профиля/настроек с точкой состояния синхронизации.
class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.icon, this.fill = 0});

  final IconData icon;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sync = AppScope.of(context).services.sync;
    return ValueListenableBuilder<SyncState>(
      valueListenable: sync.state,
      builder: (context, state, _) {
        final dot = syncDotColor(state, t);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, fill: fill),
            if (dot != null)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.bg, width: 2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
