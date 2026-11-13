import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'poster_card.dart';
import 'state_views.dart';
import 'toast.dart';

/// Горизонтальная лента постеров с заголовком по центру и автопрокруткой
/// «рывками» (design/screens.md §1.1, components.md «PosterCarousel»):
/// онгоинги сезонов в каталоге, «Связанные» и «Рекомендации AniList» в
/// карточке тайтла.
///
/// Автопрокрутка: каждые [interval] — на одну карточку, в конце — плавно
/// к началу. Пауза — наведение мыши, фокус клавиатуры внутри, касание
/// (и ещё [interval] после него), прокрутка пользователем, приложение в
/// фоне, вкладка скрыта. Нет автопрокрутки при «уменьшить движение» в
/// системе, при выключенной настройке и после нажатия на индикатор.
class PosterCarousel extends StatefulWidget {
  const PosterCarousel({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    this.labels,
    this.loading = false,
    this.error = false,
    this.onRetry,
    required this.emptyText,
    this.errorText = 'Не удалось загрузить',
    required this.onOpenTitle,
    this.interval = const Duration(seconds: 5),
    this.announce = false,
  });

  /// Анонсы: постеры без оценки (design/screens.md §1.1).
  final bool announce;

  final String title;
  final String? subtitle;
  final List<Anime> items;

  /// Подпись над каждым постером («Сиквел», «Фильм»…), как [items].
  final List<String>? labels;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;
  final String emptyText;
  final String errorText;
  final ValueChanged<Anime> onOpenTitle;
  final Duration interval;

  static const stoppedToast =
      'Автопрокрутка остановлена. Включить снова — в настройках';

  @override
  State<PosterCarousel> createState() => PosterCarouselState();
}

