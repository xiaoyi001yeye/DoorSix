import 'dart:ui';

class GameTableLayoutConfig {
  const GameTableLayoutConfig({
    required this.schema,
    required this.id,
    required this.name,
    required this.grid,
    required this.breakpoints,
    required this.layers,
  });

  static const assetPath =
      'assets/config/table_layouts/immersive_tianjin_table.yaml';

  static const fallback = GameTableLayoutConfig(
    schema: 'door_six.game_table_layout.v1',
    id: 'builtin_immersive_tianjin_table',
    name: '内置新版沉浸式牌桌',
    grid: BucketGrid(columns: 100, rows: 100),
    breakpoints: LayoutBreakpoints(
      compactMaxLogicalHeight: 430,
      compactMaxLogicalWidth: 900,
    ),
    layers: {
      'top_bar': GameTableLayerConfig(
        id: 'top_bar',
        debugName: '横屏/顶栏',
        landscapeRegular: BucketRect(
          x: 1.3,
          y: 1.9,
          width: 97.4,
          height: 12.9,
        ),
        landscapeCompact: BucketRect(
          x: 1.3,
          y: 1.9,
          width: 97.4,
          height: 12.9,
        ),
      ),
      'seat_stage': GameTableLayerConfig(
        id: 'seat_stage',
        debugName: '横屏/座位舞台',
        landscapeRegular: BucketRect(
          x: 1.0,
          y: 9.1,
          width: 84.5,
          height: 73.8,
        ),
        landscapeCompact: BucketRect(
          x: 1.9,
          y: 17.6,
          width: 78.1,
          height: 41.0,
        ),
      ),
      'hand_dock': GameTableLayerConfig(
        id: 'hand_dock',
        debugName: '横屏/手牌区',
        landscapeRegular: BucketRect(
          x: 14.0,
          y: 70.0,
          width: 58.2,
          height: 28.0,
        ),
        landscapeCompact: BucketRect(
          x: 14.0,
          y: 69.6,
          width: 36.9,
          height: 28.0,
        ),
      ),
      'action_column': GameTableLayerConfig(
        id: 'action_column',
        debugName: '横屏/右侧操作栏',
        landscapeRegular: BucketRect(
          x: 75.0,
          y: 76.0,
          width: 13.0,
          height: 22.0,
        ),
        landscapeCompact: BucketRect(
          x: 75.0,
          y: 66.0,
          width: 13.0,
          height: 22.0,
        ),
      ),
      'utility_actions': GameTableLayerConfig(
        id: 'utility_actions',
        debugName: '横屏/左下辅助操作',
        landscapeRegular: BucketRect(
          x: 7.3,
          y: 75.3,
          width: 5.4,
          height: 4.6,
        ),
        landscapeCompact: BucketRect(
          x: 9.2,
          y: 64.3,
          width: 8.8,
          height: 8.0,
        ),
      ),
    },
  );

  final String schema;
  final String id;
  final String name;
  final BucketGrid grid;
  final LayoutBreakpoints breakpoints;
  final Map<String, GameTableLayerConfig> layers;

  bool isLandscapeCompact(Size logicalSize) {
    return logicalSize.height < breakpoints.compactMaxLogicalHeight ||
        logicalSize.width < breakpoints.compactMaxLogicalWidth;
  }

  BucketRect layerBucketRect(String id, {required bool compact}) {
    final layer = layers[id] ?? fallback.layers[id];
    if (layer == null) {
      return const BucketRect(x: 0, y: 0, width: 0, height: 0);
    }
    return compact ? layer.landscapeCompact : layer.landscapeRegular;
  }
}

class BucketGrid {
  const BucketGrid({
    required this.columns,
    required this.rows,
  });

  final int columns;
  final int rows;
}

class LayoutBreakpoints {
  const LayoutBreakpoints({
    required this.compactMaxLogicalHeight,
    required this.compactMaxLogicalWidth,
  });

  final double compactMaxLogicalHeight;
  final double compactMaxLogicalWidth;
}

class GameTableLayerConfig {
  const GameTableLayerConfig({
    required this.id,
    required this.debugName,
    required this.landscapeRegular,
    required this.landscapeCompact,
  });

  final String id;
  final String debugName;
  final BucketRect landscapeRegular;
  final BucketRect landscapeCompact;
}

class BucketRect {
  const BucketRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.anchor = BucketAnchor.topLeft,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final BucketAnchor anchor;

  Rect resolve(Size parentSize, BucketGrid grid) {
    final bucketWidth = parentSize.width / grid.columns;
    final bucketHeight = parentSize.height / grid.rows;
    final resolvedWidth = width * bucketWidth;
    final resolvedHeight = height * bucketHeight;
    var left = x * bucketWidth;
    var top = y * bucketHeight;

    switch (anchor) {
      case BucketAnchor.topLeft:
        break;
      case BucketAnchor.center:
        left -= resolvedWidth / 2;
        top -= resolvedHeight / 2;
        break;
    }

    return Rect.fromLTWH(left, top, resolvedWidth, resolvedHeight);
  }
}

enum BucketAnchor {
  topLeft,
  center,
}
