import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/app_tokens.dart';
import 'skeleton.dart';

/// Картинка по URL с заглушкой цвета обложки на время загрузки и при
/// ошибке.
class NetworkCover extends StatelessWidget {
  const NetworkCover({
    super.key,
    required this.url,
    this.color,
    this.fit = BoxFit.cover,
    this.radius = AppRadius.md,
  });

  final String? url;

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
    final tint = parseColor(color);
    final placeholderColor = tint == null
        ? t.skeleton
        : Color.alphaBlend(tint.withValues(alpha: 0.35), t.skeleton);
    final placeholder = Skeleton(radius: radius, color: placeholderColor);

    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: u == null
          ? ColoredBox(color: placeholderColor)
          : Image(
              image: AppScope.of(context).imageResolver(u),
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) {
                if (sync || frame != null) {
                  return AnimatedOpacity(
                    opacity: 1,
                    duration: AppMotion.fast,
                    child: child,
                  );
                }
                return placeholder;
              },
              errorBuilder: (_, _, _) => ColoredBox(color: placeholderColor),
            ),
    );
  }
}
