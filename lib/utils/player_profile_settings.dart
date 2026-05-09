import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_avatar.dart';

class PlayerProfileSettings extends ChangeNotifier {
  PlayerProfileSettings._();

  static final PlayerProfileSettings instance = PlayerProfileSettings._();

  static const _avatarPresetIdKey = 'player_avatar_preset_id';

  String _avatarPresetId = PlayerAvatarPreset.defaultId;

  String get avatarPresetId => _avatarPresetId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_avatarPresetIdKey);
    _avatarPresetId = PlayerAvatarPreset.isKnown(saved)
        ? saved!
        : PlayerAvatarPreset.defaultId;
  }

  void setAvatarPresetId(String id) {
    final next = PlayerAvatarPreset.byId(id).id;
    if (next == _avatarPresetId) {
      return;
    }

    _avatarPresetId = next;
    notifyListeners();
    _saveAvatarPresetId(next);
  }

  Future<void> _saveAvatarPresetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarPresetIdKey, id);
  }
}

class PlayerProfileSettingsScope
    extends InheritedNotifier<PlayerProfileSettings> {
  const PlayerProfileSettingsScope({
    required PlayerProfileSettings settings,
    required super.child,
    super.key,
  }) : super(notifier: settings);

  static PlayerProfileSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PlayerProfileSettingsScope>();
    return scope?.notifier ?? PlayerProfileSettings.instance;
  }
}
