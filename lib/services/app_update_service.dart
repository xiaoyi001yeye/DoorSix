import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_update.dart';
import 'app_build_info.dart';
import 'app_update_state_store.dart';
import 'server_log_store.dart';

class AppUpdateService {
  AppUpdateService({
    AppBuildInfo buildInfo = const AppBuildInfo(),
    AppUpdateStateStore stateStore = const AppUpdateStateStore(),
    String baseUrl = const String.fromEnvironment(
      'DOORSIX_API_BASE_URL',
      defaultValue: 'http://39.104.67.175',
    ),
  })  : _buildInfo = buildInfo,
        _stateStore = stateStore,
        _baseUri = Uri.parse(baseUrl);

  final AppBuildInfo _buildInfo;
  final AppUpdateStateStore _stateStore;
  final Uri _baseUri;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  final ServerLogStore _logs = ServerLogStore.instance;

  AppBuildInfo get buildInfo => _buildInfo;
  AppUpdateStateStore get stateStore => _stateStore;

  Future<AppUpdateInfo?> checkLatest({
    bool manual = false,
    String source = 'startup',
  }) async {
    final checkedAt = DateTime.now();
    final deviceId = await _stateStore.getOrCreateDeviceId();
    final uri = _uri('/api/v1/app-updates/latest').replace(
      queryParameters: {
        'platform': _buildInfo.platform,
        'channel': _buildInfo.channel,
        'versionCode': _buildInfo.versionCode.toString(),
        'versionName': _buildInfo.versionName,
        'deviceId': deviceId,
      },
    );

    _logs.info(
      '检查新版本',
      detail: '来源：$source，当前：${_buildInfo.versionName}+${_buildInfo.versionCode}',
    );
    try {
      final request = await _http.getUrl(uri).timeout(
            const Duration(seconds: 6),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      final raw = await utf8.decodeStream(response);
      await _stateStore.markChecked(checkedAt);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logs.warning(
          '检查新版本失败',
          detail: '状态码：${response.statusCode}，响应：${_compact(raw)}',
        );
        return null;
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['hasUpdate'] != true) {
        await _stateStore.clearForceLock();
        _logs.success('已是最新版本', detail: _compact(raw));
        return null;
      }

      final info = AppUpdateInfo.fromJson(decoded);
      if (info.isForce) {
        await _stateStore.lockForceUpdate(info.versionCode);
      } else {
        await _stateStore.clearForceLock();
      }
      _logs.success(
        '发现新版本',
        detail: '${info.versionName}+${info.versionCode}，'
            '${info.isForce ? '强制升级' : '普通升级'}',
      );
      return info;
    } on TimeoutException {
      _logs.warning('检查新版本超时', detail: '更新接口暂时没有响应');
      return null;
    } catch (error) {
      _logs.warning('检查新版本异常', detail: error.toString());
      return null;
    }
  }

  Future<bool> shouldCheckOnResume() async {
    final last = await _stateStore.lastCheckAt();
    if (last == null) {
      return true;
    }
    return DateTime.now().difference(last) >= const Duration(minutes: 30);
  }

  Uri _uri(String path) {
    final prefix =
        _baseUri.path.endsWith('/') ? _baseUri.path : '${_baseUri.path}/';
    return _baseUri.replace(
      path: '$prefix${path.replaceFirst(RegExp('^/'), '')}',
    );
  }

  String _compact(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 800
        ? normalized
        : '${normalized.substring(0, 800)}...';
  }
}
