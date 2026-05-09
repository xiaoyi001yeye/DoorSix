import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppUpdateStateStore {
  const AppUpdateStateStore();

  static const _deviceIdKey = 'app_update.device_id';
  static const _lastCheckAtKey = 'app_update.last_check_at';
  static const _dismissedVersionCodeKey = 'app_update.dismissed_version_code';
  static const _dismissedAtKey = 'app_update.dismissed_at';
  static const _forceLockedVersionCodeKey =
      'app_update.force_locked_version_code';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _randomId();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  Future<DateTime?> lastCheckAt() async {
    final value = (await SharedPreferences.getInstance()).getString(
      _lastCheckAtKey,
    );
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> markChecked(DateTime checkedAt) async {
    await (await SharedPreferences.getInstance()).setString(
      _lastCheckAtKey,
      checkedAt.toIso8601String(),
    );
  }

  Future<bool> shouldShowOptionalUpdate({
    required int versionCode,
    required DateTime now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_dismissedVersionCodeKey) != versionCode) {
      return true;
    }
    final dismissedAt = DateTime.tryParse(
      prefs.getString(_dismissedAtKey) ?? '',
    );
    if (dismissedAt == null) {
      return true;
    }
    return now.difference(dismissedAt) >= const Duration(hours: 24);
  }

  Future<void> dismissOptionalUpdate(int versionCode, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedVersionCodeKey, versionCode);
    await prefs.setString(_dismissedAtKey, now.toIso8601String());
  }

  Future<void> lockForceUpdate(int versionCode) async {
    await (await SharedPreferences.getInstance()).setInt(
      _forceLockedVersionCodeKey,
      versionCode,
    );
  }

  Future<void> clearForceLock() async {
    await (await SharedPreferences.getInstance()).remove(
      _forceLockedVersionCodeKey,
    );
  }

  String _randomId() {
    final random = Random.secure();
    String hex(int length) => List.generate(
          length,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }
}
