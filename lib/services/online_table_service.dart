import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/online_table.dart';
import 'app_build_info.dart';
import 'server_log_store.dart';

enum ServerHealthStatus {
  checking,
  available,
  busy,
  down,
}

class ServerHealthSnapshot {
  const ServerHealthSnapshot({
    required this.status,
    required this.checkedAt,
  });

  final ServerHealthStatus status;
  final DateTime checkedAt;
}

class DoorSixBackendException implements Exception {
  const DoorSixBackendException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class DoorSixBackendClient {
  DoorSixBackendClient({
    String baseUrl = const String.fromEnvironment(
      'DOORSIX_API_BASE_URL',
      defaultValue: 'http://39.104.67.175',
    ),
    AppBuildInfo buildInfo = const AppBuildInfo(),
  })  : _baseUri = Uri.parse(baseUrl),
        _buildInfo = buildInfo;

  final Uri _baseUri;
  final AppBuildInfo _buildInfo;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  final ServerLogStore _logs = ServerLogStore.instance;

  Uri get baseUri => _baseUri;

  Future<ServerHealthSnapshot> health() async {
    final checkedAt = DateTime.now();
    final uri = _uri('/health');
    _logs.info('HTTP GET /health', detail: '请求：$uri');
    try {
      final request = await _http
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (_isBusyStatus(response.statusCode)) {
        await response.drain<void>();
        _logs.warning(
          'HTTP GET /health 服务器忙',
          detail: '状态码：${response.statusCode}',
        );
        return ServerHealthSnapshot(
          status: ServerHealthStatus.busy,
          checkedAt: checkedAt,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _logs.error(
          'HTTP GET /health 失败',
          detail: '状态码：${response.statusCode}',
        );
        return ServerHealthSnapshot(
          status: ServerHealthStatus.down,
          checkedAt: checkedAt,
        );
      }
      final raw = await utf8.decodeStream(response);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final status = decoded['ok'] == true
          ? ServerHealthStatus.available
          : ServerHealthStatus.busy;
      if (status == ServerHealthStatus.available) {
        _logs.success('HTTP GET /health 成功', detail: _compact(raw));
      } else {
        _logs.warning('HTTP GET /health 忙碌', detail: _compact(raw));
      }
      return ServerHealthSnapshot(
        status: status,
        checkedAt: checkedAt,
      );
    } on TimeoutException {
      _logs.warning('HTTP GET /health 超时', detail: '4 秒内没有收到响应');
      return ServerHealthSnapshot(
        status: ServerHealthStatus.busy,
        checkedAt: checkedAt,
      );
    } catch (error) {
      _logs.error('HTTP GET /health 异常', detail: error.toString());
      return ServerHealthSnapshot(
        status: ServerHealthStatus.down,
        checkedAt: checkedAt,
      );
    }
  }

  Future<OnlineSession> createRoom({
    required String nickname,
    int seatIndex = 0,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/rooms',
      body: {
        'nickname': nickname,
        'seatIndex': seatIndex,
      },
    );
    return OnlineSession.fromJson(data);
  }

  Future<OnlineSession> joinRoom({
    required String roomCode,
    required String nickname,
    int? seatIndex,
  }) async {
    final body = <String, Object?>{'nickname': nickname};
    if (seatIndex != null) {
      body['seatIndex'] = seatIndex;
    }
    final data = await _request(
      'POST',
      '/api/v1/rooms/by-code/$roomCode/join',
      body: body,
    );
    return OnlineSession.fromJson(data);
  }

  Future<void> leaveRoom(OnlineSession session) async {
    await _request(
      'POST',
      '/api/v1/rooms/${session.room.roomId}/leave',
      token: session.playerToken,
      body: {'reason': 'android_client_exit'},
    );
  }

  Future<OnlineTableSnapshot> snapshot(OnlineSession session) async {
    final data = await _request(
      'GET',
      '/api/v1/rooms/${session.room.roomId}/snapshot',
      token: session.playerToken,
    );
    return OnlineTableSnapshot.fromJson(data);
  }

  Future<WebSocket> connect(OnlineSession session) async {
    final uri = _socketUrl(session);
    _logs.info(
      'WS 连接房间 ${session.room.roomCode}',
      detail: _redactUri(uri).toString(),
    );
    try {
      final socket = await WebSocket.connect(uri.toString());
      _logs.success('WS 已连接', detail: '房间：${session.room.roomCode}');
      return socket;
    } catch (error) {
      _logs.error('WS 连接失败', detail: error.toString());
      rethrow;
    }
  }

  void close() {
    _http.close(force: true);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final uri = _uri(path);
    final startedAt = DateTime.now();
    _logs.info(
      'HTTP $method $path',
      detail: body == null ? '请求：$uri' : '请求体：${_compact(jsonEncode(body))}',
    );
    try {
      final request = await _http.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      _setAppHeaders(request.headers);
      if (token != null) {
        request.headers.set('X-Player-Token', token);
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final raw = await utf8.decodeStream(response);
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final decoded = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String? ?? '后端请求失败';
        final code = error?['code'] as String?;
        _logs.error(
          'HTTP $method $path 失败',
          detail: '状态码：${response.statusCode}，耗时：${elapsed}ms\n'
              '错误：${code ?? 'UNKNOWN'} $message\n响应：${_compact(raw)}',
        );
        throw DoorSixBackendException(message, code: code);
      }
      if (decoded['success'] == false) {
        final error = decoded['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String? ?? '后端请求失败';
        final code = error?['code'] as String?;
        _logs.error(
          'HTTP $method $path 失败',
          detail: '耗时：${elapsed}ms\n'
              '错误：${code ?? 'UNKNOWN'} $message\n响应：${_compact(raw)}',
        );
        throw DoorSixBackendException(message, code: code);
      }
      _logs.success(
        'HTTP $method $path 成功',
        detail: '状态码：${response.statusCode}，耗时：${elapsed}ms\n'
            '响应：${_compact(raw)}',
      );
      return decoded['data'] as Map<String, dynamic>;
    } catch (error) {
      if (error is DoorSixBackendException) {
        rethrow;
      }
      _logs.error('HTTP $method $path 异常', detail: error.toString());
      rethrow;
    }
  }

  Uri _uri(String path) {
    final prefix = _baseUri.path.endsWith('/') ? _baseUri.path : '${_baseUri.path}/';
    return _baseUri.replace(path: '$prefix${path.replaceFirst(RegExp('^/'), '')}');
  }

  Uri _socketUrl(OnlineSession session) {
    final raw = Uri.parse(session.webSocketUrl);
    final uri = raw.hasScheme ? raw : _baseUri.replace(path: raw.path);
    final params = Map<String, String>.from(uri.queryParameters)
      ..['playerToken'] = session.playerToken;
    return uri.replace(queryParameters: params);
  }

  void _setAppHeaders(HttpHeaders headers) {
    headers.set('X-App-Platform', _buildInfo.platform);
    headers.set('X-App-Version-Code', _buildInfo.versionCode.toString());
    headers.set('X-App-Version-Name', _buildInfo.versionName);
    headers.set('X-App-Channel', _buildInfo.channel);
  }

  bool _isBusyStatus(int statusCode) {
    return statusCode == HttpStatus.tooManyRequests ||
        statusCode == HttpStatus.serviceUnavailable ||
        statusCode == HttpStatus.gatewayTimeout;
  }

  Uri _redactUri(Uri uri) {
    if (!uri.queryParameters.containsKey('playerToken')) {
      return uri;
    }
    final query = Map<String, String>.from(uri.queryParameters)
      ..['playerToken'] = '***';
    return uri.replace(queryParameters: query);
  }

  String _compact(String text) {
    final normalized = _redactText(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 800) {
      return normalized;
    }
    return '${normalized.substring(0, 800)}...';
  }

  String _redactText(String text) {
    return text
        .replaceAll(RegExp(r'"playerToken"\s*:\s*"[^"]+"'), '"playerToken":"***"')
        .replaceAll(RegExp(r'playerToken=[^&\s"]+'), 'playerToken=***');
  }
}
