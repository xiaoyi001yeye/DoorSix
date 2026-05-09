import 'package:flutter/material.dart';

class PlayerAvatarPreset {
  const PlayerAvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  static const defaultId = 'sun';

  static const presets = [
    PlayerAvatarPreset(
      id: 'sun',
      label: '金日',
      icon: Icons.wb_sunny_rounded,
      background: Color(0xFF6B4F1D),
      foreground: Color(0xFFFFD166),
    ),
    PlayerAvatarPreset(
      id: 'leaf',
      label: '青叶',
      icon: Icons.eco_rounded,
      background: Color(0xFF174D3C),
      foreground: Color(0xFF6DE7A7),
    ),
    PlayerAvatarPreset(
      id: 'spark',
      label: '星火',
      icon: Icons.auto_awesome_rounded,
      background: Color(0xFF4A274A),
      foreground: Color(0xFFFFA8D4),
    ),
    PlayerAvatarPreset(
      id: 'wave',
      label: '海浪',
      icon: Icons.water_rounded,
      background: Color(0xFF163C5C),
      foreground: Color(0xFF62D2FF),
    ),
    PlayerAvatarPreset(
      id: 'stone',
      label: '青石',
      icon: Icons.hexagon_rounded,
      background: Color(0xFF34423E),
      foreground: Color(0xFFCED9D2),
    ),
    PlayerAvatarPreset(
      id: 'crown',
      label: '王冠',
      icon: Icons.workspace_premium_rounded,
      background: Color(0xFF5A3E16),
      foreground: Color(0xFFFFE08A),
    ),
  ];

  static PlayerAvatarPreset byId(String? id) {
    for (final preset in presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return presets.first;
  }

  static bool isKnown(String? id) {
    return presets.any((preset) => preset.id == id);
  }
}
