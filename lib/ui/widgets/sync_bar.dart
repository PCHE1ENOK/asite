import 'package:flutter/material.dart';

import '../../data/sync/sync_service.dart';
import '../app_scope.dart';
import '../login_flow.dart';
import '../settings/sync_visuals.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Полоса состояния синхронизации над «Моими списками».
class SyncBar extends StatelessWidget {
  const SyncBar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sync = AppScope.of(context).services.sync;
    return ValueListenableBuilder<SyncState>(
      valueListenable: sync.state,
      builder: (context, state, _) {
        final v = syncVisual(state, t);
        final Widget? action = switch (state.status) {
          SyncStatus.signedOut when sync.canSignIn => FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (context) => LoginFlow(
                  sync: sync,
                  onDone: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            child: const Text('Войти через GitHub'),
          ),
          SyncStatus.pending => OutlinedButton(
            onPressed: sync.syncNow,
            child: const Text('Синхронизировать'),
          ),
          SyncStatus.error => OutlinedButton(
            onPressed: sync.syncNow,
            child: const Text('Повторить'),
          ),
          _ => null,
        };
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(v.icon, color: v.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: v.label,
                          style: AppText.labelStrong.copyWith(color: t.fg),
                        ),
                        TextSpan(
                          text: ' · ${v.detail}',
                          style: AppText.label.copyWith(color: t.fg2),
                        ),
                      ],
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 12), action],
              ],
            ),
          ),
        );
      },
    );
  }
}
