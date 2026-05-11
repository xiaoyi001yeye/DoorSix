import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FontSizePreset {
  small('小号', 0.92),
  medium('中号', 1.0),
  large('大号', 1.14),
  extraLarge('超大号', 1.28);

  const FontSizePreset(this.label, this.scale);

  final String label;
  final double scale;
}

enum GameTableExperience {
  legacy('经典牌桌'),
  immersive('新版牌桌');

  const GameTableExperience(this.label);

  final String label;
}

class CardDisplayMetrics {
  const CardDisplayMetrics({
    required this.scale,
    required this.width,
    required this.height,
    required this.compactWidth,
    required this.compactHeight,
  });

  final double scale;
  final double width;
  final double height;
  final double compactWidth;
  final double compactHeight;

  int get percent => (scale * 100).round();
}

class CardDisplaySettings extends ChangeNotifier {
  CardDisplaySettings._();

  static final CardDisplaySettings instance = CardDisplaySettings._();

  static const double minScale = 1.0;
  static const double maxScale = 1.5;
  static const double baseWidth = 52.0;
  static const double baseHeight = 76.0;
  static const double compactBaseWidth = 40.0;
  static const double compactBaseHeight = 58.0;

  static const _scaleKey = 'card_display_scale';
  static const _fontSizePresetKey = 'font_size_preset';
  static const _tableExperienceKey = 'game_table_experience';

  double _scale = minScale;
  FontSizePreset _fontSizePreset = FontSizePreset.medium;
  GameTableExperience _tableExperience = GameTableExperience.legacy;

  double get scale => _scale;
  FontSizePreset get fontSizePreset => _fontSizePreset;
  double get fontScale => _fontSizePreset.scale;
  GameTableExperience get tableExperience => _tableExperience;

  CardDisplayMetrics get metrics {
    return CardDisplayMetrics(
      scale: _scale,
      width: baseWidth * _scale,
      height: baseHeight * _scale,
      compactWidth: compactBaseWidth * _scale,
      compactHeight: compactBaseHeight * _scale,
    );
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _scale = _clampScale(prefs.getDouble(_scaleKey) ?? minScale);
    _fontSizePreset = _presetFromName(
      prefs.getString(_fontSizePresetKey),
    );
    _tableExperience = _experienceFromName(
      prefs.getString(_tableExperienceKey),
    );
  }

  void setScale(double value) {
    final next = _clampScale(value);
    if (next == _scale) {
      return;
    }

    _scale = next;
    notifyListeners();
    _saveScale(next);
  }

  void setFontSizePreset(FontSizePreset preset) {
    if (preset == _fontSizePreset) {
      return;
    }

    _fontSizePreset = preset;
    notifyListeners();
    _saveFontSizePreset(preset);
  }

  void setTableExperience(GameTableExperience experience) {
    if (experience == _tableExperience) {
      return;
    }

    _tableExperience = experience;
    notifyListeners();
    _saveTableExperience(experience);
  }

  double _clampScale(double value) {
    return value.clamp(minScale, maxScale).toDouble();
  }

  Future<void> _saveScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scaleKey, value);
  }

  Future<void> _saveFontSizePreset(FontSizePreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontSizePresetKey, preset.name);
  }

  Future<void> _saveTableExperience(GameTableExperience experience) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tableExperienceKey, experience.name);
  }

  FontSizePreset _presetFromName(String? name) {
    for (final preset in FontSizePreset.values) {
      if (preset.name == name) {
        return preset;
      }
    }
    return FontSizePreset.medium;
  }

  GameTableExperience _experienceFromName(String? name) {
    for (final experience in GameTableExperience.values) {
      if (experience.name == name) {
        return experience;
      }
    }
    return GameTableExperience.legacy;
  }
}

class CardDisplaySettingsScope extends InheritedNotifier<CardDisplaySettings> {
  const CardDisplaySettingsScope({
    required CardDisplaySettings settings,
    required super.child,
    super.key,
  }) : super(notifier: settings);

  static CardDisplaySettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CardDisplaySettingsScope>();
    return scope?.notifier ?? CardDisplaySettings.instance;
  }
}
