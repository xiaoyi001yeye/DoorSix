import 'dart:convert';

import 'package:flutter/services.dart';

class GameRuntimeConfig {
  const GameRuntimeConfig({
    required this.turnDurationSeconds,
  });

  static const assetPath = 'server/config/game_settings.json';

  static late final GameRuntimeConfig instance;

  final int turnDurationSeconds;

  static Future<void> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    instance = GameRuntimeConfig(
      turnDurationSeconds: data['turnDurationSeconds'] as int,
    );
  }
}
