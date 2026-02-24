import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';

/// WebSocket 连接状态。
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// 连接管理、自动重连与心跳的 WebSocket 服务。
/// 用于私信实时消息；需配合后端 WebSocket 端点（如 /ws）。
class WebSocketService {
  WebSocketService({
    required String? Function() getToken,
    String? wsBaseUrl,
    String wsPath = '/ws',
  })  : _getToken = getToken,
        _wsBaseUrl = wsBaseUrl ?? ApiConstants.wsBaseUrl,
        _wsPath = wsPath;

  final String? Function() _getToken;
  final String _wsBaseUrl;
  final String _wsPath;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelaySeconds = 30;
  static const int _heartbeatIntervalSeconds = 25;
  static const int _pongTimeoutSeconds = 5;
  Timer? _pongTimeout;
  bool _disposed = false;
  bool _manualDisconnect = false;

  final _connectionStateController = StreamController<WsConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  /// 当前连接状态流。
  Stream<WsConnectionState> get connectionState => _connectionStateController.stream;

  /// 服务端下发的消息流（已解析为 JSON Map）。
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// 是否已连接。
  bool get isConnected => _channel != null;

  void _emitConnectionState(WsConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// 建立连接（带 token 查询参数）。
  Future<void> connect() async {
    if (_disposed) return;
    _manualDisconnect = false;
    final token = _getToken();
    if (token == null || token.isEmpty) {
      _emitConnectionState(WsConnectionState.disconnected);
      return;
    }
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_disposed || _manualDisconnect) return;
    _emitConnectionState(_reconnectAttempts > 0 ? WsConnectionState.reconnecting : WsConnectionState.connecting);
    final token = _getToken();
    if (token == null || token.isEmpty) {
      _emitConnectionState(WsConnectionState.disconnected);
      return;
    }
    final uri = Uri.parse(_wsBaseUrl).replace(
      path: _wsPath,
      queryParameters: <String, String>{'token': token},
    );
    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _reconnectAttempts = 0;
      _emitConnectionState(WsConnectionState.connected);
      _startHeartbeat();
    } catch (e) {
      _emitConnectionState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    _cancelPongTimeout();
    if (data == 'pong' || data.trim() == '{"type":"pong"}') {
      return;
    }
    try {
      final map = _parseJsonMap(data);
      if (map != null && map['type'] == 'pong') return;
      if (map != null && !_messageController.isClosed) {
        _messageController.add(map);
      }
    } catch (_) {}
  }

  Map<String, dynamic>? _parseJsonMap(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      return _jsonDecodeMap(trimmed);
    }
    return null;
  }

  Map<String, dynamic>? _jsonDecodeMap(String json) {
    try {
      final decoded = jsonDecode(json) as dynamic;
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  void _onError(Object error) {
    _emitConnectionState(WsConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    _stopHeartbeat();
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    if (!_manualDisconnect && !_disposed) {
      _emitConnectionState(WsConnectionState.disconnected);
      _scheduleReconnect();
    } else {
      _emitConnectionState(WsConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: _heartbeatIntervalSeconds), (_) {
      if (_channel == null || _disposed) return;
      send(<String, dynamic>{'type': 'ping'});
      _pongTimeout = Timer(const Duration(seconds: _pongTimeoutSeconds), () {
        _channel?.sink.close();
      });
    });
  }

  void _cancelPongTimeout() {
    _pongTimeout?.cancel();
    _pongTimeout = null;
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelPongTimeout();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null || _disposed || _manualDisconnect) return;
    _reconnectAttempts++;
    final seconds = (1 << (_reconnectAttempts.clamp(0, 5))).clamp(1, _maxReconnectDelaySeconds);
    final capped = Duration(seconds: seconds);
    _reconnectTimer = Timer(capped, () {
      _reconnectTimer = null;
      _connectInternal();
    });
  }

  /// 发送 JSON 可序列化数据（由调用方保证可序列化为 JSON）。
  void send(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  /// 主动断开，不触发重连。
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _channel?.sink.close();
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    _emitConnectionState(WsConnectionState.disconnected);
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _connectionStateController.close();
    _messageController.close();
  }
}
