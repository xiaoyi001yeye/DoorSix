import 'dart:convert';
import 'dart:io';

import '../models/online_table.dart';

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
  }) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  Uri get baseUri => _baseUri;

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

  Future<WebSocket> connect(OnlineSession session) {
    return WebSocket.connect(_socketUrl(session).toString());
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
    final request = await _http.openUrl(method, _uri(path));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set('X-Player-Token', token);
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final raw = await utf8.decodeStream(response);
    final decoded = raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw DoorSixBackendException(
        error?['message'] as String? ?? '后端请求失败',
        code: error?['code'] as String?,
      );
    }
    if (decoded['success'] == false) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw DoorSixBackendException(
        error?['message'] as String? ?? '后端请求失败',
        code: error?['code'] as String?,
      );
    }
    return decoded['data'] as Map<String, dynamic>;
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
}