@visibleForTesting
class PosterCarouselState extends State<PosterCarousel>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  Timer? _timer;
  Timer? _touchTimer;

  /// Остановлена нажатием на индикатор (до перезапуска экрана).
  bool _stopped = false;
  bool _hover = false;
  bool _focus = false;
  bool _touch = false;
  bool _background = false;
  bool _auto = false;

  /// Лента прокручивается пальцем или мышью (для привязки к карточке).
  bool _dragging = false;

  /// Ширина шага: карточка + промежуток (из последней раскладки).
  double _step = 180;

  /// Из последней сборки: «уменьшить движение» и видна ли вкладка.
  bool _reduceMotion = false;
  bool _visible = true;

  /// Автопрокрутка разрешена (настройка, система, кнопка, данные).
  bool get enabled {
    final settings = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.settings;
    return (settings?.autoScroll ?? true) &&
        !_reduceMotion &&
        !_stopped &&
        !widget.loading &&
        !widget.error &&
        widget.items.length > 1;
  }

  /// Листает прямо сейчас (разрешена и не на паузе).
  bool get running =>
      enabled && !_hover && !_focus && !_touch && !_background && _visible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _tick());
  }

  @override
  void didUpdateWidget(PosterCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _timer?.cancel();
      _timer = Timer.periodic(widget.interval, (_) => _tick());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _touchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _set(() => _background = state != AppLifecycleState.resumed);
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  /// Лента разложена и знает свою длину.
  bool get _ready =>
      _scroll.hasClients && _scroll.position.hasContentDimensions;

  void _tick() {
    if (!mounted || !running || !_ready) return;
    final p = _scroll.position;
    final target = p.pixels >= p.maxScrollExtent - 1
        ? 0.0
        : math.min(p.pixels + _step, p.maxScrollExtent);
    _auto = true;
    _scroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: AppMotion.standard,
        )
        .whenComplete(() => _auto = false);
  }

  /// Касание или прокрутка пользователем: пауза ещё [interval] после.
  void _pauseByTouch() {
    _touchTimer?.cancel();
    _set(() => _touch = true);
  }

  void _resumeAfterTouch() {
    _touchTimer?.cancel();
    _touchTimer = Timer(widget.interval, () => _set(() => _touch = false));
  }

  /// Стрелки и клавиатура: на одну карточку.
  void _move(int direction) {
    if (!_ready) return;
    final p = _scroll.position;
    final target = (p.pixels + direction * _step).clamp(0.0, p.maxScrollExtent);
    if (_reduceMotion) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: AppMotion.standard,
      );
    }
  }

  /// Привязка к началу карточки после прокрутки пальцем или колёсиком.
  void _snap() {
    if (!_ready || _auto) return;
    final p = _scroll.position;
    final snapped = ((p.pixels / _step).round() * _step).clamp(
      0.0,
      p.maxScrollExtent,
    );
    if ((snapped - p.pixels).abs() < 1) return;
    _auto = true;
    final done = _reduceMotion
        ? Future<void>.sync(() => _scroll.jumpTo(snapped))
        : _scroll.animateTo(
            snapped,
            duration: const Duration(milliseconds: 200),
            curve: AppMotion.standard,
          );
    done.whenComplete(() => _auto = false);
  }

  void _toggleStopped() {
    final stop = !_stopped;
    _set(() => _stopped = stop);
    if (stop) {
      ScaffoldMessenger.maybeOf(context)
          ?.showToast(PosterCarousel.stoppedToast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    final settings = AppScope.maybeOf(context)?.settings;
    if (settings == null) return _layout(t);
    // Настройка «Автопрокрутка каруселей» меняет индикатор сразу.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => _layout(t),
    );
  }

  Widget _layout(AppTokens t) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < AppLayout.medium;
        final itemWidth = phone ? 116.0 : 160.0;
        final gap = phone ? 12.0 : 20.0;
        _step = itemWidth + gap;
        final indicator = enabled ? _indicator(t) : null;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Карусель «${widget.title}»',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t, phone, indicator),
              const SizedBox(height: 16),
              _body(t, phone, itemWidth, gap),
            ],
          ),
        );
      },
    );
  }

  Widget _header(AppTokens t, bool phone, Widget? indicator) {
    final titles = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 2,
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.title.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppText.labelStrong.copyWith(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: t.fg,
          ),
        ),
        if (widget.subtitle case final s?) ...[
          const SizedBox(height: 2),
          Text(
            s,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: t.fg2),
          ),
        ],
        if (phone && indicator != null) ...[
          const SizedBox(height: 4),
          indicator,
        ],
      ],
    );
    if (phone || indicator == null) return Center(child: titles);
    return Stack(
      alignment: Alignment.center,
      children: [
        titles,
        Positioned(right: 0, child: indicator),
      ],
    );
  }

  Widget _indicator(AppTokens t) {
    final playing = running;
    return Semantics(
      button: true,
      label: _stopped
          ? 'Автопрокрутка остановлена. Включить'
          : 'Остановить автопрокрутку',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: _toggleStopped,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: playing
              ? _PulseDot(color: t.accent, period: widget.interval)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.pause_rounded, size: 14, color: t.fg2),
                    const SizedBox(width: 4),
                    Text(
                      'Пауза',
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _body(AppTokens t, bool phone, double itemWidth, double gap) {
    if (widget.error) {
      return ErrorState(
        message: widget.errorText,
        hint: 'Проверьте подключение к интернету и попробуйте ещё раз.',
        onRetry: widget.onRetry ?? () {},
      );
    }
    if (!widget.loading && widget.items.isEmpty) {
      return EmptyState(
        icon: Symbols.search_off_rounded,
        text: widget.emptyText,
      );
    }
    final labels = widget.labels;
    final labelHeight = labels == null ? 0.0 : 20.0;
    final posterHeight = itemWidth * 1.5;
    final height = posterHeight + PosterCard.captionHeight + labelHeight;
    final count = widget.loading ? 8 : widget.items.length;
    final strip = ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: false, dragDevices: {...PointerDeviceKind.values}),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _dragging = true;
            _pauseByTouch();
          } else if (n is ScrollEndNotification && _dragging) {
            _dragging = false;
            _resumeAfterTouch();
            WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
          }
          return false;
        },
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, _) => SizedBox(width: gap),
          itemBuilder: (context, i) => SizedBox(
            width: itemWidth,
            child: widget.loading
                ? const PosterCardSkeleton()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (labels != null)
                        SizedBox(
                          height: labelHeight,
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: t.accent),
                          ),
                        ),
                      Expanded(
                        child: PosterCard(
                          anime: widget.items[i],
                          announce: widget.announce,
                          onTap: () => widget.onOpenTitle(widget.items[i]),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    final arrowTop = labelHeight + posterHeight / 2 - 20;
    return Focus(
      onFocusChange: (f) => _set(() => _focus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _move(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _move(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => _set(() => _hover = true),
        onExit: (_) => _set(() => _hover = false),
        child: Listener(
          onPointerDown: (e) {
            if (e.kind != PointerDeviceKind.mouse) _pauseByTouch();
          },
          onPointerUp: (e) {
            if (e.kind != PointerDeviceKind.mouse) _resumeAfterTouch();
          },
          onPointerCancel: (_) => _resumeAfterTouch(),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: strip),
                // Стрелки — только на ПК (на телефоне лента листается свайпом).
                // По краям ленты, не за ними: за границей виджета нажатие
                // не доходит до кнопки.
                if (!phone && !widget.loading)
                  ListenableBuilder(
                    listenable: _scroll,
                    builder: (context, _) {
                      final has =
                          _scroll.hasClients &&
                          _scroll.position.hasContentDimensions;
                      final atStart = !has || _scroll.position.pixels <= 0;
                      final atEnd =
                          !has ||
                          _scroll.position.pixels >=
                              _scroll.position.maxScrollExtent - 1;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (!atStart)
                            Positioned(
                              left: 0,
                              top: arrowTop,
                              child: _Arrow(
                                icon: Symbols.chevron_left_rounded,
                                tooltip: 'Назад',
                                onPressed: () => _move(-1),
                              ),
                            ),
                          if (!atEnd)
                            Positioned(
                              right: 0,
                              top: arrowTop,
                              child: _Arrow(
                                icon: Symbols.chevron_right_rounded,
                                tooltip: 'Вперёд',
                                onPressed: () => _move(1),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.surface1,
        border: Border.all(color: t.border),
        boxShadow: t.shadowE2,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          color: t.fg,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// Точка 8 с медленной пульсацией в такт автопрокрутке.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.period});

  final Color color;
  final Duration period;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
