import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../theme/app_tokens.dart';

/// Картинка по URL с заглушкой цвета обложки на время загрузки и при
/// ошибке.
///
/// Для обложки AniList ([cover]) размер выбирается по месту на экране
/// (medium ≈ 100 px, large ≈ 230 px, extraLarge ≈ 460 px по ширине), а
/// картинка декодируется сразу в нужном размере — меньше памяти и работы
/// при прокрутке. Заглушка неподвижная: без мерцания; загруженная из сети
/// картинка проявляется плавно, из памяти — сразу.
class NetworkCover extends StatelessWidget {
  const NetworkCover({
    super.key,
    this.url,
    this.cover,
    this.color,
    this.fit = BoxFit.cover,
    this.radius = AppRadius.md,
  });

  final String? url;

  /// Обложка AniList: размер выбирается по ширине на экране.
  final CoverImage? cover;

  /// Средний цвет обложки от AniList (`#rrggbb`).
  final String? color;
  final BoxFit fit;
  final double radius;

  static Color? parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    final v = int.tryParse(hex.substring(1), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tint = parseColor(color ?? cover?.color);
    final placeholderColor = tint == null
        ? t.skeleton
        : Color.alphaBlend(tint.withValues(alpha: 0.35), t.skeleton);
    final placeholder = ColoredBox(color: placeholderColor);
    final resolver = AppScope.of(context).imageResolver;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final px = constraints.hasBoundedWidth
              ? (constraints.maxWidth * dpr).ceil()
              : null;
          final u = url ?? cover?.forWidth(px);
          if (u == null) return placeholder;
          final image = px == null || px <= 0
              ? resolver(u)
              : ResizeImage(
                  resolver(u),
                  width: px,
                  policy: ResizeImagePolicy.fit,
                );
          // Цвет-заглушка — фоном: картинка ложится поверх, без смены
          // виджетов и мерцания (и прозрачные места не чернеют).
          return ColoredBox(
            color: placeholderColor,
            child: Image(
              image: image,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) {
                if (frame == null) return const SizedBox.expand();
                if (sync || reduceMotion) return child;
                return _FadeIn(child: child);
              },
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

/// Плавное появление один раз, без повторов при пересборке.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppMotion.fast,
    builder: (_, v, child) => Opacity(opacity: v, child: child),
    child: child,
  );
}
