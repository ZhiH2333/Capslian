import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/storage_providers.dart';
import '../../../core/network/websocket_service.dart';
import '../../auth/providers/auth_providers.dart';

/// WebSocket 服务单例：连接管理、重连、心跳；登出时自动断开。
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final getToken = () => ref.read(tokenStorageProvider).getToken();
  final service = WebSocketService(getToken: getToken);
  ref.onDispose(() => service.dispose());
  return service;
});

/// 登录后仅断开时清理 WebSocket；连接推迟到用户打开聊天 Tab 时再执行。
final wsLifecycleProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (Object? prev, AsyncValue<dynamic> next) {
    next.whenData((dynamic user) {
      final ws = ref.read(webSocketServiceProvider);
      if (user == null) {
        ws.disconnect();
      }
    });
  });
});

/// 当前 WebSocket 连接状态。
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  return service.connectionState;
});

/// 服务端通过 WebSocket 下发的原始消息（type / message 等），供 ChatKitsInitializer 等使用。
final wsRawMessagesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  return service.messages;
});
