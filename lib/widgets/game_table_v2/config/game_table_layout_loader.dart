import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import 'game_table_layout_config.dart';

class GameTableLayoutLoader {
  const GameTableLayoutLoader._();

  static Future<GameTableLayoutConfig> load({
    String assetPath = GameTableLayoutConfig.assetPath,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    final yaml = loadYaml(raw);
    if (yaml is! YamlMap) {
      throw const FormatException('Table layout YAML root must be a map.');
    }
    return _parseConfig(yaml);
  }

  static GameTableLayoutConfig _parseConfig(YamlMap yaml) {
    final gridMap = _mapAt(yaml, 'layoutGrid');
    final breakpointsMap = _mapAt(yaml, 'breakpoints');
    final landscapeMap = _mapAt(breakpointsMap, 'landscape');
    final compactWhenMap = _mapAt(landscapeMap, 'compactWhen');
    final layersList = _listAt(yaml, 'layers');
    final layers = <String, GameTableLayerConfig>{};

    for (final item in layersList) {
      if (item is! YamlMap) {
        continue;
      }
      final layer = _parseLayer(item);
      layers[layer.id] = layer;
    }

    return GameTableLayoutConfig(
      schema: _stringAt(yaml, 'schema'),
      id: _stringAt(yaml, 'id'),
      name: _stringAt(yaml, 'name'),
      grid: BucketGrid(
        columns: _intAt(gridMap, 'columns'),
        rows: _intAt(gridMap, 'rows'),
      ),
      breakpoints: LayoutBreakpoints(
        compactMaxLogicalHeight: _doubleAt(
          compactWhenMap,
          'maxLogicalHeight',
        ),
        compactMaxLogicalWidth: _doubleAt(
          compactWhenMap,
          'maxLogicalWidth',
        ),
      ),
      layers: layers,
    );
  }

  static GameTableLayerConfig _parseLayer(YamlMap yaml) {
    final landscapeMap = _mapAt(yaml, 'landscape');
    final regularMap = _mapAt(landscapeMap, 'regular');
    final compactMap = _mapAt(landscapeMap, 'compact');
    return GameTableLayerConfig(
      id: _stringAt(yaml, 'id'),
      debugName: _optionalStringAt(yaml, 'debugName') ?? _stringAt(yaml, 'id'),
      landscapeRegular: _parseBucketRect(
        _mapAt(regularMap, 'bucketPosition'),
      ),
      landscapeCompact: _parseBucketRect(
        _mapAt(compactMap, 'bucketPosition'),
      ),
    );
  }

  static BucketRect _parseBucketRect(YamlMap yaml) {
    final mode = _stringAt(yaml, 'mode');
    if (mode != 'bucket') {
      throw FormatException('Unsupported position mode: $mode');
    }
    return BucketRect(
      x: _doubleAt(yaml, 'x'),
      y: _doubleAt(yaml, 'y'),
      width: _doubleAt(yaml, 'width'),
      height: _doubleAt(yaml, 'height'),
      anchor: _anchorFromName(_optionalStringAt(yaml, 'anchor')),
    );
  }

  static BucketAnchor _anchorFromName(String? name) {
    return switch (name) {
      null || 'topLeft' => BucketAnchor.topLeft,
      'center' => BucketAnchor.center,
      _ => throw FormatException('Unsupported bucket anchor: $name'),
    };
  }

  static YamlMap _mapAt(YamlMap map, String key) {
    final value = map[key];
    if (value is YamlMap) {
      return value;
    }
    throw FormatException('Missing YAML map: $key');
  }

  static YamlList _listAt(YamlMap map, String key) {
    final value = map[key];
    if (value is YamlList) {
      return value;
    }
    throw FormatException('Missing YAML list: $key');
  }

  static String _stringAt(YamlMap map, String key) {
    final value = map[key];
    if (value is String) {
      return value;
    }
    throw FormatException('Missing YAML string: $key');
  }

  static String? _optionalStringAt(YamlMap map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Invalid YAML string: $key');
  }

  static int _intAt(YamlMap map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    throw FormatException('Missing YAML int: $key');
  }

  static double _doubleAt(YamlMap map, String key) {
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    throw FormatException('Missing YAML number: $key');
  }
}
