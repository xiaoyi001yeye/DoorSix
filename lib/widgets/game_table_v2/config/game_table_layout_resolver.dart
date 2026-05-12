import 'dart:ui';

import 'game_table_layout_config.dart';

class ResolvedGameTableLayout {
  const ResolvedGameTableLayout({
    required this.configId,
    required this.compact,
    required this.rects,
  });

  final String configId;
  final bool compact;
  final Map<String, Rect> rects;

  Rect rectFor(String id) {
    return rects[id] ?? Rect.zero;
  }
}

class GameTableLayoutResolver {
  const GameTableLayoutResolver._();

  static ResolvedGameTableLayout resolveLandscape({
    required GameTableLayoutConfig config,
    required Size parentSize,
  }) {
    final compact = config.isLandscapeCompact(parentSize);
    return ResolvedGameTableLayout(
      configId: config.id,
      compact: compact,
      rects: {
        for (final id in config.layers.keys)
          id: config
              .layerBucketRect(id, compact: compact)
              .resolve(parentSize, config.grid),
      },
    );
  }
}
