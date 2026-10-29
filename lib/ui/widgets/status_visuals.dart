import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/library_entry.dart';

/// Иконки статусов списка из `tokens.json`.
IconData statusIcon(ListStatus s) => switch (s) {
  ListStatus.current => Symbols.play_circle_rounded,
  ListStatus.planning => Symbols.bookmark_rounded,
  ListStatus.completed => Symbols.check_circle_rounded,
  ListStatus.paused => Symbols.pause_circle_rounded,
  ListStatus.dropped => Symbols.cancel_rounded,
  ListStatus.repeating => Symbols.replay_rounded,
};

/// Порядок статусов в составной полосе.
const statusBarOrder = [
  ListStatus.current,
  ListStatus.planning,
  ListStatus.completed,
  ListStatus.paused,
  ListStatus.dropped,
];
