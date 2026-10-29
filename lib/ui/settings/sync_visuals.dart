import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/sync/sync_service.dart';
import '../format.dart';
import '../theme/app_tokens.dart';

/// Иконка, цвет и подписи состояния синхронизации (tokens.json `sync`).
({IconData icon, Color color, String label, String detail}) syncVisual(
  SyncState s,
  AppTokens t,
) => switch (s.status) {
  SyncStatus.synced => (
    icon: Symbols.cloud_done_rounded,
    color: t.good,
    label: 'Синхронизировано',
    detail: 'Списки совпадают с приватным Gist',
  ),
  SyncStatus.pending => (
    icon: Symbols.cloud_upload_rounded,
    color: t.warn,
    label: 'Не синхронизировано',
    detail:
        '${s.pendingCount} ${Fmt.plural(s.pendingCount, 'изменение ждёт', 'изменения ждут', 'изменений ждут')} отправки',
  ),
  SyncStatus.syncing => (
    icon: Symbols.sync_rounded,
    color: t.fg3,
    label: 'Синхронизация…',
    detail: 'Сверяем списки с Gist',
  ),
  SyncStatus.error => (
    icon: Symbols.cloud_off_rounded,
    color: t.bad,
    label: 'Нет сети',
    detail: 'Изменения сохранены на устройстве и уйдут при подключении',
  ),
  SyncStatus.signedOut => (
    icon: Symbols.smartphone_rounded,
    color: t.fg3,
    label: 'Только на этом устройстве',
    detail: 'Войдите через GitHub, чтобы хранить списки в приватном Gist',
  ),
};

/// Цвет точки на пункте профиля; `null` — точки нет.
Color? syncDotColor(SyncState s, AppTokens t) => switch (s.status) {
  SyncStatus.synced => t.good,
  SyncStatus.pending => t.warn,
  SyncStatus.syncing => t.fg3,
  SyncStatus.error => t.bad,
  SyncStatus.signedOut => null,
};
