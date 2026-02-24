import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/storage_providers.dart';
import '../../../core/network/websocket_service.dart';
import '../data/models/message_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// WebSocket 服务单例：连接管理、重连、心跳；登出时自动断开。
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final getToken = () => ref.read(tokenStorageProvider).getToken();
  final service = WebSocketService(getToken: getToken);
  ref.onDispose(() => service.dispose());
  return service;
});

/// 登录后自动连接 WebSocket、登出后断开；在根组件 watch 以生效。
final wsLifecycleProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (Object? prev, AsyncValue<dynamic> next) {
    next.whenData((dynamic user) {
      final ws = ref.read(webSocketServiceProvider);
      if (user != null) {
        ws.connect();
      } else {
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

/// 服务端通过 WebSocket 下发的原始消息（type / message 等）。
final wsRawMessagesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  return service.messages;
});

/// 与指定用户的聊天消息列表（REST 初载 + 内存追加 WebSocket 新消息）。
/// 使用 [chatMessagesNotifierProvider(peerUserId)] 获取列表并调用 notifier 追加/更新。
final chatMessagesNotifierProvider =
    AsyncNotifierProvider.family<ChatMessagesNotifier, List<MessageModel>, String>(
        ChatMessagesNotifier.new);

class ChatMessagesNotifier extends FamilyAsyncNotifier<List<MessageModel>, String> {
  @override
  Future<List<MessageModel>> build(String peerUserId) async {
    if (peerUserId.isEmpty) return [];
    final repo = ref.read(socialRepositoryProvider);
    final raw = await repo.getMessages(peerUserId);
    final list = raw.map((e) => MessageModel.fromJson(e)).toList();
    list.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    return list;
  }

  /// 从 WebSocket 收到新消息时追加（去重）。
  void appendFromWs(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((m) => m.id == message.id)) return;
    final next = List<MessageModel>.from(current)..add(message);
    next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    state = AsyncData(next);
  }

  /// 乐观追加一条（发送中），返回临时 id 用于后续替换。
  void appendOptimistic(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = List<MessageModel>.from(current)..add(message);
    next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    state = AsyncData(next);
  }

  /// 按 id 替换或追加一条（发送成功/服务端回包）。
  void replaceOrAppend(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.indexWhere((m) => m.id == message.id);
    final next = List<MessageModel>.from(current);
    if (idx >= 0) {
      next[idx] = message;
    } else {
      next.add(message);
      next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    }
    state = AsyncData(next);
  }

  /// 将指定临时 id 的消息标记为发送失败。
  void markFailed(String temporaryId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.map((m) {
      if (m.id == temporaryId) return m.copyWith(status: MessageStatus.failed);
      return m;
    }).toList();
    state = AsyncData(next);
  }
}

int _compareCreatedAt(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}
